//
//  NotificationDelegate.swift
//  Offset
//
//  UNUserNotificationCenter delegate (04 §4.5 foreground presentation + §4.3
//  action routing). Installed at launch in OffsetApp. VIEW_MARKET deep-link
//  routing is completed by DeepLinkRouter in M7 — logged until then.
//

import Foundation
import OffsetKit
import OSLog
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    private let scheduleStore: ScheduleStore
    private let alertsStore: AlertsStore
    private nonisolated let logger =
        Logger(subsystem: SharedConstants.logSubsystem, category: "alerts")

    init(scheduleStore: ScheduleStore, alertsStore: AlertsStore) {
        self.scheduleStore = scheduleStore
        self.alertsStore = alertsStore
    }

    // Foreground presentation: [.banner, .list, .sound] — without a delegate the
    // system suppresses foreground banners entirely (research-MS §1). The
    // hero-on-screen suppression case lands with TodayView in M7.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        #if DEBUG
        if notification.request.identifier == "debug:banner-probe" {
            await MainActor.run {
                alertsStore.markProbeFired(at: Date())
            }
        }
        #endif
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionID = response.actionIdentifier
        let threadID = response.notification.request.content.threadIdentifier
        logger.info("alerts: action \(actionID, privacy: .public) on thread \(threadID, privacy: .public)")

        switch actionID {
        case NotificationActionID.muteToday:
            guard let market = MarketID(rawValue: threadID) else { return }
            await MainActor.run {
                // Mute expires at the market's NEXT day change in its own zone
                // (04 §8.7 — a Tokyo mute survives a New York evening).
                let engine = scheduleStore.engine
                let record = engine.seed.markets.first { $0.id == market }
                guard let zoneID = record?.timeZoneID, let zone = TimeZone(identifier: zoneID) else { return }
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = zone
                let now = Date()
                let startOfTomorrow = calendar.date(
                    byAdding: .day, value: 1, to: calendar.startOfDay(for: now)
                ) ?? now.addingTimeInterval(86_400)
                alertsStore.muteToday(market: market, until: startOfTomorrow)
                Task {
                    await alertsStore.rebuild(
                        events: horizonEvents(from: scheduleStore, now: now),
                        rules: scheduleStore.settings.alertRules,
                        now: now
                    )
                }
            }

        case NotificationActionID.muteSeries:
            await MainActor.run {
                var settings = scheduleStore.settings
                for index in settings.alertRules.indices {
                    if case .econ = settings.alertRules[index].target {
                        settings.alertRules[index].enabled = false
                    }
                }
                scheduleStore.update(settings: settings)
            }

        case NotificationActionID.viewMarket, UNNotificationDefaultActionIdentifier:
            // Deep-link routing (offset://market/{id} · offset://today) — M7 DeepLinkRouter.
            break

        default:
            break
        }
    }
}

/// The 7-day planning horizon feeding the planner (04 §3: events from
/// `engine.events(in: now ..< now + 7 days)`).
@MainActor
func horizonEvents(from scheduleStore: ScheduleStore, now: Date) -> [MarketEvent] {
    scheduleStore.engine.events(
        in: DateInterval(start: now, end: now.addingTimeInterval(7 * 86_400)),
        settings: scheduleStore.settings,
        econEvents: scheduleStore.econEvents
    )
}
