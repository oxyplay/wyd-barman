import Foundation

// MARK: - Snapshot v1 (mirrors wyd barman contract keys verbatim)

struct Snapshot: Codable {
    let schemaVersion: Int
    let wydVersion: String
    let generatedAt: String
    let system: SystemMetrics
    let projects: [Project]
    let sessions: [Session]
    let resources: [Resource]
    let containers: [Container]
    let leftovers: Leftovers

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case wydVersion = "wyd_version"
        case generatedAt = "generated_at"
        case system, projects, sessions, resources, containers, leftovers
    }
}

/// Host gauges for the one-line menu status (measured by the engine).
struct SystemMetrics: Codable {
    let cpuPercent: Float
    let usedMemoryBytes: UInt64
    let totalMemoryBytes: UInt64
    let freeDiskBytes: UInt64

    enum CodingKeys: String, CodingKey {
        case cpuPercent = "cpu_percent"
        case usedMemoryBytes = "used_memory_bytes"
        case totalMemoryBytes = "total_memory_bytes"
        case freeDiskBytes = "free_disk_bytes"
    }

    var memoryUsedPercent: Int {
        guard totalMemoryBytes > 0 else { return 0 }
        return Int((Double(usedMemoryBytes) / Double(totalMemoryBytes) * 100).rounded())
    }

    var oneLine: String {
        "CPU \(Int(cpuPercent.rounded()))% · RAM \(memoryUsedPercent)% · Disk \(formattedFree)"
    }

    private var formattedFree: String {
        let gb = Double(freeDiskBytes) / 1_000_000_000
        return gb < 1 ? "\(Int(Double(freeDiskBytes) / 1_000_000)) MB" : String(format: "%.0f GB", gb)
    }
}

struct Project: Codable, Identifiable {
    let id: String
    let name: String
    let agent: String?
    let resourceCount: Int
    let memoryBytes: UInt64
    let resourceIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, agent
        case resourceCount = "resource_count"
        case memoryBytes = "memory_bytes"
        case resourceIDs = "resource_ids"
    }
}

struct Session: Codable, Identifiable {
    let id: String
    let agent: String
    let projectID: String?
    let status: String
    let ageSeconds: UInt64
    let resourceIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id, agent
        case projectID = "project_id"
        case status
        case ageSeconds = "age_seconds"
        case resourceIDs = "resource_ids"
    }
}

struct Resource: Codable, Identifiable {
    let id: String
    let kind: String
    let name: String
    let status: String
    let projectID: String?
    let sessionID: String?
    let port: Int?
    let ports: [Int]
    let pid: Int?
    let memoryBytes: UInt64
    let cpuPercent: Float
    let url: String?
    let classification: String
    let confidence: String?
    let reasons: [String]
    let estimatedReclaimBytes: UInt64
    let actions: [String]

    enum CodingKeys: String, CodingKey {
        case id, kind, name, status
        case projectID = "project_id"
        case sessionID = "session_id"
        case port, ports, pid
        case memoryBytes = "memory_bytes"
        case cpuPercent = "cpu_percent"
        case url, classification, confidence, reasons
        case estimatedReclaimBytes = "estimated_reclaim_bytes"
        case actions
    }

    /// The engine omits empty arrays (`skip_serializing_if`); decode them as
    /// `[]` instead of failing on a missing key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        status = try c.decode(String.self, forKey: .status)
        projectID = try c.decodeIfPresent(String.self, forKey: .projectID)
        sessionID = try c.decodeIfPresent(String.self, forKey: .sessionID)
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        ports = try c.decodeIfPresent([Int].self, forKey: .ports) ?? []
        pid = try c.decodeIfPresent(Int.self, forKey: .pid)
        memoryBytes = try c.decode(UInt64.self, forKey: .memoryBytes)
        cpuPercent = try c.decode(Float.self, forKey: .cpuPercent)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        classification = try c.decode(String.self, forKey: .classification)
        confidence = try c.decodeIfPresent(String.self, forKey: .confidence)
        reasons = try c.decodeIfPresent([String].self, forKey: .reasons) ?? []
        estimatedReclaimBytes = try c.decode(UInt64.self, forKey: .estimatedReclaimBytes)
        actions = try c.decode([String].self, forKey: .actions)
    }
}
struct Container: Codable, Identifiable {
    let id: String
    let name: String
    let composeProject: String?
    let ports: [Int]
    let url: String?
    let status: String
    let sizeBytes: UInt64
    let actions: [String]
    let estimatedReclaimBytes: UInt64

    enum CodingKeys: String, CodingKey {
        case id, name, status, actions, url
        case composeProject = "compose_project"
        case ports
        case sizeBytes = "size_bytes"
        case estimatedReclaimBytes = "estimated_reclaim_bytes"
    }
}

struct Leftovers: Codable {
    let count: Int
    let estimatedReclaimBytes: UInt64
    let resourceIDs: [String]

    enum CodingKeys: String, CodingKey {
        case count
        case estimatedReclaimBytes = "estimated_reclaim_bytes"
        case resourceIDs = "resource_ids"
    }
}

// MARK: - Actions & cleanup

/// UI-side action token. The engine's `actions` arrays use these same raw
/// values except `open`, which is handled locally via the supplied `url`
/// (NSWorkspace) and never sent to the engine (`open-url` is engine-side).
enum ResourceAction: String {
    case open
    case start
    case stop
    case restart
    case kill

    var engineName: String {
        self == .open ? "open-url" : rawValue
    }

    var verb: String {
        switch self {
        case .open: "open"
        case .start: "start"
        case .stop: "stop"
        case .restart: "restart"
        case .kill: "kill"
        }
    }
}

struct ActionResult: Codable {
    let ok: Bool
    let target: String
    let action: String?
    let detail: String?
    let url: String?
    let error: String?
    let stale: Bool
}

struct CleanupPlan: Codable {
    let planID: String
    let items: [CleanupItem]
    let protected: [ProtectedItem]
    let estimatedReclaimBytes: UInt64

    enum CodingKeys: String, CodingKey {
        case planID = "plan_id"
        case items, protected
        case estimatedReclaimBytes = "estimated_reclaim_bytes"
    }
}

struct CleanupItem: Codable, Identifiable {
    var id: String { resourceID }
    let resourceID: String
    let selected: Bool
    let safe: Bool
    let reason: String

    enum CodingKeys: String, CodingKey {
        case resourceID = "resource_id"
        case selected, safe, reason
    }
}

struct ProtectedItem: Codable, Identifiable {
    var id: String { resourceID }
    let resourceID: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case resourceID = "resource_id"
        case reason
    }
}

struct CleanupResult: Codable {
    let ok: Bool
    let planID: String
    let stopped: [String]
    let killed: [String]
    let failed: [CleanupFailure]
    let reclaimedBytes: UInt64
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case planID = "plan_id"
        case stopped, killed, failed
        case reclaimedBytes = "reclaimed_bytes"
        case error
    }
}

struct CleanupFailure: Codable {
    let resourceID: String
    let error: String

    enum CodingKeys: String, CodingKey {
        case resourceID = "resource_id"
        case error
    }
}

struct ApiVersion: Codable {
    let schemaVersion: Int
    let wydVersion: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case wydVersion = "wyd_version"
    }
}

/// Decoded before the full snapshot so a schema mismatch surfaces as
/// `incompatible` instead of a Codable crash.
struct VersionProbe: Codable {
    let schemaVersion: Int
    let wydVersion: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case wydVersion = "wyd_version"
    }
}
