import SwiftUI
import UniformTypeIdentifiers

struct SightingMapView: View {
    @EnvironmentObject private var store: GuideStore
    @State private var selectedMap = ""
    @State private var server = ""
    @State private var creatureID = ""
    @State private var selected: UUID?
    private var maps: [String] { Array(Set(store.sightings.map(\.map))).sorted() }
    private var servers: [String] { Array(Set(store.sightings.filter { $0.map == selectedMap }.map(\.server))).sorted() }
    private var points: [Sighting] {
        store.sightings.filter { $0.map == selectedMap && (server.isEmpty || $0.server == server) && (creatureID.isEmpty || $0.creatureID == creatureID) }
    }
    private func name(_ item: Sighting) -> String { store.creatures.first { $0.id == item.creatureID }?.arabic ?? item.creatureID }
    var body: some View {
        NavigationStack {
            List {
                if maps.isEmpty {
                    Section {
                        Label("ابدأ بتسجيل مشاهدة", systemImage: "mappin.slash").font(.headline)
                        Text("اختر مخلوقاً من الدليل وسجّل إحداثياته، ثم ستظهر النقطة هنا.")
                    }
                } else {
                    Section("تصفية المشاهدات") {
                        Picker("الخريطة", selection: $selectedMap) {
                            ForEach(maps, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("الخادم", selection: $server) {
                            Text("كل الخوادم").tag("")
                            ForEach(servers, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("المخلوق", selection: $creatureID) {
                            Text("كل المخلوقات").tag("")
                            ForEach(store.creatures) { Text($0.arabic).tag($0.id) }
                        }
                    }
                    Section {
                        CoordinateGrid(points: points, title: name, selection: $selected)
                            .aspectRatio(1, contentMode: .fit)
                        Text("شبكة إحداثيات 0–100: خط العرض عمودي، وخط الطول أفقي. هذه نقاط محفوظة، وليست خريطة تضاريس أو تتبعاً حياً.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("المشاهدات الظاهرة: \(points.count)") {
                        if points.isEmpty { Text("لا توجد مشاهدات تطابق التصفية.") }
                        if let item = points.first(where: { $0.id == selected }) {
                            SightingRow(sighting: item, title: name(item))
                        }
                        ForEach(points.filter { $0.id != selected }) { item in
                            Button { selected = item.id } label: {
                                SightingRow(sighting: item, title: name(item))
                            }.foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("خريطة المشاهدات")
            .onAppear { if !maps.contains(selectedMap) { selectedMap = maps.first ?? "" } }
            .onChange(of: maps) { values in
                if !values.contains(selectedMap) { selectedMap = values.first ?? "" }
            }
            .onChange(of: selectedMap) { _ in server = ""; selected = nil }
        }
    }
}

struct CoordinateGrid: View {
    let points: [Sighting]
    let title: (Sighting) -> String
    @Binding var selection: UUID?
    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 28
            let width = max(1, geometry.size.width - inset * 2)
            let height = max(1, geometry.size.height - inset * 2)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground))
                Canvas { context, _ in
                    var lines = Path()
                    for index in 0...5 {
                        let x = inset + CGFloat(index) / 5 * width
                        let y = inset + CGFloat(index) / 5 * height
                        lines.move(to: CGPoint(x: x, y: inset)); lines.addLine(to: CGPoint(x: x, y: inset + height))
                        lines.move(to: CGPoint(x: inset, y: y)); lines.addLine(to: CGPoint(x: inset + width, y: y))
                    }
                    context.stroke(lines, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
                    for index in 0...5 {
                        let value = String(index * 20)
                        context.draw(Text(value).font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: inset + CGFloat(index) / 5 * width, y: 12))
                        context.draw(Text(value).font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: 12, y: inset + CGFloat(index) / 5 * height))
                    }
                }.accessibilityHidden(true)
                ForEach(points) { point in
                    Button { selection = point.id } label: {
                        Image(systemName: selection == point.id ? "mappin.circle.fill" : "circle.fill")
                            .font(selection == point.id ? .title : .body)
                            .foregroundStyle(selection == point.id ? Color.orange : Color.teal)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("\(title(point))، خط العرض \(point.latitude)، خط الطول \(point.longitude)، \(point.server)")
                    .position(x: inset + CGFloat(point.longitude / 100) * width, y: inset + CGFloat(point.latitude / 100) * height)
                }
            }
        }.environment(\.layoutDirection, .leftToRight)
    }
}

struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BackupError.invalid }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct BackupSection: View {
    @EnvironmentObject private var store: GuideStore
    @State private var exporting = false
    @State private var importing = false
    @State private var document = BackupFile()
    @State private var message: String?
    var body: some View {
        Section("النسخ الاحتياطي") {
            Button("تصدير المفضلة والمشاهدات") {
                do { document = BackupFile(data: try store.backupData()); exporting = true }
                catch { message = error.localizedDescription }
            }.frame(minHeight: 44)
            Button("دمج نسخة احتياطية") { importing = true }.frame(minHeight: 44)
            Text("الدمج يحفظ مشاهداتك الحالية ويتجاهل السجلات المكررة. تحفظ الملفات في المكان الذي تختاره.")
                .font(.caption).foregroundStyle(.secondary)
            if let message { Text(message).font(.callout).accessibilityAddTraits(.updatesFrequently) }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "ark-guide-backup") { result in
            switch result {
            case .success: message = "تم تصدير النسخة الاحتياطية."
            case .failure(let error): message = "تعذّر التصدير: \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 5_000_000 else { throw BackupError.invalid }
                let count = try store.importBackup(Data(contentsOf: url))
                message = "تم دمج النسخة. المشاهدات المضافة: \(count)."
            } catch { message = "تعذّر الدمج: \(error.localizedDescription)" }
        }
    }
}
