import Foundation
import Testing

@testable import VirtualGearsCore

@Suite("Cycling power broadcast")
struct CyclingPowerBroadcastTests {
    @Test("Power is passed through unchanged")
    func passesPowerThrough() throws {
        var broadcast = CyclingPowerBroadcast()
        let data = broadcast.encode(powerWatts: 231, cadenceRPM: 90, at: 0)
        let decoded = try CyclingPowerMeasurement.decode(data)
        #expect(decoded.powerWatts == 231)
    }

    @Test("A trainer reporting no cadence does not claim a crank")
    func omitsCrankDataWithoutCadence() throws {
        var broadcast = CyclingPowerBroadcast()
        let data = broadcast.encode(powerWatts: 100, cadenceRPM: nil, at: 0)
        let decoded = try CyclingPowerMeasurement.decode(data)
        #expect(decoded.cumulativeCrankRevolutions == nil)
        #expect(decoded.lastCrankEventTime == nil)
        #expect(data.count == 4)
    }

    /// The point of the whole type: a riding app divides revolutions by elapsed
    /// crank time to recover cadence, so what it gets back has to be the
    /// cadence that went in.
    @Test("Cadence survives the round trip")
    func cadenceSurvivesTheRoundTrip() throws {
        var broadcast = CyclingPowerBroadcast()
        var tracker = CrankCadenceTracker()
        var recovered: [Double] = []

        for second in 0...20 {
            let data = broadcast.encode(
                powerWatts: 200,
                cadenceRPM: 85,
                at: TimeInterval(second)
            )
            if let cadence = tracker.update(
                with: try CyclingPowerMeasurement.decode(data)
            ) {
                recovered.append(cadence)
            }
        }

        let last = try #require(recovered.last)
        #expect(abs(last - 85) < 1)
    }

    @Test("Revolutions climb at the cadence asked for")
    func revolutionsClimbAtTheRightRate() throws {
        var broadcast = CyclingPowerBroadcast()
        // A minute at 60 rpm is sixty revolutions.
        for second in 0...60 {
            _ = broadcast.encode(
                powerWatts: 150,
                cadenceRPM: 60,
                at: TimeInterval(second)
            )
        }
        let data = broadcast.encode(powerWatts: 150, cadenceRPM: 60, at: 60)
        let decoded = try CyclingPowerMeasurement.decode(data)
        #expect(decoded.cumulativeCrankRevolutions == 60)
    }

    @Test("A stopped rider's counter stands still")
    func stoppedRiderDoesNotAdvance() throws {
        var broadcast = CyclingPowerBroadcast()
        _ = broadcast.encode(powerWatts: 0, cadenceRPM: 0, at: 0)
        let data = broadcast.encode(powerWatts: 0, cadenceRPM: 0, at: 30)
        let decoded = try CyclingPowerMeasurement.decode(data)
        #expect(decoded.cumulativeCrankRevolutions == 0)
    }

    /// Bluetooth timestamps can arrive out of order, and a counter that ran
    /// backwards would be read as a huge negative cadence.
    @Test("A clock that goes backwards does not wind the counter back")
    func clockGoingBackwardsIsIgnored() throws {
        var broadcast = CyclingPowerBroadcast()
        for second in 0...10 {
            _ = broadcast.encode(
                powerWatts: 200,
                cadenceRPM: 90,
                at: TimeInterval(second)
            )
        }
        let forward = try CyclingPowerMeasurement.decode(
            broadcast.encode(powerWatts: 200, cadenceRPM: 90, at: 10)
        )
        let backward = try CyclingPowerMeasurement.decode(
            broadcast.encode(powerWatts: 200, cadenceRPM: 90, at: 5)
        )
        #expect(
            backward.cumulativeCrankRevolutions
                == forward.cumulativeCrankRevolutions
        )
    }
}
