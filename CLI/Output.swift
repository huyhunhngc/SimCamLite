import Foundation

enum Output {
    static func json<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }

    /// Prints rows as left-aligned columns separated by two spaces.
    static func table(_ rows: [[String]], header: [String]? = nil) {
        let all = (header.map { [$0] } ?? []) + rows
        guard let columns = all.map(\.count).max() else { return }
        let widths = (0..<columns).map { column in all.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0 }
        for row in all {
            let cells = row.enumerated().map { index, cell in
                index == row.count - 1 ? cell : cell.padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }
            print(cells.joined(separator: "  "))
        }
    }

    static func message(_ response: ControlResponse) {
        if let message = response.message { print(message) }
    }

    static func status(_ status: StatusSnapshot) {
        let state = status.streaming ? "● streaming \(status.fps) fps" : "○ stopped (\(status.fps) fps)"
        print("SimCamLite  \(state) · profile \(status.profile)")
        print("Back        \(describe(status.back))")
        print("Front       \(status.frontFollowsBack ? "follows back" : describe(status.front))")
        var notes: [String] = []
        if !status.injectInstalled { notes.append("inject library missing") }
        if !status.sharedMemoryReady { notes.append("shared memory unavailable") }
        print("Inject      \(notes.isEmpty ? "installed" : notes.joined(separator: ", "))")
        if status.clients.isEmpty {
            print("Clients     none")
        } else {
            print("Clients")
            table(status.clients.map {
                ["  \($0.pid)", $0.processName, $0.bundleID, $0.camera, "\($0.frames) frames", "\($0.photos) photos"]
            })
        }
    }

    private static func describe(_ stream: StreamSnapshot) -> String {
        var parts = [kindTitle(stream.kind), stream.filePath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? stream.title]
        var options = [stream.fill ? "fill" : "fit"]
        if stream.rotation != 0 { options.append("rotate \(stream.rotation * 90)°") }
        if stream.mirror { options.append("mirror") }
        if stream.paused { options.append("paused") }
        parts.append("(\(options.joined(separator: ", ")))")
        if let error = stream.error { parts.append("⚠︎ \(error)") }
        return parts.joined(separator: "  ")
    }

    private static func kindTitle(_ kind: String) -> String {
        switch kind {
        case "testPattern": "pattern"
        case "macCamera": "camera"
        case "qrCode": "qr"
        default: kind
        }
    }
}
