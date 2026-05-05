import XCTest
@testable import CodexPetLimitsViewerCore

final class CodexPetLimitsViewerCoreTests: XCTestCase {
    func testHoverAppearsOnlyAfterStableDelay() {
        var gate = HoverGate(hoverDelay: 0.50, movementSettleDelay: 0.20)
        let petFrame = CGRect(x: 100, y: 100, width: 64, height: 64)
        let pointer = CGPoint(x: 120, y: 120)

        XCTAssertFalse(gate.update(now: 10.00, pointer: pointer, petFrame: petFrame, mouseDown: false))
        XCTAssertFalse(gate.update(now: 10.49, pointer: pointer, petFrame: petFrame, mouseDown: false))
        XCTAssertTrue(gate.update(now: 10.51, pointer: pointer, petFrame: petFrame, mouseDown: false))
        XCTAssertFalse(gate.update(now: 10.60, pointer: CGPoint(x: 20, y: 20), petFrame: petFrame, mouseDown: false))
    }

    func testDragOrPetMovementSuppressesHover() {
        var gate = HoverGate(hoverDelay: 0.50, movementSettleDelay: 0.20)
        let firstFrame = CGRect(x: 100, y: 100, width: 64, height: 64)
        let movedFrame = CGRect(x: 150, y: 100, width: 64, height: 64)
        let pointer = CGPoint(x: 160, y: 120)

        XCTAssertFalse(gate.update(now: 20.00, pointer: pointer, petFrame: firstFrame, mouseDown: true))
        XCTAssertFalse(gate.update(now: 20.10, pointer: pointer, petFrame: firstFrame, mouseDown: false))
        XCTAssertTrue(gate.update(now: 20.61, pointer: pointer, petFrame: firstFrame, mouseDown: false))

        XCTAssertFalse(gate.update(now: 20.70, pointer: pointer, petFrame: movedFrame, mouseDown: false))
        XCTAssertFalse(gate.update(now: 21.10, pointer: pointer, petFrame: movedFrame, mouseDown: false))
        XCTAssertTrue(gate.update(now: 21.61, pointer: pointer, petFrame: movedFrame, mouseDown: false))
    }

    func testPopoverPlacementPrefersAboveAndClampsToScreen() {
        let size = CGSize(width: 180, height: 92)
        let screen = CGRect(x: 0, y: 0, width: 400, height: 300)
        let middlePet = CGRect(x: 100, y: 100, width: 64, height: 64)

        let middle = LimitPopoverPlacer.origin(for: size, near: middlePet, in: screen)
        XCTAssertEqual(middle.x, 42, accuracy: 0.001)
        XCTAssertEqual(middle.y, 172, accuracy: 0.001)

        let leftPet = CGRect(x: 2, y: 100, width: 64, height: 64)
        let left = LimitPopoverPlacer.origin(for: size, near: leftPet, in: screen)
        XCTAssertEqual(left.x, 8, accuracy: 0.001)

        let topPet = CGRect(x: 100, y: 250, width: 64, height: 64)
        let top = LimitPopoverPlacer.origin(for: size, near: topPet, in: screen)
        XCTAssertEqual(top.y, 150, accuracy: 0.001)
    }

    func testElectronNegativeYFrameMapsToAppKitScreenFrame() {
        let screen = CGRect(x: -549, y: 982, width: 2560, height: 1440)
        let rawPet = CGRect(x: -469, y: -1348, width: 80, height: 87)
        let mapped = PetFrameMapper.appKitFrame(from: rawPet, screens: [screen])

        XCTAssertEqual(mapped.origin.x, -469, accuracy: 0.001)
        XCTAssertEqual(mapped.origin.y, 2243, accuracy: 0.001)
        XCTAssertTrue(screen.contains(mapped))
    }

    func testLimitLineFormatting() {
        let fiveHour = LimitBucket(name: "5h", percentRemaining: 0.72, resetText: "14:35")
        XCTAssertEqual(fiveHour.displayLine, "5h    72% left    resets 14:35")

        let weekly = LimitBucket(name: "Week", percentRemaining: nil, resetText: nil)
        XCTAssertEqual(weekly.displayLine, "Week  unavailable")
    }

    func testLiveUsageShapeDecodesPrimaryAndSecondaryLimits() throws {
        let json = """
        {
          "rate_limit": {
            "primary": { "used_percent": 21.2, "reset_at": 1777996800 },
            "secondary": { "used_percent": 4.7, "reset_at": 1778020740 }
          }
        }
        """
        let state = LimitStateReader().parseUsageJSON(Data(json.utf8), source: "Live")

        XCTAssertEqual(state?.fiveHour.percentRemaining ?? -1, 0.788, accuracy: 0.001)
        XCTAssertEqual(state?.weekly.percentRemaining ?? -1, 0.953, accuracy: 0.001)
        XCTAssertEqual(state?.source, "Live")
    }
}
