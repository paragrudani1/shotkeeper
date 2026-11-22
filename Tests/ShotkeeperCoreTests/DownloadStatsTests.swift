import XCTest
@testable import ShotkeeperCore

final class DownloadStatsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let gb: Int64 = 1_000_000_000

    func testBytesSpeedAndTimeLeft() {
        var stats = DownloadStats(totalBytes: 9_100_000_000)
        XCTAssertEqual(stats.bytesText, "0 MB of 9.1 GB")
        XCTAssertNil(stats.speedText)
        XCTAssertNil(stats.timeLeftText)
        XCTAssertEqual(stats.summary, "0 MB of 9.1 GB")

        stats.record(bytes: 4_000_000_000, at: start)
        stats.record(bytes: 4_100_000_000, at: start.addingTimeInterval(10))  // 10 MB/s
        XCTAssertEqual(stats.bytesText, "4.1 of 9.1 GB")
        XCTAssertEqual(stats.speedText, "10.0 MB/s")
        XCTAssertEqual(stats.secondsRemaining, 500)
        XCTAssertEqual(stats.timeLeftText, "About 8 min left")
        XCTAssertEqual(stats.summary, "4.1 of 9.1 GB · 10.0 MB/s · About 8 min left")
    }

    func testSmallAmountsAndSlowSpeeds() {
        var stats = DownloadStats(totalBytes: 10_400_000_000)
        stats.record(bytes: 0, at: start)
        stats.record(bytes: 350_000_000, at: start.addingTimeInterval(400))  // 875 KB/s
        XCTAssertEqual(stats.bytesText, "350 MB of 10.4 GB")
        XCTAssertEqual(stats.speedText, "875 KB/s")
        XCTAssertEqual(stats.timeLeftText, "About 3 h 11 min left")
    }

    func testSpeedFollowsTheLastSecondsNotTheAverage() {
        var stats = DownloadStats(totalBytes: 10 * gb, window: 10)
        stats.record(bytes: 0, at: start)
        stats.record(bytes: 2 * gb, at: start.addingTimeInterval(20))        // fast at first: 100 MB/s
        for second in 21...40 {                                              // then 1 MB/s
            stats.record(bytes: 2 * gb + Int64(second - 20) * 1_000_000, at: start.addingTimeInterval(Double(second)))
        }
        XCTAssertEqual(stats.bytesPerSecond ?? 0, 1_000_000, accuracy: 1)
        XCTAssertLessThanOrEqual(stats.samples.count, 12)
    }

    func testStallsRestartsAndTheEnd() {
        var stats = DownloadStats(totalBytes: 2 * gb)
        stats.record(bytes: gb, at: start)
        stats.record(bytes: gb, at: start.addingTimeInterval(5))
        XCTAssertEqual(stats.timeLeftText, "Stalled")
        XCTAssertNil(stats.secondsRemaining)

        stats.record(bytes: 100_000_000, at: start.addingTimeInterval(6))   // fewer bytes: measured again
        XCTAssertNil(stats.bytesPerSecond)
        stats.record(bytes: 1_999_000_000, at: start.addingTimeInterval(16))
        XCTAssertEqual(stats.timeLeftText, "Less than a minute left")
        stats.record(bytes: 3 * gb, at: start.addingTimeInterval(17))        // more than the catalog size
        XCTAssertTrue(stats.exceedsEstimate)
        XCTAssertEqual(stats.bytesText, "3.0 GB so far")
        XCTAssertNil(stats.secondsRemaining, "no time left once the estimate was too low")
        XCTAssertNil(stats.timeLeftText)
        XCTAssertTrue(stats.summary.hasPrefix("3.0 GB so far · "), stats.summary)
    }

    func testLongDownloadsReadInHours() {
        var stats = DownloadStats(totalBytes: 17_300_000_000)
        stats.record(bytes: 0, at: start)
        stats.record(bytes: 2_400_000, at: start.addingTimeInterval(1))       // 2.4 MB/s → 2 h
        XCTAssertEqual(stats.timeLeftText, "About 2 h left")
    }

    func testDiskCheckNeedsTheRestOfTheDownloadTheRuntimeAndAMargin() {
        let needed = 10_400_000_000 + DiskSpaceCheck.runtimeEnvironmentBytes + DiskSpaceCheck.safetyMarginBytes
        XCTAssertEqual(DiskSpaceCheck.evaluate(availableBytes: needed, downloadBytes: 10_400_000_000, alreadyOnDisk: 0,
                                               needsRuntime: true), .enough)
        let short = DiskSpaceCheck.evaluate(availableBytes: 6_200_000_000, downloadBytes: 10_400_000_000,
                                            alreadyOnDisk: 0, needsRuntime: true)
        XCTAssertEqual(short, .notEnough(neededBytes: needed, availableBytes: 6_200_000_000))
        XCTAssertEqual(short.message, "Not enough disk space: the download needs about 13.4 GB free, and this Mac has "
                       + "6.2 GB. Free up 7.2 GB and try again.")
        XCTAssertNil(DiskSpaceCheck.Verdict.enough.message)

        // A resumed download needs only what is missing; an installed runtime needs nothing more.
        XCTAssertEqual(DiskSpaceCheck.evaluate(availableBytes: 6_200_000_000, downloadBytes: 10_400_000_000,
                                               alreadyOnDisk: 6_500_000_000, needsRuntime: false), .enough)
        // Free space unknown: allowed (hf download fails cleanly on a full disk).
        XCTAssertEqual(DiskSpaceCheck.evaluate(availableBytes: nil, downloadBytes: 10_400_000_000, alreadyOnDisk: 0,
                                               needsRuntime: true), .enough)
    }
}
