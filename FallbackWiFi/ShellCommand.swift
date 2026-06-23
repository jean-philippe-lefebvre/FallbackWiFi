import Foundation

struct ShellResult {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

enum ShellCommand {
    static func run(_ executable: String, _ arguments: [String]) async -> ShellResult {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return ShellResult(exitCode: 127, standardOutput: "", standardError: error.localizedDescription)
            }

            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            return ShellResult(
                exitCode: process.terminationStatus,
                standardOutput: String(decoding: outputData, as: UTF8.self),
                standardError: String(decoding: errorData, as: UTF8.self)
            )
        }.value
    }
}
