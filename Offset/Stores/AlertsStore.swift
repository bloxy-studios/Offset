//
//  AlertsStore.swift
//  Offset
//
//  The APPLY side of the notification pipeline (04 §3.4, §4): registers
//  categories/actions, requests authorization, applies [PlannedNotification]
//  idempotently (remove-all + re-add — deterministic ids make re-adds exact),
//  and exposes the budget-health data consumed by AlertsView's BudgetHealthRow
//  in M7 ("41 of 64 slots · scheduled through Thu").
//
//  Free personal team: `.timeSensitive` delivery is gated behind
//  `Capabilities.timeSensitiveEntitlementPresent` (DECISIONS Setup facts M0) —
//  false ⇒ deliver at `.active`. The deprecated
//  `UNAuthorizationOptions.timeSensitive` is never requested.
//

import Foundation
import Observation
import OffsetKit
import OSLog
import UserNotifications

@MainActor
@Observable
final class AlertsStore {

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var pendingCount = 0
    private(set) var plannedCount = 0
    private(set) var coverageEnd: Date?
    private(set) var categoriesRegistered = false
    private(set) var lastApplyError: String?

    #if DEBUG
    /// Timestamp of the DEBUG pipeline probe's delivery (set from willPresent) —
    /// simulator evidence that schedule → fire works end to end. Provisional
    /// authorization delivers quietly (no banner even foregrounded), so the
    /// delegate's fire callback is the observable signal on the simulator.
    private(set) var probeFiredAt: Date?

    func markProbeFired(at date: Date) {
        probeFiredAt = date
    }
    #endif

    /// Per-market mute set by the MUTE_TODAY action; expires at the market's next
    /// day change, not device midnight (04 §8.7). Filters events before planning.
    private(set) var muteTodayUntil: [MarketID: Date] = [:]

    let planner = NotificationPlanner()
    @ObservationIgnored private nonisolated let logger =
        Logger(subsystem: SharedConstants.logSubsystem, category: "alerts")

    // MARK: Categories & actions (04 §4.3 — registered once at launch)

    func registerCategories() {
        let viewMarket = UNNotificationAction(
            identifier: NotificationActionID.viewMarket,
            title: "View market",
            options: [.foreground]
        )
        let muteToday = UNNotificationAction(
            identifier: NotificationActionID.muteToday,
            title: "Mute today",
            options: []
        )
        let openMarket = UNNotificationCategory(
            identifier: NotificationCategoryID.openMarket,
            actions: [viewMarket, muteToday],
            intentIdentifiers: []
        )

        let viewCalendar = UNNotificationAction(
            identifier: NotificationActionID.viewMarket,
            title: "View calendar",
            options: [.foreground]
        )
        let muteSeries = UNNotificationAction(
            identifier: NotificationActionID.muteSeries,
            title: "Mute this series",
            options: []
        )
        let econEvent = UNNotificationCategory(
            identifier: NotificationCategoryID.econEvent,
            actions: [viewCalendar, muteSeries],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([openMarket, econEvent])
        categoriesRegistered = true
        logger.info("alerts: registered categories OPEN_MARKET + ECON_EVENT")
    }

    // MARK: Authorization (04 §4.1/§7.1 — the priming UI lands with onboarding, M7)

    func requestAuthorization(provisional: Bool = false) async {
        var options: UNAuthorizationOptions = [.alert, .sound, .badge]
        if provisional { options.insert(.provisional) }   // quiet path for simulator QA
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
        } catch {
            logger.error("alerts: authorization request failed: \(error)")
        }
        await refreshStatus()
    }

    func refreshStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        pendingCount = await center.pendingNotificationRequests().count
    }

    // MARK: Rebuild (plan + apply — invoked by RefreshCoordinator on every trigger)

    func rebuild(events: [MarketEvent], rules: [AlertRule], now: Date) async {
        let mutes = muteTodayUntil
        let filtered = events.filter { event in
            guard let market = event.market, let until = mutes[market] else { return true }
            return event.date >= until
        }
        let plan = planner.plan(events: filtered, rules: rules, now: now)
        plannedCount = plan.count
        coverageEnd = plan.last?.fireDate
        await apply(plan)
    }

    /// Idempotent apply per 04 §3.4: remove-all then re-add with deterministic ids.
    private func apply(_ plan: [PlannedNotification]) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        lastApplyError = nil

        for planned in plan {
            guard let zone = TimeZone(identifier: planned.zoneID) else { continue }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            var components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: planned.fireDate
            )
            components.timeZone = zone                    // explicit zone — research-MS §1

            let content = UNMutableNotificationContent()
            content.title = planned.title
            content.body = planned.body
            content.sound = .default
            content.categoryIdentifier = planned.categoryID
            content.threadIdentifier = planned.threadID
            content.interruptionLevel = Self.interruptionLevel(
                for: planned.style,
                timeSensitiveEntitlementPresent: Capabilities.timeSensitiveEntitlementPresent
            )

            let request = UNNotificationRequest(
                identifier: planned.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            do {
                try await center.add(request)
            } catch {
                lastApplyError = String(describing: error)
                logger.error("alerts: add failed for \(planned.id, privacy: .public): \(error)")
            }
        }

        pendingCount = await center.pendingNotificationRequests().count
        #if DEBUG
        assert(pendingCount <= 64, "pending notifications exceed the 64 cap")
        #endif
        logger.info("alerts: applied \(self.plannedCount) planned, \(self.pendingCount) pending")
    }

    /// The free-team gate (DECISIONS Setup facts M0): `.timeSensitive` only when
    /// the entitlement is present; otherwise `.active`. Never `.critical`.
    nonisolated static func interruptionLevel(
        for style: AlertStyle,
        timeSensitiveEntitlementPresent: Bool
    ) -> UNNotificationInterruptionLevel {
        switch style {
        case .timeSensitive where timeSensitiveEntitlementPresent: .timeSensitive
        case .timeSensitive, .standard, .criticalAlarm: .active
        }
    }

    // MARK: Ad-hoc single request (reserve-slot lane: between-rebuild econ arrivals,
    // snooze, and DEBUG probes — 04 §3.2 reserve note)

    func scheduleAdHoc(_ planned: PlannedNotification) async {
        let center = UNUserNotificationCenter.current()
        guard let zone = TimeZone(identifier: planned.zoneID) else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: planned.fireDate
        )
        components.timeZone = zone

        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        content.sound = .default
        content.categoryIdentifier = planned.categoryID
        content.threadIdentifier = planned.threadID
        content.interruptionLevel = Self.interruptionLevel(
            for: planned.style,
            timeSensitiveEntitlementPresent: Capabilities.timeSensitiveEntitlementPresent
        )
        do {
            try await center.add(UNNotificationRequest(
                identifier: planned.id, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ))
        } catch {
            lastApplyError = String(describing: error)
        }
        pendingCount = await center.pendingNotificationRequests().count
    }

    // MARK: Mute today (04 §4.3/§8.7 — invoked from the notification action)

    func muteToday(market: MarketID, until: Date) {
        muteTodayUntil[market] = until
        logger.info("alerts: muted \(market.rawValue, privacy: .public) until \(until, privacy: .public)")
    }

    /// Clear expired mutes (called on refresh passes).
    func expireMutes(now: Date) {
        muteTodayUntil = muteTodayUntil.filter { $0.value > now }
    }
}
