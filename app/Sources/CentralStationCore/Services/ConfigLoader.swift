import Foundation
import Yams

public enum ConfigLoader {
    public static func load(from path: String) throws -> ProjectConfig {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let content = try String(contentsOf: url, encoding: .utf8)

        if path.hasSuffix(".yaml") || path.hasSuffix(".yml") {
            return try YAMLDecoder().decode(ProjectConfig.self, from: content)
        } else {
            let data = content.data(using: .utf8)!
            return try JSONDecoder().decode(ProjectConfig.self, from: data)
        }
    }
}
