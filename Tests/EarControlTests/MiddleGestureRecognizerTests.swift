import AppKit
import XCTest
@testable import EarControl

final class MiddleGestureRecognizerTests: XCTestCase {
    func testSingleClickWaitsForWindowAndFiresOnce() {
        var recognizer = MiddleGestureRecognizer()
        recognizer.press(at: 0)
        XCTAssertNil(recognizer.release(at: 0.10))
        XCTAssertNil(recognizer.flush(at: 0.449))
        XCTAssertEqual(recognizer.flush(at: 0.45), .gesture(.single))
        XCTAssertNil(recognizer.flush(at: 1.0))
    }

    func testDoubleClickDoesNotFireSingle() {
        var recognizer = MiddleGestureRecognizer()
        recognizer.press(at: 0)
        XCTAssertNil(recognizer.release(at: 0.10))
        recognizer.press(at: 0.18)
        XCTAssertNil(recognizer.release(at: 0.28))
        XCTAssertNil(recognizer.flush(at: 0.629))
        XCTAssertEqual(recognizer.flush(at: 0.63), .gesture(.double))
        XCTAssertNil(recognizer.flush(at: 1.0))
    }

    func testTripleClickFiresImmediatelyOnThirdRelease() {
        var recognizer = MiddleGestureRecognizer()
        recognizer.press(at: 0)
        XCTAssertNil(recognizer.release(at: 0.10))
        recognizer.press(at: 0.18)
        XCTAssertNil(recognizer.release(at: 0.28))
        recognizer.press(at: 0.36)
        XCTAssertEqual(recognizer.release(at: 0.46), .gesture(.triple))
        XCTAssertNil(recognizer.flush(at: 1.0))
    }

    func testShortClickFollowedByLongPressOnlyFiresLongPress() {
        var recognizer = MiddleGestureRecognizer()
        recognizer.press(at: 0)
        XCTAssertNil(recognizer.release(at: 0.10))
        recognizer.press(at: 0.18)
        XCTAssertEqual(recognizer.release(at: 1.0), .longPress)
        XCTAssertNil(recognizer.flush(at: 2.0))
    }

    func testResetCancelsPendingGesture() {
        var recognizer = MiddleGestureRecognizer()
        recognizer.press(at: 0)
        XCTAssertNil(recognizer.release(at: 0.10))
        recognizer.reset()
        XCTAssertNil(recognizer.flush(at: 1.0))
    }
}

final class VoiceTriggerStateMachineTests: XCTestCase {
    func testRestartDelayIsEightyMilliseconds() {
        XCTAssertEqual(VoiceTriggerStateMachine.restartDelay, 0.08)
    }

    func testInitialStartPressesImmediately() {
        var stateMachine = VoiceTriggerStateMachine()

        XCTAssertEqual(stateMachine.startOrRestart(), [.press])
        XCTAssertEqual(stateMachine.state, .held)
    }

    func testActiveVoiceReleasesThenSchedulesRestart() {
        var stateMachine = VoiceTriggerStateMachine()
        _ = stateMachine.startOrRestart()

        XCTAssertEqual(stateMachine.startOrRestart(), [.release, .scheduleRestart])
        XCTAssertEqual(stateMachine.state, .restartPending)
        XCTAssertEqual(stateMachine.restartDelayElapsed(), [.press])
        XCTAssertEqual(stateMachine.state, .held)
    }

    func testRepeatedRestartReplacesPendingSchedule() {
        var stateMachine = VoiceTriggerStateMachine()
        _ = stateMachine.startOrRestart()
        _ = stateMachine.startOrRestart()

        XCTAssertEqual(
            stateMachine.startOrRestart(),
            [.cancelScheduledRestart, .scheduleRestart]
        )
        XCTAssertEqual(stateMachine.restartDelayElapsed(), [.press])
        XCTAssertEqual(stateMachine.restartDelayElapsed(), [])
    }

    func testCancelHeldVoiceReleasesModifier() {
        var stateMachine = VoiceTriggerStateMachine()
        _ = stateMachine.startOrRestart()

        XCTAssertEqual(stateMachine.cancel(), [.release])
        XCTAssertEqual(stateMachine.state, .idle)
    }

    func testCancelPendingRestartPreventsDelayedPress() {
        var stateMachine = VoiceTriggerStateMachine()
        _ = stateMachine.startOrRestart()
        _ = stateMachine.startOrRestart()

        XCTAssertEqual(stateMachine.cancel(), [.cancelScheduledRestart])
        XCTAssertEqual(stateMachine.state, .idle)
        XCTAssertEqual(stateMachine.restartDelayElapsed(), [])
    }
}

final class WindowPresentationPolicyTests: XCTestCase {
    func testSetupWindowHasHighestPriority() {
        XCTAssertEqual(
            menuBarClickTarget(setupAvailable: true, settingsAvailable: true),
            .setup
        )
    }

    func testSettingsWindowPreventsPanelFromOpening() {
        XCTAssertEqual(
            menuBarClickTarget(setupAvailable: false, settingsAvailable: true),
            .settings
        )
    }

    func testPanelOpensOnlyWithoutPrimaryWindows() {
        XCTAssertEqual(
            menuBarClickTarget(setupAvailable: false, settingsAvailable: false),
            .panel
        )
    }
}

final class VoiceLifecycleModelTests: XCTestCase {
    func testRestartAndSpaceChangeKeepBlueStateAccurate() {
        let model = EarControlModel()

        model.recordMappedAction(.voiceStarted(.rightOption))
        XCTAssertTrue(model.voiceActive)

        model.recordMappedAction(.voiceRestarting(.rightOption))
        XCTAssertFalse(model.voiceActive)

        model.recordMappedAction(.voiceRestarted(.rightOption))
        XCTAssertTrue(model.voiceActive)

        model.recordMappedAction(.voiceInterruptedBySpaceChange)
        XCTAssertFalse(model.voiceActive)
        XCTAssertEqual(model.lastMappedAction, "桌面切换导致语音结束")
    }
}

final class RecordedShortcutTests: XCTestCase {
    func testDisplayNamesForKeysAndModifiers() {
        XCTAssertEqual(RecordedShortcut.key(keyCode: 0, modifiers: []).displayTitle, "A")
        XCTAssertEqual(RecordedShortcut.key(keyCode: 36, modifiers: []).displayTitle, "Return")
        XCTAssertEqual(RecordedShortcut.key(keyCode: 51, modifiers: []).displayTitle, "Delete")
        XCTAssertEqual(RecordedShortcut.key(keyCode: 53, modifiers: []).displayTitle, "Escape")
        XCTAssertEqual(
            RecordedShortcut.key(keyCode: 40, modifiers: [.command, .shift]).displayTitle,
            "⇧⌘K"
        )
        XCTAssertEqual(RecordedShortcut.modifier(keyCode: 55)?.displayTitle, "左 Command")
        XCTAssertEqual(RecordedShortcut.modifier(keyCode: 61)?.displayTitle, "右 Option")
        XCTAssertEqual(MiddleGestureAction.selectAllAndDelete.displayTitle, "全选并删除")
        XCTAssertEqual(MiddleGestureAction.finishVoiceAndSend.displayTitle, "结束语音并发送")
    }

    func testMappingsPersistAndReload() throws {
        let suiteName = "EarControlTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var mappings = MiddleGestureMappings.defaults
        mappings.single = .shortcut(.key(keyCode: 18, modifiers: []))
        mappings.double = .selectAllAndDelete
        mappings.triple = .finishVoiceAndSend
        MiddleGestureMappingsStore.save(mappings, to: defaults)

        XCTAssertEqual(MiddleGestureMappingsStore.load(from: defaults), mappings)
    }

    func testLegacyMappingsMigrateToV2() throws {
        let suiteName = "EarControlTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacy = LegacyMiddleGestureMappingsFixture(
            single: .key(keyCode: 18, modifiers: []),
            double: .key(keyCode: 19, modifiers: [.command]),
            triple: .modifier(keyCode: 61)
        )
        defaults.set(
            try JSONEncoder().encode(legacy),
            forKey: MiddleGestureMappingsStore.legacyDefaultsKey
        )

        let migrated = MiddleGestureMappingsStore.load(from: defaults)
        XCTAssertEqual(migrated.single, .shortcut(try XCTUnwrap(legacy.single)))
        XCTAssertEqual(migrated.double, .shortcut(try XCTUnwrap(legacy.double)))
        XCTAssertEqual(migrated.triple, .shortcut(try XCTUnwrap(legacy.triple)))
        XCTAssertNotNil(defaults.data(forKey: MiddleGestureMappingsStore.defaultsKey))
    }
}

final class MenuBarIconTests: XCTestCase {
    func testSourceImageContainsResolvedPixelsForMenuBarCaptureApps() throws {
        let darkOnLightImage = makeMenuBarRemoteImage(color: .black)
        let lightOnDarkImage = makeMenuBarRemoteImage(color: .white)
        XCTAssertFalse(darkOnLightImage.isTemplate)
        XCTAssertFalse(lightOnDarkImage.isTemplate)

        let darkColor = try renderedColor(of: darkOnLightImage, at: NSPoint(x: 9, y: 12))
        let lightColor = try renderedColor(of: lightOnDarkImage, at: NSPoint(x: 9, y: 12))

        XCTAssertLessThan(darkColor.brightnessComponent, 0.25)
        XCTAssertGreaterThan(lightColor.brightnessComponent, 0.75)
        XCTAssertGreaterThan(darkColor.alphaComponent, 0.5)
        XCTAssertGreaterThan(lightColor.alphaComponent, 0.5)
    }

    private func renderedColor(
        of image: NSImage,
        at point: NSPoint
    ) throws -> NSColor {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 18,
                pixelsHigh: 18,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let color = try XCTUnwrap(bitmap.colorAt(x: Int(point.x), y: Int(point.y)))
        return try XCTUnwrap(color.usingColorSpace(.deviceRGB))
    }
}

private struct LegacyMiddleGestureMappingsFixture: Codable {
    let single: RecordedShortcut?
    let double: RecordedShortcut?
    let triple: RecordedShortcut?
}
