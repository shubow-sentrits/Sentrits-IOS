import Darwin
import Foundation

final class DiscoveryListener: @unchecked Sendable {
    struct Message {
        let payload: DiscoveryInfo
        let sourceAddress: String
        let receivedAt: Date
    }

    var onMessage: ((Message) -> Void)?
    var onError: ((Error) -> Void)?

    private let port: UInt16
    private let queue = DispatchQueue(label: "com.vibeeverywhere.ios.discovery-listener")
    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?

    init(port: UInt16 = 18087) {
        self.port = port
    }

    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func startOnQueue() {
        guard socketFD == -1 else { return }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            publishError(DiscoveryListenerError.socketCreationFailed(errno))
            return
        }

        var reuseAddress: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseAddress, socklen_t(MemoryLayout.size(ofValue: reuseAddress)))
        var reusePort: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reusePort, socklen_t(MemoryLayout.size(ofValue: reusePort)))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port.bigEndian)
        address.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            let code = errno
            close(fd)
            publishError(DiscoveryListenerError.bindFailed(code))
            return
        }

        socketFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readAvailableMessages()
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.socketFD >= 0 else { return }
            close(self.socketFD)
            self.socketFD = -1
        }
        readSource = source
        source.resume()
    }

    private func stopOnQueue() {
        readSource?.cancel()
        readSource = nil
    }

    private func readAvailableMessages() {
        guard socketFD >= 0 else { return }

        while true {
            var buffer = [UInt8](repeating: 0, count: 65_535)
            var sourceAddress = sockaddr_in()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received = withUnsafeMutablePointer(to: &sourceAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(socketFD, &buffer, buffer.count, 0, $0, &sourceLength)
                }
            }

            if received < 0 {
                let code = errno
                if code == EWOULDBLOCK || code == EAGAIN {
                    return
                }
                publishError(DiscoveryListenerError.readFailed(code))
                return
            }

            if received == 0 {
                return
            }

            let data = Data(buffer.prefix(Int(received)))
            guard let payload = try? JSONDecoder().decode(DiscoveryInfo.self, from: data) else {
                continue
            }

            let source = String(cString: inet_ntoa(sourceAddress.sin_addr))
            let message = Message(payload: payload, sourceAddress: source, receivedAt: Date())
            let callback = onMessage
            DispatchQueue.main.async {
                callback?(message)
            }
        }
    }

    private func publishError(_ error: Error) {
        let callback = onError
        DispatchQueue.main.async {
            callback?(error)
        }
    }
}

enum DiscoveryListenerError: LocalizedError {
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case readFailed(Int32)

    var errorDescription: String? {
        switch self {
        case let .socketCreationFailed(code):
            return "Discovery listener socket creation failed (\(code))."
        case let .bindFailed(code):
            return "Discovery listener bind failed (\(code))."
        case let .readFailed(code):
            return "Discovery listener read failed (\(code))."
        }
    }
}
