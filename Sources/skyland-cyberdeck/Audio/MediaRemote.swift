import AppKit

// Now playing through MediaRemote. Since macOS 15.4 only entitled processes get it:
// /usr/bin/perl is one, it loads the MediaRemoteAdapter library built with this package
// (Sources/MediaRemoteAdapter, BSD-3) and prints the state as JSON lines. The script is
// the upstream mediaremote-adapter.pl (797729d, BSD-3), embedded below.

/// What plays, from the adapter's JSON (keys: MediaRemoteAdapter adapter/keys.m).
struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var album: String
    var bundleID: String?
    var pid: pid_t?
    var playing: Bool
    var duration: Double? // seconds
    var elapsed: Double?  // seconds, at `timestamp`
    var timestamp: Date?
    var rate: Double
    var track: Int?
    var tracks: Int?
    var artwork: Data?

    /// nil when nothing plays (an empty payload or no title).
    init?(_ payload: [String: Any]) {
        guard let title = payload["title"] as? String, !title.isEmpty else { return nil }
        self.title = title
        artist = payload["artist"] as? String ?? ""
        album = payload["album"] as? String ?? ""
        // a browser tab plays in a helper process: the app is its parent
        bundleID = payload["parentApplicationBundleIdentifier"] as? String ?? payload["bundleIdentifier"] as? String
        pid = (payload["processIdentifier"] as? Int).map { pid_t($0) }
        playing = payload["playing"] as? Bool ?? false
        duration = (payload["durationMicros"] as? Double).map { $0 / 1_000_000 }
        elapsed = (payload["elapsedTimeMicros"] as? Double).map { $0 / 1_000_000 }
        timestamp = (payload["timestampEpochMicros"] as? Double).map { Date(timeIntervalSince1970: $0 / 1_000_000) }
        rate = payload["playbackRate"] as? Double ?? 1
        track = payload["trackNumber"] as? Int
        tracks = payload["totalTrackCount"] as? Int
        artwork = (payload["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }
    }

    /// Elapsed seconds at `date`: the elapsed time of the timestamp, moved on at the
    /// playback rate while playing, within the track.
    func elapsed(at date: Date) -> Double? {
        guard var now = elapsed else { return nil }
        if playing, let timestamp { now += date.timeIntervalSince(timestamp) * rate }
        if let duration { now = min(now, duration) }
        return max(0, now)
    }
}

enum MediaRemote {
    enum Command: Int {
        case play = 0, pause = 1, toggle = 2, next = 4, previous = 5
    }

    /// The library SwiftPM built: next to the executable (swift build), or in lib /
    /// libexec beside its bin directory (an installed package).
    static var library: URL? {
        guard let bin = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent() else { return nil }
        let prefix = bin.deletingLastPathComponent()
        return [bin, prefix.appending(path: "lib"), prefix.appending(path: "libexec")]
            .map { $0.appending(path: "libMediaRemoteAdapter.dylib") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The script and the framework it expects (`X.framework/X`), in the cache, once
    /// per process; nil without the library.
    static let files: (script: URL, framework: URL)? = {
        guard let library else { return nil }
        let manager = FileManager.default
        let cache = manager.homeDirectoryForCurrentUser.appending(path: "Library/Caches/skyland-cyberdeck/mediaremote")
        let framework = cache.appending(path: "MediaRemoteAdapter.framework"), binary = framework.appending(path: "MediaRemoteAdapter")
        let script = cache.appending(path: "mediaremote-adapter.pl")
        do {
            try manager.createDirectory(at: framework, withIntermediateDirectories: true)
            if !manager.contentsEqual(atPath: library.path, andPath: binary.path) {
                try? manager.removeItem(at: binary)
                try manager.copyItem(at: library, to: binary)
            }
            if (try? String(contentsOf: script, encoding: .utf8)) != adapterScript {
                try adapterScript.write(to: script, atomically: true, encoding: .utf8)
            }
        } catch {
            return nil
        }
        return (script, framework)
    }()

    /// The adapter running `arguments` (not started), nil without the library.
    static func process(_ arguments: [String]) -> Process? {
        guard let files else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [files.script.path, files.framework.path] + arguments
        process.standardError = FileHandle.nullDevice
        return process
    }

    static func send(_ command: Command) { run(["send", String(command.rawValue)]) }

    static func seek(to seconds: Double) { run(["seek", String(Int((max(0, seconds) * 1_000_000).rounded()))]) }

    private static func run(_ arguments: [String]) {
        guard let process = process(arguments) else { return }
        process.standardOutput = FileHandle.nullDevice
        try? process.run()
    }
}

/// The adapter's stream: one perl process for the deck's life, ended with it.
final class NowPlayingStream {
    var onChange: (NowPlaying?) -> Void = { _ in }
    /// false: the adapter library is not installed (now playing unavailable)
    private(set) var available = MediaRemote.files != nil
    private var process: Process?

    func start() {
        guard let process = MediaRemote.process(["stream", "--no-diff", "--micros", "--debounce=100"]) else {
            available = false
            return
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        var buffer = Data()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { handle.readabilityHandler = nil; return }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0a) {
                let line = buffer[buffer.startIndex ..< newline]
                buffer.removeSubrange(buffer.startIndex ... newline)
                guard let json = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      let payload = json["payload"] as? [String: Any] else { continue }
                let info = NowPlaying(payload)
                DispatchQueue.main.async { self?.onChange(info) }
            }
        }
        guard (try? process.run()) != nil else { available = false; return }
        self.process = process
        // the deck ends with exit(): the stream must not outlive it
        nowPlayingStreamPID = process.processIdentifier
        atexit { if nowPlayingStreamPID > 0 { kill(nowPlayingStreamPID, SIGTERM) } }
    }
}

nonisolated(unsafe) var nowPlayingStreamPID: pid_t = 0

/// ungive/mediaremote-adapter bin/mediaremote-adapter.pl at 797729d (BSD 3-Clause).
private let adapterScript = #"""
#!/usr/bin/perl
# Copyright (c) 2025 Jonas van den Berg
# This file is licensed under the BSD 3-Clause License.

# For usage information read below or run the script without arguments.

use strict;
use warnings;
use DynaLoader;
use File::Spec;
use File::Basename;

sub print_help() {
  print <<'HELP';
Usage:
  mediaremote-adapter.pl FRAMEWORK_PATH [TEST_CLIENT_PATH]
                         [FUNCTION [PARAMS|OPTIONS...]]

FRAMEWORK_PATH:
  Absolute path to the MediaRemoteAdapter.framework directory

TEST_CLIENT_PATH: (optional)
  Absolute path to the MediaRemoteAdapterTestClient executable. Only for "test"

FUNCTION:
  stream   Streams now playing information (as diff by default)
  get      Prints now playing information once with all available metadata
  send     Sends a command to the now playing application
  seek     Seeks to a specific timeline position
  shuffle  Sets the shuffle mode
  repeat   Sets the repeat mode
  speed    Sets the playback speed
  test     Tests if the adapter is entitled to use the MediaRemote framework.
           An exit code other than 0 indicates the adapter is non-functional

PARAMS:
  send(command)
    command: The MRCommand ID as a number (e.g. kMRPlay = 0)
  seek(position)
    position: The timeline position in microseconds
  shuffle(mode)
    mode: The shuffle mode
  repeat(mode)
    mode: The repeat mode
  speed(speed)
    speed: The playback speed

OPTIONS:
  get
    --now: Adds an "elapsedTimeNow" key with an estimation of the current
      elapsed playback time. This estimation may be off by up to a second.
      To determine a more accurate time without polling "get" continuously,
      calculate it using the "elapsedTime" and "timestamp" keys. "elapsedTime"
      contains the elapsed time at the time that is stored in "timestamp".
  stream
    --no-diff: Disable diffing and always dump all metadata
    --debounce=N: Delay in milliseconds to prevent spam (0 by default)
  get, stream
    --micros: Replaces the following time keys with microsecond equivalents:
      "duration" -> "durationMicros"
      "elapsedTime" -> "elapsedTimeMicros"
      "elapsedTimeNow" -> "elapsedTimeNowMicros"
      "timestamp" -> "timestampEpochMicros" (converted to epoch time)
    --no-artwork: Omits "artworkData" and "artworkMimeType" from the payload.
      Useful for consumers that do not render artwork, since this avoids
      emitting several hundred kilobytes of base64 data per update.
    --allow-missing-title: By default, media with a null or absent title is
      ignored. This flag leads to media with a null or absent title being
      emitted. The consumer needs to explicitly handle the possibility of the
      title being null or absent.
    --human-readable, -h: Makes values human-readable. Use only for debugging.
      The JSON output is pretty-printed and the following keys are adapted:
      "artworkData" -> Binary data is truncated to a shorter representation

Examples (script name and framework path omitted):
  stream --no-diff --debounce=100
  send 2    # Toggles play/pause in the media player (kMRATogglePlayPause)
  repeat 3  # Sets the repeat mode to "playlist" (kMRARepeatModePlaylist)

HELP
  exit 0;
}

if (!defined $ARGV[1]) {
  print_help();
}

sub fail {
  my ($error) = @_;
  print STDERR "$error\n";
  exit 1;
}

fail "Framework path not provided" unless @ARGV >= 1;

my $framework_path = shift @ARGV;

# Optionally accept MEDIAREMOTEADAPTER_TEST_CLIENT_PATH path as second argument
my $maybe_helper_path = $ARGV[0] // '';
if ($maybe_helper_path =~ m{/}){
  my $helper_path = shift @ARGV;
  $ENV{MEDIAREMOTEADAPTER_TEST_CLIENT_PATH} = $helper_path;
}

if (!defined $ARGV[0]) {
  print_help();
}

my $framework_basename = File::Basename::basename($framework_path);
fail "Provided path is not a framework: $framework_path"
  unless $framework_basename =~ s/\.framework$//;

my $framework = File::Spec->catfile($framework_path, $framework_basename);
fail "Framework not found at $framework" unless -e $framework;

my $handle = DynaLoader::dl_load_file($framework, 0)
  or fail "Failed to load framework: $framework";
my $function_name = shift @ARGV or fail "Missing function name";
fail "Invalid function name: '$function_name'"
  unless $function_name eq "stream"
  || $function_name eq "get"
  || $function_name eq "send"
  || $function_name eq "seek"
  || $function_name eq "shuffle"
  || $function_name eq "repeat"
  || $function_name eq "speed"
  || $function_name eq "test";

sub parse_options {
  my ($start_index) = @_;
  my %arg_map;
  my $i = $start_index;
  while ($i <= $#ARGV) {
    my $arg = $ARGV[$i];
    if ($arg =~ /^--([a-z:\.\\-]+)(?:=(.*))?$/) {
      my $key = $1;
      my $value = defined $2 ? $2 : undef;
      $arg_map{$key} = $value;
      splice @ARGV, $i, 1;
    }
    elsif ($arg =~ /^-([a-zA-Z]+)$/) {
      my @flags = split //, $1;
      $arg_map{$_} = undef for @flags;
      splice @ARGV, $i, 1;
    }
    else {
      $i++;
    }
  }
  return \%arg_map;
}

sub env_func {
  my $symbol_name = shift;
  return "${symbol_name}_env";
}

sub set_env_param {
  my ($func, $index, $name, $value) = @_;
  $ENV{"MEDIAREMOTEADAPTER_PARAM_${func}_${index}_${name}"} = "$value";
}

sub set_env_option_unsafe {
  my ($name, $value) = @_;
  $name =~ s/-/_/g;
  $ENV{"MEDIAREMOTEADAPTER_OPTION_${name}"} = defined $value ? "$value" : "";
}

sub set_env_option {
  my ($options, $key) = @_;
  my $value = $options->{$key};
  if (defined $value) {
    fail "Unexpected value for option '$key'";
  }
  set_env_option_unsafe($key, $value);
}

sub set_env_option_value {
  my ($options, $key) = @_;
  my $value = $options->{$key};
  if (!defined $value) {
    fail "Missing value for option '$key'";
  }
  set_env_option_unsafe($key, $value);
}

my $symbol_name = "adapter_$function_name";
if ($function_name eq "send") {
  my $id = shift @ARGV;
  fail "Missing ID for '$function_name' command" unless defined $id;
  set_env_param($symbol_name, 0, "command", "$id");
  $symbol_name = env_func($symbol_name);
}
elsif ($function_name eq "stream") {
  my $options = parse_options(0);
  foreach my $key (keys %{$options}) {
    if ($key eq "no-diff") {
      set_env_option($options, $key);
    }
    elsif ($key eq "debounce") {
      set_env_option_value($options, $key);
    }
    elsif ($key eq "micros") {
      set_env_option($options, $key);
    }
    elsif ($key eq "no-artwork") {
      set_env_option($options, $key);
    }
    elsif ($key eq "allow-missing-title") {
      set_env_option($options, $key);
    }
    elsif ($key eq "human-readable" || $key eq "h") {
      set_env_option($options, "human-readable");
    }
    elsif ($key eq "experimental-peculiar-debounce:com.tidal.desktop") {
      set_env_option_value($options, $key);
    }
    else {
      fail "Unrecognized option '$key'";
    }
  }
  $symbol_name = env_func($symbol_name);
}
elsif ($function_name eq "get") {
  my $options = parse_options(0);
  foreach my $key (keys %{$options}) {
    if ($key eq "micros") {
      set_env_option($options, $key);
    }
    elsif ($key eq "no-artwork") {
      set_env_option($options, $key);
    }
    elsif ($key eq "allow-missing-title") {
      set_env_option($options, $key);
    }
    elsif ($key eq "human-readable" || $key eq "h") {
      set_env_option($options, "human-readable");
    }
    elsif ($key eq "now") {
      set_env_option($options, $key);
    }
    else {
      fail "Unrecognized option '$key'";
    }
  }
  $symbol_name = env_func($symbol_name);
}
elsif ($function_name eq "seek") {
  my $position = shift @ARGV;
  fail "Missing position for '$function_name' command" unless defined $position;
  set_env_param($symbol_name, 0, "position", "$position");
  $symbol_name = env_func($symbol_name);
}
elsif ($function_name eq "shuffle") {
  my $mode = shift @ARGV;
  fail "Missing mode for '$function_name' command" unless defined $mode;
  set_env_param($symbol_name, 0, "mode", "$mode");
  $symbol_name = env_func($symbol_name);
}
elsif ($function_name eq "repeat") {
  my $mode = shift @ARGV;
  fail "Missing mode for '$function_name' command" unless defined $mode;
  set_env_param($symbol_name, 0, "mode", "$mode");
  $symbol_name = env_func($symbol_name);
}
elsif ($function_name eq "speed") {
  my $speed = shift @ARGV;
  fail "Missing speed for '$function_name' command" unless defined $speed;
  set_env_param($symbol_name, 0, "speed", "$speed");
  $symbol_name = env_func($symbol_name);
}
elsif ($function_name eq "test") {
  $symbol_name = "adapter_test";
}

if (defined shift @ARGV) {
  fail "Too many arguments";
}

my $symbol = DynaLoader::dl_find_symbol($handle, "$symbol_name")
  or fail "Symbol '$symbol_name' not found in $framework";
DynaLoader::dl_install_xsub("main::$function_name", $symbol);

eval {
  no strict "refs";
  &{"main::$function_name"}();
};
if ($@) {
  fail "Error executing $function_name: $@";
}
"""#
