//
//  SharedConstants.swift
//  Offset
//
//  Compiled into BOTH the app target and the widget extension (spine §2).
//  All identifiers use the real root `com.bloxy-studios` per DECISIONS
//  "Setup facts (M0)" — case-sensitive, capital "O" in Offset — superseding the
//  docs' `dev.offsetapp` placeholder.
//

import Foundation
import OffsetKit

nonisolated enum SharedConstants {

    /// App Group — single source of truth lives in OffsetKit (`AppGroup.identifier`).
    static let appGroupID = AppGroup.identifier

    /// OSLog subsystem for app/extension components (02 §8).
    static let logSubsystem = "com.bloxy-studios.Offset"

    enum BGTaskID {
        static let schedule = "com.bloxy-studios.Offset.refresh.schedule"
        static let news = "com.bloxy-studios.Offset.refresh.news"
    }

    /// Deep links (DECISIONS: offset://today · market/{id} · news/briefing · alerts).
    enum DeepLink {
        static let scheme = "offset"
        static let today = URL(string: "offset://today")!
        static let briefing = URL(string: "offset://news/briefing")!
        static let alerts = URL(string: "offset://alerts")!

        static func market(_ id: MarketID) -> URL {
            URL(string: "offset://market/\(id.rawValue)")!
        }
    }
}

/// Capability gates tied to the signing situation (DECISIONS "Setup facts M0").
nonisolated enum Capabilities {
    /// FREE personal team: the Time Sensitive Notifications entitlement is ABSENT
    /// and must not be added. `.timeSensitive` delivery is gated behind this flag
    /// (false → deliver at `.active`). When the paid Developer Program entitlement
    /// returns, flip this to true — zero other changes (04 §4.4 wiring in M4).
    static let timeSensitiveEntitlementPresent = false
}
