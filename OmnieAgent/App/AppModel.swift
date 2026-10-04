import Foundation
import Observation
import SwiftUI

/// Owns the saved agents and which one is active.
@Observable
final class AppModel {
    private(set) var connections: [Connection] = []
    private(set) var live: [UUID: AgentConnection] = [:]
    var activeID: UUID? {
        didSet { UserDefaults.standard.set(activeID?.uuidString, forKey: Keys.active) }
    }
    /// Set by deep links / Shortcuts: text to start a new chat with.
    var pendingPrompt: String?
    /// Set by `omnie://connect` links and QR codes.
    var pendingLink: ConnectionLink?

    private enum Keys {
        static let connections = "omnie.connections.v1"
        static let active = "omnie.connections.active"
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Keys.connections),
           let saved = try? JSONDecoder().decode([Connection].self, from: data) {
            connections = saved
        }
        activeID = UserDefaults.standard.string(forKey: Keys.active).flatMap(UUID.init(uuidString:))
        if activeID == nil || !connections.contains(where: { $0.id == activeID }) {
            activeID = connections.first?.id
        }
    }

    var active: AgentConnection? {
        guard let activeID else { return nil }
        return agent(for: activeID)
    }

    func agent(for id: UUID) -> AgentConnection? {
        if let existing = live[id] { return existing }
        guard let connection = connections.first(where: { $0.id == id }) else { return nil }
        let agent = AgentConnection(connection: connection, secret: Keychain.secret(for: id) ?? "")
        live[id] = agent
        return agent
    }

    func save(_ connection: Connection, secret: String?) {
        if let secret { Keychain.setSecret(secret, for: connection.id) }
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        // Rebuild the live connection so new settings take effect.
        if let old = live.removeValue(forKey: connection.id) {
            Task { await old.close() }
        }
        persist()
        activeID = connection.id
    }

    func remove(_ connection: Connection) {
        connections.removeAll { $0.id == connection.id }
        Keychain.removeSecret(for: connection.id)
        if let old = live.removeValue(forKey: connection.id) {
            Task { await old.close() }
        }
        if connection.kind == .openAI {
            LocalTranscriptStore(scope: connection.id.uuidString).deleteAll()
        }
        if activeID == connection.id { activeID = connections.first?.id }
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        connections.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func foreground() async {
        for agent in live.values { await agent.backend.foreground() }
    }

    func handle(url: URL) {
        if let link = ConnectionLink(url: url) {
            pendingLink = link
            return
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), url.scheme == "omnie" else { return }
        let items = components.queryItems ?? []
        switch components.host {
        case "chat", "ask", "new":
            pendingPrompt = items.first { $0.name == "text" || $0.name == "q" }?.value ?? ""
        case "agent":
            if let name = items.first(where: { $0.name == "name" })?.value,
               let match = connections.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                activeID = match.id
            }
        default:
            break
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(connections) {
            UserDefaults.standard.set(data, forKey: Keys.connections)
        }
    }
}
