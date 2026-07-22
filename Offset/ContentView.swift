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

    var body: some View {
        NavigationStack {
            List {
                Section("Refresh (M3 acceptance)") {
                    LabeledContent("BG tasks registered",
                                   value: refreshCoordinator.backgroundTasksRegistered ? "✓" : "✗")
                    LabeledContent("Task ids") {
                        Text("…refresh.schedule + …refresh.news")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let last = refreshCoordinator.lastRefresh {
                        LabeledContent("Last refresh") {
                            Text(last, style: .time)
                        }
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
        }
    }
}
