import Foundation

public enum SecureFile {
    /// Write data to a file with 0600 (owner read/write only) permissions.
    public static func write(_ data: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent().path
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: dir, isDirectory: &isDir) {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        try data.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
}
