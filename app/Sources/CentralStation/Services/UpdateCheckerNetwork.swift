import Foundation
import CentralStationCore

extension UpdateChecker {
    private static let releasesURL = "https://api.github.com/repos/jgodwin-ai/central-station/releases/latest"

    public static func check() async -> UpdateInfo? {
        guard let url = URL(string: releasesURL) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            return nil
        }

        return parseRelease(data: data)
    }
}
