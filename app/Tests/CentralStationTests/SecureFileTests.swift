import Foundation
import Testing
@testable import CentralStationCore

@Suite("SecureFile")
struct SecureFileTests {

    @Test func writesWithRestrictedPermissions() throws {
        let path = NSTemporaryDirectory() + "secure-test-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let data = Data("test".utf8)
        try SecureFile.write(data, to: path)

        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let perms = attrs[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test func writesCorrectContent() throws {
        let path = NSTemporaryDirectory() + "secure-test-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let original = Data("{\"key\":\"value\"}".utf8)
        try SecureFile.write(original, to: path)

        let readBack = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(readBack == original)
    }

    @Test func overwritesExistingFile() throws {
        let path = NSTemporaryDirectory() + "secure-test-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let first = Data("first".utf8)
        try SecureFile.write(first, to: path)

        let second = Data("second".utf8)
        try SecureFile.write(second, to: path)

        let readBack = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(readBack == second)
    }

    @Test func createsParentDirectoryIfNeeded() throws {
        let dir = NSTemporaryDirectory() + "secure-test-\(UUID().uuidString)"
        let path = dir + "/nested/file.json"
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let data = Data("nested".utf8)
        try SecureFile.write(data, to: path)

        let readBack = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(readBack == data)

        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let perms = attrs[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }
}
