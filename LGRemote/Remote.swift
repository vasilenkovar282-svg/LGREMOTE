import Foundation
import SwiftUI
import Network

struct TVApp: Identifiable { let id: String; let title: String }

@MainActor final class Remote: ObservableObject {
    @Published var host = UserDefaults.standard.string(forKey: "host") ?? ""
    @Published var mac = UserDefaults.standard.string(forKey: "mac") ?? ""
    @Published var status = "Не подключено"
    @Published var ready = false
    @Published var pointerReady = false
    @Published var apps: [TVApp] = []
    @Published var volume: Double = 0
    private var socket: URLSessionWebSocketTask?
    private var pointer: URLSessionWebSocketTask?
    private var session = URLSession(configuration: .ephemeral)
    private var generation = UUID()
    private var connectedHost = ""
    private var wakeConnection: NWConnection?
    private var timeout: Task<Void, Never>?

    func connect() {
        disconnect()
        let ip = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = ip.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }), let url = URL(string: "ws://\(ip):3000") else { status = "Введите IPv4 телевизора"; return }
        connectedHost = ip
        UserDefaults.standard.set(ip, forKey: "host")
        let token = generation
        let ws = session.webSocketTask(with: url)
        socket = ws; ws.resume(); status = "Подтверди подключение на ТВ"
        let permissions = ["LAUNCH", "LAUNCH_WEBAPP", "CLOSE", "CONTROL_AUDIO", "CONTROL_DISPLAY", "CONTROL_INPUT_TV", "CONTROL_INPUT_TEXT", "CONTROL_MOUSE_AND_KEYBOARD", "CONTROL_INPUT_MEDIA_PLAYBACK", "CONTROL_POWER", "READ_INSTALLED_APPS", "READ_CURRENT_CHANNEL", "READ_INPUT_DEVICE_LIST", "READ_RUNNING_APPS", "TEST_SECURE"]
        var payload: [String: Any] = ["forcePairing": false, "pairingType": "PROMPT", "manifest": ["manifestVersion": 1, "appVersion": "1.0", "appId": "local.romote.lg", "localizedAppNames": ["": "LG Remote"], "permissions": permissions, "signed": ["permissions": permissions]]]
        if let key = UserDefaults.standard.string(forKey: "key." + ip) { payload["client-key"] = key }
        send(["id": "register", "type": "register", "payload": payload])
        Task { [weak self] in
            do {
                while let self = self, self.generation == token {
                    let msg = try await ws.receive()
                    guard self.generation == token else { return }
                    self.handle(msg)
                }
            } catch { if let self = self, self.generation == token { self.fail(error.localizedDescription) } }
        }
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            if !Task.isCancelled, let self = self, self.generation == token, !self.ready { self.fail("Нет ответа или подтверждения от ТВ") }
        }
    }
    func disconnect() {
        generation = UUID(); timeout?.cancel(); timeout = nil
        socket?.cancel(with: .goingAway, reason: nil); pointer?.cancel(with: .goingAway, reason: nil)
        socket = nil; pointer = nil; ready = false; pointerReady = false; apps = []; status = "Не подключено"
    }
    func forget() { UserDefaults.standard.removeObject(forKey: "key." + host.trimmingCharacters(in: .whitespacesAndNewlines)); disconnect(); status = "Ключ удалён. Подключись снова." }
    private func fail(_ message: String) { disconnect(); status = message }
    private func send(_ object: [String: Any]) {
        guard let ws = socket, let data = try? JSONSerialization.data(withJSONObject: object), let string = String(data: data, encoding: .utf8) else { return }
        let token = generation
        Task { do { try await ws.send(.string(string)) } catch { if generation == token { fail(error.localizedDescription) } } }
    }
    func request(_ uri: String, _ payload: [String: Any] = [:], id: String = UUID().uuidString) {
        guard ready else { return }
        send(["id": id, "type": "request", "uri": "ssap://" + uri, "payload": payload])
    }
    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message { case .data(let d): data = d; case .string(let s): data = Data(s.utf8); @unknown default: return }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        let p = obj["payload"] as? [String: Any] ?? [:]
        let id = obj["id"] as? String ?? ""
        if obj["type"] as? String == "registered" {
            if let key = p["client-key"] as? String { UserDefaults.standard.set(key, forKey: "key." + connectedHost) }
            timeout?.cancel(); ready = true; status = "Подключено"
            request("com.webos.service.networkinput/getPointerInputSocket", id: "pointer")
            request("audio/getVolume", id: "volume")
            request("com.webos.applicationManager/listLaunchPoints", id: "apps")
        } else if obj["type"] as? String == "error" || p["returnValue"] as? Bool == false {
            let error = obj["error"] as? String ?? p["errorText"] as? String ?? "Команда не поддерживается"
            if !ready { fail(error) } else { status = error }
        } else if id == "pointer", let path = p["socketPath"] as? String, let url = URL(string: path), url.host == connectedHost, url.scheme == "ws" {
            let ws = session.webSocketTask(with: url); pointer = ws; ws.resume(); pointerReady = true
            let token = generation
            Task { [weak self] in
                do { while let self = self, self.generation == token { _ = try await ws.receive() } }
                catch { if let self = self, self.generation == token { self.pointerReady = false; self.status = "Курсор отключён; переподключись" } }
            }
        } else if id == "apps" {
            let rows = p["launchPoints"] as? [[String: Any]] ?? p["apps"] as? [[String: Any]] ?? []
            var seen = Set<String>()
            apps = rows.compactMap { row in
                guard let id = row["id"] as? String, seen.insert(id).inserted else { return nil }
                return TVApp(id: id, title: row["title"] as? String ?? id)
            }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        } else if id == "volume" {
            if let v = p["volume"] as? NSNumber { volume = v.doubleValue }
            else if let s = p["volumeStatus"] as? [String: Any], let v = s["volume"] as? NSNumber { volume = v.doubleValue }
        }
    }
    private func pointerSend(_ text: String) {
        guard pointerReady, let ws = pointer else { return }
        let token = generation
        Task { do { try await ws.send(.string(text)) } catch { if generation == token { pointerReady = false; status = "Ошибка управления курсором" } } }
    }
    func key(_ name: String) { pointerSend("type:button\nname:\(name)\n\n") }
    func move(_ x: Int, _ y: Int) { if x != 0 || y != 0 { pointerSend("type:move\ndx:\(x)\ndy:\(y)\ndown:0\n\n") } }
    func click() { pointerSend("type:click\n\n") }
    func launch(_ id: String) { request("system.launcher/launch", ["id": id]) }
    func text(_ value: String) { request("com.webos.service.ime/insertText", ["text": value, "replace": 0]) }
    func wake() {
        let clean = mac.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count == 12 else { status = "Введите MAC телевизора"; return }
        var bytes: [UInt8] = []; var i = clean.startIndex
        for _ in 0..<6 { let j = clean.index(i, offsetBy: 2); guard let b = UInt8(clean[i..<j], radix: 16) else { status = "Неверный MAC"; return }; bytes.append(b); i = j }
        UserDefaults.standard.set(mac, forKey: "mac")
        let packet = Data(Array(repeating: UInt8(255), count: 6) + Array(repeating: bytes, count: 16).flatMap { $0 })
        // Unicast Wake-on-LAN; some routers/TVs require broadcast instead.
        let ip = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard IPv4Address(ip) != nil else { status = "Введите IP телевизора"; return }
        let c = NWConnection(host: NWEndpoint.Host(ip), port: 9, using: .udp)
        wakeConnection?.cancel(); wakeConnection = c
        status = "Отправка сигнала включения"
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let c = c else { return }
            if case .ready = state { c.send(content: packet, completion: .contentProcessed { error in
                Task { @MainActor in self?.status = error == nil ? "Сигнал отправлен; включение не подтверждено" : "Ошибка Wake-on-LAN" }; c.cancel()
            }) } else if case .failed = state { Task { @MainActor in self?.status = "Wake-on-LAN недоступен" }; c.cancel() }
        }
        c.start(queue: .global(qos: .utility))
    }
}
