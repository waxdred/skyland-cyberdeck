@testable import skyland_cyberdeck
import Foundation
import XCTest

final class AudioDeckTests: XCTestCase {
    private func payload(_ json: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    }

    func testNowPlayingFromTheAdapter() {
        let info = NowPlaying(payload("""
            {"title":"Neon Rain","artist":"Case","album":"Sprawl","bundleIdentifier":"com.apple.WebKit.GPU",
             "parentApplicationBundleIdentifier":"com.apple.Safari","processIdentifier":4242,"playing":true,
             "durationMicros":215000000,"elapsedTimeMicros":12500000,"timestampEpochMicros":1760000000000000,
             "playbackRate":1,"trackNumber":3,"totalTrackCount":12,"artworkData":"AAEC"}
            """))
        XCTAssertEqual(info?.title, "Neon Rain")
        XCTAssertEqual(info?.artist, "Case")
        XCTAssertEqual(info?.bundleID, "com.apple.Safari") // the app, not its helper
        XCTAssertEqual(info?.pid, 4242)
        XCTAssertEqual(info?.playing, true)
        XCTAssertEqual(info?.duration, 215)
        XCTAssertEqual(info?.elapsed, 12.5)
        XCTAssertEqual(info?.track, 3)
        XCTAssertEqual(info?.tracks, 12)
        XCTAssertEqual(info?.artwork, Data([0, 1, 2]))
        XCTAssertEqual(NowPlaying(payload(#"{"title":"t","bundleIdentifier":"com.apple.Music"}"#))?.bundleID, "com.apple.Music")
        XCTAssertNil(NowPlaying(payload("{}"))) // nothing plays
        XCTAssertNil(NowPlaying(payload(#"{"title":""}"#)))
    }

    func testElapsedMovesOnWhilePlaying() {
        var info = NowPlaying(payload("""
            {"title":"t","playing":true,"durationMicros":100000000,"elapsedTimeMicros":10000000,"timestampEpochMicros":1000000000000000}
            """))!
        let start = Date(timeIntervalSince1970: 1_000_000_000)
        XCTAssertEqual(info.elapsed(at: start.addingTimeInterval(5))!, 15, accuracy: 0.001)
        XCTAssertEqual(info.elapsed(at: start.addingTimeInterval(500)), 100) // within the track
        info.rate = 2
        XCTAssertEqual(info.elapsed(at: start.addingTimeInterval(5))!, 20, accuracy: 0.001)
        info.playing = false
        XCTAssertEqual(info.elapsed(at: start.addingTimeInterval(5)), 10) // paused: stays
    }

    func testTheNowPlayingSourceComesFirst() {
        let music = AudioSource(id: 10, name: "Music", bundleID: "com.apple.Music", live: true)
        let safari = AudioSource(id: 20, name: "Safari", bundleID: "com.apple.Safari", live: true)
        let spotify = AudioSource(id: 30, name: "Spotify", bundleID: "com.spotify.client", live: false)
        XCTAssertEqual(AudioSources.merged([music, safari], nowPlaying: nil), [music, safari])
        // live on the bus: the live one, moved first
        XCTAssertEqual(AudioSources.merged([music, safari], nowPlaying: AudioSource(id: 20, name: "Safari", bundleID: "com.apple.Safari", live: false)), [safari, music])
        XCTAssertEqual(AudioSources.merged([music, safari], nowPlaying: AudioSource(id: 99, name: "Music", bundleID: "com.apple.Music", live: false)), [music, safari])
        // silent: added first, paused
        XCTAssertEqual(AudioSources.merged([music, safari], nowPlaying: spotify), [spotify, music, safari])
    }

    func testTimecode() {
        XCTAssertEqual(timecode(0), "00:00")
        XCTAssertEqual(timecode(65.9), "01:05")
        XCTAssertEqual(timecode(3600), "60:00")
        XCTAssertEqual(timecode(-3), "00:00")
    }
}

final class AudioSourceOwnerTests: XCTestCase {
    func testOutermostApp() {
        // a browser's helper belongs to the browser: the outermost .app of its path
        XCTAssertEqual(AudioSources.outermostApp("/Applications/Brave Browser.app/Contents/Frameworks/Brave Browser Framework.framework/Helpers/Brave Browser Helper.app/Contents/MacOS/Brave Browser Helper"), "/Applications/Brave Browser.app")
        XCTAssertEqual(AudioSources.outermostApp("/Applications/Spotify.app/Contents/MacOS/Spotify"), "/Applications/Spotify.app")
        XCTAssertNil(AudioSources.outermostApp("/usr/bin/afplay"))
    }
}
