//
//  AlertModels.swift
//  OffsetKit
//
//  Alert rule model types. Names/signatures per docs/00-SPINE.md §4 — verbatim.
//

import Foundation

nonisolated public enum AlertTarget: Codable, Hashable, Sendable {
    case market(MarketID, SegmentKind)
    case overlap
    case killzone(KillzoneID)
    case econ(minImpact: EconImpact)
    case fxWeek
}

nonisolated public enum AlertMoment: Codable, Hashable, Sendable {
    case atOpen, atClose
    case before(minutes: Int)
}

/// Delivery style for a rule. `.timeSensitive` stays in the model even while the
/// free-personal-team entitlement is absent — delivery is gated at apply time behind
/// `Capabilities.timeSensitiveEntitlementPresent` (DECISIONS.md, Setup facts M0; wired in M4).
nonisolated public enum AlertStyle: String, Codable, Sendable {
    case standard, timeSensitive, criticalAlarm
}

nonisolated public struct AlertRule: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var target: AlertTarget
    public var moments: Set<AlertMoment>
    public var style: AlertStyle
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        target: AlertTarget,
        moments: Set<AlertMoment>,
        style: AlertStyle,
        enabled: Bool
    ) {
        self.id = id
        self.target = target
        self.moments = moments
        self.style = style
        self.enabled = enabled
    }
}
