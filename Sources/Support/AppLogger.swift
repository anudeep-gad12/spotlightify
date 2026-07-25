import Foundation

final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    private let queue = DispatchQueue(label: "app.spotlightify.logger")
    private let timestampFormatter = ISO8601DateFormatter()
    private var fileURL: URL?

    private init() {
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func configure(logFileURL: URL) {
        queue.sync {
            guard fileURL == nil else { return }
            fileURL = logFileURL
            try? FileManager.default.createDirectory(
                at: logFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )

            let header = "\n=== Spotlightify launch \(timestampFormatter.string(from: Date())) ===\n"
            append(header, to: logFileURL)
        }
    }

    func log(_ message: String, category: String = "app", file: StaticString = #fileID, line: Int = #line) {
        let fileName = String(describing: file)
        let isMainThread = Thread.isMainThread ? "main" : "background"

        queue.async { [weak self] in
            guard let self, let fileURL = self.fileURL else { return }
            let timestamp = self.timestampFormatter.string(from: Date())
            let entry = "[\(timestamp)] [\(category)] [\(isMainThread)] \(fileName):\(line) \(message)\n"
            self.append(entry, to: fileURL)
        }
    }

    func logFilePath() -> String? {
        queue.sync {
            fileURL?.path
        }
    }

    private func append(_ string: String, to url: URL) {
        let data = Data(string.utf8)

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: data, attributes: nil)
            return
        }

        do {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            fputs("Spotlightify logger write failed: \(error)\n", stderr)
        }
    }
}
