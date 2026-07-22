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

extension AlertRule {
    /// The ship-ready default AlertRule set — docs/04-ALERTS-NOTIFICATIONS.md §2.1,
    /// rules R1–R20 verbatim (Beginner defaults: only R1–R4 enabled). Every rule
    /// exists from day one so AlertsView can show toggleable rows; only `enabled`
    /// differs. Rule ids are fresh UUIDs at creation (04 §2); persisted once by
    /// SettingsStore on first launch (M3).
    nonisolated public static func defaultRules() -> [AlertRule] {
        [
            // R1–R4 — enabled Beginner set (~40 notifications/week, inside 56).
            AlertRule(target: .market(.fxLondon, .regular),
                      moments: [.atOpen, .before(minutes: 15)], style: .timeSensitive, enabled: true),
            AlertRule(target: .market(.fxNewYork, .regular),
                      moments: [.atOpen, .before(minutes: 15)], style: .timeSensitive, enabled: true),
            AlertRule(target: .market(.usEquities, .regular),
                      moments: [.atOpen, .before(minutes: 15)], style: .timeSensitive, enabled: true),
            AlertRule(target: .econ(minImpact: .high),
                      moments: [.atOpen, .before(minutes: 15)], style: .timeSensitive, enabled: true),
            // R5–R7 — closes for the big three.
            AlertRule(target: .market(.fxLondon, .regular),
                      moments: [.atClose], style: .standard, enabled: false),
            AlertRule(target: .market(.fxNewYork, .regular),
                      moments: [.atClose], style: .standard, enabled: false),
            AlertRule(target: .market(.usEquities, .regular),
                      moments: [.atClose], style: .standard, enabled: false),
            // R8–R11 — remaining session opens.
            AlertRule(target: .market(.fxSydney, .regular),
                      moments: [.atOpen], style: .standard, enabled: false),
            AlertRule(target: .market(.fxTokyo, .regular),
                      moments: [.atOpen], style: .standard, enabled: false),
            AlertRule(target: .market(.lse, .regular),
                      moments: [.atOpen, .before(minutes: 15)], style: .standard, enabled: false),
            AlertRule(target: .market(.cmeEquity, .regular),
                      moments: [.atOpen, .before(minutes: 15)], style: .standard, enabled: false),
            // R12–R13 — extended hours (off by default: DECISIONS, budget).
            AlertRule(target: .market(.usEquities, .preMarket),
                      moments: [.atOpen], style: .standard, enabled: false),
            AlertRule(target: .market(.usEquities, .afterHours),
                      moments: [.atClose], style: .standard, enabled: false),
            // R14 — London–NY overlap.
            AlertRule(target: .overlap, moments: [.atOpen], style: .standard, enabled: false),
            // R15–R19 — killzones (Pro suggestions; disabled at Beginner).
            AlertRule(target: .killzone(.london),
                      moments: [.atOpen, .before(minutes: 5)], style: .standard, enabled: false),
            AlertRule(target: .killzone(.nyAM),
                      moments: [.atOpen, .before(minutes: 5)], style: .standard, enabled: false),
            AlertRule(target: .killzone(.asia),
                      moments: [.atOpen], style: .standard, enabled: false),
            AlertRule(target: .killzone(.londonClose),
                      moments: [.atOpen], style: .standard, enabled: false),
            AlertRule(target: .killzone(.nyPM),
                      moments: [.atOpen], style: .standard, enabled: false),
            // R20 — FX week markers.
            AlertRule(target: .fxWeek, moments: [.atOpen, .atClose], style: .standard, enabled: false),
        ]
    }
}
