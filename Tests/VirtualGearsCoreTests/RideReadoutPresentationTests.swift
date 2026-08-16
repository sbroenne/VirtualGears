import XCTest
@testable import VirtualGearsCore

/// The gear read-out is the only thing on the screen a rider looks at while
/// pedalling, so how it is drawn is a decision worth pinning down rather than
/// leaving to whichever font size someone last typed into the view.
final class RideReadoutPresentationTests: XCTestCase {
    func testTheRailFillsEveryGearBehindTheConfirmedOne() {
        let markers = GearRail.markers(count: 8, selected: 3, requested: nil)

        XCTAssertEqual(
            markers,
            [.behind, .behind, .behind, .selected, .ahead, .ahead, .ahead, .ahead]
        )
    }

    func testTheRailMarksTheRequestedGearUntilTheTrainerConfirmsIt() {
        let harder = GearRail.markers(count: 6, selected: 2, requested: 4)
        XCTAssertEqual(
            harder,
            [.behind, .behind, .selected, .ahead, .requested, .ahead]
        )

        let easier = GearRail.markers(count: 6, selected: 4, requested: 1)
        XCTAssertEqual(
            easier,
            [.behind, .requested, .behind, .behind, .selected, .ahead]
        )
    }

    func testAConfirmedRequestIsDrawnOnlyAsTheSelectedGear() {
        let markers = GearRail.markers(count: 4, selected: 2, requested: 2)

        XCTAssertEqual(markers, [.behind, .behind, .selected, .ahead])
        XCTAssertFalse(markers.contains(.requested))
    }

    func testAnUnconfirmedRailClaimsNoPosition() {
        let markers = GearRail.markers(count: 3, selected: nil, requested: nil)

        XCTAssertEqual(markers, [.ahead, .ahead, .ahead])
        XCTAssertFalse(markers.contains(.selected))
        XCTAssertFalse(markers.contains(.behind))
    }

    func testTheRailIgnoresPositionsThatDoNotExist() {
        XCTAssertTrue(GearRail.markers(count: 0, selected: 0, requested: 0).isEmpty)
        XCTAssertTrue(GearRail.markers(count: -4, selected: nil, requested: nil).isEmpty)
        XCTAssertEqual(
            GearRail.markers(count: 3, selected: 9, requested: -2),
            [.ahead, .ahead, .ahead]
        )
    }

    func testEveryMarkerKindIsDistinguishableWithoutColour() {
        // Colour alone is not readable at a glance on a bike, and is not
        // readable at all to a rider who cannot tell these colours apart.
        let heights = Set(GearRailMarker.allCases.map(\.relativeHeight))
        XCTAssertEqual(heights.count, GearRailMarker.allCases.count)
        XCTAssertEqual(GearRailMarker.selected.relativeHeight, 1)
        for marker in GearRailMarker.allCases where marker != .selected {
            XCTAssertLessThan(marker.relativeHeight, 1)
            XCTAssertGreaterThan(marker.relativeHeight, 0)
        }
    }

    func testTheSecondLineStaysSubordinateToTheGearNumber() {
        // The gear position owns the screen. Everything else on the read-out is
        // a caption to it, whatever size the gear itself ends up being — unless
        // being subordinate would take it below the size it can still be read
        // at, in which case being readable wins.
        for primary in stride(from: 44.0, through: 320.0, by: 4.0) {
            let secondary = GearReadoutMetrics.secondaryPointSize(forPrimary: primary)
            XCTAssertGreaterThanOrEqual(secondary, 15)
            XCTAssertLessThanOrEqual(secondary, 24)
            XCTAssertTrue(
                secondary <= primary * 0.3 || secondary == 15,
                "\(secondary)pt is too loud next to a \(primary)pt gear"
            )
        }
    }

    func testTheSecondLineNeverShrinksAsTheGearGrows() {
        let sizes = stride(from: 44.0, through: 320.0, by: 8.0)
            .map(GearReadoutMetrics.secondaryPointSize(forPrimary:))

        XCTAssertEqual(sizes, sizes.sorted())
    }

    func testCassettesOfTheSameSpreadAreToldApartByTheirCogCount() {
        // Three different cassettes are all called "11-28". Saying only that
        // leaves a rider unable to tell which one they picked.
        let repeated = Dictionary(grouping: DrivetrainCatalog.cassettes, by: \.name)
            .filter { $0.value.count > 1 }
        XCTAssertFalse(repeated.isEmpty, "The catalogue no longer repeats a name")

        for option in DrivetrainCatalog.cassettes {
            XCTAssertEqual(option.qualifiedName, "\(option.name) · \(option.speeds) cogs")
        }

        let qualified = Set(DrivetrainCatalog.cassettes.map(\.qualifiedName))
        XCTAssertEqual(qualified.count, DrivetrainCatalog.cassettes.count)
    }
}
