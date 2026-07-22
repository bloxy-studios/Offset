//
//  AlertsStoreTests.swift
//  OffsetTests
//
//  The free-personal-team delivery gate (DECISIONS Setup facts M0; 04 §4.4):
//  .timeSensitive maps to the time-sensitive interruption level ONLY when the
//  entitlement is present — absent (current signing) it delivers at .active.
//

import Testing
import UserNotifications
@testable import Offset
@testable import OffsetKit

@Suite("AlertsStore interruption gate")
struct AlertsStoreInterruptionTests {

    @Test func timeSensitiveIsGatedByEntitlement() {
        #expect(AlertsStore.interruptionLevel(for: .timeSensitive,
                                              timeSensitiveEntitlementPresent: false) == .active)
        #expect(AlertsStore.interruptionLevel(for: .timeSensitive,
                                              timeSensitiveEntitlementPresent: true) == .timeSensitive)
    }

    @Test func standardAndCriticalNeverEscalate() {
        for present in [true, false] {
            #expect(AlertsStore.interruptionLevel(for: .standard,
                                                  timeSensitiveEntitlementPresent: present) == .active)
            // .criticalAlarm never reaches the notification lane as more than .active
            // (the alarm experience is AlarmKit's, 04 §5).
            #expect(AlertsStore.interruptionLevel(for: .criticalAlarm,
                                                  timeSensitiveEntitlementPresent: present) == .active)
        }
    }

    @Test func currentBuildHasNoTimeSensitiveEntitlement() {
        // Free personal team (DECISIONS Setup facts M0) — flips with the paid program.
        #expect(!Capabilities.timeSensitiveEntitlementPresent)
    }
}
