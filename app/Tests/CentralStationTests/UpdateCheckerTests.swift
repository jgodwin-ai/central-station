import Testing
import Foundation
@testable import CentralStationCore

@Suite("Version comparison")
struct UpdateCheckerTests {
    @Test func newerMajor() {
        #expect(UpdateChecker.isNewer(remote: "2.0.0", local: "1.0.0"))
    }

    @Test func newerMinor() {
        #expect(UpdateChecker.isNewer(remote: "1.1.0", local: "1.0.0"))
    }

    @Test func newerPatch() {
        #expect(UpdateChecker.isNewer(remote: "1.0.1", local: "1.0.0"))
    }

    @Test func sameVersion() {
        #expect(!UpdateChecker.isNewer(remote: "1.0.0", local: "1.0.0"))
    }

    @Test func olderVersion() {
        #expect(!UpdateChecker.isNewer(remote: "0.9.0", local: "1.0.0"))
    }

    @Test func mismatchedSegments() {
        #expect(UpdateChecker.isNewer(remote: "1.0.0.1", local: "1.0.0"))
        #expect(!UpdateChecker.isNewer(remote: "1.0", local: "1.0.0"))
    }

    // MARK: - Release decoding

    @Test func decodeRelease() throws {
        let json = """
        {"tag_name": "v1.2.3", "html_url": "https://github.com/example/releases/v1.2.3"}
        """
        let data = json.data(using: .utf8)!
        let release = try JSONDecoder().decode(UpdateChecker.Release.self, from: data)
        #expect(release.tag_name == "v1.2.3")
        #expect(release.html_url == "https://github.com/example/releases/v1.2.3")
    }

    @Test func decodeReleaseIgnoresExtraFields() throws {
        let json = """
        {"tag_name": "v2.0.0", "html_url": "https://example.com", "draft": false, "prerelease": true}
        """
        let data = json.data(using: .utf8)!
        let release = try JSONDecoder().decode(UpdateChecker.Release.self, from: data)
        #expect(release.tag_name == "v2.0.0")
    }

    // MARK: - UpdateInfo

    @Test func updateInfoProperties() {
        let info = UpdateChecker.UpdateInfo(version: "3.1.0", url: "https://example.com/release")
        #expect(info.version == "3.1.0")
        #expect(info.url == "https://example.com/release")
    }

    // MARK: - currentVersion

    @Test func currentVersionIsSemver() {
        let parts = UpdateChecker.currentVersion.split(separator: ".")
        #expect(parts.count == 3)
        for part in parts {
            #expect(Int(part) != nil)
        }
    }

    // MARK: - parseRelease

    @Test func parseReleaseNewerVersion() {
        let json = """
        {"tag_name": "v99.0.0", "html_url": "https://github.com/example/releases/v99.0.0"}
        """
        let result = UpdateChecker.parseRelease(data: json.data(using: .utf8)!)
        #expect(result != nil)
        #expect(result?.version == "99.0.0")
        #expect(result?.url == "https://github.com/example/releases/v99.0.0")
    }

    @Test func parseReleaseOlderVersion() {
        let json = """
        {"tag_name": "v0.0.1", "html_url": "https://example.com"}
        """
        let result = UpdateChecker.parseRelease(data: json.data(using: .utf8)!)
        #expect(result == nil)
    }

    @Test func parseReleaseSameVersion() {
        let json = """
        {"tag_name": "v\(UpdateChecker.currentVersion)", "html_url": "https://example.com"}
        """
        let result = UpdateChecker.parseRelease(data: json.data(using: .utf8)!)
        #expect(result == nil)
    }

    @Test func parseReleaseInvalidJSON() {
        let result = UpdateChecker.parseRelease(data: "not json".data(using: .utf8)!)
        #expect(result == nil)
    }

    @Test func parseReleaseStripsVPrefix() {
        let json = """
        {"tag_name": "v99.1.2", "html_url": "https://example.com"}
        """
        let result = UpdateChecker.parseRelease(data: json.data(using: .utf8)!)
        #expect(result?.version == "99.1.2")
    }
}
