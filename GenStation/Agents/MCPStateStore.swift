// MCPStateStore.swift
// Persistent MCP runtime state (WS-7.1 Phase A). macOS only.
//
// One JSON file in the app container holds the ONLY MCP state that must
// survive an app restart: the daily spend ledger, outstanding budget
// reservations, and video job records. Settings (enabled / confirm-first /
// standing budget dollar amount) stay in UserDefaults. History is NOT here —
// jobs reference history items by UUID; the history remains the source of truth.
//
// Single writer: MCPCore (@MainActor) owns the live state and calls save() after
// every mutation. Writes are atomic (temp + rename), file mode 0600.

#if os(macOS)
import Foundation

struct PersistedReservation: Codable {
    var amount: Double
    var sessionID: Int
    var chargesStanding: Bool
}

/// Only video jobs are persisted — image generation is synchronous, so an app
/// quit mid-image kills the socket and the in-flight request together.
struct PersistedJob: Codable {
    var sessionID: Int
    var queueJobID: String?     // JobQueue job UUID (string form)
    var historyItemID: String?  // history item UUID (string form) — the durable cost link
    var reservationID: String?
    var costCounted: Bool
}

struct MCPPersistentState: Codable {
    var schemaVersion: Int = 1
    var ledgerByDay: [String: Double] = [:]
    var reservations: [String: PersistedReservation] = [:]
    var jobs: [String: PersistedJob] = [:]
}

/// Pure daily-ledger helpers (no I/O) so the arithmetic is trivial to exercise.
/// A "day" is local-time calendar day; the ledger keeps at most the last 30 days.
enum MCPLedger {
    static func dayKey(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func spentToday(_ dict: [String: Double], now: Date = Date()) -> Double {
        dict[dayKey(now)] ?? 0
    }

    static func addSpend(_ amount: Double, to dict: inout [String: Double], now: Date = Date()) {
        guard amount > 0 else { return }
        let key = dayKey(now)
        dict[key] = (dict[key] ?? 0) + amount
        if dict.count > 30 {
            for stale in dict.keys.sorted().dropLast(30) { dict.removeValue(forKey: stale) }
        }
    }
}

enum MCPStateStore {
    /// Same container dir as the socket; the file sits next to mcp.sock.
    static var fileURL: URL {
        AppStorageContext.current.agentDirectory.appendingPathComponent("mcp_state.json")
    }

    /// Legacy UserDefaults key the daily ledger used before WS-7.1.
    private static let legacyLedgerDefaultsKey = "mcpStandingBudgetSpendByDay"

    static func load() -> MCPPersistentState {
        let url = fileURL
        if let data = try? Data(contentsOf: url),
           let state = try? JSONDecoder().decode(MCPPersistentState.self, from: data) {
            return state
        }
        // First launch on WS-7.1: migrate the ledger out of UserDefaults, once.
        var state = MCPPersistentState()
        if let legacy = AppStorageContext.defaults.dictionary(forKey: legacyLedgerDefaultsKey) as? [String: Double],
           !legacy.isEmpty {
            state.ledgerByDay = legacy
            save(state)
            AppStorageContext.defaults.removeObject(forKey: legacyLedgerDefaultsKey)
            Log.debug("MCP: migrated \(legacy.count)-day spend ledger from UserDefaults to sidecar")
        }
        return state
    }

    static func save(_ state: MCPPersistentState) {
        let url = fileURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(state) else {
            Log.debug("MCP: failed to encode persistent state")
            return
        }
        let tmp = dir.appendingPathComponent("mcp_state.\(UUID().uuidString).tmp")
        do {
            try data.write(to: url, options: .atomic)
            chmod(url.path, 0o600)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            Log.debug("MCP: failed to write persistent state: \(error.localizedDescription)")
        }
    }
}
#endif
