@testable import skyland_cyberdeck
import Foundation
import XCTest

final class HudTests: XCTestCase {
    func testCpuUsage() {
        XCTAssertEqual(cpuUsage(from: CPUTicks(busy: 100, total: 1000), to: CPUTicks(busy: 150, total: 1100)), 0.5)
        XCTAssertNil(cpuUsage(from: CPUTicks(busy: 100, total: 1000), to: CPUTicks(busy: 100, total: 1000))) // no interval
        XCTAssertNil(cpuUsage(from: CPUTicks(busy: 100, total: 1000), to: CPUTicks(busy: 50, total: 1100))) // counter reset
    }

    func testRate() {
        XCTAssertEqual(rate(from: 1000, to: 3000, seconds: 2), 1000)
        XCTAssertNil(rate(from: 3000, to: 1000, seconds: 1)) // counter reset
        XCTAssertNil(rate(from: 0, to: 10, seconds: 0))
    }

    func testFormatBytes() {
        XCTAssertEqual(formatBytes(0), "0 B")
        XCTAssertEqual(formatBytes(1_234_567, perSecond: true), "1.2 MB/s")
        XCTAssertEqual(formatBytes(340_000), "340 KB")
        XCTAssertEqual(formatBytes(36 * 1024 * 1024 * 1024, binary: true), "36.0 GB")
        XCTAssertEqual(formatBytes(-5), "0 B")
    }

    func testHistoryKeepsTheLastValues() {
        var history = History(capacity: 3)
        for value in [1.0, 2, 3, 4] { history.append(value) }
        XCTAssertEqual(history.values, [2, 3, 4])
    }

    func testMonthGrid() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16))!
        // 1 October 2026 is a Thursday
        let monday = monthGrid(october, firstWeekday: 2, calendar: calendar)
        XCTAssertEqual(monday.prefix(3).filter { $0 == nil }.count, 3)
        XCTAssertEqual(monday[3].map { calendar.component(.day, from: $0) }, 1)
        XCTAssertEqual(monday.compactMap { $0 }.count, 31)
        XCTAssertEqual(monday.count % 7, 0)
        let sunday = monthGrid(october, firstWeekday: 1, calendar: calendar)
        XCTAssertEqual(sunday[4].map { calendar.component(.day, from: $0) }, 1)
        let february = calendar.date(from: DateComponents(year: 2028, month: 2, day: 1))! // leap year
        XCTAssertEqual(monthGrid(february, firstWeekday: 2, calendar: calendar).compactMap { $0 }.count, 29)
    }

    func testWidgetList() {
        XCTAssertEqual(parseWidgetList(" clock, HERDR,unknown,clock ,sound"), ["clock", "herdr", "sound"])
        XCTAssertEqual(parseWidgetList(""), [])
    }

    func testHerdrPanes() {
        let json = """
            {"id":"cli:pane:list","result":{"panes":[
              {"agent":"claude","agent_status":"working","terminal_title_stripped":"fix tests","cwd":"/a"},
              {"agent":"claude","agent_status":"idle","cwd":"/code/skyland"},
              {"agent":"codex","agent_status":"blocked","terminal_title_stripped":"permission"},
              {"agent_status":"idle","cwd":"/shell"}
            ]}}
            """
        let summary = parseHerdrPanes(Data(json.utf8))
        XCTAssertEqual(summary?.total, 3) // the shell pane has no agent
        XCTAssertEqual(summary?.running, 1)
        XCTAssertEqual(summary?.idle, 1)
        XCTAssertEqual(summary?.blocked, 1)
        XCTAssertEqual(summary?.agents[1].title, "skyland") // falls back to the folder
        XCTAssertNil(parseHerdrPanes(Data("not json".utf8)))
    }

    func testConfigParse() {
        let values = Config.parse("""
            [hud]
            widgets = "clock, system" # comment
            clock-24h = false
            refresh-ms = 2000
            [colors]
            primary = "#36f5ff"
            """)
        XCTAssertEqual(values["hud.widgets"], "clock, system")
        XCTAssertEqual(values["hud.clock-24h"], "false")
        XCTAssertEqual(values["hud.refresh-ms"], "2000")
        XCTAssertEqual(values["colors.primary"], "#36f5ff") // # inside quotes is not a comment
    }
}
