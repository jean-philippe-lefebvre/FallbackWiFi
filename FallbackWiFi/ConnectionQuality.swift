import Foundation

struct ConnectionQuality: Equatable {
    let latencyMs: Double?
    let jitterMs: Double?
    let packetLossPercent: Double?
    let downloadMbps: Double?
    let measuredAt: Date

    var summary: String {
        let latency = latencyMs.map { "\(Int($0.rounded())) ms" } ?? "ping n/a"
        let packetLoss = packetLossPercent.map { String(format: "%.0f pct loss", $0) } ?? "loss n/a"
        let jitter = jitterMs.map { "\(Int($0.rounded())) ms jitter" } ?? "jitter n/a"
        let download = downloadMbps.map { String(format: "%.1f Mbps", $0) }
        return ([latency, packetLoss, jitter] + (download.map { [$0] } ?? [])).joined(separator: ", ")
    }

    func isPoor(maximumLatencyMs: Double, minimumDownloadMbps: Double) -> Bool {
        if isLightPoor(maximumLatencyMs: maximumLatencyMs) {
            return true
        }

        if downloadMbps != nil {
            return isSpeedPoor(minimumDownloadMbps: minimumDownloadMbps)
        }

        return false
    }

    func isLightPoor(maximumLatencyMs: Double) -> Bool {
        if latencyMs == nil, jitterMs == nil, packetLossPercent == nil {
            return true
        }

        if let latencyMs, latencyMs > maximumLatencyMs {
            return true
        }

        if let jitterMs, jitterMs > max(150, maximumLatencyMs / 2) {
            return true
        }

        if let packetLossPercent, packetLossPercent >= 20 {
            return true
        }

        return false
    }

    func isSpeedPoor(minimumDownloadMbps: Double) -> Bool {
        guard let downloadMbps else { return true }
        return downloadMbps < minimumDownloadMbps
    }

    func addingSpeed(from quality: ConnectionQuality) -> ConnectionQuality {
        ConnectionQuality(
            latencyMs: latencyMs,
            jitterMs: jitterMs,
            packetLossPercent: packetLossPercent,
            downloadMbps: quality.downloadMbps,
            measuredAt: quality.measuredAt
        )
    }
}

protocol ConnectionQualityChecking: Sendable {
    func measureLight() async -> ConnectionQuality
    func measureSpeed() async -> ConnectionQuality
    func measureFull() async -> ConnectionQuality
}

struct HTTPConnectionQualityChecker: ConnectionQualityChecking {
    func measureLight() async -> ConnectionQuality {
        let ping = await pingMetrics()
        return ConnectionQuality(
            latencyMs: ping.latencyMs,
            jitterMs: ping.jitterMs,
            packetLossPercent: ping.packetLossPercent,
            downloadMbps: nil,
            measuredAt: Date()
        )
    }

    func measureSpeed() async -> ConnectionQuality {
        ConnectionQuality(
            latencyMs: nil,
            jitterMs: nil,
            packetLossPercent: nil,
            downloadMbps: await downloadSpeed(),
            measuredAt: Date()
        )
    }

    func measureFull() async -> ConnectionQuality {
        async let light = measureLight()
        async let download = downloadSpeed()
        let lightQuality = await light

        return await ConnectionQuality(
            latencyMs: lightQuality.latencyMs,
            jitterMs: lightQuality.jitterMs,
            packetLossPercent: lightQuality.packetLossPercent,
            downloadMbps: download,
            measuredAt: Date()
        )
    }

    private func pingMetrics() async -> (latencyMs: Double?, jitterMs: Double?, packetLossPercent: Double?) {
        let result = await ShellCommand.run("/sbin/ping", ["-c", "5", "-W", "1000", "1.1.1.1"])
        guard result.exitCode == 0 || !result.standardOutput.isEmpty else {
            return (nil, nil, nil)
        }

        let loss = packetLossPercent(from: result.standardOutput)
        guard let statsLine = result.standardOutput
            .split(separator: "\n")
            .first(where: { $0.contains("round-trip") || $0.contains("min/avg/max") }),
            let values = statsLine.split(separator: "=").last
        else {
            return (nil, nil, loss)
        }

        let parts = values
            .replacingOccurrences(of: "ms", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")

        let latency = parts.count >= 2 ? Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) : nil
        let jitter = parts.count >= 4 ? Double(parts[3].trimmingCharacters(in: .whitespacesAndNewlines)) : nil
        return (latency, jitter, loss)
    }

    private func packetLossPercent(from output: String) -> Double? {
        guard let line = output
            .split(separator: "\n")
            .first(where: { $0.localizedCaseInsensitiveContains("packet loss") })
        else {
            return nil
        }

        return line
            .split(separator: ",")
            .compactMap { part -> Double? in
                guard part.localizedCaseInsensitiveContains("packet loss") else { return nil }
                let cleaned = part
                    .replacingOccurrences(of: "%", with: "")
                    .replacingOccurrences(of: "packet loss", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return Double(cleaned)
            }
            .first
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
