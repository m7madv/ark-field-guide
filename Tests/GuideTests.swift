import XCTest
@testable import ARKFieldGuide

final class GuideTests: XCTestCase {
    func testArabicSearchVariants() {
        let creature = Creature(id: "argentavis", arabic: "أرجنتافيس", english: "Argentavis", aliases: ["أرجي"])
        XCTAssertTrue(creature.matches("ارجنتافيس"))
        XCTAssertTrue(creature.matches("أَرْجِي"))
        XCTAssertTrue(creature.matches("ARGENT"))
        XCTAssertFalse(creature.matches("ريكس"))
    }

    func testCoordinateValidation() {
        XCTAssertEqual(Sighting.coordinate("٢٥٫٥"), 25.5)
        XCTAssertEqual(Sighting.coordinate("۲۵٫۵"), 25.5)
        XCTAssertEqual(Sighting.coordinate("100"), 100)
        XCTAssertNil(Sighting.coordinate("100.1"))
        XCTAssertNil(Sighting.coordinate("-1"))
        XCTAssertNil(Sighting.coordinate("nan"))
        XCTAssertNil(Sighting.coordinate(""))
    }

    @MainActor func testBackupMergeAndRejectInvalidCoordinates() throws {
        let suite = "ARKGuideBackupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GuideStore(defaults: defaults)
        let creature = try XCTUnwrap(store.creatures.first)
        store.add(Sighting(creatureID: creature.id, server: "خادم تجريبي", map: "الجزيرة", latitude: 40, longitude: 60, created: Date()))
        XCTAssertEqual(try store.importBackup(store.backupData()), 0)
        let invalid = GuideBackup(version: 1, favorites: [], sightings: [Sighting(creatureID: creature.id, server: "خادم", map: "الجزيرة", latitude: 101, longitude: 60, created: Date())])
        XCTAssertThrowsError(try store.importBackup(JSONEncoder().encode(invalid)))
        XCTAssertEqual(store.sightings.count, 1)
        let other = GuideBackup(version: 1, favorites: [creature.id], sightings: [Sighting(creatureID: creature.id, server: "خادم آخر", map: "الجزيرة", latitude: 20, longitude: 30, created: Date())])
        XCTAssertEqual(try store.importBackup(JSONEncoder().encode(other)), 1)
        XCTAssertEqual(store.sightings.count, 2)
        XCTAssertTrue(store.favorites.contains(creature.id))
    }

    @MainActor func testCorruptSavedDataIsNotOverwritten() throws {
        let suite = "ARKGuideCorruptTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let invalid = Data("invalid-json".utf8)
        defaults.set(invalid, forKey: "ark.guide.userdata.v1")
        let store = GuideStore(defaults: defaults)
        XCTAssertNotNil(store.error)
        store.favorite(try XCTUnwrap(store.creatures.first))
        XCTAssertEqual(defaults.data(forKey: "ark.guide.userdata.v1"), invalid)
        XCTAssertThrowsError(try store.backupData())
    }

    @MainActor func testPersistedSightings() throws {
        let suite = "ARKGuideTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bundle = Bundle(for: GuideTests.self)
        // App resources are loaded from the host application during hosted tests.
        let store = GuideStore(bundle: .main, defaults: defaults)
        XCTAssertFalse(store.creatures.isEmpty, "Missing catalog in host application: \(bundle)")
        let creature = try XCTUnwrap(store.creatures.first)
        store.favorite(creature)
        store.add(Sighting(creatureID: creature.id, server: "اختبار", map: "الجزيرة", latitude: 20, longitude: 30, created: Date()))
        let restored = GuideStore(defaults: defaults)
        XCTAssertTrue(restored.favorites.contains(creature.id))
        XCTAssertEqual(restored.sightings.count, 1)
        restored.remove(try XCTUnwrap(restored.sightings.first).id)
        XCTAssertTrue(GuideStore(defaults: defaults).sightings.isEmpty)
    }
}
