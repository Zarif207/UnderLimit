import FitKit
import SwiftUI
import UniformTypeIdentifiers

/// One dropped file and what happened to it.
struct FileRow: Identifiable {
    let id = UUID()
    let url: URL
    var status = "ready"
    var sizes = ""
}

/// Holds the file list and runs FitKit off the main thread.
final class FitModel: ObservableObject {
    @Published var rows: [FileRow] = []
    @Published var running = false

    /// Adds files; folders expand to their supported files (not recursive).
    func add(_ urls: [URL]) {
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            let files = isDir.boolValue ? Fitter.expand(folder: url, recursive: false) : [url]
            for file in files where !rows.contains(where: { $0.url == file }) {
                rows.append(FileRow(url: file, sizes: Self.sizeText(of: file)))
            }
        }
    }

    func fit(limit: ByteLimit) {
        guard !running, !rows.isEmpty else { return }
        running = true
        let urls = rows.map(\.url)
        for i in rows.indices { rows[i].status = "waiting" }
        DispatchQueue.global(qos: .userInitiated).async {
            for (i, url) in urls.enumerated() {
                DispatchQueue.main.async { self.rows[i].status = "working…" }
                let result = Fitter.fit([url], options: FitOptions(limit: limit)).first
                    ?? .failed(input: url, reason: "no result")
                DispatchQueue.main.async { self.apply(result, at: i) }
            }
            DispatchQueue.main.async { self.running = false }
        }
    }

    func clear() {
        if !running { rows.removeAll() }
    }

    private func apply(_ result: FitResult, at i: Int) {
        switch result {
        case .done(_, let output, let before, let after, _):
            rows[i].status = "done → \(output.lastPathComponent)"
            rows[i].sizes = "\(SizeParser.format(bytes: before)) → \(SizeParser.format(bytes: after))"
        case .skipped(_, let reason):
            rows[i].status = "skipped: \(reason)"
        case .failed(_, let reason):
            rows[i].status = "failed: \(reason)"
        }
    }

    private static func sizeText(of url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return SizeParser.format(bytes: size)
    }
}

/// Limit choices shown in the picker.
enum LimitChoice: String, CaseIterable, Identifiable {
    case kb200 = "200 KB", kb500 = "500 KB", mb1 = "1 MB", mb2 = "2 MB", custom = "Custom"
    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var model = FitModel()
    @State private var choice: LimitChoice = .kb200
    @State private var customText = "300kb"
    @State private var dropTargeted = false

    /// The chosen limit, or nil if the custom text does not parse.
    private var limit: ByteLimit? {
        switch choice {
        case .kb200: return ByteLimit(bytes: 200_000)
        case .kb500: return ByteLimit(bytes: 500_000)
        case .mb1: return ByteLimit(bytes: 1_000_000)
        case .mb2: return ByteLimit(bytes: 2_000_000)
        case .custom: return try? SizeParser.parse(customText)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            dropArea
            HStack {
                Picker("Limit", selection: $choice) {
                    ForEach(LimitChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                .fixedSize()
                if choice == .custom {
                    TextField("e.g. 750kb", text: $customText)
                        .frame(width: 100)
                    if limit == nil {
                        Text("invalid size").foregroundColor(.red).font(.caption)
                    }
                }
                Spacer()
                Button("Clear") { model.clear() }
                    .disabled(model.running || model.rows.isEmpty)
                Button("Fit") { if let limit { model.fit(limit: limit) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.running || model.rows.isEmpty || limit == nil)
            }
            List(model.rows) { row in
                HStack {
                    Text(row.url.lastPathComponent).lineLimit(1)
                    Spacer()
                    Text(row.status).foregroundColor(.secondary).lineLimit(1)
                    Text(row.sizes).monospacedDigit().frame(minWidth: 140, alignment: .trailing)
                }
            }
            Text("Outputs are saved next to the originals. Photo location data is removed; PDF text becomes unselectable.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var dropArea: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
            .foregroundColor(dropTargeted ? .accentColor : .secondary)
            .frame(height: 110)
            .overlay(Text("Drop images, PDFs, or folders here").foregroundColor(.secondary))
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        DispatchQueue.main.async { model.add([url]) }
                    }
                }
                return true
            }
    }
}
