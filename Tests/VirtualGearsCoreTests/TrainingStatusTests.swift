import Foundation
import Testing

@testable import VirtualGearsCore

@Suite("Training status")
struct TrainingStatusTests {
    @Test("A waiting trainer says it is idle")
    func idle() {
        #expect(FTMSTrainingStatus.idle.encode() == Data([0x00, 0x01]))
    }

    @Test("A trainer sending ride data says the rider is riding")
    func riding() {
        // 0x0D is manual mode: riding, but not following a stored workout,
        // which is what passing a real trainer through amounts to.
        #expect(FTMSTrainingStatus.manualMode.encode() == Data([0x00, 0x0D]))
    }

    @Test("No status string is claimed")
    func noString() {
        for status in [FTMSTrainingStatus.idle, .manualMode] {
            #expect(status.encode().first == 0x00)
            #expect(status.encode().count == 2)
        }
    }
}
