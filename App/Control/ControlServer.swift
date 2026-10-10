import Darwin
import Foundation

/// Accepts `simcam` connections on the control socket and hands each request to the main actor.
final class ControlServer: @unchecked Sendable {
    typealias Handler = @MainActor (ControlRequest) async -> ControlResponse

    private let path: String
    private let handler: Handler
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "dev.ifateam.simcamlite.control", attributes: .concurrent)

    init(path: String = ControlPaths.socket, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    func start() throws {
        guard listenFD < 0 else { return }
        try FileManager.default.createDirectory(at: ControlPaths.directory, withIntermediateDirectories: true)
        if ControlSocket.isReachable(path: path) {
            throw ControlSocket.Failure.system("Another SimCamLite instance owns \(path)")
        }
        unlink(path)
        let fd = try ControlSocket.makeSocket()
        let bound = try ControlSocket.withAddress(path) { bind(fd, $0, $1) }
        guard bound == 0, listen(fd, 16) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw ControlSocket.Failure.system("Control socket: \(message)")
        }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { close(fd) }
        source.resume()
        acceptSource = source
    }

    func stop() {
        guard listenFD >= 0 else { return }
        acceptSource?.cancel()
        acceptSource = nil
        listenFD = -1
        unlink(path)
    }

    private func acceptPending() {
        while true {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { return }
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            var interval = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
            queue.async { [handler] in Self.serve(client, handler: handler) }
        }
    }

    private static func serve(_ fd: Int32, handler: @escaping Handler) {
        let response: ControlResponse
        if let data = try? ControlSocket.readAll(fd, limit: 1 << 20),
           let request = try? JSONDecoder().decode(ControlRequest.self, from: data) {
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var result = ControlResponse.failure("No response")
            Task { @MainActor in
                result = await handler(request)
                semaphore.signal()
            }
            semaphore.wait()
            response = result
        } else {
            response = .failure("Malformed request")
        }
        if let data = try? JSONEncoder().encode(response) {
            try? ControlSocket.write(data, to: fd)
        }
        close(fd)
    }
}
