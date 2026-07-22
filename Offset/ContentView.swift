//
//  ContentView.swift
//  Offset
//
//  M3 interim shell: proves the store pipeline end-to-end (engine → ScheduleStore
//  → UI) with a minimal readout. Replaced by RootTabView + the full 07-spec UI in M7.
//

import OffsetKit
import SwiftUI

struct ContentView: View {
    @Environment(ScheduleStore.self) private var scheduleStore
    @Environment(RefreshCoordinator.self) private var refreshCoordinator
    @Environment(AlertsStore.self) private var alertsStore

    var body: some View {
        NavigationStack {
            List {
                Section("Alerts (M4 acceptance)") {
                    LabeledContent("BG tasks", value: refreshCoordinator.backgroundTasksRegistered ? "registered ✓" : "✗")
                    LabeledContent("Authorization", value: authorizationLabel)
                    LabeledContent("Categories", value: alertsStore.categoriesRegistered ? "OPEN_MARKET + ECON_EVENT ✓" : "✗")
                    LabeledContent("Budget", value: budgetLabel)          // BudgetHealthRow data (UI lands M7)
                    #if DEBUG
                    LabeledContent("Test notification") {
                        if let fired = alertsStore.probeFiredAt {
                            Text("fired ✓ \(fired.formatted(date: .omitted, time: .standard))")
                        } else {
                            Text("scheduled — awaiting fire")
                        }
                    }
                    #endif
                    if let error = alertsStore.lastApplyError {
                        Text("Apply error: \(error)").font(.caption).foregroundStyle(.red)
                    }
                }
                Section("Up next") {
                    if let next = scheduleStore.nextEvent {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(next.title).font(.headline)
                            Text(next.subtitle).font(.subheadline).foregroundStyle(.secondary)
                            Text(next.date, style: .relative)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No upcoming events").foregroundStyle(.secondary)
                    }
                }
                Section("Today · \(scheduleStore.todayEvents.count) events") {
                    ForEach(scheduleStore.todayEvents.prefix(8)) { event in
                        HStack {
                            Text(event.title)
                            Spacer()
                            Text(event.date, style: .time).foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Offset")
        }
        .task {
            scheduleStore.refresh()
            #if DEBUG
            await debugProveNotificationPipeline()
            #endif
        }
    }

    private var authorizationLabel: String {
        switch alertsStore.authorizationStatus {
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .denied: "denied"
        case .notDetermined: "not determined"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown"
        }
    }

    /// The BudgetHealthRow arithmetic (04 §3.3): "N of 64 slots · through {weekday}".
    private var budgetLabel: String {
        var label = "\(alertsStore.pendingCount) of 64 slots"
        if let end = alertsStore.coverageEnd {
            label += " · through \(end.formatted(.dateTime.weekday(.wide)))"
        }
        return label
    }

    #if DEBUG
    /// M4 simulator acceptance: provisional auth (no prompt on sim), full rebuild
    /// through the planner, plus one near-term notification through the REAL apply
    /// path so the foreground banner + category can be captured in a screenshot.
    private func debugProveNotificationPipeline() async {
        await alertsStore.requestAuthorization(provisional: true)
        await refreshCoordinator.rebuildAlerts()
        let probe = PlannedNotification(
            id: "debug:banner-probe",
            fireDate: Date().addingTimeInterval(45),
            zoneID: TimeZone.current.identifier,
            title: "LDN opens in 15 min",
            body: "08:00 LDN · demo of the M4 pipeline",
            categoryID: NotificationCategoryID.openMarket,
            threadID: MarketID.fxLondon.rawValue,
            style: .timeSensitive,                        // delivered at .active (free team gate)
            priorityRank: 1
        )
        await alertsStore.scheduleAdHoc(probe)
        await alertsStore.refreshStatus()
    }
    #endif
}
