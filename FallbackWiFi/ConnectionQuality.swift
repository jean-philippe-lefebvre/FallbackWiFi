import Foundation

struct ConnectionQuality: Equatable {
    let latencyMs: Double?
    let downloadMbps: Double?
    let measuredAt: Date

    var summary: String {
        let latency = latencyMs.map { "\(Int($0.rounded())) ms" } ?? "ping n/a"
        let download = downloadMbps.map { String(format: "%.1f Mbps", $0) } ?? "speed n/a"
        return "\(latency), \(download)"
    }

    func isPoor(maximumLatencyMs: Double, minimumDownloadMbps: Double) -> Bool {
        if let latencyMs, latencyMs > maximumLatencyMs {
            return true
        }

        if let downloadMbps, downloadMbps < minimumDownloadMbps {
            return true
        }

        return latencyMs == nil && downloadMbps == nil
    }
}

protocol ConnectionQualityChecking: Sendable {
    func measure() async -> ConnectionQuality
}

struct HTTPConnectionQualityChecker: ConnectionQualityChecking {
    func measure() async -> ConnectionQuality {
        async let latency = pingLatency()
        async let download = downloadSpeed()

        return await ConnectionQuality(
            latencyMs: latency,
            downloadMbps: download,
            measuredAt: Date()
        )
    }

    private func pingLatency() async -> Double? {
        let result = await ShellCommand.run("/sbin/ping", ["-c", "3", "-W", "1000", "1.1.1.1"])
        guard result.exitCode == 0 else { return nil }

        guard let line = result.standardOutput
            .split(separator: "\n")
            .first(where: { $0.contains("round-trip") || $0.contains("min/avg/max") }),
            let values = line.split(separator: "=").last
        else {
            return nil
        }

        let parts = values
            .replacingOccurrences(of: "ms", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")

        guard parts.count >= 2 else { return nil }
        return Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func downloadSpeed() async -> Double? {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=1000000") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let startedAt = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                return nil
            }

            let elapsed = Date().timeIntervalSince(startedAt)
            guard elapsed > 0, !data.isEmpty else { return nil }
            return Double(data.count * 8) / elapsed / 1_000_000
        } catch {
            return nil
        }
    }
}
