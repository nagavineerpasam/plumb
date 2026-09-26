import XCTest
import WritingSignalsCore

final class AppUpdateTests: XCTestCase {
    func testVersionsCompareNumerically() throws {
        let v = { (s: String) in try XCTUnwrap(AppVersion(s)) }
        XCTAssertLessThan(try v("0.2.0"), try v("0.2.1"))
        XCTAssertLessThan(try v("0.2.1"), try v("0.10.0"), "10 is more than 2, not less")
        XCTAssertEqual(try v("v0.2.0"), try v("0.2.0"), "a leading v is ignored")
        XCTAssertEqual(try v("0.2"), try v("0.2.0"))
        XCTAssertFalse(try v("0.2.0") < v("0.2.0"))
        XCTAssertNil(AppVersion("models-v1"), "not an app release")
    }

    func testReadsTheVersionAndWhatsNewFromAGitHubRelease() throws {
        let json = #"{"tag_name":"v0.2.0","name":"Plumb 0.2.0","body":"Plumb now updates itself.\r\n\r\n- Update from inside the app\r\n* A proper Settings window\r\n- Friendlier score messages\r\n- Fourth thing"}"#
        let release = try XCTUnwrap(ReleaseInfo.parse(Data(json.utf8)))

        XCTAssertEqual(release.tag, "v0.2.0")
        XCTAssertEqual(release.version, AppVersion("0.2.0"))
        XCTAssertEqual(release.highlights, ["Update from inside the app", "A proper Settings window", "Friendlier score messages"])
    }

    func testAReleaseWithoutBulletsStillSaysSomething() throws {
        let release = try XCTUnwrap(ReleaseInfo.parse(Data(#"{"tag_name":"v0.3.0","body":""}"#.utf8)))
        XCTAssertEqual(release.highlights, ["Improvements and fixes."])
    }

    func testAFileMatchesOnlyItsOwnFingerprint() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("plumb".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let other = "9a1f5f0b6ea32b3d3f9f2b54f6c0b3ec9a0f5bd4f1e1b1a6d6b0f58e5e1bd8b4  Plumb.dmg"

        // `shasum -a 256` of "plumb"
        XCTAssertEqual(Fingerprint.sha256(of: file), "7b8a3f1af073c9b72ea0631011b870e4cd2938bede9fadadccdf876136c0bb1c")
        XCTAssertTrue(Fingerprint.matches(file, published: "7b8a3f1af073c9b72ea0631011b870e4cd2938bede9fadadccdf876136c0bb1c  Plumb.dmg\n"))
        XCTAssertFalse(Fingerprint.matches(file, published: other))
        XCTAssertFalse(Fingerprint.matches(file, published: ""))
    }
}
