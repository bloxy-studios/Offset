//
//  RefreshCoordinator.swift
//  Offset
//
//  Refresh choreography per 02 §5: foreground refresh is the PRIMARY mechanism;
//  BG tasks are opportunistic top-up only ("the system doesn't guarantee
//  launching the task" — research-MS HALF2 §2). Registers BOTH BGTask ids before
//  end of launch; re-submits at the start of each handler and on every
//  foreground pass; maps system change signals to actions (02 §5.2 table).
//
//  M3 skeleton: handlers re-derive the schedule. M4 adds notification/alarm
//  rebuild; M5 adds Live Activity maintenance; M8 fleshes out the news task.
//

import BackgroundTasks
import Foundation
import Observation
import OffsetKit
import OSLog
import UIKit

@MainActor
@Observable
final class RefreshCoordinator {

    private(set) var lastRefresh: Date?
    private(set) var backgroundTasksRegistered = false

    private let scheduleStore: ScheduleStore
    private let alertsStore: AlertsStore
    @ObservationIgnored private nonisolated let logger =
        Logger(subsystem: SharedConstants.logSubsystem, category: "refresh")

    init(scheduleStore: ScheduleStore, alertsStore: AlertsStore) {
        self.scheduleStore = scheduleStore
        self.alertsStore = alertsStore
    }

    // MARK: BGTask registration (must complete before end of app launch)

    func registerBackgroundTasks() {
        guard !backgroundTasksRegistered else { return }
        register(id: SharedConstants.BGTaskID.schedule) { [weak self] task in
            self?.handleScheduleRefreshTask(task)
        }
        register(id: SharedConstants.BGTaskID.news) { [weak self] task in
            self?.handleNewsRefreshTask(task)
        }
        backgroundTasksRegistered = true
        logger.info("refresh: registered BG tasks \(SharedConstants.BGTaskID.schedule, privacy: .public) + \(SharedConstants.BGTaskID.news, privacy: .public)")
        #if DEBUG
        print("refresh: registered BG tasks [\(SharedConstants.BGTaskID.schedule), \(SharedConstants.BGTaskID.news)]")
        #endif
    }

    /// Registers on the MAIN queue (`using: .main`) so the launch handler executes
    /// on the main actor and the non-Sendable BGTask never crosses isolation —
    /// `assumeIsolated` is sound here by construction. (The queue argument is
    /// system-API plumbing, not DispatchQueue-for-logic; 02 §2 ban respected.)
    private nonisolated func register(id: String, handler: @escaping @MainActor (BGAppRefreshTask) -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // BGTask is a pre-concurrency SDK class with no Sendable annotation;
            // `using: .main` above serializes this whole handler on the main
            // queue, so the region checker's "send" is a false positive here.
            // nonisolated(unsafe) asserts exactly that guarantee (BUILDLOG M3).
            nonisolated(unsafe) let mainQueueTask = refreshTask
            MainActor.assumeIsolated {
                handler(mainQueueTask)
            }
        }
    }

    /// Re-submit both requests (earliestBeginDate now + 4 h; resubmitting replaces
    /// the previous request — research-MS HALF2 §2). Submission is expected to fail
    /// on the simulator — log and carry on, never crash.
    func submitBackgroundRequests(now: Date = Date()) {
        for id in [SharedConstants.BGTaskID.schedule, SharedConstants.BGTaskID.news] {
            let request = BGAppRefreshTaskRequest(identifier: id)
            request.earliestBeginDate = now.addingTimeInterval(4 * 60 * 60)
            do {
                try BGTaskScheduler.shared.submit(request)
                logger.debug("refresh: submitted \(id, privacy: .public)")
            } catch {
                logger.debug("refresh: submit failed for \(id, privacy: .public): \(error) (expected on simulator)")
            }
        }
    }

    // MARK: BG handlers (02 §5.1 — must fit ~30 s)

    private func handleScheduleRefreshTask(_ task: BGAppRefreshTask) {
        submitBackgroundRequests()                       // 1. always re-submit first
        let work = Task { @MainActor in
            await self.refreshSchedulePipelineAsync()    // 2–4 (M5 adds LA maintenance)
            guard !Task.isCancelled else { return }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    private func handleNewsRefreshTask(_ task: BGAppRefreshTask) {
        submitBackgroundRequests()
        let work = Task { @MainActor in
            // M8: stale-based econ/headline fetch + briefing catch-up.
            guard !Task.isCancelled else { return }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: System change signals → actions (02 §5.2 table)

    /// Foreground (`scenePhase == .active`) — the primary full pass.
    func handleScenePhaseActive(now: Date = Date(), zone: TimeZone = .current) {
        refreshSchedulePipeline(now: now, zone: zone)
        submitBackgroundRequests(now: now)
    }

    /// New day at midnight, carrier time update, DST change (redelivered on
    /// foreground if missed) — wall clocks just moved; recompute everything.
    func handleSignificantTimeChange(now: Date = Date(), zone: TimeZone = .current) {
        refreshSchedulePipeline(now: now, zone: zone)
    }

    /// Device time zone changed (travel/settings): reset the cached system zone
    /// FIRST (research-MS §2), then re-derive all device-local projections.
    /// SDK note: the reset API lives on NSTimeZone (docs say TimeZone.…) —
    /// UNVERIFIED resolution recorded in BUILDLOG (M3).
    func handleTimeZoneChange(now: Date = Date()) {
        NSTimeZone.resetSystemTimeZone()
        refreshSchedulePipeline(now: now, zone: .current)
    }

    /// Day flip ("no guarantees about timeliness"): roll horizons, top up windows.
    func handleDayChange(now: Date = Date(), zone: TimeZone = .current) {
        refreshSchedulePipeline(now: now, zone: zone)
    }

    // MARK: Shared pipeline pass

    private func refreshSchedulePipeline(now: Date = Date(), zone: TimeZone = .current) {
        scheduleStore.refresh(now: now, zone: zone)
        lastRefresh = now
        // Notification rebuild is async (system calls); fire-and-forget from the
        // sync signal paths — the plan is deterministic for a given `now`.
        Task { await self.rebuildAlerts(now: now) }
        logger.debug("refresh: pipeline pass complete (\(self.scheduleStore.todayEvents.count) events today)")
    }

    private func refreshSchedulePipelineAsync(now: Date = Date(), zone: TimeZone = .current) async {
        scheduleStore.refresh(now: now, zone: zone)
        lastRefresh = now
        await rebuildAlerts(now: now)
        // M5: ActivityController maintenance (phase/staleDate roll, chain pre-schedule).
    }

    /// 04 §1 rebuild: 7-day event horizon → NotificationPlanner → idempotent apply.
    func rebuildAlerts(now: Date = Date()) async {
        alertsStore.expireMutes(now: now)
        await alertsStore.rebuild(
            events: horizonEvents(from: scheduleStore, now: now),
            rules: scheduleStore.settings.alertRules,
            now: now
        )
    }
}
