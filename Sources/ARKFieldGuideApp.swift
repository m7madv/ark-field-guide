import SwiftUI

@main struct ARKFieldGuideApp: App {
    @StateObject private var store = GuideStore()
    var body: some Scene {
        WindowGroup {
            GuideView()
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .tint(.teal)
        }
    }
}

struct GuideView: View {
    @EnvironmentObject private var store: GuideStore
    var body: some View {
        TabView {
            CatalogView().tabItem { Label("المخلوقات", systemImage: "leaf") }
            SightingMapView().tabItem { Label("الخريطة", systemImage: "map") }
            SavedSightingsView().tabItem { Label("مواقعي", systemImage: "mappin.and.ellipse") }
            NavigationStack {
                List {
                    Section("هذه النسخة") {
                        Text("بحث عربي، مفضلة، ومواقع تسجّلها بنفسك وتبقى محفوظة على جهازك.")
                        Text("الدليل أولي. الأسماء العربية تعريب وصفي، وليست ترجمة رسمية معتمدة.")
                    }
                    BackupSection()
                    Section("التتبع الحي") {
                        Label("غير متصل باللعبة", systemImage: "link.badge.plus")
                        Text("لا تقرأ هذه النسخة مواقع الحيوانات الحية، ولا ترسم خطوطاً فوق اللعبة. المواقع المحفوظة مشاهدات سابقة وليست تتبعاً متجدداً.")
                    }
                }.navigationTitle("حول الدليل")
            }.tabItem { Label("حول", systemImage: "info.circle") }
        }
        .alert("تعذّر إكمال العملية", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("حسناً") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct CatalogView: View {
    @EnvironmentObject private var store: GuideStore
    @State private var query = ""
    @State private var favoritesOnly = false
    private var results: [Creature] {
        store.creatures.filter { $0.matches(query) && (!favoritesOnly || store.favorites.contains($0.id)) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("دليلك للمخلوقات", systemImage: "binoculars")
                        .font(.title2.bold())
                    Text("ابحث بالعربية أو بالاسم الشائع، ثم احفظ ما يهمك.")
                        .foregroundStyle(.secondary)
                    Toggle("المفضلة فقط", isOn: $favoritesOnly)
                }
                Section("النتائج: \(results.count)") {
                    if results.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("لا توجد نتائج").font(.headline)
                            Text("جرّب اسماً آخر، أو أوقف تصفية المفضلة.").foregroundStyle(.secondary)
                        }.padding(.vertical, 12)
                    }
                    ForEach(results) { creature in
                        NavigationLink(value: creature) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(creature.arabic).font(.headline)
                                Text(creature.english).font(.subheadline).foregroundStyle(.secondary)
                                    .environment(\.layoutDirection, .leftToRight)
                            }.padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle("دليل أرك")
            .searchable(text: $query, prompt: "اسم المخلوق، مثل: ريكس أو قندس")
            .navigationDestination(for: Creature.self) { CreatureDetail(creature: $0) }
        }
    }
}

struct CreatureDetail: View {
    let creature: Creature
    @EnvironmentObject private var store: GuideStore
    @State private var showForm = false
    var body: some View {
        List {
            Section {
                Text(creature.arabic).font(.largeTitle.bold())
                Text(creature.english).foregroundStyle(.secondary)
                if creature.assetPath != nil {
                    Label("ملف النوع موجود في نسخة أندرويد المفحوصة", systemImage: "checkmark.seal")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    store.favorite(creature)
                } label: {
                    Label(store.favorites.contains(creature.id) ? "إزالة من المفضلة" : "إضافة إلى المفضلة", systemImage: store.favorites.contains(creature.id) ? "star.fill" : "star")
                        .frame(minHeight: 44)
                }
            }
            Section("المواقع") {
                Text("احفظ المكان الذي شاهدت فيه هذا المخلوق. قد يتحرك أو يختفي بعد تسجيله.")
                Button("تسجيل مشاهدة") { showForm = true }.frame(minHeight: 44)
                ForEach(store.sightings.filter { $0.creatureID == creature.id }) { sighting in
                    SightingRow(sighting: sighting, title: creature.arabic)
                }
            }
            Section("حالة التتبع") {
                Label("لا يوجد مصدر لموقع حي", systemImage: "antenna.radiowaves.left.and.right.slash")
                Text("لا تتضمن هذه النسخة زر تفعيل شكلياً أو إحداثيات تجريبية توحي بوجود تتبع فعلي.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(creature.arabic)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showForm) { SightingForm(creature: creature) }
    }
}

struct SightingForm: View {
    let creature: Creature
    @EnvironmentObject private var store: GuideStore
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var map = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var attempted = false
    private var valid: Bool {
        !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !map.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Sighting.coordinate(latitude) != nil && Sighting.coordinate(longitude) != nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("مشاهدة: \(creature.arabic)") {
                    TextField("اسم الخادم أو اللعب الفردي", text: $server)
                    TextField("اسم الخريطة", text: $map)
                }
                Section {
                    TextField("خط العرض من 0 إلى 100", text: $latitude).keyboardType(.decimalPad)
                    TextField("خط الطول من 0 إلى 100", text: $longitude).keyboardType(.decimalPad)
                } header: { Text("إحداثيات خريطة اللعبة") } footer: {
                    Text("هذه إحداثيات داخل اللعبة، وليست موقع الهاتف الجغرافي.")
                }
                if attempted && !valid {
                    Label("أدخل اسم الخادم والخريطة، وإحداثيين صحيحين بين 0 و100.", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("تسجيل مشاهدة")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        attempted = true
                        guard valid, let lat = Sighting.coordinate(latitude), let lon = Sighting.coordinate(longitude) else { return }
                        store.add(Sighting(creatureID: creature.id, server: server.trimmingCharacters(in: .whitespacesAndNewlines), map: map.trimmingCharacters(in: .whitespacesAndNewlines), latitude: lat, longitude: lon, created: Date()))
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SightingRow: View {
    let sighting: Sighting
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text("\(sighting.server) · \(sighting.map)").font(.subheadline)
            Text("خط العرض: \(sighting.latitude, specifier: "%.2f")، خط الطول: \(sighting.longitude, specifier: "%.2f")")
            Text(sighting.created, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
            Text("مشاهدة محفوظة؛ الموقع لا يتحدث تلقائياً").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
    }
}

struct SavedSightingsView: View {
    @EnvironmentObject private var store: GuideStore
    var body: some View {
        NavigationStack {
            List {
                if store.sightings.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("لا توجد مشاهدات محفوظة", systemImage: "mappin.slash")
                            .font(.headline)
                        Text("افتح صفحة مخلوق من الدليل واختر «تسجيل مشاهدة».").foregroundStyle(.secondary)
                    }.padding(.vertical, 24)
                }
                ForEach(store.sightings) { sighting in
                    SightingRow(sighting: sighting, title: store.creatures.first { $0.id == sighting.creatureID }?.arabic ?? sighting.creatureID)
                        .swipeActions { Button("حذف", role: .destructive) { store.remove(sighting.id) } }
                }
            }.navigationTitle("مواقعي المحفوظة")
        }
    }
}
