import AppKit
import Carbon.HIToolbox
import XCTest

@testable import Halo

final class GammaTableTests: XCTestCase {
    func testScalingMultipliesEveryChannelPastOne() {
        let table = GammaTable(red: [0, 0.5, 1], green: [0, 0.25, 1], blue: [0, 0.75, 1])

        let scaled = table.scaled(by: 1.5)

        XCTAssertEqual(scaled.red, [0, 0.75, 1.5])
        XCTAssertEqual(scaled.green, [0, 0.375, 1.5])
        XCTAssertEqual(scaled.blue, [0, 1.125, 1.5])
    }

    func testScalingByOneLeavesTableUnchanged() {
        let table = GammaTable(red: [0, 0.4, 1], green: [0, 0.5, 1], blue: [0, 0.6, 1])

        XCTAssertEqual(table.scaled(by: 1), table)
    }
}

final class BoostFactorTests: XCTestCase {
    func testStoredValueInsideRangeIsKept() {
        XCTAssertEqual(BoostFactor.clamped(1.25), 1.25)
    }

    func testStoredValueOutsideRangeIsClampedToTheNearestBound() {
        XCTAssertEqual(BoostFactor.clamped(3.0), 2.0)
        XCTAssertEqual(BoostFactor.clamped(0.2), 1.0)
    }

    func testMissingOrInvalidValueFallsBackToDefault() {
        XCTAssertEqual(BoostFactor.clamped(nil), 1.5)
        XCTAssertEqual(BoostFactor.clamped("bright"), 1.5)
        XCTAssertEqual(BoostFactor.clamped(Double.nan), 1.5)
    }

    func testSteppingMovesOneStepEitherWay() {
        XCTAssertEqual(BoostFactor.stepped(1.5, by: 1), 1.6, accuracy: 1e-9)
        XCTAssertEqual(BoostFactor.stepped(1.5, by: -1), 1.4, accuracy: 1e-9)
    }

    func testSteppingStopsAtTheEndsOfTheRange() {
        XCTAssertEqual(BoostFactor.stepped(1.95, by: 1), 2.0)
        XCTAssertEqual(BoostFactor.stepped(1.05, by: -1), 1.0)
    }
}

final class KeyComboTests: XCTestCase {
    private let keyB: UInt16 = 11
    private let space: UInt16 = 49

    func testRequiresCommandOptionOrControl() {
        XCTAssertNil(KeyCombo(keyCode: keyB, modifiers: [], characters: "b"))
        XCTAssertNil(KeyCombo(keyCode: keyB, modifiers: .shift, characters: "B"))
        XCTAssertNotNil(KeyCombo(keyCode: keyB, modifiers: .option, characters: "b"))
    }

    func testIgnoresModifiersThatAreNotPartOfAShortcut() {
        let combo = KeyCombo(keyCode: keyB, modifiers: [.control, .capsLock], characters: "b")
        XCTAssertEqual(combo?.modifiers, .control)
    }

    func testDisplayStringFollowsMenuOrder() {
        let combo = KeyCombo(
            keyCode: keyB, modifiers: [.command, .shift, .option, .control], characters: "b")
        XCTAssertEqual(combo?.displayString, "⌃⌥⇧⌘B")
    }

    func testBlankKeysUseTheirOwnName() {
        let combo = KeyCombo(keyCode: space, modifiers: .command, characters: " ")
        XCTAssertEqual(combo?.displayString, "⌘Space")
    }

    func testCarbonModifiersMatchHeldKeys() {
        let combo = KeyCombo(keyCode: keyB, modifiers: [.control, .option], characters: "b")
        XCTAssertEqual(combo?.carbonModifiers, UInt32(controlKey | optionKey))
    }

    func testKeyWithNothingToShowIsRefused() {
        XCTAssertNil(KeyCombo(keyCode: keyB, modifiers: .command, characters: nil))
        XCTAssertNil(KeyCombo(keyCode: keyB, modifiers: .command, characters: " "))
    }

    func testFunctionKeysPastF12UseTheirOwnName() {
        let combo = KeyCombo(
            keyCode: UInt16(kVK_F19), modifiers: .control, characters: "\u{F716}")
        XCTAssertEqual(combo?.displayString, "⌃F19")
    }

    func testSameKeysUnderAnotherLayoutsNameStillMatch() throws {
        let recorded = try XCTUnwrap(
            KeyCombo(keyCode: keyB, modifiers: .command, characters: "b"))
        let underAnotherLayout = try XCTUnwrap(
            KeyCombo(keyCode: keyB, modifiers: .command, characters: "x"))
        let withShift = try XCTUnwrap(
            KeyCombo(keyCode: keyB, modifiers: [.command, .shift], characters: "b"))

        XCTAssertTrue(recorded.usesSameKeys(as: underAnotherLayout))
        XCTAssertFalse(recorded.usesSameKeys(as: withShift))
    }

    func testCommandAloneWithAStandardKeyIsAStandardAppShortcut() throws {
        let quit = try XCTUnwrap(
            KeyCombo(keyCode: UInt16(kVK_ANSI_Q), modifiers: .command, characters: "q"))
        let withOption = try XCTUnwrap(
            KeyCombo(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.command, .option], characters: "q"))
        let commandB = try XCTUnwrap(
            KeyCombo(keyCode: keyB, modifiers: .command, characters: "b"))

        XCTAssertTrue(quit.isStandardAppShortcut)
        XCTAssertFalse(withOption.isStandardAppShortcut)
        XCTAssertFalse(commandB.isStandardAppShortcut)
    }

    // Shortcuts are saved to UserDefaults as JSON and read back at launch.
    func testSavedComboDecodesToTheSameShortcut() throws {
        let combo = try XCTUnwrap(
            KeyCombo(keyCode: keyB, modifiers: [.command, .shift], characters: "b"))

        let decoded = try JSONDecoder().decode(
            KeyCombo.self, from: JSONEncoder().encode(combo))

        XCTAssertEqual(decoded, combo)
        XCTAssertEqual(decoded.displayString, "⇧⌘B")
    }
}

final class FullBrightnessRuleTests: XCTestCase {
    func testDroppingBelowTheDimmedLevelSuspendsTheBoost() {
        XCTAssertEqual(
            FullBrightnessRule.change(from: 1, to: 0.5, isEnabled: true, isWaiting: false),
            .suspend)
        XCTAssertEqual(
            FullBrightnessRule.change(from: 0.8, to: 0.79, isEnabled: true, isWaiting: false),
            .suspend)
    }

    // Auto-brightness moves the slider like this as the room light changes.
    func testSmallDipFromFullLeavesTheBoostOn() {
        XCTAssertNil(
            FullBrightnessRule.change(from: 1, to: 0.9, isEnabled: true, isWaiting: false))
        XCTAssertNil(
            FullBrightnessRule.change(from: 0.9, to: 0.8, isEnabled: true, isWaiting: false))
    }

    func testDimmingFurtherLeavesAManualBoostOn() {
        let change = FullBrightnessRule.change(
            from: 0.6, to: 0.5, isEnabled: true, isWaiting: false)
        XCTAssertNil(change)
    }

    func testReachingFullResumesOnlyWhileWaiting() {
        XCTAssertEqual(
            FullBrightnessRule.change(from: 0.9, to: 1, isEnabled: false, isWaiting: true), .resume)
        XCTAssertNil(
            FullBrightnessRule.change(from: 0.9, to: 1, isEnabled: false, isWaiting: false))
    }

    func testStayingBelowFullKeepsWaiting() {
        XCTAssertNil(
            FullBrightnessRule.change(from: 0.5, to: 0.8, isEnabled: false, isWaiting: true))
    }

    func testDimmedStartsJustBelowTheDimmedLevel() {
        XCTAssertFalse(FullBrightnessRule.isDimmed(0.8))
        XCTAssertTrue(FullBrightnessRule.isDimmed(0.799))
    }

    func testTopOfTheSliderJustUnderOneCountsAsFull() {
        XCTAssertTrue(FullBrightnessRule.isFull(0.999))
        XCTAssertFalse(FullBrightnessRule.isFull(0.98))
    }
}

final class BoostErrorTests: XCTestCase {
    // The message is all Settings shows, so it has to say which display and which call failed.
    func testMessageNamesTheDisplayAndTheError() {
        let error = BoostError.gammaWrite(display: 2, error: .illegalArgument)
        XCTAssertEqual(
            error.message, "Couldn't set the gamma table of display 2 (CGError 1001).")
    }
}
