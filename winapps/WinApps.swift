// WinApps — janela principal (SwiftUI).
// Biblioteca de programas Windows, instalar/adicionar com poucos cliques,
// arrastar e soltar .exe/.msi e acesso aos arquivos do "C:".
// A parte pesada (Wine) fica no script `winapps`, que vem dentro do app.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Caminhos

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let base = home.appendingPathComponent("Library/Application Support/WinApps")
    static let prefix = base.appendingPathComponent("prefixes/default")
    static let driveC = prefix.appendingPathComponent("drive_c")
    static let apps = home.appendingPathComponent("Applications")
    static let logs = home.appendingPathComponent("Library/Logs/WinApps")
    static let installedBin = base.appendingPathComponent("bin")
    static var bundledScript: URL { Bundle.main.url(forResource: "winapps", withExtension: nil)! }
}

// MARK: - Script

enum Script {
    /// Roda `winapps <args>` e devolve (código, stdout). Não trava a interface.
    static func run(_ args: [String], porcelain: Bool = false, prefix: String? = nil) async -> (code: Int32, out: String) {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [Paths.bundledScript.path] + args
            var env = ProcessInfo.processInfo.environment
            if porcelain { env["WINAPPS_PORCELAIN"] = "1" }
            if let prefix { env["WINAPPS_PREFIX"] = prefix }   // ambiente do atalho
            p.environment = env
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe   // mensagens de erro do script também chegam ao app
            // aviso de término registrado ANTES de iniciar: waitUntilExit() fora da thread
            // principal pode perder o evento e esperar para sempre
            let finished = DispatchSemaphore(value: 0)
            p.terminationHandler = { _ in finished.signal() }
            do { try p.run() } catch {
                cont.resume(returning: (-1, error.localizedDescription)); return
            }
            DispatchQueue.global().async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                finished.wait()
                cont.resume(returning: (p.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
        }
    }

    /// Dispara sem esperar (para abrir programas).
    static func launch(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [Paths.bundledScript.path] + args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// Mantém a cópia instalada do script (usada pelos atalhos) igual à do app.
    static func syncInstalledCopy() {
        let fm = FileManager.default
        guard let res = Bundle.main.resourceURL else { return }
        try? fm.createDirectory(at: Paths.installedBin, withIntermediateDirectories: true)
        let vendor = res.appendingPathComponent("vendor")
        let files: [(URL, URL)] =
            ["winapps", "exe-icon.py", "icon-frame", "ntlm_auth", "exe-kind.py", "compat.json"].map { (res.appendingPathComponent($0), Paths.installedBin.appendingPathComponent($0)) } +
            ["winetricks", "cabextract"].map { (vendor.appendingPathComponent($0), Paths.installedBin.appendingPathComponent($0)) }
        for (src, dst) in files where fm.fileExists(atPath: src.path) {
            if fm.contentsEqual(atPath: src.path, andPath: dst.path) { continue }
            try? fm.removeItem(at: dst)
            try? fm.copyItem(at: src, to: dst)
        }
        // motor corrigido: o script instala no setup (e quando o motor já existe, abaixo)
        let vdst = Paths.base.appendingPathComponent("vendor")
        if fm.fileExists(atPath: vendor.path) {
            try? fm.removeItem(at: vdst)
            try? fm.copyItem(at: vendor, to: vdst)
        }
    }
}

// MARK: - Modelo

struct LibraryApp: Identifiable, Hashable {
    let id: URL          // caminho do .app
    let name: String
    let exe: String
    var prefix: String? = nil   // ambiente Windows do atalho (WinAppsPrefix); nil = padrão
    var icon: NSImage { NSWorkspace.shared.icon(forFile: id.path) }
}

struct PendingFile: Identifiable {
    let id = UUID()
    let url: URL
    let isInstaller: Bool
    let reason: String
    var needs: [String] = []     // componentes que faltam (ex.: dotnet48)
    var compat: Compat? = nil    // aviso de compatibilidade conhecido
}

/// Aviso da lista de compatibilidade (compat.json).
struct Compat {
    let name: String, status: String, why: String, alt: String
    var verified = false
    var tested = ""
    var fixes: [String] = []
    var summary = ""
    var category = ""
    var needs: [String] = []
    var broken: Bool { status == "nao-funciona" }
    var works: Bool { status == "funciona" }

    init(name: String, status: String, why: String, alt: String,
         verified: Bool = false, tested: String = "", fixes: [String] = []) {
        self.name = name; self.status = status; self.why = why; self.alt = alt
        self.verified = verified; self.tested = tested; self.fixes = fixes
    }

    /// Linha JSON de `winapps compat` (exe-kind.py --compat).
    init?(json out: String) {
        guard let line = out.split(separator: "\n").last(where: { $0.hasPrefix("{") }),
              let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String] else { return nil }
        self.init(name: o["name"] ?? "", status: o["status"] ?? "", why: o["why"] ?? "", alt: o["alt"] ?? "",
                  verified: !(o["verified"] ?? "").isEmpty, tested: o["tested"] ?? "",
                  fixes: (o["fixes"] ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    /// Regra do compat.json (aba Compatibilidade).
    init(rule r: [String: Any]) {
        self.init(name: r["name"] as? String ?? "", status: r["status"] as? String ?? "",
                  why: r["why"] as? String ?? "", alt: r["alt"] as? String ?? "",
                  verified: r["verified"] as? Bool ?? false, tested: r["tested"] as? String ?? "",
                  fixes: r["fixes"] as? [String] ?? [])
        summary = r["summary"] as? String ?? ""
        category = r["category"] as? String ?? ""
        needs = r["needs"] as? [String] ?? []
    }

    var badge: Badge {
        if verified { return .verified }
        switch status {
        case "funciona": return .works
        case "parcial": return .partial
        case "nao-funciona": return .broken
        default: return .untested
        }
    }
}

/// Selo de compatibilidade (biblioteca, aba Compatibilidade, aviso ao abrir).
enum Badge {
    case verified, works, partial, broken, untested
    var label: String {
        switch self {
        case .verified: return "Verificado"
        case .works: return "Funciona"
        case .partial: return "Parcial"
        case .broken: return "Não funciona"
        case .untested: return "Não testado"
        }
    }
    var symbol: String {
        switch self {
        case .verified: return "checkmark.seal.fill"
        case .works: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.triangle.fill"
        case .broken: return "xmark.octagon.fill"
        case .untested: return "questionmark.circle"
        }
    }
    var color: Color {
        switch self {
        case .verified: return .green
        case .works: return .teal
        case .partial: return .orange
        case .broken: return .red
        case .untested: return .secondary
        }
    }
    var help: String {
        switch self {
        case .verified: return "Testado de ponta a ponta, com correções próprias do WinApps. Garantido nesta versão."
        case .works: return "Testado: abre e o uso principal funciona."
        case .partial: return "Funciona com limitações."
        case .broken: return "Não roda no WinApps."
        case .untested: return "Ainda não testado pelo WinApps: pode funcionar, mas ninguém conferiu."
        }
    }
}

struct BadgeView: View {
    let badge: Badge
    var compact = false
    var body: some View {
        Label(badge.label, systemImage: badge.symbol)
            .font(compact ? .caption2.weight(.medium) : .caption.weight(.semibold))
            .foregroundStyle(badge.color)
            .padding(.horizontal, compact ? 6 : 8).padding(.vertical, compact ? 2 : 3)
            .background(Capsule().fill(badge.color.opacity(0.12)))
            .help(badge.help)
    }
}

/// Nomes amigáveis dos componentes do Windows.
func componentLabel(_ c: String) -> String {
    switch c {
    case "dotnet48": return ".NET Framework 4.8"
    case "winrt-metadata": return "metadados do Windows (WinRT)"
    case "webview2": return "WebView2 (navegador embutido)"
    case let s where s.hasPrefix("dotnetdesktop"): return ".NET \(s.dropFirst(13)) Desktop Runtime"
    case let s where s.hasPrefix("dotnet"): return ".NET \(s.dropFirst(6)) Runtime"
    default: return c
    }
}

struct Candidate: Identifiable {
    let id = UUID()
    let path: String
    var name: String
    var selected: Bool
}

@MainActor
final class Model: ObservableObject {
    static let shared = Model()

    @Published var library: [LibraryApp] = []
    @Published var wineVersion: String?
    @Published var checkedWine = false
    @Published var busy: String?
    @Published var pending: PendingFile?
    @Published var candidates: [Candidate] = []
    @Published var showCandidates = false
    @Published var message: String?
    @Published var nativeMenu: [String: Bool] = [:]   // exe (minúsculo) → menu na barra do Mac
    @Published var nativeMenuAll = true                 // padrão para todos os programas
    @Published var titleBar: [URL: Bool] = [:]          // atalho → barra de título do Mac (MacTitleBar)
    @Published var titleBarAll = true
    @Published var dxmtOn = FileManager.default.fileExists(atPath: Paths.base.appendingPathComponent(".dxmt-installed").path)
    @Published var gamepadOn = FileManager.default.fileExists(atPath: Paths.base.appendingPathComponent(".gamepad-sdl").path)
    @Published var badges: [String: Compat] = [:]       // exe → regra do compat.json (sem regra = não testado)
    @Published var badgesChecked: Set<String> = []
    @Published var toast: String?                       // aviso rápido ("importado para o WinApps")
    // 0 Biblioteca, 1 Compatibilidade, 2 Arquivos — lembrada entre aberturas
    @Published var tab = UserDefaults.standard.integer(forKey: "tab") {
        didSet { UserDefaults.standard.set(tab, forKey: "tab") }
    }

    func start() {
        Script.syncInstalledCopy()
        reloadLibrary()
        claimFileTypesOnce()
        Task {
            await refreshWine()
            // temporários do Windows não servem para nada: some com eles (só se nada estiver aberto)
            if (await Script.run(["clean", "--temp"])).code == 0 { loadStorage() }
        }
    }

    /// O WinApps é o app nativo que roda .exe/.msi: vira o app padrão deles na 1ª abertura.
    /// Só uma vez (se a pessoa trocar depois no Finder, a escolha dela vale).
    func claimFileTypesOnce() {
        let key = "claimedFileTypes"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        makeDefaultHandler(silent: true)
    }

    func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if toast == text { toast = nil }
        }
    }

    /// Selos da biblioteca: cada programa é conferido uma vez na lista de compatibilidade.
    func loadBadges() {
        for app in library where !badgesChecked.contains(app.exe) {
            badgesChecked.insert(app.exe)
            let exe = app.exe
            Task {
                let r = await Script.run(["compat", exe])
                if let c = Compat(json: r.out) { badges[exe] = c }
            }
        }
    }

    func badge(_ app: LibraryApp) -> Badge { badges[app.exe]?.badge ?? .untested }
    func size(of app: LibraryApp) -> Int64? { storage.first { $0.kind == 2 && $0.name == app.name }?.bytes }
    /// Programa da biblioteca que corresponde a uma regra do compat.json (para a tabela).
    func installed(_ c: Compat) -> LibraryApp? { library.first { badges[$0.exe]?.name == c.name } }

    // ---------- armazenamento (quanto o WinApps ocupa)

    struct StorageItem: Identifiable { let id = UUID(); let name: String; let bytes: Int64; let kind: Int }  // kind 0 motor, 1 ambiente, 2 programa, 3 cache
    @Published var storage: [StorageItem] = []
    @Published var storageFree: Int64 = 0
    @Published var storageLoading = false

    /// Pasta de um programa dentro do C: (Program Files\X, Portable\X ou a pasta do topo).
    static func programFolder(_ exe: String) -> URL? {
        let c = Paths.driveC.path + "/"
        guard exe.hasPrefix(c) else { return nil }
        let parts = exe.dropFirst(c.count).split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let deep = ["Program Files", "Program Files (x86)", "Portable", "ProgramData", "users"].contains(parts[0])
        let n = deep && parts.count > 2 ? 2 : 1
        return Paths.driveC.appendingPathComponent(parts.prefix(n).joined(separator: "/"))
    }

    /// Tamanho em disco de cada pasta, medida separadamente (o du conta um arquivo uma vez só
    /// por chamada) e sem seguir links (o ambiente tem z: → disco inteiro).
    nonisolated static func du(_ paths: [String]) -> [String: Int64] {
        var out: [String: Int64] = [:]
        for path in paths {
            let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path   // a pasta em si pode ser link
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
            p.arguments = ["-sk", real]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { continue }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            if let k = String(decoding: data, as: UTF8.self).split(separator: "\t").first.flatMap({ Int64($0) }) {
                out[path] = k * 1024
            }
        }
        return out
    }

    func cleanUp() {
        Task {
            busy = "Fechando os programas Windows e liberando espaço…"
            let r = await Script.run(["clean", "--force"])
            busy = nil
            let clean = r.out.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
            let lines = clean.split(separator: "\n").map(String.init)
            if let err = lines.first(where: { $0.hasPrefix("Erro:") }) {
                message = String(err.dropFirst(6)).prefix(1).uppercased() + String(err.dropFirst(7)) + "."
            } else {
                showToast(lines.last.map { $0.replacingOccurrences(of: "==> ", with: "") } ?? "Espaço liberado.")
            }
            loadStorage()
        }
    }

    func loadStorage() {
        guard !storageLoading else { return }
        storageLoading = true
        var programs: [(String, String)] = []   // (nome, pasta)
        for app in library {
            if let f = Self.programFolder(app.exe), !programs.contains(where: { $0.1 == f.path }) { programs.append((app.name, f.path)) }
        }
        let motor = Paths.base.appendingPathComponent("motor").path
        let prefix = Paths.prefix.path
        let cache = Paths.home.appendingPathComponent("Library/Caches/WinApps/downloads").path
        let users = (try? FileManager.default.contentsOfDirectory(atPath: Paths.driveC.appendingPathComponent("users").path)) ?? []
        let temps = users.map { Paths.driveC.appendingPathComponent("users/\($0)/AppData/Local/Temp").path }
            + [Paths.driveC.appendingPathComponent("windows/temp").path]
        Task.detached {
            let sizes = Self.du([motor, prefix, cache] + temps + programs.map(\.1))
            let temp = temps.reduce(Int64(0)) { $0 + (sizes[$1] ?? 0) }
            let free = (try? URL(fileURLWithPath: prefix).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                .volumeAvailableCapacityForImportantUsage ?? 0
            var items: [StorageItem] = []
            let progs = programs.map { StorageItem(name: $0.0, bytes: sizes[$0.1] ?? 0, kind: 2) }.sorted { $0.bytes > $1.bytes }
            items.append(StorageItem(name: "Motor", bytes: sizes[motor] ?? 0, kind: 0))
            items.append(StorageItem(name: "Ambiente Windows",
                                     bytes: max(0, (sizes[prefix] ?? 0) - progs.reduce(0) { $0 + $1.bytes } - temp), kind: 1))
            items += progs
            let junk = temp + (sizes[cache] ?? 0)
            if junk > 1_000_000 { items.append(StorageItem(name: "Temporários e cache", bytes: junk, kind: 3)) }
            let result = items
            await MainActor.run {
                self.storage = result
                self.storageFree = Int64(free)
                self.storageLoading = false
            }
        }
    }

    func refreshWine() async {
        _ = await Script.run(["engine-patch"])   // aplica o motor corrigido (e o DXMT) que vem no app
        dxmtOn = FileManager.default.fileExists(atPath: Paths.base.appendingPathComponent(".dxmt-installed").path)
        let r = await Script.run(["version"])
        wineVersion = r.code == 0 ? r.out.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        checkedWine = true
    }

    func reloadLibrary() {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: Paths.apps, includingPropertiesForKeys: nil)) ?? []
        library = items.filter { $0.pathExtension == "app" }.compactMap { app in
            let plist = app.appendingPathComponent("Contents/Info.plist")
            guard let d = NSDictionary(contentsOf: plist), let exe = d["WinAppsExe"] as? String else { return nil }
            return LibraryApp(id: app, name: app.deletingPathExtension().lastPathComponent, exe: exe,
                              prefix: d["WinAppsPrefix"] as? String)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        loadNativeMenuStates()
        loadBadges()
        loadStorage()
    }

    /// Lê do registro do ambiente (user.reg) quais programas usam o menu na barra do Mac.
    func loadNativeMenuStates() {
        let reg = Paths.prefix.appendingPathComponent("user.reg")
        guard let text = try? String(contentsOf: reg, encoding: .utf8) else { return }
        var states: [String: Bool] = [:]
        var all = true
        var current: String? = nil
        var inGlobal = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let l = line.lowercased()
            if l.hasPrefix("[") {
                current = nil
                inGlobal = l.hasPrefix("[software\\\\wine\\\\mac driver]")
                if let r = l.range(of: "\\\\appdefaults\\\\"), l.contains("\\\\mac driver]") {
                    let rest = l[r.upperBound...]
                    if let end = rest.range(of: "\\\\mac driver]") { current = String(rest[..<end.lowerBound]) }
                }
            } else if l.hasPrefix("\"nativemenubar\"=") {
                if let exe = current { states[exe] = l.contains("=\"y") }
                else if inGlobal { all = l.contains("=\"y") }
            }
        }
        nativeMenu = states
        nativeMenuAll = all
        loadTitleBarStates()
    }

    /// Valor "MacTitleBar" no user.reg do ambiente: do programa, senão o global, senão ligado.
    static func macTitleBar(prefix: URL, exe: String?) -> Bool {
        guard let text = try? String(contentsOf: prefix.appendingPathComponent("user.reg"), encoding: .utf8) else { return true }
        var section = "", appValue: Bool? = nil, globalValue: Bool? = nil
        let appSection = exe.map { "[software\\\\wine\\\\appdefaults\\\\\($0.lowercased())\\\\mac driver]" }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let l = line.lowercased()
            if l.hasPrefix("[") { section = String(l.prefix(while: { $0 != "]" })) + "]"; continue }
            guard l.hasPrefix("\"mactitlebar\"=") else { continue }
            let on = l.contains("=\"y")
            if let s = appSection, section == s { appValue = on }
            else if section == "[software\\\\wine\\\\mac driver]" { globalValue = on }
        }
        return appValue ?? globalValue ?? true
    }

    func loadTitleBarStates() {
        var states: [URL: Bool] = [:]
        for app in library {
            let pfx = app.prefix.map { URL(fileURLWithPath: $0) } ?? Paths.prefix
            states[app.id] = Self.macTitleBar(prefix: pfx, exe: URL(fileURLWithPath: app.exe).lastPathComponent)
        }
        titleBar = states
        titleBarAll = Self.macTitleBar(prefix: Paths.prefix, exe: nil)
    }

    func toggleTitleBar(_ app: LibraryApp) {
        let on = !(titleBar[app.id] ?? true)
        Task {
            _ = await Script.run(["titlebar", app.exe, on ? "on" : "off"], prefix: app.prefix)
            loadTitleBarStates()
            message = on
                ? "\(app.name) vai usar a barra de título do Mac (com os botões e menus do Mac). Feche e abra o programa para aplicar.\n\nPara ver a barra original dele na hora: menu Janela → Mostrar a Barra do Programa."
                : "\(app.name) volta a mostrar a própria barra de título. Feche e abra o programa para aplicar."
        }
    }

    func toggleTitleBarAll() {
        let on = !titleBarAll
        Task {
            _ = await Script.run(["titlebar", "--all", on ? "on" : "off"])
            loadTitleBarStates()
            message = on
                ? "Programas que desenham a própria barra de título (Power BI e parecidos) vão usar a barra do Mac. Reabra os programas para aplicar."
                : "Esses programas voltam a mostrar a própria barra de título. Reabra os programas para aplicar."
        }
    }

    func hasNativeMenu(_ app: LibraryApp) -> Bool {
        nativeMenu[URL(fileURLWithPath: app.exe).lastPathComponent.lowercased()] ?? nativeMenuAll
    }

    func toggleNativeMenu(_ app: LibraryApp) {
        let on = !hasNativeMenu(app)
        Task {
            _ = await Script.run(["menubar", app.exe, on ? "on" : "off"])
            loadNativeMenuStates()
            message = on
                ? "O menu do \(app.name) vai aparecer na barra de menus do Mac, lá em cima. Feche e abra o programa para aplicar."
                : "O menu do \(app.name) volta a ficar só dentro da janela. Feche e abra o programa para aplicar."
        }
    }

    // ---------- preparar o ambiente Windows

    func setup() async -> Bool {
        busy = "Preparando o ambiente Windows…\nSó na primeira vez: o motor (~225 MB) e tudo que os programas precisam (fontes, Visual C++, DirectX, .NET Framework 4.8 e WebView2). Leva uns 15 minutos; depois tudo abre direto."
        let r = await Script.run(["setup"])
        busy = nil
        await refreshWine()
        if wineVersion == nil {
            message = "Não consegui preparar o ambiente Windows.\n\(r.out.suffix(400))"
            return false
        }
        return true
    }

    // ---------- abrir um arquivo (.exe/.msi)

    /// O que o WinApps aceita abrir: .exe, .msi, .zip ou uma pasta.
    nonisolated static func acceptable(_ url: URL) -> Bool {
        if ["exe", "msi", "zip"].contains(url.pathExtension.lowercased()) { return true }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && url.pathExtension != "app"
    }

    func handle(_ url: URL) {
        Task {
            // aberto pelo Finder: espera a conferência inicial do motor antes de decidir
            while !checkedWine { try? await Task.sleep(nanoseconds: 100_000_000) }
            if wineVersion == nil, !(await setup()) { return }
            // pasta ou .zip: o script acha o programa (importa) ou o instalador (instala)
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDir || url.pathExtension.lowercased() == "zip" {
                importBundle(url); return
            }
            busy = "Analisando \(url.lastPathComponent)…"
            let r = await Script.run(["detect", url.path])
            let n = await Script.run(["needs", url.path])
            let c = await Script.run(["compat", url.path])
            let compat = Compat(json: c.out)
            busy = nil
            let parts = r.out.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
            let needs = n.out.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
                .filter { $0.hasPrefix("dotnet") || $0.hasPrefix("vcrun") || $0.hasPrefix("d3d") ||
                          $0 == "winrt-metadata" || $0 == "webview2" }
            // .msi é sempre instalador; .exe: o detector decide (na dúvida, é tratado como programa solto)
            let installer = url.pathExtension.lowercased() == "msi" || parts.first == "installer"
            // programa solto: importa direto para o WinApps (sem perguntar), a não ser que a
            // lista de compatibilidade avise que ele não funciona
            if !installer, compat?.broken != true {
                withComponents(needs) { self.adoptPortable(url, open: true) }
                return
            }
            pending = PendingFile(url: url, isInstaller: installer,
                                  reason: parts.count > 1 ? parts[1] : "",
                                  needs: needs, compat: compat)
        }
    }

    func runOnce(_ url: URL) {
        Script.launch(["run", url.path])
    }

    /// Instala os componentes que faltam e depois executa `then`.
    func withComponents(_ needs: [String], then: @escaping () -> Void) {
        guard !needs.isEmpty else { then(); return }
        Task {
            let names = needs.map(componentLabel).joined(separator: ", ")
            busy = "Instalando \(names)…\nIsso pode levar vários minutos (só acontece uma vez)."
            let r = await Script.run(["components"] + needs)
            busy = nil
            if r.code != 0 {
                let clean = r.out.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
                let err = clean.split(separator: "\n").first(where: { $0.hasPrefix("Erro:") }).map { String($0.dropFirst(6)) }
                message = err ?? "Não consegui instalar \(names). O programa pode não funcionar direito."
                if err != nil { return }
            }
            then()
        }
    }

    func install(_ url: URL) {
        Task {
            busy = "Instalando \(url.deletingPathExtension().lastPathComponent)…\nSiga as telas do instalador normalmente."
            let r = await Script.run(["install", url.path], porcelain: true)
            busy = nil
            let exes = r.out.split(separator: "\n").compactMap { line -> String? in
                line.hasPrefix("EXE\t") ? String(line.dropFirst(4)) : nil
            }
            if exes.isEmpty {
                message = "A instalação terminou, mas nenhum programa novo foi encontrado.\nSe ele já estava instalado, use \"Adicionar programa\" e escolha o .exe dentro de Arquivos do Windows."
                return
            }
            var list: [Candidate] = []
            for (i, p) in exes.enumerated() {
                list.append(Candidate(path: p, name: await Self.appName(p), selected: i == 0 || exes.count <= 2))
            }
            candidates = list
            showCandidates = true
        }
    }

    func addCandidates() {
        let chosen = candidates.filter(\.selected)
        showCandidates = false
        Task {
            busy = "Adicionando à biblioteca…"
            for c in chosen { _ = await Script.run(["shortcut", c.path, c.name]) }
            busy = nil
            reloadLibrary()
        }
    }

    /// Pasta ou .zip de um programa: importa a pasta inteira (acha o .exe principal) ou,
    /// se dentro houver um instalador, segue o fluxo de instalação.
    func importBundle(_ url: URL) {
        Task {
            busy = "Analisando \(url.lastPathComponent)…"
            let r = await Script.run(["import", url.path])
            busy = nil
            let lines = r.out.split(separator: "\n").map(String.init)
            if let inst = lines.first(where: { $0.hasPrefix("INSTALLER\t") }) {
                handle(URL(fileURLWithPath: String(inst.dropFirst(10)))); return
            }
            guard let line = lines.first(where: { $0.hasPrefix("PATH\t") }) else {
                let clean = r.out.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
                message = clean.split(separator: "\n").first(where: { $0.hasPrefix("Erro:") }).map { String($0.dropFirst(6)) }
                    ?? "Não encontrei um programa do Windows em \(url.lastPathComponent)."
                return
            }
            await finishImport(String(line.dropFirst(5)), open: true)
        }
    }

    func finishImport(_ dest: String, open: Bool) async {
        busy = "Adicionando à biblioteca…"
        _ = await Script.run(["shortcut", dest])
        busy = nil
        tab = 0
        reloadLibrary()
        if let app = library.first(where: { $0.exe == dest }) {
            showToast("\(app.name) foi importado para o WinApps: está na biblioteca e em Aplicativos. O original pode ser apagado.")
            if open { self.open(app) }
        }
    }

    /// Programa portátil: copia para dentro do C:\Portable, cria o atalho e abre.
    func adoptPortable(_ url: URL, open: Bool) {
        Task {
            busy = "Adicionando \(url.deletingPathExtension().lastPathComponent) à biblioteca…"
            let r = await Script.run(["import", url.path])
            guard let line = r.out.split(separator: "\n").first(where: { $0.hasPrefix("PATH\t") }) else {
                busy = nil; message = "Não consegui copiar o programa."; return
            }
            busy = nil
            await finishImport(String(line.dropFirst(5)), open: open)
        }
    }

    /// "Adicionar programa": um .exe já instalado no C: vira atalho direto;
    /// um de fora (Downloads etc.) passa pelo fluxo normal (instalar/portátil).
    func addExisting(_ url: URL) {
        if url.path.hasPrefix(Paths.driveC.path) {
            Task {
                busy = "Adicionando à biblioteca…"
                _ = await Script.run(["shortcut", url.path])
                busy = nil
                reloadLibrary()
            }
        } else {
            handle(url)
        }
    }

    // ---------- biblioteca

    func open(_ app: LibraryApp) {
        NSWorkspace.shared.openApplication(at: app.id, configuration: NSWorkspace.OpenConfiguration())
    }

    func remove(_ app: LibraryApp) {
        Task {
            _ = await Script.run(["remove", app.name])
            reloadLibrary()
        }
    }

    /// Duplo clique em qualquer .exe/.msi no Finder passa a abrir o WinApps.
    func makeDefaultHandler(silent: Bool = false) {
        let id = Bundle.main.bundleIdentifier ?? "com.winapps.launcher"
        var ok = true
        for t in ["com.microsoft.windows-executable", "com.microsoft.msi-installer"] {
            ok = (LSSetDefaultRoleHandlerForContentType(t as CFString, .viewer, id as CFString) == noErr) && ok
        }
        if silent { return }   // configuração automática: sem alerta (o .exe é o principal)
        message = ok ? "Pronto! Agora é só dar dois cliques em qualquer arquivo .exe ou .msi no Finder."
                     : "O macOS não deixou mudar o app padrão. Use Obter Informações → Abrir com → WinApps → Alterar Tudo."
    }

    func toggleGamepad() {
        let on = !gamepadOn
        Task {
            busy = on ? "Ligando os controles de jogo (SDL)…" : "Voltando os controles para o modo leve…"
            _ = await Script.run(["gamepad", on ? "on" : "off"])
            busy = nil
            gamepadOn = FileManager.default.fileExists(atPath: Paths.base.appendingPathComponent(".gamepad-sdl").path)
            message = gamepadOn
                ? "Controles de jogo via SDL ligados: melhor para jogos com controle de Xbox/PlayStation, mas gasta um pouco de CPU o tempo todo. Reabra os programas."
                : "Controles no modo leve: continuam funcionando, sem gastar CPU à toa. Reabra os programas."
        }
    }

    func toggleDXMT() {
        let on = !dxmtOn
        Task {
            busy = on ? "Ligando os gráficos via Metal (DXMT)…" : "Desligando o DXMT…"
            let r = await Script.run(["dxmt", on ? "on" : "off"])
            busy = nil
            dxmtOn = FileManager.default.fileExists(atPath: Paths.base.appendingPathComponent(".dxmt-installed").path)
            if r.code != 0 {
                let clean = r.out.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
                message = clean.split(separator: "\n").first(where: { $0.hasPrefix("Erro:") }).map { String($0.dropFirst(6)) }
                    ?? "Não consegui mudar o DXMT."
            } else {
                message = on
                    ? "Jogos e programas Direct3D 10/11 agora desenham direto pelo Metal (DXMT). Reabra os programas para aplicar."
                    : "DXMT desligado: volta o Direct3D padrão do motor (que costuma travar no Mac com Direct3D 11)."
            }
        }
    }

    func toggleNativeMenuAll() {
        let on = !nativeMenuAll
        Task {
            _ = await Script.run(["menubar", "--all", on ? "on" : "off"])
            loadNativeMenuStates()
            message = on
                ? "Os menus dos programas Windows vão aparecer na barra de menus do Mac. Reabra os programas para aplicar.\n\nPara desligar só um programa: botão direito nele na Biblioteca."
                : "Os menus voltam a ficar só dentro das janelas dos programas. Reabra os programas para aplicar."
        }
    }

    /// Instala componentes do Windows (sem nomes: os essenciais).
    func installComponents(_ names: [String], label: String) {
        Task {
            busy = "Instalando \(label)…\nIsso pode levar vários minutos."
            let r = await Script.run(["components"] + names)
            busy = nil
            let clean = r.out.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
            let lines = clean.split(separator: "\n").map(String.init)
            if r.code == 0 {
                message = "\(label.prefix(1).uppercased() + label.dropFirst()) instalado(s)."
            } else if let err = lines.first(where: { $0.hasPrefix("Erro:") }) {
                message = String(err.dropFirst(6))
            } else {
                message = "Alguns componentes não foram instalados.\n" + lines.suffix(3).joined(separator: "\n")
            }
        }
    }

    func killAll() {
        Task { _ = await Script.run(["kill"]); message = "Todos os programas Windows foram fechados." }
    }

    /// Nome do atalho: quem decide é o script (regra do compat.json / nome do produto).
    static func appName(_ path: String) async -> String {
        let r = await Script.run(["name", path])
        let n = r.out.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty || r.code != 0 ? friendlyName(path) : n
    }

    static func friendlyName(_ path: String) -> String {
        let base = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        // usa o nome da pasta do programa quando o .exe tem nome genérico
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
        let generic = ["app", "main", "launcher", "game", "start", "client", "program"]
        if generic.contains(base.lowercased()), !folder.isEmpty { return folder }
        return base
    }
}

// MARK: - Seletores de arquivo

@MainActor
enum Pick {
    static func program() -> URL? {
        let p = NSOpenPanel()
        p.title = "Abrir programa do Windows"
        p.message = "Escolha um instalador (.msi, setup.exe), um programa (.exe), um .zip ou a pasta do programa"
        p.prompt = "Abrir"
        p.canChooseDirectories = true
        p.allowedContentTypes = [UTType(filenameExtension: "exe")!, UTType(filenameExtension: "msi")!, .zip, .folder]
        p.directoryURL = Paths.home.appendingPathComponent("Downloads")
        return p.runModal() == .OK ? p.url : nil
    }

    static func existing() -> URL? {
        let p = NSOpenPanel()
        p.title = "Adicionar programa à biblioteca"
        p.message = "Escolha o .exe do programa — um já instalado (em Arquivos do Windows) ou um portátil"
        p.prompt = "Adicionar"
        p.allowedContentTypes = [UTType(filenameExtension: "exe")!]
        p.directoryURL = Paths.driveC
        return p.runModal() == .OK ? p.url : nil
    }
}

// MARK: - Interface

/// Estado local simples (substitui @State, cujo macro não vem nas Command Line Tools)
final class Flag: ObservableObject { @Published var on = false }

/// Valor simples observável (substitui @State para textos, filtros etc.)
final class Box<T>: ObservableObject { @Published var v: T; init(_ v: T) { self.v = v } }

struct ContentView: View {
    @ObservedObject var model = Model.shared
    @StateObject private var drop = Flag()
    @StateObject private var search = Box("")

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Group {
                    switch model.tab {
                    case 1: CompatibilityView()
                    case 2: FileBrowserView()
                    default: libraryTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let toast = model.toast { toastView(toast) }
            if let busy = model.busy { busyOverlay(busy) }
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("WinApps")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Seção", selection: $model.tab) {
                    Text("Biblioteca").tag(0)
                    Text("Compatibilidade").tag(1)
                    Text("Arquivos").tag(2)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            if model.checkedWine && model.wineVersion == nil {
                ToolbarItem(placement: .primaryAction) { statusPill }
            }
            ToolbarItem(placement: .primaryAction) {
                ProminentButton(title: "Abrir programa", symbol: "plus") {
                    if let u = Pick.program() { model.handle(u) }
                }
                .help("Abrir um .exe, .msi, .zip ou a pasta de um programa do Windows (⌘O)")
            }
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .primaryAction) { menu }.sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .primaryAction) { menu }
            }
        }
        .sheet(item: $model.pending) { PendingSheet(file: $0) }
        .sheet(isPresented: $model.showCandidates) { CandidatesSheet() }
        .alert("WinApps", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reloadLibrary()
        }
    }

    // ---- barra de ferramentas

    var menu: some View {
        Menu {
            if let v = model.wineVersion {
                Text("Ambiente Windows pronto · motor \(v)")
                Divider()
            }
            Button("Guia do WinApps") { Guide.show() }
            Divider()
            Button("Fechar todos os programas Windows") { model.killAll() }
            Divider()
            // o padrão já é o que funcionou nos testes; aqui só para casos específicos
            Menu("Avançado") {
                Toggle("Menus dos programas na barra do Mac", isOn: Binding(
                    get: { model.nativeMenuAll }, set: { _ in model.toggleNativeMenuAll() }))
                Toggle("Barra de título do Mac em programas com barra própria", isOn: Binding(
                    get: { model.titleBarAll }, set: { _ in model.toggleTitleBarAll() }))
                Toggle("Gráficos via Metal para jogos (Direct3D 10/11)", isOn: Binding(
                    get: { model.dxmtOn }, set: { _ in model.toggleDXMT() }))
                Toggle("Controles de jogo avançados (usa mais CPU)", isOn: Binding(
                    get: { model.gamepadOn }, set: { _ in model.toggleGamepad() }))
                Divider()
                Button("Adicionar programa já instalado…") { if let u = Pick.existing() { model.addExisting(u) } }
                Button("Abrir .exe e .msi sempre com o WinApps") { model.makeDefaultHandler() }
                Button("Reparar o ambiente Windows (reinstala os componentes)") {
                    model.installComponents([], label: "componentes do Windows")
                }
                Button("Configurações do Windows…") { Script.launch(["config"]) }
                Button("Abrir pasta de registros (logs)") { NSWorkspace.shared.open(Paths.logs) }
            }
            Divider()
            Button("Créditos e licenças") { Guide.showLicenses() }
        } label: { Image(systemName: "ellipsis.circle") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Mais opções")
    }

    @ViewBuilder var statusPill: some View {
        if !model.checkedWine {
            ProgressView().controlSize(.small)
        } else if let v = model.wineVersion {
            Circle().fill(Color.green).frame(width: 8, height: 8)
                .help("Ambiente Windows pronto (motor \(v))")
        } else {
            Button {
                Task { _ = await model.setup() }
            } label: { Label("Preparar o Windows", systemImage: "arrow.down.circle.fill") }
            .buttonStyle(.bordered)
        }
    }

    // ---- biblioteca

    var filteredLibrary: [LibraryApp] {
        let q = search.v.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? model.library : model.library.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var libraryTab: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    dropBanner
                    HStack(spacing: 10) {
                        Text("Biblioteca").font(.title3.weight(.semibold))
                        Text("\(model.library.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        if model.library.count > 6 { SearchField(text: $search.v, prompt: "Buscar na biblioteca").frame(width: 220) }
                        Button { NSWorkspace.shared.open(Paths.apps) } label: {
                            Label("Ver em Aplicativos", systemImage: "arrow.up.forward.app")
                        }.buttonStyle(.link).font(.callout)
                    }
                    if model.library.isEmpty {
                        Text("Nenhum programa ainda. Arraste um para a faixa acima.")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 30)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 118, maximum: 140), spacing: 14)], spacing: 14) {
                            ForEach(filteredLibrary) { app in AppTile(app: app) }
                        }
                    }
                    StorageView()
                }
                .padding(24)
            }
            if drop.on { dropOverlay }
        }
        .onDrop(of: [.fileURL], isTargeted: $drop.on) { providers in
            for prov in providers {
                _ = prov.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, Model.acceptable(url) else { return }
                    Task { @MainActor in Model.shared.handle(url) }
                }
            }
            return true
        }
    }

    var dropBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 26)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("Arraste um programa do Windows para cá").font(.callout.weight(.semibold))
                Text("Instaladores (.msi, setup.exe) são instalados. Programas soltos — .exe, pasta ou .zip — são importados.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Escolher…") { if let u = Pick.program() { model.handle(u) } }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
    }

    var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.accentColor.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor, lineWidth: 3))
            .overlay(Label("Solte para abrir no WinApps", systemImage: "arrow.down.doc.fill")
                .font(.title2.weight(.semibold)).foregroundStyle(Color.accentColor))
            .padding(10)
            .allowsHitTesting(false)
    }

    func toastView(_ text: String) -> some View {
        VStack {
            Spacer()
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                Button { model.toast = nil } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
            .padding(14).frame(maxWidth: 520)
            .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 3))
            .padding(.bottom, 20)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    func busyOverlay(_ text: String) -> some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text(text).multilineTextAlignment(.center).font(.callout)
            }
            .padding(28).frame(maxWidth: 380)
            .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial))
        }
    }
}

/// Quanto o WinApps ocupa: barra empilhada + lista (motor, ambiente, cada programa, cache).
struct StorageView: View {
    @ObservedObject var model = Model.shared
    static let colors: [Color] = [.gray, .blue, .orange, .purple]
    static let programColors: [Color] = [.orange, .pink, .yellow, .mint, .red, .brown, .cyan]

    func color(_ item: Model.StorageItem, _ i: Int) -> Color {
        item.kind == 2 ? Self.programColors[i % Self.programColors.count] : Self.colors[item.kind]
    }
    static func help(_ kind: Int) -> String {
        switch kind {
        case 0: return "O motor que roda os programas do Windows (um só para todos)."
        case 1: return "O Windows compartilhado por todos os programas: fontes, Visual C++, DirectX, .NET 4.8 e WebView2."
        case 2: return "A pasta do programa dentro do ambiente Windows."
        default: return "Arquivos temporários do Windows e downloads em cache. Podem ser apagados (botão Liberar)."
        }
    }
    static func fmt(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

    var body: some View {
        let items = model.storage
        let total = items.reduce(Int64(0)) { $0 + $1.bytes }
        let progIndex: [UUID: Int] = Dictionary(uniqueKeysWithValues: items.filter { $0.kind == 2 }.enumerated().map { ($1.id, $0) })
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Armazenamento").font(.title3.weight(.semibold))
                if total > 0 {
                    Text("WinApps ocupa \(Self.fmt(total))").font(.callout.weight(.medium))
                    Text("· \(Self.fmt(model.storageFree)) livres no disco").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if model.storageLoading { ProgressView().controlSize(.small) }
                if let junk = items.first(where: { $0.kind == 3 }) {
                    Button("Liberar \(Self.fmt(junk.bytes))") { model.cleanUp() }
                        .help("Fecha os programas Windows abertos e apaga temporários e downloads em cache")
                }
                Button { model.loadStorage() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Recalcular")
            }
            if total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(items) { it in
                            Rectangle().fill(color(it, progIndex[it.id] ?? 0))
                                .frame(width: max(2, geo.size.width * CGFloat(it.bytes) / CGFloat(total) - 2))
                                .help("\(it.name): \(Self.fmt(it.bytes))")
                        }
                    }
                }
                .frame(height: 10).clipShape(Capsule())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 18, alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(items) { it in
                        HStack(spacing: 8) {
                            Circle().fill(color(it, progIndex[it.id] ?? 0)).frame(width: 8, height: 8)
                            Text(it.name).font(.callout).lineLimit(1)
                                .help(Self.help(it.kind))
                            Spacer(minLength: 6)
                            Text(Self.fmt(it.bytes)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            } else if model.storageLoading {
                Text("Calculando…").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .padding(.top, 8)
    }
}

/// Botão de destaque da barra (vidro colorido no macOS 26+, preenchido antes).
struct ProminentButton: View {
    let title: String, symbol: String, action: () -> Void
    var body: some View {
        let b = Button(action: action) { Label(title, systemImage: symbol).labelStyle(.titleAndIcon) }
        if #available(macOS 26.0, *) { b.buttonStyle(.glassProminent) } else { b.buttonStyle(.borderedProminent) }
    }
}

/// Campo de busca no estilo do macOS (lupa + limpar).
struct SearchField: View {
    @Binding var text: String
    let prompt: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.secondary.opacity(0.25)))
    }
}

struct AppTile: View {
    let app: LibraryApp
    @ObservedObject var model = Model.shared
    @StateObject private var hoverFlag = Flag()
    private var hover: Bool { hoverFlag.on }

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: app.icon).resizable().frame(width: 72, height: 72)
                .shadow(color: .black.opacity(hover ? 0.35 : 0.15), radius: hover ? 8 : 3, y: hover ? 4 : 1)
                .scaleEffect(hover ? 1.06 : 1)
            Text(app.name).font(.callout.weight(.medium)).lineLimit(2).multilineTextAlignment(.center)
            BadgeView(badge: model.badge(app), compact: true)
            Text(model.size(of: app).map(StorageView.fmt) ?? " ")
                .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(hover ? Color.primary.opacity(0.06) : .clear))
        .animation(.easeOut(duration: 0.15), value: hover)
        .contentShape(Rectangle())
        .onHover { hoverFlag.on = $0 }
        .onTapGesture { model.open(app) }
        .help("Abrir \(app.name) — clique com o botão direito para mais opções")
        .contextMenu {
            Button("Abrir") { model.open(app) }
            Button("Mostrar arquivos do programa") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.exe)])
            }
            Button("Mostrar atalho em Aplicativos") {
                NSWorkspace.shared.activateFileViewerSelecting([app.id])
            }
            Divider()
            Toggle("Menu na barra do Mac", isOn: Binding(
                get: { model.hasNativeMenu(app) },
                set: { _ in model.toggleNativeMenu(app) }))
            Toggle("Barra de título do Mac", isOn: Binding(
                get: { model.titleBar[app.id] ?? true },
                set: { _ in model.toggleTitleBar(app) }))
            Divider()
            Button("Remover da biblioteca", role: .destructive) { model.remove(app) }
        }
    }
}

struct PendingSheet: View {
    let file: PendingFile
    @ObservedObject var model = Model.shared
    @StateObject private var installNeeds: Flag = { let f = Flag(); f.on = true; return f }()
    private var needs: [String] { installNeeds.on ? file.needs : [] }
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                    .resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.url.lastPathComponent).font(.headline).lineLimit(1)
                    Label(file.isInstaller ? "Instalador" : "Programa portátil (roda sem instalar)",
                          systemImage: file.isInstaller ? "shippingbox.fill" : "bolt.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(file.isInstaller ? .blue : .purple)
                }
            }
            if let c = file.compat {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: c.badge.symbol)
                        .font(.title3).foregroundStyle(c.badge.color)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(c.name).font(.callout.weight(.semibold))
                            BadgeView(badge: c.badge, compact: true)
                        }
                        Text(c.why).font(.callout).fixedSize(horizontal: false, vertical: true)
                        if !c.alt.isEmpty {
                            Label(c.alt, systemImage: "lightbulb.fill").font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill((c.broken ? Color.red : c.works ? Color.green : Color.orange).opacity(0.12)))
            }
            Text(file.isInstaller
                 ? "O programa será instalado no WinApps: siga as telas do instalador normalmente. No fim, ele aparece na sua biblioteca e em Aplicativos."
                 : "Ele será importado para o WinApps e ganhará um ícone na biblioteca e em Aplicativos.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !file.needs.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Este programa precisa de: \(file.needs.map(componentLabel).joined(separator: ", "))")
                            .font(.callout.weight(.medium))
                        Toggle("Instalar antes de continuar (pode levar vários minutos)", isOn: $installNeeds.on)
                            .font(.caption)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.10)))
            }
            HStack {
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if file.isInstaller {
                    let b = Button(file.compat?.broken == true ? "Instalar mesmo assim" : "Instalar") {
                        let u = file.url; model.withComponents(needs) { model.install(u) }; dismiss()
                    }
                    if file.compat?.broken == true { b } else { b.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
                } else {
                    let b = Button(file.compat?.broken == true ? "Importar mesmo assim" : "Importar e abrir") {
                        let u = file.url; model.withComponents(needs) { model.adoptPortable(u, open: true) }; dismiss()
                    }
                    if file.compat?.broken == true { b } else { b.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
                }
            }
        }
        .padding(24).frame(width: 480)
    }
}

/// Programas testados: tabela com busca (compat.json embutido no app — a mesma fonte do
/// COMPATIBILIDADE.md do repositório). Clique numa linha para ver os detalhes.
struct CompatibilityView: View {
    @ObservedObject var model = Model.shared
    @StateObject private var query = Box("")
    @StateObject private var filter = Box(0)            // 0 todos, 1 verificados, 2 funcionam, 3 não funcionam
    // "-expand <nome>" ao abrir o app: linha já expandida (testes da interface)
    @StateObject private var expanded = Box(Set([UserDefaults.standard.string(forKey: "expand")].compactMap { $0 }))

    static let order = ["Produtividade", "Jogos", "Utilitários", "Não suportados", "Por tecnologia"]
    static let repoTable = URL(string: "https://github.com/matthfaria96/rubinot-macos-bypass/blob/master/COMPATIBILIDADE.md")!

    static let all: [Compat] = {
        guard let url = Bundle.main.url(forResource: "compat", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = obj["rules"] as? [[String: Any]] else { return [] }
        let list = rules.map(Compat.init(rule:))
        return list.enumerated().sorted { a, b in
            let ia = order.firstIndex(of: a.element.category) ?? 99, ib = order.firstIndex(of: b.element.category) ?? 99
            return ia != ib ? ia < ib : a.offset < b.offset
        }.map(\.element)
    }()

    var rows: [Compat] {
        let q = query.v.trimmingCharacters(in: .whitespaces)
        return Self.all.filter { c in
            switch filter.v {
            case 1: if !c.verified { return false }
            case 2: if !(c.works || c.verified) { return false }
            case 3: if !c.broken { return false }
            default: break
            }
            guard !q.isEmpty else { return true }
            return [c.name, c.summary, c.category, c.why, c.alt, c.fixes.joined(separator: " ")]
                .contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    // larguras das colunas
    let wName: CGFloat = 250, wBadge: CGFloat = 116, wDate: CGFloat = 84, wFix: CGFloat = 76

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SearchField(text: $query.v, prompt: "Buscar programa, correção…").frame(width: 250)
                Picker("", selection: $filter.v) {
                    Text("Todos").tag(0)
                    Text("Verificados").tag(1)
                    Text("Funcionam").tag(2)
                    Text("Não funcionam").tag(3)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                Text("\(rows.count) de \(Self.all.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Link(destination: Self.repoTable) { Image(systemName: "arrow.up.right.square") }
                    .help("Abrir a tabela no GitHub (COMPATIBILIDADE.md)")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            headerRow
            Divider()
            if rows.isEmpty {
                VStack(spacing: 6) {
                    Text("Nada encontrado").font(.headline)
                    Text("Programas fora desta lista aparecem como Não testado: podem funcionar, só ninguém conferiu ainda.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: 420, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.name) { i, c in
                            row(c, odd: i % 2 == 1)
                        }
                    }
                }
            }
            Divider()
            HStack(spacing: 14) {
                ForEach([Badge.verified, .works, .partial, .broken, .untested], id: \.label) { b in
                    Label(b.label, systemImage: b.symbol).foregroundStyle(b.color).help(b.help)
                }
                Spacer()
                Text("Clique numa linha para ver detalhes").foregroundStyle(.tertiary)
            }
            .font(.caption).padding(.horizontal, 16).padding(.vertical, 7)
        }
    }

    var headerRow: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 12, height: 1)
            Text("Programa").frame(width: wName, alignment: .leading)
            Text("Situação").frame(width: wBadge, alignment: .leading)
            Text("Resumo").frame(maxWidth: .infinity, alignment: .leading)
            Text("Testado").frame(width: wDate, alignment: .leading)
            Text("Correções").frame(width: wFix, alignment: .trailing)
        }
        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 6)
    }

    func row(_ c: Compat, odd: Bool) -> some View {
        let open = expanded.v.contains(c.name)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 12)
                HStack(spacing: 6) {
                    if let app = model.installed(c) {
                        Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
                            .help("Na sua biblioteca")
                    }
                    Text(c.name).font(.callout.weight(.medium)).lineLimit(1).help(c.name)
                }
                .frame(width: wName, alignment: .leading)
                BadgeView(badge: c.badge, compact: true).frame(width: wBadge, alignment: .leading)
                Text(c.summary).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(c.tested.isEmpty ? "—" : c.tested).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: wDate, alignment: .leading)
                Text(c.fixes.isEmpty ? "—" : "\(c.fixes.count)").font(.caption.monospacedDigit())
                    .foregroundStyle(c.fixes.isEmpty ? Color.secondary : Color.green)
                    .frame(width: wFix, alignment: .trailing)
            }
            .padding(.horizontal, 16).frame(height: 32)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) {
                    if open { expanded.v.remove(c.name) } else { expanded.v.insert(c.name) }
                }
            }
            if open { details(c) }
        }
        .background(odd ? Color.primary.opacity(0.035) : Color.clear)
    }

    func details(_ c: Compat) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 6) {
            detail("Detalhes", c.why)
            if !c.alt.isEmpty { detail("Dica", c.alt) }
            if !c.needs.isEmpty {
                detail("Precisa de", c.needs.map(componentLabel).joined(separator: ", ") + " — já incluídos no WinApps")
            }
            if !c.fixes.isEmpty {
                GridRow {
                    Text("Correções").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(c.fixes, id: \.self) { f in
                            Label(f, systemImage: "wrench.and.screwdriver").font(.caption)
                        }
                    }
                }
            }
            if !c.category.isEmpty { detail("Categoria", c.category) }
        }
        .padding(.leading, 38).padding(.trailing, 16).padding(.bottom, 12).padding(.top, 2)
        .textSelection(.enabled)
    }

    @ViewBuilder func detail(_ label: String, _ text: String) -> some View {
        GridRow {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CandidatesSheet: View {
    @ObservedObject var model = Model.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Instalação concluída", systemImage: "checkmark.seal.fill")
                .font(.title3.weight(.semibold)).foregroundStyle(.green)
            Text("Marque o que deve aparecer na sua biblioteca (e em Aplicativos). Você pode mudar o nome.")
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach($model.candidates) { $c in
                    HStack(spacing: 10) {
                        Toggle("", isOn: $c.selected).labelsHidden()
                        Image(nsImage: NSWorkspace.shared.icon(forFile: c.path)).resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Nome", text: $c.name).textFieldStyle(.roundedBorder)
                            Text(c.path.replacingOccurrences(of: Paths.driveC.path + "/", with: "C:/"))
                                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
            HStack {
                Button("Agora não") { model.showCandidates = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Adicionar à biblioteca") { model.addCandidates() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(!model.candidates.contains(where: \.selected))
            }
        }
        .padding(24).frame(width: 520)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in for u in urls { Model.shared.handle(u) } }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for w in NSApp.windows where w.isVisible {
                let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(w.frame) }
                if !onScreen { w.center() }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct WinAppsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("WinApps", id: "main") {
            ContentView()
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 980, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Abrir programa do Windows…") { if let u = Pick.program() { Model.shared.handle(u) } }
                    .keyboardShortcut("o")
                Button("Adicionar programa já instalado…") { if let u = Pick.existing() { Model.shared.addExisting(u) } }
            }
            CommandGroup(replacing: .help) {
                Button("Guia do WinApps") { Guide.show() }.keyboardShortcut("?")
            }
        }
    }
}

// MARK: - Guia (GUIA.md: o mesmo arquivo do repositório, embutido no app)

enum Guide {
    static var windows: [String: NSWindow] = [:]

    static func show() { show(resource: "GUIA", title: "Guia do WinApps") }
    static func showLicenses() { show(resource: "LICENCAS", title: "Créditos e licenças") }

    static func show(resource: String, title: String) {
        if let w = windows[resource] { w.makeKeyAndOrderFront(nil); return }
        let text = Bundle.main.url(forResource: resource, withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "# \(title)\n\nArquivo não encontrado no app."
        let w = NSWindow(contentViewController: NSHostingController(rootView: GuideView(blocks: GuideBlock.parse(text))))
        w.title = title
        w.setContentSize(NSSize(width: 720, height: 760))
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        windows[resource] = w
    }
}

/// Markdown simples do guia: títulos, parágrafos, listas (com um nível de recuo) e código.
enum GuideBlock: Hashable {
    case heading(Int, String), paragraph(String), bullet(Int, String), numbered(String, String), code(String)

    static func parse(_ text: String) -> [GuideBlock] {
        var out: [GuideBlock] = []
        var code: [String]? = nil
        func appendToLast(_ s: String) {
            guard let last = out.popLast() else { out.append(.paragraph(s)); return }
            switch last {
            case .paragraph(let t): out.append(.paragraph(t + " " + s))
            case .bullet(let l, let t): out.append(.bullet(l, t + " " + s))
            case .numbered(let n, let t): out.append(.numbered(n, t + " " + s))
            default: out.append(last); out.append(.paragraph(s))
            }
        }
        var continuing = false
        for raw in text.components(separatedBy: "\n") {
            if raw.hasPrefix("```") {
                if let c = code { out.append(.code(c.joined(separator: "\n"))); code = nil } else { code = [] }
                continuing = false
                continue
            }
            if code != nil { code!.append(raw); continue }
            let indent = raw.prefix(while: { $0 == " " }).count
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continuing = false; continue }
            let hashes = line.prefix(while: { $0 == "#" }).count
            let digits = line.prefix(while: { $0.isNumber })
            if (1...3).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") {
                out.append(.heading(hashes, String(line.dropFirst(hashes + 1)))); continuing = false
            } else if line.hasPrefix("- ") {
                out.append(.bullet(indent >= 2 ? 1 : 0, String(line.dropFirst(2)))); continuing = true
            } else if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
                out.append(.numbered(String(digits), String(line.dropFirst(digits.count + 2)))); continuing = true
            } else if continuing {
                appendToLast(line)
            } else {
                out.append(.paragraph(line)); continuing = true
            }
        }
        return out
    }
}

struct GuideView: View {
    let blocks: [GuideBlock]

    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                    switch b {
                    case .heading(let level, let t):
                        Text(Self.inline(t))
                            .font(level == 1 ? .largeTitle.bold() : level == 2 ? .title2.bold() : .title3.weight(.semibold))
                            .padding(.top, level == 1 ? 0 : 12)
                    case .paragraph(let t):
                        Text(Self.inline(t)).fixedSize(horizontal: false, vertical: true)
                    case .bullet(let level, let t):
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(level == 0 ? "•" : "◦").foregroundStyle(.secondary)
                            Text(Self.inline(t)).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, level == 0 ? 4 : 26)
                    case .numbered(let n, let t):
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(n + ".").monospacedDigit().foregroundStyle(.secondary)
                            Text(Self.inline(t)).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, 4)
                    case .code(let t):
                        Text(t).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
                    }
                }
            }
            .padding(.horizontal, 36).padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }
}
