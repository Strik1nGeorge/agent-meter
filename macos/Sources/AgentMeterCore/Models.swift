import Foundation

// What the local service's /api/quotas returns; the widget reads only these fields. Everything is optional,
// so a field the service leaves out (or a newer service adds) never breaks decoding.

public struct Snapshot: Decodable {
    public var providers: [Provider]?
    public var collectedAt: Double?
    public var loading: Bool?

    public init(providers: [Provider]? = nil, collectedAt: Double? = nil, loading: Bool? = nil) {
        self.providers = providers; self.collectedAt = collectedAt; self.loading = loading
    }

    public func provider(_ id: String) -> Provider? { providers?.first { $0.id == id } }
}

public struct Provider: Decodable {
    public var id: String?
    public var name: String?
    public var connected: Bool?
    public var quotaStatus: String?
    public var quotaMessage: String?
    public var limits: Limits?
    public var activity: Activity?

    public init(id: String? = nil, name: String? = nil, connected: Bool? = nil, quotaStatus: String? = nil, quotaMessage: String? = nil, limits: Limits? = nil, activity: Activity? = nil) {
        self.id = id; self.name = name; self.connected = connected; self.quotaStatus = quotaStatus
        self.quotaMessage = quotaMessage; self.limits = limits; self.activity = activity
    }
}

// What the platform's agents are doing now (lib/activity.mjs): drives the pets and the hover card.
public struct Activity: Decodable {
    public var working: Bool?
    public var activeSessions: Int?
    public var todayTokens: Double?
    public var todayRequests: Int?
    public var lastActiveAt: Double?
    public var model: String?
    public var effort: String?

    public init(working: Bool? = nil, activeSessions: Int? = nil, todayTokens: Double? = nil, todayRequests: Int? = nil, lastActiveAt: Double? = nil, model: String? = nil, effort: String? = nil) {
        self.working = working; self.activeSessions = activeSessions; self.todayTokens = todayTokens
        self.todayRequests = todayRequests; self.lastActiveAt = lastActiveAt; self.model = model; self.effort = effort
    }
}

public struct Limits: Decodable {
    public var plan: String?
    public var windows: [QuotaWindow]?
    public var collectedAt: Double?
    public var source: String?
    public var staleAfterMs: Double?
    public var stale: Bool?

    public init(plan: String? = nil, windows: [QuotaWindow]? = nil, collectedAt: Double? = nil, source: String? = nil, staleAfterMs: Double? = nil, stale: Bool? = nil) {
        self.plan = plan; self.windows = windows; self.collectedAt = collectedAt
        self.source = source; self.staleAfterMs = staleAfterMs; self.stale = stale
    }
}

public struct QuotaWindow: Decodable, Equatable {
    public var id: String?
    public var name: String?
    public var remainingPercent: Double?
    public var windowMinutes: Double?
    public var resetsAt: Double?

    public init(id: String? = nil, name: String? = nil, remainingPercent: Double? = nil, windowMinutes: Double? = nil, resetsAt: Double? = nil) {
        self.id = id; self.name = name; self.remainingPercent = remainingPercent
        self.windowMinutes = windowMinutes; self.resetsAt = resetsAt
    }
}
