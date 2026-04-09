import BLEProtocol
import Foundation
import XCTest
@testable import BLECentralClient

final class LastKnownPayloadCacheTests: XCTestCase {
    func testEmptyCacheReturnsNilAndIsStale() async {
        let cache = LastKnownPayloadCache()
        let entry = await cache.entry(for: .clock)
        XCTAssertNil(entry)
        let stale = await cache.isStale(for: .clock, at: 0)
        XCTAssertTrue(stale)
        let screens = await cache.cachedScreens
        XCTAssertTrue(screens.isEmpty)
    }

    func testStoreAndFetchPerScreen() async {
        let cache = LastKnownPayloadCache()
        let clockBody = Data([0x01, 0x02, 0x03])
        let navBody = Data([0xAA, 0xBB])
        await cache.store(clockBody, for: .clock, at: 1.0)
        await cache.store(navBody, for: .navigation, at: 1.5)

        let clockEntry = await cache.entry(for: .clock)
        XCTAssertEqual(clockEntry?.body, clockBody)
        XCTAssertEqual(clockEntry?.receivedAt, 1.0)

        let navEntry = await cache.entry(for: .navigation)
        XCTAssertEqual(navEntry?.body, navBody)
        XCTAssertEqual(navEntry?.receivedAt, 1.5)

        // Screens independent of each other.
        let weather = await cache.entry(for: .weather)
        XCTAssertNil(weather)
    }

    func testStorageOverwritePreservesLatest() async {
        let cache = LastKnownPayloadCache()
        await cache.store(Data([0x01]), for: .clock, at: 1.0)
        await cache.store(Data([0x02, 0x03]), for: .clock, at: 2.0)
        let entry = await cache.entry(for: .clock)
        XCTAssertEqual(entry?.body, Data([0x02, 0x03]))
        XCTAssertEqual(entry?.receivedAt, 2.0)
    }

    func testStalenessThreshold() async {
        let cache = LastKnownPayloadCache(stalenessThresholdSeconds: 2.0)
        await cache.store(Data([0x01]), for: .clock, at: 10.0)
        // Within threshold.
        let fresh = await cache.isStale(for: .clock, at: 11.0)
        XCTAssertFalse(fresh)
        // Exactly at threshold: NOT stale (strict >).
        let onEdge = await cache.isStale(for: .clock, at: 12.0)
        XCTAssertFalse(onEdge)
        // Past threshold.
        let stale = await cache.isStale(for: .clock, at: 12.01)
        XCTAssertTrue(stale)
    }

    func testUpdateClearsStaleness() async {
        let cache = LastKnownPayloadCache(stalenessThresholdSeconds: 1.0)
        await cache.store(Data([0x01]), for: .clock, at: 0.0)
        let stale = await cache.isStale(for: .clock, at: 5.0)
        XCTAssertTrue(stale)
        await cache.store(Data([0x02]), for: .clock, at: 5.0)
        let fresh = await cache.isStale(for: .clock, at: 5.5)
        XCTAssertFalse(fresh)
    }

    func testCachedScreensLists() async {
        let cache = LastKnownPayloadCache()
        await cache.store(Data([0x00]), for: .clock, at: 0)
        await cache.store(Data([0x00]), for: .navigation, at: 0)
        await cache.store(Data([0x00]), for: .weather, at: 0)
        let screens = Set(await cache.cachedScreens)
        XCTAssertEqual(screens, Set<ScreenID>([.clock, .navigation, .weather]))
    }

    func testRemoveAndClear() async {
        let cache = LastKnownPayloadCache()
        await cache.store(Data([0x01]), for: .clock, at: 0)
        await cache.store(Data([0x02]), for: .navigation, at: 0)
        await cache.remove(.clock)
        let clockEntry = await cache.entry(for: .clock)
        XCTAssertNil(clockEntry)
        let navEntry = await cache.entry(for: .navigation)
        XCTAssertNotNil(navEntry)
        // Remove non-existent is a no-op.
        await cache.remove(.weather)
        await cache.clear()
        let afterClear = await cache.cachedScreens
        XCTAssertTrue(afterClear.isEmpty)
    }

    func testEntryEquality() {
        let a = LastKnownPayloadCache.Entry(body: Data([0x01]), receivedAt: 1.0)
        let b = LastKnownPayloadCache.Entry(body: Data([0x01]), receivedAt: 1.0)
        let c = LastKnownPayloadCache.Entry(body: Data([0x02]), receivedAt: 1.0)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
