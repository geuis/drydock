import XCTest
@testable import Drydock

final class UpdateCheckerTests: XCTestCase {
    private let pageURL: URL = URL(string: "https://github.com/geuis/drydock/releases/tag/v0.2.0")!

    // MARK: - Version parsing

    func testParsesTagWithLeadingV() throws {
        let version: AppVersion = try XCTUnwrap(AppVersion("v0.2.0"))

        XCTAssertEqual(version.components, [0, 2, 0])
        XCTAssertEqual(version.description, "0.2.0")
    }

    func testIgnoresDevSuffix() throws {
        let version: AppVersion = try XCTUnwrap(AppVersion("0.0.0-dev"))

        XCTAssertEqual(version.components, [0, 0, 0])
    }

    func testRejectsUnreadableVersions() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("v"))
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertNil(AppVersion("1.2.x"))
    }

    // MARK: - Version comparison

    func testComparesEachPartAsANumber() throws {
        let older: AppVersion = try XCTUnwrap(AppVersion("0.9.0"))
        let newer: AppVersion = try XCTUnwrap(AppVersion("0.10.0"))

        XCTAssertLessThan(older, newer)
        XCTAssertFalse(newer < older)
    }

    func testMissingPartsCountAsZero() throws {
        let short: AppVersion = try XCTUnwrap(AppVersion("1.0"))
        let long: AppVersion = try XCTUnwrap(AppVersion("1.0.0"))

        XCTAssertEqual(short, long)
        XCTAssertFalse(short < long)
        XCTAssertFalse(long < short)
        XCTAssertLessThan(short, try XCTUnwrap(AppVersion("1.0.1")))
    }

    // MARK: - GitHub response

    func testDecodesGitHubLatestReleaseResponse() throws {
        // Trimmed from a real /releases/latest response; the extra fields must
        // be ignored.
        let json: Data = Data("""
        {
          "url": "https://api.github.com/repos/geuis/drydock/releases/1",
          "html_url": "https://github.com/geuis/drydock/releases/tag/v0.2.0",
          "tag_name": "v0.2.0",
          "name": "Drydock 0.2.0",
          "draft": false,
          "prerelease": false,
          "assets": []
        }
        """.utf8)

        let release: LatestRelease = try JSONDecoder().decode(LatestRelease.self, from: json)

        XCTAssertEqual(release.tagName, "v0.2.0")
        XCTAssertEqual(release.pageURL, pageURL)
    }

    // MARK: - Update decision

    @MainActor
    func testNewerReleaseIsOffered() throws {
        let release: LatestRelease = LatestRelease(tagName: "v0.2.0", pageURL: pageURL)
        let current: AppVersion = try XCTUnwrap(AppVersion("0.1.0"))
        let expected: AppVersion = try XCTUnwrap(AppVersion("0.2.0"))

        XCTAssertEqual(try UpdateChecker.evaluate(release, currentVersion: current), .updateAvailable(version: expected, pageURL: pageURL))
    }

    @MainActor
    func testSameOrOlderReleaseIsUpToDate() throws {
        let release: LatestRelease = LatestRelease(tagName: "v0.2.0", pageURL: pageURL)

        XCTAssertEqual(try UpdateChecker.evaluate(release, currentVersion: try XCTUnwrap(AppVersion("0.2.0"))), .upToDate)
        XCTAssertEqual(try UpdateChecker.evaluate(release, currentVersion: try XCTUnwrap(AppVersion("0.3.0"))), .upToDate)
    }

    @MainActor
    func testUnreadableReleaseTagThrows() throws {
        let release: LatestRelease = LatestRelease(tagName: "nightly", pageURL: pageURL)

        XCTAssertThrowsError(try UpdateChecker.evaluate(release, currentVersion: try XCTUnwrap(AppVersion("0.1.0"))))
    }
}
