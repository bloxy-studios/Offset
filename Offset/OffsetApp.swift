//
//  OffsetApp.swift
//  Offset
//
//  @main. Scene setup; registers BOTH BGTask ids before end of launch
//  (research-MS HALF2 §2); runs the KeychainStore secrets bootstrap (02 §6);
//  observes system change signals on the root view (02 §5.2).
//  M5 adds Live Activity orphan reconciliation; M4 adds the notification
//  delegate installation.
//

import OffsetKit
import OSLog
import SwiftUI

@main
struct OffsetApp: App {

    @State private var scheduleStore: ScheduleStore
    @State private var refreshCoordinator: RefreshCoordinator
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Seed decode failures are programmer errors — fail fast with an OSLog
        // fault (03 §2d): bundled data is fixed at build time.
        let engine: SessionScheduleEngine
        do {
            engine = SessionScheduleEngine(seed: try SessionScheduleEngine.loadBundledSeed())
        } catch {
            Logger(subsystem: SharedConstants.logSubsystem, category: "engine")
                .fault("Bundled seed decode failed: \(error)")
            fatalError("Offset cannot start without its bundled seed data: \(error)")
        }

        let store = ScheduleStore(engine: engine)
        let coordinator = RefreshCoordinator(scheduleStore: store)
        coordinator.registerBackgroundTasks()            // before end of launch
        KeychainStore().bootstrap()                      // secrets pipeline (02 §6)

        _scheduleStore = State(initialValue: store)
        _refreshCoordinator = State(initialValue: coordinator)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(scheduleStore)
                .environment(refreshCoordinator)
                .onReceive(NotificationCenter.default.publisher(
                    for: UIApplication.significantTimeChangeNotification)) { _ in
                    refreshCoordinator.handleSignificantTimeChange()
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: .NSSystemTimeZoneDidChange)) { _ in
                    refreshCoordinator.handleTimeZoneChange()
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: .NSCalendarDayChanged)) { _ in
                    refreshCoordinator.handleDayChange()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshCoordinator.handleScenePhaseActive()
            }
        }
    }
}
