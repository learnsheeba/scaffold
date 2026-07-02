import Vapor
import Foundation

// SwiftChat relay server.
//
// SECURITY INVARIANT: This target intentionally does NOT link SwiftChatKit's
// CryptoEngine. It only reads routing metadata (type/senderID/convoID) and
// forwards `ciphertext` verbatim. It can never read plaintext message content.

/// Minimal mirror of the routing fields we're allowed to read. We deliberately
/// decode only metadata and keep `ciphertext` as opaque bytes.
struct RoutingHeader: Content {
    var type: String
    var senderID: UUID
    var convoID: UUID
}

actor Hub {
    /// Active sockets keyed by a per-connection id, grouped by conversation.
    private var sockets: [UUID: [UUID: WebSocket]] = [:]  // convoID -> (connID -> socket)

    func add(_ ws: WebSocket, connID: UUID, convoID: UUID) {
        sockets[convoID, default: [:]][connID] = ws
    }

    func remove(connID: UUID, convoID: UUID) {
        sockets[convoID]?[connID] = nil
        if sockets[convoID]?.isEmpty == true { sockets[convoID] = nil }
    }

    /// Broadcast opaque bytes to everyone else in the conversation.
    func relay(_ data: [UInt8], from connID: UUID, convoID: UUID) async {
        guard let peers = sockets[convoID] else { return }
        for (id, socket) in peers where id != connID {
            try? await socket.send(data)
        }
    }
}

let hub = Hub()

let app = try await Application.make(.detect())
defer { app.shutdown() }

// LAN-only: bind to all interfaces on the local network. No TLS (E2EE handles
// confidentiality); traffic is expected to stay on the local Wi-Fi.
app.http.server.configuration.hostname = "0.0.0.0"
app.http.server.configuration.port = 8080

app.get("health") { _ in "SwiftChat relay OK" }

// The single relay endpoint. Query params carry the routing identity so the
// server never needs to parse encrypted bodies.
app.webSocket("chat") { req, ws async in
    let connID = UUID()
    let convoID = (try? req.query.get(UUID.self, at: "convo")) ?? UUID()

    await hub.add(ws, connID: connID, convoID: convoID)
    req.logger.info("client \(connID) joined convo \(convoID)")

    // Binary frames: opaque envelopes. Forward as-is.
    ws.onBinary { _, buffer async in
        let bytes = Array(buffer.readableBytesView)
        await hub.relay(bytes, from: connID, convoID: convoID)
    }

    // Some clients may send text; forward its raw bytes too.
    ws.onText { _, text async in
        await hub.relay(Array(text.utf8), from: connID, convoID: convoID)
    }

    ws.onClose.whenComplete { _ in
        Task { await hub.remove(connID: connID, convoID: convoID) }
    }
}

try await app.execute()
