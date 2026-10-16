import AppKit
import CoreAudio

// The apps on the audio bus: CoreAudio's process objects (macOS 14.4+) say which
// processes output sound right now. Helpers (browser renderers, WebKit's audio
// service) count for the app they belong to.

struct AudioSource: Identifiable, Equatable {
    let id: pid_t // the app's pid
    let name: String
    let bundleID: String?
    var live: Bool // outputting sound now (else: the now playing app, paused)
}

enum AudioSources {
    /// Apps with a process outputting sound now, by name. Empty before macOS 14.4.
    static func live() -> [AudioSource] {
        guard #available(macOS 14.4, *) else { return [] }
        var apps: [pid_t: AudioSource] = [:]
        for process in processes() where process.running {
            guard let app = owner(of: process.pid, bundleID: process.bundleID) else { continue }
            apps[app.pid] = AudioSource(id: app.pid, name: app.name, bundleID: app.bundleID, live: true)
        }
        return apps.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The live sources with the now playing app (first, paused when it is silent).
    static func merged(_ live: [AudioSource], nowPlaying: AudioSource?) -> [AudioSource] {
        guard let nowPlaying else { return live }
        let current = live.first { $0.id == nowPlaying.id || ($0.bundleID != nil && $0.bundleID == nowPlaying.bundleID) }
        return [current ?? nowPlaying] + live.filter { $0.id != (current ?? nowPlaying).id }
    }

    @available(macOS 14.4, *)
    private static func processes() -> [(pid: pid_t, bundleID: String?, running: Bool)] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard let pid = int32(id, kAudioProcessPropertyPID) else { return nil }
            return (pid, string(id, kAudioProcessPropertyBundleID), (uint32(id, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0)
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func int32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Int32? {
        var where_ = address(selector)
        var value: Int32 = 0
        var size = UInt32(MemoryLayout<Int32>.size)
        return AudioObjectGetPropertyData(object, &where_, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var where_ = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &where_, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var where_ = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &where_, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    struct App: Equatable {
        let pid: pid_t
        let name: String
        let bundleID: String?
    }

    /// The app a process belongs to: itself or an ancestor known to LaunchServices; else
    /// the outermost .app of its executable path (an app started from a terminal or tmux
    /// is not in LaunchServices: NSRunningApplication does not see it, Brave included);
    /// WebKit's audio service (launched by launchd) is Safari's; a helper named after its
    /// app (com.google.Chrome.helper) is that app's.
    static func owner(of pid: pid_t, bundleID: String?) -> App? {
        var current = pid
        for _ in 0 ..< 6 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                return App(pid: app.processIdentifier, name: app.localizedName ?? app.bundleIdentifier ?? "?", bundleID: app.bundleIdentifier)
            }
            guard let parent = parentPID(current), parent > 1 else { break }
            current = parent
        }
        if let app = bundleOwner(of: pid) { return app }
        guard let bundleID else { return nil }
        let running = { (id: String) in
            NSRunningApplication.runningApplications(withBundleIdentifier: id).first { $0.activationPolicy == .regular }
                .map { App(pid: $0.processIdentifier, name: $0.localizedName ?? id, bundleID: id) }
        }
        if bundleID.hasPrefix("com.apple.WebKit") { return running("com.apple.Safari") }
        var parts = bundleID.split(separator: ".")
        while parts.count > 2 {
            parts.removeLast()
            if let app = running(parts.joined(separator: ".")) { return app }
        }
        return nil
    }

    /// From the executable path: the outermost `X.app` holding it, its name and bundle id;
    /// the app's pid is the ancestor running that bundle's executable (else `pid`).
    static func bundleOwner(of pid: pid_t) -> App? {
        guard let path = executablePath(pid), let app = outermostApp(path) else { return nil }
        let bundle = Bundle(url: URL(fileURLWithPath: app))
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent
        var owner = pid, current = pid
        for _ in 0 ..< 6 { // the main process: the ancestor whose executable is the bundle's own
            if let p = executablePath(current), p.hasPrefix(app + "/Contents/MacOS/") { owner = current; break }
            guard let parent = parentPID(current), parent > 1 else { break }
            current = parent
        }
        return App(pid: owner, name: name, bundleID: bundle?.bundleIdentifier)
    }

    /// "/Applications/Brave Browser.app/Contents/Frameworks/…/Helper.app/Contents/MacOS/x"
    /// -> "/Applications/Brave Browser.app"
    static func outermostApp(_ path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : nil
    }

    /// The app's icon: from LaunchServices, else from its bundle on disk (an app started
    /// from a terminal is not in LaunchServices).
    static func icon(of pid: pid_t) -> NSImage? {
        if let icon = NSRunningApplication(processIdentifier: pid)?.icon { return icon }
        return executablePath(pid).flatMap(outermostApp).map { NSWorkspace.shared.icon(forFile: $0) }
    }

    private static func parentPID(_ pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
