import XCTest
import BLEProtocol
@testable import ScramCore

@MainActor
final class ScreenPickerViewModelTests: XCTestCase {
    func test_initialState_loadsAvailableScreens() {
        let controller = ScreenController()
        let vm = ScreenPickerViewModel(controller: controller)
        XCTAssertEqual(vm.screens.count, ScreenSelection.availableScreens.count)
        XCTAssertEqual(vm.activeScreenID, .clock)
    }

    func test_selectScreen_updatesActiveAndEmitsCommand() async throws {
        let controller = ScreenController()
        let vm = ScreenPickerViewModel(controller: controller)

        var iterator = controller.commands.makeAsyncIterator()
        vm.selectScreen(.compass)
        XCTAssertEqual(vm.activeScreenID, .compass)
        let cmd = await iterator.next()
        XCTAssertEqual(cmd, .setActiveScreen(.compass))
    }

    func test_selectDisabledScreen_isIgnored() async {
        let controller = ScreenController()
        let vm = ScreenPickerViewModel(controller: controller)
        vm.setEnabled(.compass, enabled: false)
        vm.selectScreen(.compass)
        XCTAssertEqual(vm.activeScreenID, .clock)
    }

    func test_setEnabled_persistsToStore() {
        let store = InMemoryKeyValueStore()
        let controller = ScreenController()
        let vm = ScreenPickerViewModel(controller: controller, store: store)
        vm.setEnabled(.navigation, enabled: false)
        let prefs = ScreenPreferences.load(from: store)
        XCTAssertEqual(prefs?.disabledScreenIDs.contains(0x01), true)
    }

    func test_move_persistsAndReorders() {
        let store = InMemoryKeyValueStore()
        let controller = ScreenController()
        let vm = ScreenPickerViewModel(controller: controller, store: store)
        // Move first item (clock) past compass.
        vm.move(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        let prefs = ScreenPreferences.load(from: store)
        XCTAssertEqual(prefs?.orderedScreenIDs.first, vm.screens.first?.screenID.rawValue)
    }

    func test_persistedReorderRestoresOnReinit() {
        let store = InMemoryKeyValueStore()
        let controller = ScreenController()
        let vm = ScreenPickerViewModel(controller: controller, store: store)
        vm.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        let firstAfterMove = vm.screens.first?.screenID

        let vm2 = ScreenPickerViewModel(controller: controller, store: store)
        XCTAssertEqual(vm2.screens.first?.screenID, firstAfterMove)
    }

    func test_brightnessSliderEmitsCommand() async throws {
        let controller = ScreenController()
        let vm = ScreenPickerViewModel(controller: controller)
        vm.brightnessPercent = 60
        var iterator = controller.commands.makeAsyncIterator()
        vm.applyBrightness()
        let cmd = await iterator.next()
        XCTAssertEqual(cmd, .setBrightness(60))
    }

    func test_sleepWakeClearEmitCommands() async throws {
        let controller = ScreenController()
        let vm = ScreenPickerViewModel(controller: controller)
        var iterator = controller.commands.makeAsyncIterator()
        vm.sleep()
        let a = await iterator.next()
        vm.wake()
        let b = await iterator.next()
        vm.clearAlertOverlay()
        let c = await iterator.next()
        XCTAssertEqual([a, b, c], [.sleep, .wake, .clearAlertOverlay])
    }
}
