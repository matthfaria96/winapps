// Navegador de arquivos com duas colunas: Mac (esquerda) ⇄ Windows C: (direita).
// Copiar/mover entre os dois ambientes com botões ou arrastando.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable {
    let id: URL
    let name: String
    let isDir: Bool
    let size: Int64?
    let modified: Date?
    /// Preenchido quando é um atalho do Windows que, na verdade, leva a uma pasta do Mac.
    let macTarget: String?
}

struct Place: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let url: URL
}

@MainActor
final class Pane: ObservableObject {
    enum Side { case mac, windows }
    let side: Side
    let places: [Place]
    @Published var url: URL
    @Published var items: [FileItem] = []
    @Published var selection = Set<URL>()
    @Published var dropTarget = false

    init(side: Side) {
        self.side = side
        let fm = FileManager.default
        let h = Paths.home
        switch side {
        case .mac:
            var p = [
                Place(name: "Pasta pessoal", symbol: "house.fill", url: h),
                Place(name: "Mesa", symbol: "menubar.dock.rectangle", url: h.appendingPathComponent("Desktop")),
                Place(name: "Documentos", symbol: "doc.fill", url: h.appendingPathComponent("Documents")),
                Place(name: "Downloads", symbol: "arrow.down.circle.fill", url: h.appendingPathComponent("Downloads")),
                Place(name: "Imagens", symbol: "photo.fill", url: h.appendingPathComponent("Pictures")),
            ]
            let icloud = h.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
            if fm.fileExists(atPath: icloud.path) {
                p.append(Place(name: "iCloud Drive", symbol: "icloud.fill", url: icloud))
            }
            p.append(Place(name: "Discos externos", symbol: "externaldrive.fill", url: URL(fileURLWithPath: "/Volumes")))
            places = p
            url = h.appendingPathComponent("Downloads")
        case .windows:
            let c = Paths.driveC
            let user = c.appendingPathComponent("users/\(NSUserName())")
            places = [
                Place(name: "Disco C:", symbol: "internaldrive.fill", url: c),
                Place(name: "Programas (Program Files)", symbol: "shippingbox.fill", url: c.appendingPathComponent("Program Files")),
                Place(name: "Programas 32-bit (x86)", symbol: "shippingbox", url: c.appendingPathComponent("Program Files (x86)")),
                Place(name: "Portáteis", symbol: "bolt.fill", url: c.appendingPathComponent("Portable")),
                Place(name: "Usuário do Windows", symbol: "person.fill", url: user),
                Place(name: "AppData (saves e configurações)", symbol: "gearshape.fill", url: user.appendingPathComponent("AppData")),
            ]
            url = c
        }
        load()
    }

    var isWindows: Bool { side == .windows }
    var title: String { isWindows ? "WINDOWS" : "MAC" }
    var color: Color { isWindows ? .purple : .blue }

    /// Caminho amigável: "C:\Program Files\Notepad++"  ou  "Pasta pessoal › Downloads"
    var location: String {
        let p = url.standardizedFileURL.path
        if isWindows {
            let c = Paths.driveC.standardizedFileURL.path
            if p.hasPrefix(c) {
                let rest = String(p.dropFirst(c.count)).replacingOccurrences(of: "/", with: "\\")
                return "C:" + (rest.isEmpty ? "\\" : rest)
            }
            return "Mac: " + p
        }
        let h = Paths.home.path
        if p == h { return "Pasta pessoal" }
        if p.hasPrefix(h + "/") {
            return "Pasta pessoal › " + p.dropFirst(h.count + 1).replacingOccurrences(of: "/", with: " › ")
        }
        return p.replacingOccurrences(of: "/", with: " › ")
    }

    var canGoUp: Bool {
        if isWindows { return url.standardizedFileURL.path != Paths.driveC.standardizedFileURL.path }
        return url.path != "/"
    }

    func load() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]
        let urls = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys,
                                                 options: [.skipsHiddenFiles])) ?? []
        let prefix = Paths.prefix.resolvingSymlinksInPath().path
        items = urls.map { u in
            let v = try? u.resourceValues(forKeys: Set(keys))
            let resolved = u.resolvingSymlinksInPath()
            let isDir = (try? resolved.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            var macTarget: String? = nil
            if isWindows, v?.isSymbolicLink == true, !resolved.path.hasPrefix(prefix) {
                macTarget = resolved.path.replacingOccurrences(of: Paths.home.path, with: "Pasta pessoal")
                    .replacingOccurrences(of: "/", with: " › ")
            }
            return FileItem(id: u, name: u.lastPathComponent, isDir: isDir,
                            size: isDir ? nil : v?.fileSize.map(Int64.init),
                            modified: v?.contentModificationDate, macTarget: macTarget)
        }
        .sorted {
            if $0.isDir != $1.isDir { return $0.isDir }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        selection = selection.filter { s in items.contains { $0.id == s } }
    }

    func go(_ u: URL) { url = u; selection = []; load() }
    func up() { if canGoUp { go(url.deletingLastPathComponent()) } }

    func open(_ item: FileItem) {
        if item.isDir { go(item.id); return }
        let ext = item.id.pathExtension.lowercased()
        if ["exe", "msi"].contains(ext) {
            // dentro do C: → só executa; fora → fluxo normal (instalar/adicionar)
            if item.id.path.hasPrefix(Paths.driveC.path) { Model.shared.runOnce(item.id) }
            else { Model.shared.handle(item.id) }
        } else {
            NSWorkspace.shared.open(item.id)
        }
    }
}

// MARK: - Cópia / movimento

@MainActor
enum Transfer {
    /// Copia (ou move) `urls` para dentro de `dest`. Nunca sobrescreve: cria "nome (2)".
    static func run(_ urls: [URL], to dest: URL, move: Bool, refresh: [Pane]) {
        guard !urls.isEmpty else { return }
        let verb = move ? "Movendo" : "Copiando"
        Model.shared.busy = "\(verb) \(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) itens")…"
        Task.detached {
            var errors: [String] = []
            let fm = FileManager.default
            for src in urls {
                if src.deletingLastPathComponent().standardizedFileURL == dest.standardizedFileURL, !move { continue }
                let target = uniqueURL(for: src.lastPathComponent, in: dest)
                do {
                    if move { try fm.moveItem(at: src, to: target) }
                    else { try fm.copyItem(at: src, to: target) }
                } catch {
                    errors.append("\(src.lastPathComponent): \(error.localizedDescription)")
                }
            }
            let failed = errors
            await MainActor.run {
                Model.shared.busy = nil
                refresh.forEach { $0.load() }
                if !failed.isEmpty { Model.shared.message = "Alguns itens falharam:\n" + failed.joined(separator: "\n") }
            }
        }
    }

    nonisolated static func uniqueURL(for name: String, in dir: URL) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            n += 1
        }
        return candidate
    }

    static func trash(_ urls: [URL], refresh: Pane) {
        NSWorkspace.shared.recycle(urls) { _, _ in
            Task { @MainActor in refresh.load() }
        }
    }
}

// MARK: - Views

struct FileBrowserView: View {
    @StateObject private var mac = Pane(side: .mac)
    @StateObject private var win = Pane(side: .windows)

    var body: some View {
        HStack(spacing: 0) {
            PaneView(pane: mac, other: win)
            transferBar
            PaneView(pane: win, other: mac)
        }
        .padding(16)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            mac.load(); win.load()
        }
    }

    var transferBar: some View {
        VStack(spacing: 10) {
            Spacer()
            transferButton("Copiar", icon: "arrow.right", help: "Copiar a seleção do Mac para o Windows",
                           disabled: mac.selection.isEmpty) {
                Transfer.run(Array(mac.selection), to: win.url, move: false, refresh: [mac, win])
            }
            transferButton("Mover", icon: "arrow.right.to.line", help: "Mover a seleção do Mac para o Windows",
                           disabled: mac.selection.isEmpty) {
                Transfer.run(Array(mac.selection), to: win.url, move: true, refresh: [mac, win])
            }
            Divider().frame(width: 40).padding(.vertical, 6)
            transferButton("Copiar", icon: "arrow.left", help: "Copiar a seleção do Windows para o Mac",
                           disabled: win.selection.isEmpty) {
                Transfer.run(Array(win.selection), to: mac.url, move: false, refresh: [mac, win])
            }
            transferButton("Mover", icon: "arrow.left.to.line", help: "Mover a seleção do Windows para o Mac",
                           disabled: win.selection.isEmpty) {
                Transfer.run(Array(win.selection), to: mac.url, move: true, refresh: [mac, win])
            }
            Spacer()
        }
        .frame(width: 92)
    }

    func transferButton(_ title: String, icon: String, help: String, disabled: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(title).font(.caption2)
            }.frame(width: 64, height: 44)
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
        .help(help)
    }
}

struct PaneView: View {
    @ObservedObject var pane: Pane
    let other: Pane

    static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            footer
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(pane.dropTarget ? pane.color : Color.secondary.opacity(0.25), lineWidth: pane.dropTarget ? 3 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: pane.isWindows ? "pc" : "laptopcomputer")
                Text(pane.title).font(.caption.weight(.heavy)).tracking(1)
                Spacer()
                Menu {
                    ForEach(pane.places) { p in
                        Button { pane.go(p.url) } label: { Label(p.name, systemImage: p.symbol) }
                    }
                } label: { Label("Ir para", systemImage: "list.bullet") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .foregroundStyle(pane.color)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(pane.color.opacity(0.10))

            HStack(spacing: 6) {
                Button { pane.up() } label: { Image(systemName: "chevron.up") }
                    .disabled(!pane.canGoUp).help("Pasta acima")
                Text(pane.location)
                    .font(.system(.callout, design: pane.isWindows ? .monospaced : .default))
                    .lineLimit(1).truncationMode(.head)
                Spacer()
                Button { NSWorkspace.shared.open(pane.url) } label: { Image(systemName: "macwindow") }
                    .help("Abrir esta pasta no Finder")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
    }

    var list: some View {
        List(selection: $pane.selection) {
            ForEach(pane.items) { item in
                row(item).tag(item.id)
                    .onDrag { NSItemProvider(object: item.id as NSURL) }
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: URL.self) { sel in
            if !sel.isEmpty {
                Button(pane.isWindows ? "Copiar para o Mac (pasta da esquerda)" : "Copiar para o Windows (pasta da direita)") {
                    Transfer.run(Array(sel), to: other.url, move: false, refresh: [pane, other])
                }
                Button(pane.isWindows ? "Mover para o Mac" : "Mover para o Windows") {
                    Transfer.run(Array(sel), to: other.url, move: true, refresh: [pane, other])
                }
                Divider()
                Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting(Array(sel)) }
                if sel.count == 1, let u = sel.first, u.pathExtension.lowercased() == "exe",
                   u.path.hasPrefix(Paths.driveC.path) {
                    Button("Adicionar à biblioteca") { Model.shared.addExisting(u) }
                }
                Divider()
                Button("Mover para o Lixo", role: .destructive) { Transfer.trash(Array(sel), refresh: pane) }
            }
        } primaryAction: { sel in
            if sel.count == 1, let u = sel.first, let item = pane.items.first(where: { $0.id == u }) {
                pane.open(item)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $pane.dropTarget) { providers in
            let dest = pane.url
            let group = DispatchGroup()
            let box = URLBox()
            for prov in providers {
                group.enter()
                _ = prov.loadObject(ofClass: URL.self) { url, _ in
                    if let url { box.append(url) }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                Transfer.run(box.urls, to: dest, move: false, refresh: [pane, other])
            }
            return true
        }
    }

    func row(_ item: FileItem) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.id.path))
                .resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1)
                if let t = item.macTarget {
                    Text("↪ é uma pasta do Mac: \(t)").font(.caption2).foregroundStyle(.blue).lineLimit(1)
                }
            }
            Spacer()
            if let s = item.size {
                Text(ByteCountFormatter.string(fromByteCount: s, countStyle: .file))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if let d = item.modified {
                Text(Self.dateFmt.string(from: d)).font(.caption).foregroundStyle(.tertiary)
                    .frame(width: 110, alignment: .trailing)
            }
        }
    }

    var footer: some View {
        HStack {
            Text(pane.selection.isEmpty
                 ? "\(pane.items.count) itens · duplo clique para abrir · arraste para o outro lado"
                 : "\(pane.selection.count) selecionado(s)")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

/// Acumula URLs vindas de callbacks em threads diferentes durante um drop.
final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var urls: [URL] = []
    func append(_ u: URL) { lock.lock(); urls.append(u); lock.unlock() }
}
