import Darwin
import Foundation

/// Minimal AF_UNIX stream helpers shared by the app's control server and the `simcam` client.
enum ControlSocket {
    enum Failure: LocalizedError {
        case notRunning
        case system(String)
        case invalidReply

        var errorDescription: String? {
            switch self {
            case .notRunning: "SimCamLite is not running"
            case .system(let message): message
            case .invalidReply: "Invalid reply from SimCamLite"
            }
        }
    }

    static func send(_ request: ControlRequest, path: String = ControlPaths.socket, timeout: Int = 15) throws -> ControlResponse {
        let fd = try makeSocket()
        defer { close(fd) }
        var interval = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &interval, socklen_t(MemoryLayout<timeval>.size))
        let connected = try withAddress(path) { connect(fd, $0, $1) }
        guard connected == 0 else { throw Failure.notRunning }
        try write(try JSONEncoder().encode(request), to: fd)
        shutdown(fd, SHUT_WR)
        guard let response = try? JSONDecoder().decode(ControlResponse.self, from: try readAll(fd)) else {
            throw Failure.invalidReply
        }
        return response
    }

    static func isReachable(path: String = ControlPaths.socket) -> Bool {
        guard let fd = try? makeSocket() else { return false }
        defer { close(fd) }
        return (try? withAddress(path) { connect(fd, $0, $1) }) == 0
    }

    static func makeSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.system("socket: \(String(cString: strerror(errno)))") }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    static func withAddress<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) throws -> T {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw Failure.system("Socket path too long: \(path)") }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    static func write(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw Failure.system("write: \(String(cString: strerror(errno)))")
                }
                offset += written
            }
        }
    }

    static func readAll(_ fd: Int32, limit: Int = 4 << 20) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while data.count < limit {
            let count = read(fd, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw Failure.system("read: \(String(cString: strerror(errno)))")
            }
            data.append(buffer, count: count)
        }
        return data
    }
}
