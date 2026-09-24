import Foundation
import Network

final class AlpineStreamServer {
    private let runtime = AlpineRuntime.shared
    private let listener: NWListener
    private let command: [String]
    private let callback: Callback
    private var connection: NWConnection?
    private var process: AlpineProcess?

    init(command: [String], callback: Callback) throws {
        self.command = command
        self.callback = callback
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        listener = try NWListener(using: parameters)
    }

    func start() {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: callback.success(Int(listener.port!.rawValue))
            case .failed(let error): callback.error(error.localizedDescription); stop()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: runtime.queue)
    }

    func stop() {
        listener.cancel()
        connection?.cancel()
        if let process { runtime.stop(process.id) }
        process = nil
    }

    private func accept(_ connection: NWConnection) {
        guard self.connection == nil else { connection.cancel(); return }
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                do {
                    process = try runtime.start("exec " + command.map(shellQuote).joined(separator: " ") + " 2>&1")
                    process?.rawOutput = { [weak self] data in self?.send(data) }
                    process?.listener = { [weak self] kind, _ in if kind == "exit" { self?.stop() } }
                    receive()
                } catch { stop() }
            case .failed, .cancelled: stop()
            default: break
            }
        }
        connection.start(queue: runtime.queue)
    }

    private func receive() {
        connection?.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            if error != nil || metadata?.opcode == .close { stop(); return }
            if let data { try? process?.input.fileHandleForWriting.write(contentsOf: data) }
            receive()
        }
    }

    private func send(_ data: Data) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "stdout", metadata: [metadata])
        connection?.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.stop() }
        })
    }
}

func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
