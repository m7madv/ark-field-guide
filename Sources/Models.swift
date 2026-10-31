import Foundation
import Combine

struct Creature: Codable, Identifiable, Hashable {
    let id: String
    let arabic: String
    let english: String
    let aliases: [String]
    var assetPath: String? = nil

    func matches(_ query: String) -> Bool {
        let terms = Self.normalize(query).split(separator: " ")
        let haystack = Self.normalize(([arabic, english] + aliases).joined(separator: " "))
        return terms.allSatisfy { haystack.contains($0) }
    }

    static func normalize(_ text: String) -> String {
        let decomposed = text.decomposedStringWithCanonicalMapping
        let unmarked = String(String.UnicodeScalarView(decomposed.unicodeScalars.filter {
            !CharacterSet.nonBaseCharacters.contains($0)
        }))
        return unmarked.lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "ar"))
            .replacingOccurrences(of: "أ", with: "ا")
            .replacingOccurrences(of: "إ", with: "ا")
            .replacingOccurrences(of: "آ", with: "ا")
            .replacingOccurrences(of: "ى", with: "ي")
            .replacingOccurrences(of: "ـ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct Sighting: Codable, Identifiable {
    var id = UUID()
    let creatureID: String
    let server: String
    let map: String
    let latitude: Double
    let longitude: Double
    let created: Date

    static func coordinate(_ input: String) -> Double? {
        let arabic = Array("٠١٢٣٤٥٦٧٨٩")
        let persian = Array("۰۱۲۳۴۵۶۷۸۹")
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for index in 0...9 {
            value = value.replacingOccurrences(of: String(arabic[index]), with: String(index))
                .replacingOccurrences(of: String(persian[index]), with: String(index))
        }
        value = value.replacingOccurrences(of: "٫", with: ".").replacingOccurrences(of: ",", with: ".")
        guard let result = Double(value), result.isFinite, (0...100).contains(result) else { return nil }
        return result
    }
}

struct GuideBackup: Codable {
    let version: Int
    let favorites: Set<String>
    let sightings: [Sighting]
}

enum BackupError: LocalizedError {
    case invalid
    var errorDescription: String? { "الملف ليس نسخة احتياطية صالحة للدليل، أو يتضمن مواقع غير صحيحة." }
}

@MainActor final class GuideStore: ObservableObject {
    @Published private(set) var creatures: [Creature] = []
    @Published private(set) var favorites: Set<String> = []
    @Published private(set) var sightings: [Sighting] = []
    @Published var error: String?
    private let defaults: UserDefaults
    private let storageKey = "ark.guide.userdata.v1"
    private var writable = true

    private struct Saved: Codable {
        let favorites: Set<String>
        let sightings: [Sighting]
    }

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        do {
            guard let url = bundle.url(forResource: "creatures", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            creatures = try JSONDecoder().decode([Creature].self, from: Data(contentsOf: url))
            if let data = defaults.data(forKey: storageKey) {
                let saved = try JSONDecoder().decode(Saved.self, from: data)
                favorites = saved.favorites
                sightings = saved.sightings
            }
        } catch {
            writable = false
            self.error = "تعذّر تحميل البيانات. لم تُستبدل بياناتك المحفوظة."
        }
    }

    func favorite(_ creature: Creature) {
        guard writable else { error = "الحفظ متوقف لحماية البيانات التي تعذّر تحميلها."; return }
        if favorites.contains(creature.id) { favorites.remove(creature.id) }
        else { favorites.insert(creature.id) }
        save()
    }

    func add(_ sighting: Sighting) {
        guard writable else { error = "الحفظ متوقف لحماية البيانات التي تعذّر تحميلها."; return }
        sightings.insert(sighting, at: 0)
        save()
    }

    func remove(_ id: UUID) {
        guard writable else { error = "الحفظ متوقف لحماية البيانات التي تعذّر تحميلها."; return }
        sightings.removeAll { $0.id == id }
        save()
    }

    func backupData() throws -> Data {
        guard writable else { throw BackupError.invalid }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(GuideBackup(version: 1, favorites: favorites, sightings: sightings))
    }

    func importBackup(_ data: Data) throws -> Int {
        guard writable, data.count <= 5_000_000 else { throw BackupError.invalid }
        let backup = try JSONDecoder().decode(GuideBackup.self, from: data)
        let known = Set(creatures.map(\.id))
        guard backup.version == 1, backup.sightings.count <= 5000,
              backup.favorites.isSubset(of: known),
              Set(backup.sightings.map(\.id)).count == backup.sightings.count,
              backup.sightings.allSatisfy({ item in
                  known.contains(item.creatureID) && item.latitude.isFinite && item.longitude.isFinite &&
                  (0...100).contains(item.latitude) && (0...100).contains(item.longitude) &&
                  !item.server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && item.server.count <= 200 &&
                  !item.map.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && item.map.count <= 200 &&
                  item.created.timeIntervalSince1970.isFinite
              }) else { throw BackupError.invalid }
        let existing = Set(sightings.map(\.id))
        let added = backup.sightings.filter { !existing.contains($0.id) }
        let merged = (sightings + added).sorted { $0.created > $1.created }
        guard merged.count <= 5000 else { throw BackupError.invalid }
        let mergedFavorites = favorites.union(backup.favorites)
        // Encode completely before replacing existing state.
        let saved = try JSONEncoder().encode(Saved(favorites: mergedFavorites, sightings: merged))
        defaults.set(saved, forKey: storageKey)
        favorites = mergedFavorites
        sightings = merged
        return added.count
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(Saved(favorites: favorites, sightings: sightings)), forKey: storageKey)
        } catch { self.error = "تعذّر حفظ التغيير؛ أبقِ التطبيق مفتوحاً وأعد المحاولة." }
    }
}
