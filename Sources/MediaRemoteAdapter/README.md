# MediaRemoteAdapter (vendored)

[ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) at
797729d, BSD 3-Clause (see LICENSE), unmodified sources: `include/` and `src/` of
the upstream repository (`src/` flattened here), without the `test` command
(`src/adapter/test.m` needs the separate test client, not shipped).

Since macOS 15.4 only entitled processes get now playing information from the
MediaRemote framework. `/usr/bin/perl` is one: it loads this library and prints the
now playing state as JSON (the upstream `bin/mediaremote-adapter.pl` script, embedded
in `../skyland-cyberdeck/Audio/MediaRemote.swift`). SwiftPM builds it as
`libMediaRemoteAdapter.dylib` next to `skyland-cyberdeck`; it is bundled, not linked:
the audio deck copies it into `~/Library/Caches/skyland-cyberdeck/` as the
`MediaRemoteAdapter.framework` the script expects.
