//
//  NotificationPlannerTests.swift
//  OffsetKitTests
//
//  The budgeter suite (04 §3; BUILD_PROMPT M4 acceptance): priority, caps,
//  degradation, idempotent rebuild, identifier == MarketEvent.id, coincidence
//  merge, alarm handoff, style resolution. Pure planner over synthetic events
//  with grammar-correct ids (03 §4.1).
//

import Foundation
import Testing
@testable import OffsetKit

@Suite("NotificationPlanner (budgeter)")
struct NotificationPlannerTests {

    private let now = Date(timeIntervalSince1970: 1_785_000_000)   // fixed "now"
    private let planner = NotificationPlanner()

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    // MARK: Synthetic event builders (ids follow the 03 §4.1 grammar)

    private func open(_ market: MarketID, day: String, at date: Date,
                      segment: SegmentKind = .regular) -> MarketEvent {
        let segmentField = segment == .regular ? "" : ":\(segment.rawValue)"
        return MarketEvent(id: "open:\(market.rawValue)\(segmentField):\(day)", kind: .open,
                           market: market, date: date, title: "\(market.rawValue) opens", subtitle: "t")
    }

    private func close(_ market: MarketID, day: String, at date: Date) -> MarketEvent {
        MarketEvent(id: "close:\(market.rawValue):\(day)", kind: .close,
                    market: market, date: date, title: "\(market.rawValue) closes", subtitle: "t")
    }

    private func lead(_ market: MarketID, minutes: Int, day: String, at date: Date) -> MarketEvent {
        MarketEvent(id: "preOpen-\(minutes):\(market.rawValue):\(day)",
                    kind: .preOpen(leadMinutes: minutes), market: market, date: date,
                    title: "\(market.rawValue) opens in \(minutes) min", subtitle: "t")
    }

    private func rule(_ target: AlertTarget, _ moments: Set<AlertMoment>,
                      style: AlertStyle = .standard, enabled: Bool = true) -> AlertRule {
        AlertRule(target: target, moments: moments, style: style, enabled: enabled)
    }

    // MARK: Tests

    @Test func identifierEqualsMarketEventID() {
        let event = open(.usEquities, day: "2026-07-27", at: now.addingTimeInterval(3600))
        let plan = planner.plan(events: [event],
                                rules: [rule(.market(.usEquities, .regular), [.atOpen])],
                                now: now, calendar: utc)
        #expect(plan.count == 1)
        #expect(plan.first?.id == event.id)                        // identifier == MarketEvent.id
        #expect(plan.first?.zoneID == "America/New_York")
        #expect(plan.first?.categoryID == NotificationCategoryID.openMarket)
        #expect(plan.first?.threadID == MarketID.usEquities.rawValue)
        #expect(plan.first?.priorityRank == 1)                     // opens rank
    }

    @Test func segmentTargetingIsExact() {
        // R12-style rule targets preMarket ONLY — must not match the regular open.
        let preMarketOpen = open(.usEquities, day: "2026-07-27",
                                 at: now.addingTimeInterval(3000), segment: .preMarket)
        let regularOpen = open(.usEquities, day: "2026-07-27", at: now.addingTimeInterval(6000))
        let plan = planner.plan(events: [preMarketOpen, regularOpen],
                                rules: [rule(.market(.usEquities, .preMarket), [.atOpen])],
                                now: now, calendar: utc)
        #expect(plan.map(\.id) == [preMarketOpen.id])
    }

    @Test func disabledRulesNeverMatch() {
        let event = open(.fxLondon, day: "2026-07-27", at: now.addingTimeInterval(3600))
        let plan = planner.plan(events: [event],
                                rules: [rule(.market(.fxLondon, .regular), [.atOpen], enabled: false)],
                                now: now, calendar: utc)
        #expect(plan.isEmpty)
    }

    @Test func dropsPastAndImminentEvents() {
        let past = open(.fxLondon, day: "2026-07-24", at: now.addingTimeInterval(-60))
        let tooSoon = open(.fxNewYork, day: "2026-07-25", at: now.addingTimeInterval(3))
        let future = open(.usEquities, day: "2026-07-25", at: now.addingTimeInterval(10))
        let rules = [
            rule(.market(.fxLondon, .regular), [.atOpen]),
            rule(.market(.fxNewYork, .regular), [.atOpen]),
            rule(.market(.usEquities, .regular), [.atOpen]),
        ]
        let plan = planner.plan(events: [past, tooSoon, future], rules: rules, now: now, calendar: utc)
        #expect(plan.map(\.id) == [future.id])                     // ≤ now+5 s dropped
    }

    @Test func nearestFirstFillNeverExceedsBudget() {
        // 10 matched opens/day × 7 days = 70 candidates → exactly 56, nearest-first.
        var events: [MarketEvent] = []
        for day in 0..<7 {
            for slot in 0..<10 {
                let date = now.addingTimeInterval(TimeInterval(day * 86_400 + slot * 3600 + 600))
                events.append(open(.fxLondon, day: "2026-08-\(String(format: "%02d", day + 1))+\(slot)",
                                   at: date))
            }
        }
        let plan = planner.plan(events: events,
                                rules: [rule(.market(.fxLondon, .regular), [.atOpen])],
                                now: now, calendar: utc)
        #expect(plan.count == notificationBudget)                  // 56, reserve untouched
        // Nearest-first: the planned set is exactly the 56 earliest fire dates.
        let expected = events.map(\.date).sorted().prefix(notificationBudget)
        #expect(plan.map(\.fireDate) == Array(expected))
        #expect(notificationBudget + reserveSlots == 64)           // 64-cap arithmetic
    }

    @Test func perDayCapDropsLowestPriorityFirst() {
        // One local day: 10 opens (rank 1) + 10 closes (rank 3) → cap 16 keeps all
        // 10 opens and only 6 closes.
        // 120 s spacing — deliberately OUTSIDE the 60 s coincidence-merge window so
        // no candidates collapse (the merge behavior has its own test below).
        var events: [MarketEvent] = []
        for index in 0..<10 {
            events.append(open(.fxLondon, day: "d\(index)",
                               at: now.addingTimeInterval(TimeInterval(1000 + index * 120))))
            events.append(close(.fxLondon, day: "d\(index)",
                                at: now.addingTimeInterval(TimeInterval(18_000 + index * 120))))
        }
        let plan = planner.plan(events: events,
                                rules: [rule(.market(.fxLondon, .regular), [.atOpen, .atClose])],
                                now: now, calendar: utc)
        #expect(plan.count == perDayCap)
        #expect(plan.count(where: { $0.priorityRank == 1 }) == 10) // every open kept
        #expect(plan.count(where: { $0.priorityRank == 3 }) == 6)  // closes degraded
    }

    @Test func idempotentRebuild() {
        var events: [MarketEvent] = []
        for day in 0..<5 {
            events.append(open(.usEquities, day: "2026-08-0\(day + 1)",
                               at: now.addingTimeInterval(TimeInterval(day * 86_400 + 7200))))
            events.append(close(.usEquities, day: "2026-08-0\(day + 1)",
                               at: now.addingTimeInterval(TimeInterval(day * 86_400 + 30_000))))
        }
        let rules = [rule(.market(.usEquities, .regular), [.atOpen, .atClose], style: .timeSensitive)]
        let first = planner.plan(events: events, rules: rules, now: now, calendar: utc)
        let second = planner.plan(events: events, rules: rules, now: now, calendar: utc)
        #expect(first == second)                                   // byte-identical replan
        #expect(!first.isEmpty)
    }

    @Test func mergesCoincidentStartLikeEvents() {
        // 03 §7 T20's canonical pair: weekOpen == fxSydney Monday open, same instant.
        let instant = now.addingTimeInterval(7200)
        let sydneyOpen = open(.fxSydney, day: "2026-07-27", at: instant)
        let weekOpen = MarketEvent(id: "weekOpen:fx:2026-07-26", kind: .weekOpen, market: nil,
                                   date: instant, title: "FX week opens", subtitle: "t")
        let rules = [
            rule(.market(.fxSydney, .regular), [.atOpen]),
            rule(.fxWeek, [.atOpen, .atClose]),
        ]
        let plan = planner.plan(events: [sydneyOpen, weekOpen], rules: rules, now: now, calendar: utc)
        #expect(plan.count == 1)                                   // merged into one
        #expect(plan.first?.id == sydneyOpen.id)                   // lexicographically smallest id
        #expect(plan.first?.title == "fxSydney opens + FX week opens")
        // An end-like event at the same instant does NOT merge with start-likes.
        let sydneyClose = close(.fxTokyo, day: "2026-07-27", at: instant)
        let mixed = planner.plan(events: [sydneyOpen, weekOpen, sydneyClose],
                                 rules: rules + [rule(.market(.fxTokyo, .regular), [.atClose])],
                                 now: now, calendar: utc)
        #expect(mixed.count == 2)
    }

    @Test func alarmHandoffSuppressesAnchorAndSameRuleLeads() {
        // Critical rule A {atOpen, before(15)}; standard rule B {before(30)} on the
        // same anchor. Alarm wins: anchor + A's lead drop; B's lead survives, rank 0.
        let anchorDate = now.addingTimeInterval(10_000)
        let anchor = open(.usEquities, day: "2026-07-27", at: anchorDate)
        let leadA = lead(.usEquities, minutes: 15, day: "2026-07-27",
                         at: anchorDate.addingTimeInterval(-900))
        let leadB = lead(.usEquities, minutes: 30, day: "2026-07-27",
                         at: anchorDate.addingTimeInterval(-1800))
        let ruleA = rule(.market(.usEquities, .regular), [.atOpen, .before(minutes: 15)],
                         style: .criticalAlarm)
        let ruleB = rule(.market(.usEquities, .regular), [.before(minutes: 30)])

        let plan = planner.plan(events: [anchor, leadA, leadB], rules: [ruleA, ruleB],
                                now: now, calendar: utc)
        #expect(plan.map(\.id) == [leadB.id])                      // alarm wins; B's lead survives
        #expect(plan.first?.priorityRank == 0)                     // criticalAlarm-backed lead
        #expect(plan.first?.style == .standard)

        // Without the critical rule, everything schedules normally.
        let normalRuleA = rule(.market(.usEquities, .regular), [.atOpen, .before(minutes: 15)],
                               style: .timeSensitive)
        let normal = planner.plan(events: [anchor, leadA, leadB], rules: [normalRuleA, ruleB],
                                  now: now, calendar: utc)
        #expect(Set(normal.map(\.id)) == [anchor.id, leadA.id, leadB.id])
    }

    @Test func styleResolutionTakesMaxSeverityAndNeverEmitsCritical() {
        let event = open(.fxLondon, day: "2026-07-27", at: now.addingTimeInterval(4000))
        let plan = planner.plan(
            events: [event],
            rules: [
                rule(.market(.fxLondon, .regular), [.atOpen], style: .standard),
                rule(.market(.fxLondon, .regular), [.atOpen], style: .timeSensitive),
            ],
            now: now, calendar: utc
        )
        #expect(plan.first?.style == .timeSensitive)               // max severity wins
        // Planner output never carries .criticalAlarm (that lane is AlarmKit's).
        #expect(plan.allSatisfy { $0.style != .criticalAlarm })
    }

    @Test func econEventsMatchEconRules() {
        let release = MarketEvent(id: "econ:ff-2026-07-30-usd-fomc", kind: .econRelease("ff-2026-07-30-usd-fomc"),
                                  market: nil, date: now.addingTimeInterval(5000),
                                  title: "FOMC Statement", subtitle: "USD · high")
        let econLead = MarketEvent(id: "preOpen-15:econ:ff-2026-07-30-usd-fomc",
                                   kind: .preOpen(leadMinutes: 15), market: nil,
                                   date: now.addingTimeInterval(4100),
                                   title: "FOMC Statement in 15 min", subtitle: "USD · high")
        let plan = planner.plan(
            events: [release, econLead],
            rules: [rule(.econ(minImpact: .high), [.atOpen, .before(minutes: 15)],
                         style: .timeSensitive)],
            now: now, calendar: utc
        )
        #expect(Set(plan.map(\.id)) == [release.id, econLead.id])
        let releasePlan = plan.first { $0.id == release.id }
        #expect(releasePlan?.categoryID == NotificationCategoryID.econEvent)
        #expect(releasePlan?.threadID == "econ")
        #expect(releasePlan?.priorityRank == 2)                    // econ rank
        let leadPlan = plan.first { $0.id == econLead.id }
        #expect(leadPlan?.priorityRank == 2)                       // leads inherit anchor rank
    }

    @Test func killzoneRankRespectsStyle() {
        let start = MarketEvent(id: "kzStart:london:2026-07-27", kind: .killzoneStart(.london),
                                market: nil, date: now.addingTimeInterval(6000),
                                title: "London Killzone begins", subtitle: "t")
        let standard = planner.plan(events: [start],
                                    rules: [rule(.killzone(.london), [.atOpen])],
                                    now: now, calendar: utc)
        #expect(standard.first?.priorityRank == 4)                 // killzones standard rank
        let sensitive = planner.plan(events: [start],
                                     rules: [rule(.killzone(.london), [.atOpen], style: .timeSensitive)],
                                     now: now, calendar: utc)
        #expect(sensitive.first?.priorityRank == 1)                // 04 §3.2.6: TS killzone ranks with opens
    }
}
