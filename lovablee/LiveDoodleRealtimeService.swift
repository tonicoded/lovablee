import Foundation
import Combine
import UIKit

/// Minimal Supabase Realtime listener for live_doodles inserts.
final class LiveDoodleRealtimeService: ObservableObject {
    private var webSocket: URLSessionWebSocketTask?
    private var listenCancellable: AnyCancellable?
    private let urlSession = URLSession(configuration: .default)
    private var currentRef = 0
    private var reconnectWorkItem: DispatchWorkItem?
    private var connectConfig: ConnectConfig?
    private var heartbeatTimer: Timer?
    private var coupleKey: String = ""
    private var myUserId: String = ""
    @Published var lastEventDescription: String = "idle"

    private struct ConnectConfig {
        let projectURL: URL
        let anonKey: String
        let accessToken: String
        let coupleKey: String
        let myUserId: String
        let onReceive: (LiveDoodle) -> Void
    }

    func connect(
        projectURL: URL,
        anonKey: String,
        accessToken: String,
        coupleKey: String,
        myUserId: String,
        onReceive: @escaping (LiveDoodle) -> Void
    ) {
        disconnect()
        self.coupleKey = coupleKey
        self.myUserId = myUserId
        connectConfig = ConnectConfig(
            projectURL: projectURL,
            anonKey: anonKey,
            accessToken: accessToken,
            coupleKey: coupleKey,
            myUserId: myUserId,
            onReceive: onReceive
        )
        DispatchQueue.main.async { [weak self] in
            self?.lastEventDescription = "connecting"
        }
        print("🔌 LiveDoodle RT: connecting socket for couple \(coupleKey) user \(myUserId)")

        guard var components = URLComponents(url: projectURL, resolvingAgainstBaseURL: false) else { return }
        components.scheme = projectURL.scheme == "https" ? "wss" : "ws"
        components.path = "/realtime/v1/websocket"
        components.queryItems = [
            URLQueryItem(name: "apikey", value: anonKey),
            URLQueryItem(name: "jwt", value: accessToken),
            URLQueryItem(name: "vsn", value: "1.0.0")
        ]
        guard let socketURL = components.url else { return }

        var request = URLRequest(url: socketURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")

        let socket = urlSession.webSocketTask(with: request)
        self.webSocket = socket
        socket.resume()

        // Join channel after small delay to ensure connection open
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.sendJoin()
            self?.startReceiveLoop(onReceive: onReceive)
            self?.startHeartbeat()
            DispatchQueue.main.async { [weak self] in
                self?.lastEventDescription = "joined"
            }
            print("🔌 LiveDoodle RT: join sent")
        }
    }

    func disconnect() {
        listenCancellable?.cancel()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        stopHeartbeat()
        connectConfig = nil
        DispatchQueue.main.async { [weak self] in
            self?.lastEventDescription = "disconnected"
        }
    }

    private func sendJoin() {
        guard let socket = webSocket else { return }
        currentRef += 1
        let ref = "\(currentRef)"
        let payload: [String: Any] = [
            "config": [
                "broadcast": ["ack": false],
                "postgres_changes": [[
                    "event": "INSERT",
                    "schema": "public",
                    "table": "live_doodles",
                    "filter": "couple_key=eq.\(coupleKey)"
                ]]
            ]
        ]
        let message: [String: Any] = [
            "topic": "realtime:public:live_doodles",
            "event": "phx_join",
            "payload": payload,
            "ref": ref
        ]
        if let data = try? JSONSerialization.data(withJSONObject: message) {
            socket.send(.data(data)) { _ in }
        }
    }

    private func startReceiveLoop(onReceive: @escaping (LiveDoodle) -> Void) {
        guard let socket = webSocket else { return }
        socket.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                DispatchQueue.main.async {
                    self.lastEventDescription = "receive failure"
                }
                print("🔌 LiveDoodle RT: receive failure")
                self.stopHeartbeat()
                self.scheduleReconnect()
                return // socket is dead; wait for reconnect
            case .success(let message):
                if case let .data(data) = message {
                    self.handleMessage(data: data, onReceive: onReceive)
                } else if case let .string(text) = message, let data = text.data(using: .utf8) {
                    self.handleMessage(data: data, onReceive: onReceive)
                }
            }
            // Continue listening
            self.startReceiveLoop(onReceive: onReceive)
        }
    }

    private func handleMessage(data: Data, onReceive: @escaping (LiveDoodle) -> Void) {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let event = root["event"] as? String,
            event == "postgres_changes",
            let payload = root["payload"] as? [String: Any]
        else { return }

        // Supabase can nest data under payload["record"], payload["new"],
        // or payload["data"]["record"]/["data"]["new"] depending on the Realtime version.
        let nestedData = (payload["data"] as? [String: Any]) ?? [:]
        let record = (payload["record"] as? [String: Any])
            ?? (payload["new"] as? [String: Any])
            ?? (nestedData["record"] as? [String: Any])
            ?? (nestedData["new"] as? [String: Any])
        guard let record else { return }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: record) else { return }
        // Try strict decode; fall back to manual parsing to avoid losing events.
        let decoded: LiveDoodle? = {
            if let doodle = try? JSONDecoder.liveDoodle.decode(LiveDoodle.self, from: jsonData) {
                return doodle
            }
            if let doodle = LiveDoodleParser.parse(json: record) {
                return doodle
            }
            return nil
        }()

        if let doodle = decoded,
           doodle.coupleKey == coupleKey,
           doodle.senderId != myUserId {
            DispatchQueue.main.async {
                self.lastEventDescription = "recv \(doodle.id.uuidString.prefix(6))"
                onReceive(doodle)
            }
            print("🔌 LiveDoodle RT: received doodle \(doodle.id) from \(doodle.senderId)")
        } else {
            DispatchQueue.main.async {
                self.lastEventDescription = "recv other"
            }
            print("🔌 LiveDoodle RT: ignored event (not couple or self)")
        }
    }

    private func scheduleReconnect() {
        guard let config = connectConfig else { return }
        reconnectWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            print("🔌 LiveDoodle RT: reconnecting after failure")
            self.connect(
                projectURL: config.projectURL,
                anonKey: config.anonKey,
                accessToken: config.accessToken,
                coupleKey: config.coupleKey,
                myUserId: config.myUserId,
                onReceive: config.onReceive
            )
        }
        reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func startHeartbeat() {
        stopHeartbeat()
        let timer = Timer(timeInterval: 25, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
        heartbeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func sendHeartbeat() {
        guard let socket = webSocket else { return }
        currentRef += 1
        let ref = "\(currentRef)"
        let message: [String: Any] = [
            "topic": "phoenix",
            "event": "heartbeat",
            "payload": [:],
            "ref": ref
        ]
        if let data = try? JSONSerialization.data(withJSONObject: message) {
            socket.send(.data(data)) { _ in }
        }
    }
}
