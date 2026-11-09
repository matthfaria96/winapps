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

// MARK: - Idioma
// Inglês é o padrão; português (pt-BR) quando é o idioma preferido do Mac.
// Textos fixos da SwiftUI viram LocalizedStringKey sozinhos; textos montados em código usam L().

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

enum UILang {
    static let isPT: Bool = (Bundle.main.preferredLocalizations.first ?? "en").lowercased().hasPrefix("pt")
    /// Valor de WINAPPS_UI_LANG passado ao script.
    static var code: String { isPT ? "pt" : "en" }
}

extension String {
    /// Primeira letra maiúscula (mensagens que vêm do script).
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Saída do script sem cores ANSI.
func stripANSI(_ s: String) -> String {
    s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
}

/// Primeira linha de erro do script ("Error: …" ou, em português, "Erro: …"), sem o prefixo.
func scriptError(_ out: String) -> String? {
    for line in stripANSI(out).split(separator: "\n") {
        for p in ["Error:", "Erro:"] where line.hasPrefix(p) {
            return line.dropFirst(p.count).trimmingCharacters(in: .whitespaces)
        }
    }
    return nil
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
            env["WINAPPS_UI_LANG"] = UILang.code   // mensagens e diálogos do script no idioma do app
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
        var env = ProcessInfo.processInfo.environment
        env["WINAPPS_UI_LANG"] = UILang.code
        p.environment = env
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

/// compat.json embutido no app. Campos de texto em inglês no topo de cada regra; o objeto
/// opcional "pt" traz os mesmos campos em português (usados quando o app está em português).
enum CompatDB {
    static let rules: [[String: Any]] = {
        guard let url = Bundle.main.url(forResource: "compat", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = obj["rules"] as? [[String: Any]] else { return [] }
        return rules
    }()

    /// Campo da regra no idioma do app: rule["pt"][key] em português, senão rule[key].
    static func field(_ r: [String: Any], _ key: String) -> Any? {
        if UILang.isPT, let pt = r["pt"] as? [String: Any], let v = pt[key] { return v }
        return r[key]
    }
    static func text(_ r: [String: Any], _ key: String) -> String { field(r, key) as? String ?? "" }
    static func list(_ r: [String: Any], _ key: String) -> [String] {
        if let a = field(r, key) as? [String] { return a }
        // a saída do script junta listas com "; " (fixes) ou espaço (needs)
        let s = field(r, key) as? String ?? ""
        let sep: Character = key == "needs" ? " " : ";"
        return s.split(separator: sep).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Regra pelo nome (em inglês ou no "pt").
    static func rule(named name: String) -> [String: Any]? {
        guard !name.isEmpty else { return nil }
        return rules.first { r in
            r["name"] as? String == name || (r["pt"] as? [String: Any])?["name"] as? String == name
        }
    }
}

/// Aviso da lista de compatibilidade (compat.json).
struct Compat {
    let name: String, status: String, why: String, alt: String
    var key = ""          // nome da regra no topo do JSON (identidade, independe do idioma)
    var verified = false
    var tested = ""
    var fixes: [String] = []
    var summary = ""
    var category = ""     // texto exibido (no idioma do app)
    var categoryKey = ""  // categoria no topo do JSON (ordem da tabela)
    var needs: [String] = []
    var broken: Bool { status == "nao-funciona" }
    var works: Bool { status == "funciona" }

    init(name: String, status: String, why: String, alt: String,
         verified: Bool = false, tested: String = "", fixes: [String] = []) {
        self.name = name; self.status = status; self.why = why; self.alt = alt
        self.verified = verified; self.tested = tested; self.fixes = fixes
        self.key = name
    }

    /// Linha JSON de `winapps compat` (exe-kind.py --compat). Quando a regra existe no
    /// compat.json do app, usa ela inteira (com os textos no idioma do app).
    init?(json out: String) {
        guard let line = out.split(separator: "\n").last(where: { $0.hasPrefix("{") }),
              let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
        // "rule" = nome da regra no topo do compat.json (não depende do idioma)
        let ruleName = o["rule"] as? String ?? o["name"] as? String ?? ""
        if let r = CompatDB.rule(named: ruleName) { self.init(rule: r); return }
        let verified: Bool = (o["verified"] as? Bool) ?? !((o["verified"] as? String) ?? "").isEmpty
        self.init(name: CompatDB.text(o, "name"), status: o["status"] as? String ?? "",
                  why: CompatDB.text(o, "why"), alt: CompatDB.text(o, "alt"),
                  verified: verified, tested: o["tested"] as? String ?? "", fixes: CompatDB.list(o, "fixes"))
        key = ruleName.isEmpty ? name : ruleName
        summary = CompatDB.text(o, "summary")
        category = CompatDB.text(o, "category")
        categoryKey = o["category"] as? String ?? ""
        needs = CompatDB.list(o, "needs")
    }

    /// Regra do compat.json (aba Compatibilidade).
    init(rule r: [String: Any]) {
        self.init(name: CompatDB.text(r, "name"), status: r["status"] as? String ?? "",
                  why: CompatDB.text(r, "why"), alt: CompatDB.text(r, "alt"),
                  verified: r["verified"] as? Bool ?? false, tested: r["tested"] as? String ?? "",
                  fixes: CompatDB.list(r, "fixes"))
        key = r["name"] as? String ?? name
        summary = CompatDB.text(r, "summary")
        category = CompatDB.text(r, "category")
        categoryKey = r["category"] as? String ?? ""
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
        case .verified: return L("Verified")
        case .works: return L("Works")
        case .partial: return L("Partial")
        case .broken: return L("Doesn’t Work")
        case .untested: return L("Untested")
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
        case .verified: return L("Tested end to end, with WinApps’ own fixes. Guaranteed in this version.")
        case .works: return L("Tested: it opens and its main features work.")
        case .partial: return L("Works with limitations.")
        case .broken: return L("Doesn’t run in WinApps.")
        case .untested: return L("Not tested by WinApps yet: it may work, but nobody has checked.")
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
    case "winrt-metadata": return L("Windows metadata (WinRT)")
    case "webview2": return L("WebView2 (built-in browser)")
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
    // "-WinAppsTab N" ao abrir (capturas de tela) escolhe a aba sem mudar a lembrada
    @Published var tab = UserDefaults.standard.object(forKey: "WinAppsTab") != nil
        ? UserDefaults.standard.integer(forKey: "WinAppsTab") : UserDefaults.standard.integer(forKey: "tab") {
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
    func installed(_ c: Compat) -> LibraryApp? { library.first { badges[$0.exe]?.key == c.key } }

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
            busy = L("Quitting Windows programs and freeing up space…")
            let r = await Script.run(["clean", "--force"])
            busy = nil
            let lines = stripANSI(r.out).split(separator: "\n").map(String.init)
            if let err = scriptError(r.out) {
                message = err.capitalizedFirst + (err.hasSuffix(".") ? "" : ".")
            } else {
                showToast(lines.last.map { $0.replacingOccurrences(of: "==> ", with: "") } ?? L("Space freed up."))
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
            items.append(StorageItem(name: L("Engine"), bytes: sizes[motor] ?? 0, kind: 0))
            items.append(StorageItem(name: L("Windows Environment"),
                                     bytes: max(0, (sizes[prefix] ?? 0) - progs.reduce(0) { $0 + $1.bytes } - temp), kind: 1))
            items += progs
            let junk = temp + (sizes[cache] ?? 0)
            if junk > 1_000_000 { items.append(StorageItem(name: L("Temporary Files and Cache"), bytes: junk, kind: 3)) }
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
            message = String(format: on
                ? L("%@ will use the Mac title bar, with Mac window buttons and menus. Quit and reopen the program to apply.\n\nTo see its own title bar at any time, choose Window → Show Program Title Bar.")
                : L("%@ will go back to showing its own title bar. Quit and reopen the program to apply."), app.name)
        }
    }

    func toggleTitleBarAll() {
        let on = !titleBarAll
        Task {
            _ = await Script.run(["titlebar", "--all", on ? "on" : "off"])
            loadTitleBarStates()
            message = on
                ? L("Programs that draw their own title bar (like Power BI) will use the Mac title bar. Reopen the programs to apply.")
                : L("These programs will go back to showing their own title bar. Reopen the programs to apply.")
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
            message = String(format: on
                ? L("%@’s menus will appear in the Mac menu bar at the top of the screen. Quit and reopen the program to apply.")
                : L("%@’s menus will stay inside its window only. Quit and reopen the program to apply."), app.name)
        }
    }

    // ---------- preparar o ambiente Windows

    func setup() async -> Bool {
        busy = L("Setting up the Windows environment…\nFirst time only: the engine (~225 MB) and everything programs need (fonts, Visual C++, DirectX, .NET Framework 4.8 and WebView2). It takes about 15 minutes; after that, everything opens right away.")
        let r = await Script.run(["setup"])
        busy = nil
        await refreshWine()
        if wineVersion == nil {
            message = L("Couldn’t set up the Windows environment.") + "\n" + String(r.out.suffix(400))
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
            busy = String(format: L("Analyzing %@…"), url.lastPathComponent)
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
            busy = String(format: L("Installing %@…\nThis may take several minutes (it only happens once)."), names)
            let r = await Script.run(["components"] + needs)
            busy = nil
            if r.code != 0 {
                let err = scriptError(r.out)
                message = err ?? String(format: L("Couldn’t install %@. The program may not work properly."), names)
                if err != nil { return }
            }
            then()
        }
    }

    func install(_ url: URL) {
        Task {
            busy = String(format: L("Installing %@…\nFollow the installer’s steps as usual."), url.deletingPathExtension().lastPathComponent)
            let r = await Script.run(["install", url.path], porcelain: true)
            busy = nil
            let exes = r.out.split(separator: "\n").compactMap { line -> String? in
                line.hasPrefix("EXE\t") ? String(line.dropFirst(4)) : nil
            }
            if exes.isEmpty {
                message = L("The installation finished, but no new program was found.\nIf it was already installed, choose Add Installed Program… and pick its .exe on drive C:.")
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
            busy = L("Adding to the library…")
            for c in chosen { _ = await Script.run(["shortcut", c.path, c.name]) }
            busy = nil
            reloadLibrary()
        }
    }

    /// Pasta ou .zip de um programa: importa a pasta inteira (acha o .exe principal) ou,
    /// se dentro houver um instalador, segue o fluxo de instalação.
    func importBundle(_ url: URL) {
        Task {
            busy = String(format: L("Analyzing %@…"), url.lastPathComponent)
            let r = await Script.run(["import", url.path])
            busy = nil
            let lines = r.out.split(separator: "\n").map(String.init)
            if let inst = lines.first(where: { $0.hasPrefix("INSTALLER\t") }) {
                handle(URL(fileURLWithPath: String(inst.dropFirst(10)))); return
            }
            guard let line = lines.first(where: { $0.hasPrefix("PATH\t") }) else {
                message = scriptError(r.out)
                    ?? String(format: L("Couldn’t find a Windows program in %@."), url.lastPathComponent)
                return
            }
            await finishImport(String(line.dropFirst(5)), open: true)
        }
    }

    func finishImport(_ dest: String, open: Bool) async {
        busy = L("Adding to the library…")
        _ = await Script.run(["shortcut", dest])
        busy = nil
        tab = 0
        reloadLibrary()
        if let app = library.first(where: { $0.exe == dest }) {
            showToast(String(format: L("%@ was imported into WinApps: it’s in your library and in Applications. You can delete the original."), app.name))
            if open { self.open(app) }
        }
    }

    /// Programa portátil: copia para dentro do C:\Portable, cria o atalho e abre.
    func adoptPortable(_ url: URL, open: Bool) {
        Task {
            busy = String(format: L("Adding %@ to the library…"), url.deletingPathExtension().lastPathComponent)
            let r = await Script.run(["import", url.path])
            guard let line = r.out.split(separator: "\n").first(where: { $0.hasPrefix("PATH\t") }) else {
                busy = nil; message = scriptError(r.out) ?? L("Couldn’t copy the program."); return
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
                busy = L("Adding to the library…")
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
        message = ok ? L("Done! Now just double-click any .exe or .msi file in the Finder.")
                     : L("macOS didn’t allow changing the default app. In the Finder, choose Get Info → Open With → WinApps → Change All.")
    }

    func toggleGamepad() {
        let on = !gamepadOn
        Task {
            busy = on ? L("Turning on advanced game controllers (SDL)…") : L("Switching game controllers back to light mode…")
            _ = await Script.run(["gamepad", on ? "on" : "off"])
            busy = nil
            gamepadOn = FileManager.default.fileExists(atPath: Paths.base.appendingPathComponent(".gamepad-sdl").path)
            message = gamepadOn
                ? L("Game controllers via SDL are on: better for games with Xbox or PlayStation controllers, but they use a little CPU all the time. Reopen the programs to apply.")
                : L("Game controllers are in light mode: they still work, without wasting CPU. Reopen the programs to apply.")
        }
    }

    func toggleDXMT() {
        let on = !dxmtOn
        Task {
            busy = on ? L("Turning on Metal graphics (DXMT)…") : L("Turning off DXMT…")
            let r = await Script.run(["dxmt", on ? "on" : "off"])
            busy = nil
            dxmtOn = FileManager.default.fileExists(atPath: Paths.base.appendingPathComponent(".dxmt-installed").path)
            if r.code != 0 {
                message = scriptError(r.out) ?? L("Couldn’t change the DXMT setting.")
            } else {
                message = on
                    ? L("Direct3D 10/11 games and programs now draw directly through Metal (DXMT). Reopen the programs to apply.")
                    : L("DXMT is off: the engine’s standard Direct3D is back (it often freezes on the Mac with Direct3D 11).")
            }
        }
    }

    func toggleNativeMenuAll() {
        let on = !nativeMenuAll
        Task {
            _ = await Script.run(["menubar", "--all", on ? "on" : "off"])
            loadNativeMenuStates()
            message = on
                ? L("Windows programs’ menus will appear in the Mac menu bar. Reopen the programs to apply.\n\nTo turn this off for just one program, Control-click it in the Library.")
                : L("Menus will stay inside the programs’ windows only. Reopen the programs to apply.")
        }
    }

    /// Instala componentes do Windows (sem nomes: os essenciais).
    func installComponents(_ names: [String], label: String) {
        Task {
            busy = String(format: L("Installing %@…\nThis may take several minutes."), label)
            let r = await Script.run(["components"] + names)
            busy = nil
            let lines = stripANSI(r.out).split(separator: "\n").map(String.init)
            if r.code == 0 {
                message = String(format: L("%@ installed."), label.capitalizedFirst)
            } else if let err = scriptError(r.out) {
                message = err
            } else {
                message = L("Some components weren’t installed.") + "\n" + lines.suffix(3).joined(separator: "\n")
            }
        }
    }

    func killAll() {
        Task { _ = await Script.run(["kill"]); message = L("All Windows programs were quit.") }
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
        p.title = L("Open Windows Program")
        p.message = L("Choose an installer (.msi, setup.exe), a program (.exe), a .zip file or the program’s folder")
        p.prompt = L("Open")
        p.canChooseDirectories = true
        p.allowedContentTypes = [UTType(filenameExtension: "exe")!, UTType(filenameExtension: "msi")!, .zip, .folder]
        p.directoryURL = Paths.home.appendingPathComponent("Downloads")
        return p.runModal() == .OK ? p.url : nil
    }

    static func existing() -> URL? {
        let p = NSOpenPanel()
        p.title = L("Add Program to Library")
        p.message = L("Choose the program’s .exe — one already installed on drive C: or a portable one")
        p.prompt = L("Add")
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
                Picker("Section", selection: $model.tab) {
                    Text("Library").tag(0)
                    Text("Compatibility").tag(1)
                    Text("Files").tag(2)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            if model.checkedWine && model.wineVersion == nil {
                ToolbarItem(placement: .primaryAction) { statusPill }
            }
            ToolbarItem(placement: .primaryAction) {
                ProminentButton(title: L("Open Program"), symbol: "plus") {
                    if let u = Pick.program() { model.handle(u) }
                }
                .help("Open a Windows program’s .exe, .msi, .zip or folder (⌘O)")
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
                Text(String(format: L("Windows environment ready · engine %@"), v))
                Divider()
            }
            Button("WinApps Guide") { Guide.show() }
            Divider()
            Button("Quit All Windows Programs") { model.killAll() }
            Divider()
            // o padrão já é o que funcionou nos testes; aqui só para casos específicos
            Menu("Advanced") {
                Toggle("Program Menus in the Mac Menu Bar", isOn: Binding(
                    get: { model.nativeMenuAll }, set: { _ in model.toggleNativeMenuAll() }))
                Toggle("Mac Title Bar for Programs with Custom Title Bars", isOn: Binding(
                    get: { model.titleBarAll }, set: { _ in model.toggleTitleBarAll() }))
                Toggle("Metal Graphics for Games (Direct3D 10/11)", isOn: Binding(
                    get: { model.dxmtOn }, set: { _ in model.toggleDXMT() }))
                Toggle("Advanced Game Controllers", isOn: Binding(
                    get: { model.gamepadOn }, set: { _ in model.toggleGamepad() }))
                Divider()
                Button("Add Installed Program…") { if let u = Pick.existing() { model.addExisting(u) } }
                Button("Always Open .exe and .msi Files with WinApps") { model.makeDefaultHandler() }
                Button("Repair Windows Environment (Reinstall Components)") {
                    model.installComponents([], label: L("Windows components"))
                }
                Button("Windows Settings…") { Script.launch(["config"]) }
                Button("Open Logs Folder") { NSWorkspace.shared.open(Paths.logs) }
            }
            Divider()
            Button("About WinApps") { About.show() }
        } label: { Image(systemName: "ellipsis.circle") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("More Options")
    }

    @ViewBuilder var statusPill: some View {
        if !model.checkedWine {
            ProgressView().controlSize(.small)
        } else if let v = model.wineVersion {
            Circle().fill(Color.green).frame(width: 8, height: 8)
                .help(String(format: L("Windows environment ready (engine %@)"), v))
        } else {
            Button {
                Task { _ = await model.setup() }
            } label: { Label("Set Up Windows", systemImage: "arrow.down.circle.fill") }
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
                        Text("Library").font(.title3.weight(.semibold))
                        Text(verbatim: "\(model.library.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        if model.library.count > 6 { SearchField(text: $search.v, prompt: L("Search Library")).frame(width: 220) }
                        Button { NSWorkspace.shared.open(Paths.apps) } label: {
                            Label("Show in Applications", systemImage: "arrow.up.forward.app")
                        }.buttonStyle(.link).font(.callout)
                    }
                    if model.library.isEmpty {
                        Text("No programs yet. Drag one onto the area above to get started.")
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
                Text("Drag a Windows program here").font(.callout.weight(.semibold))
                Text("Installers (.msi, setup.exe) get installed. Standalone programs — an .exe, a folder or a .zip — get imported.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Choose…") { if let u = Pick.program() { model.handle(u) } }
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
            .overlay(Label("Drop to Open in WinApps", systemImage: "arrow.down.doc.fill")
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
        case 0: return L("The engine that runs Windows programs (one shared by all of them).")
        case 1: return L("The Windows environment shared by all programs: fonts, Visual C++, DirectX, .NET 4.8 and WebView2.")
        case 2: return L("The program’s folder inside the Windows environment.")
        default: return L("Temporary Windows files and cached downloads. They can be deleted (Free Up button).")
        }
    }
    static func fmt(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

    var body: some View {
        let items = model.storage
        let total = items.reduce(Int64(0)) { $0 + $1.bytes }
        let progIndex: [UUID: Int] = Dictionary(uniqueKeysWithValues: items.filter { $0.kind == 2 }.enumerated().map { ($1.id, $0) })
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Storage").font(.title3.weight(.semibold))
                if total > 0 {
                    Text(String(format: L("WinApps uses %@"), Self.fmt(total))).font(.callout.weight(.medium))
                    Text(String(format: L("· %@ available on disk"), Self.fmt(model.storageFree))).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if model.storageLoading { ProgressView().controlSize(.small) }
                if let junk = items.first(where: { $0.kind == 3 }) {
                    Button(String(format: L("Free Up %@"), Self.fmt(junk.bytes))) { model.cleanUp() }
                        .help("Quits open Windows programs and deletes temporary files and cached downloads")
                }
                Button { model.loadStorage() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Recalculate")
            }
            if total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(items) { it in
                            Rectangle().fill(color(it, progIndex[it.id] ?? 0))
                                .frame(width: max(2, geo.size.width * CGFloat(it.bytes) / CGFloat(total) - 2))
                                .help(Text(verbatim: "\(it.name): \(Self.fmt(it.bytes))"))
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
                Text("Calculating…").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
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
        .help(String(format: L("Open %@ — Control-click for more options"), app.name))
        .contextMenu {
            Button("Open") { model.open(app) }
            Button("Show Program Files") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.exe)])
            }
            Button("Show Shortcut in Applications") {
                NSWorkspace.shared.activateFileViewerSelecting([app.id])
            }
            Divider()
            Toggle("Menus in the Mac Menu Bar", isOn: Binding(
                get: { model.hasNativeMenu(app) },
                set: { _ in model.toggleNativeMenu(app) }))
            Toggle("Mac Title Bar", isOn: Binding(
                get: { model.titleBar[app.id] ?? true },
                set: { _ in model.toggleTitleBar(app) }))
            Divider()
            Button("Remove from Library", role: .destructive) { model.remove(app) }
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
                    Label(file.isInstaller ? L("Installer") : L("Portable program (runs without installing)"),
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
                 ? L("The program will be installed in WinApps: follow the installer’s steps as usual. When it’s done, it appears in your library and in Applications.")
                 : L("It will be imported into WinApps and get an icon in your library and in Applications."))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !file.needs.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: L("This program needs: %@"), file.needs.map(componentLabel).joined(separator: ", ")))
                            .font(.callout.weight(.medium))
                        Toggle("Install before continuing (may take several minutes)", isOn: $installNeeds.on)
                            .font(.caption)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.10)))
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if file.isInstaller {
                    let b = Button(file.compat?.broken == true ? L("Install Anyway") : L("Install")) {
                        let u = file.url; model.withComponents(needs) { model.install(u) }; dismiss()
                    }
                    if file.compat?.broken == true { b } else { b.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
                } else {
                    let b = Button(file.compat?.broken == true ? L("Import Anyway") : L("Import and Open")) {
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

    /// Ordem dos grupos na tabela (categoria do topo do JSON; aceita os nomes antigos em português).
    static let order: [String: Int] = [
        "productivity": 0, "produtividade": 0,
        "engineering & cad": 1, "design & media": 2, "business & finance": 3,
        "development & it": 4, "science & education": 5,
        "games": 6, "jogos": 6,
        "utilities": 7, "utilitários": 7,
        "not supported": 8, "unsupported": 8, "não suportados": 8,
        "by technology": 9, "por tecnologia": 9,
    ]
    static let repoTable = URL(string: "https://github.com/matthfaria96/winapps/blob/master/"
                                   + (UILang.isPT ? "COMPATIBILIDADE.md" : "COMPATIBILITY.md"))!

    static let all: [Compat] = {
        let list = CompatDB.rules.map(Compat.init(rule:))
        return list.enumerated().sorted { a, b in
            let ia = order[a.element.categoryKey.lowercased()] ?? 99, ib = order[b.element.categoryKey.lowercased()] ?? 99
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
                SearchField(text: $query.v, prompt: L("Search programs or fixes")).frame(width: 250)
                Picker("Filter", selection: $filter.v) {
                    Text("All").tag(0)
                    Text("Verified (filter)").tag(1)
                    Text("Working").tag(2)
                    Text("Not Working").tag(3)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                Text(String(format: L("%ld of %ld"), rows.count, Self.all.count)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Link(destination: Self.repoTable) { Image(systemName: "arrow.up.right.square") }
                    .help("Open the full table on GitHub")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            headerRow
            Divider()
            if rows.isEmpty {
                VStack(spacing: 6) {
                    Text("No Results").font(.headline)
                    Text("Programs not on this list show up as Untested: they may work, nobody has checked yet.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: 420, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.key) { i, c in
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
                Text("Click a row for details").foregroundStyle(.tertiary)
            }
            .font(.caption).padding(.horizontal, 16).padding(.vertical, 7)
        }
    }

    var headerRow: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 12, height: 1)
            Text("Program").frame(width: wName, alignment: .leading)
            Text("Status").frame(width: wBadge, alignment: .leading)
            Text("Summary").frame(maxWidth: .infinity, alignment: .leading)
            Text("Tested").frame(width: wDate, alignment: .leading)
            Text("Fixes").frame(width: wFix, alignment: .trailing)
        }
        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 6)
    }

    func row(_ c: Compat, odd: Bool) -> some View {
        let open = expanded.v.contains(c.key) || expanded.v.contains(c.name)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 12)
                HStack(spacing: 6) {
                    if let app = model.installed(c) {
                        Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
                            .help("In your library")
                    }
                    Text(c.name).font(.callout.weight(.medium)).lineLimit(1).help(Text(verbatim: c.name))
                }
                .frame(width: wName, alignment: .leading)
                BadgeView(badge: c.badge, compact: true).frame(width: wBadge, alignment: .leading)
                Text(c.summary).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(c.tested.isEmpty ? "—" : CompatDB.displayDate(c.tested)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: wDate, alignment: .leading)
                Text(c.fixes.isEmpty ? "—" : "\(c.fixes.count)").font(.caption.monospacedDigit())
                    .foregroundStyle(c.fixes.isEmpty ? Color.secondary : Color.green)
                    .frame(width: wFix, alignment: .trailing)
            }
            .padding(.horizontal, 16).frame(height: 32)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) {
                    if open { expanded.v.remove(c.key); expanded.v.remove(c.name) } else { expanded.v.insert(c.key) }
                }
            }
            if open { details(c) }
        }
        .background(odd ? Color.primary.opacity(0.035) : Color.clear)
    }

    func details(_ c: Compat) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 6) {
            detail(L("Details"), c.why)
            if !c.alt.isEmpty { detail(L("Tip"), c.alt) }
            if !c.needs.isEmpty {
                detail(L("Needs"), String(format: L("%@ — already included in WinApps"), c.needs.map(componentLabel).joined(separator: ", ")))
            }
            if !c.fixes.isEmpty {
                GridRow {
                    Text("Fixes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(c.fixes, id: \.self) { f in
                            Label(f, systemImage: "wrench.and.screwdriver").font(.caption)
                        }
                    }
                }
            }
            if !c.category.isEmpty { detail(L("Category"), c.category) }
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
            Label("Installation Complete", systemImage: "checkmark.seal.fill")
                .font(.title3.weight(.semibold)).foregroundStyle(.green)
            Text("Select what should appear in your library (and in Applications). You can change the names.")
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach($model.candidates) { $c in
                    HStack(spacing: 10) {
                        Toggle("", isOn: $c.selected).labelsHidden()
                        Image(nsImage: NSWorkspace.shared.icon(forFile: c.path)).resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Name", text: $c.name).textFieldStyle(.roundedBorder)
                            Text(c.path.replacingOccurrences(of: Paths.driveC.path + "/", with: "C:/"))
                                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
            HStack {
                Button("Not Now") { model.showCandidates = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add to Library") { model.addCandidates() }
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
        // ganchos para capturas de tela: -WinAppsAppearance light|dark, -WinAppsShowAbout YES, -WinAppsShowGuide YES
        switch UserDefaults.standard.string(forKey: "WinAppsAppearance")?.lowercased() {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for w in NSApp.windows where w.isVisible {
                let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(w.frame) }
                if !onScreen { w.center() }
            }
            let d = UserDefaults.standard
            if d.bool(forKey: "WinAppsShowAbout") || d.bool(forKey: "WinAppsShowLicenses") { About.show() }
            if d.bool(forKey: "WinAppsShowGuide") { Guide.show() }
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
            CommandGroup(replacing: .appInfo) {
                Button("About WinApps") { About.show() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Windows Program…") { if let u = Pick.program() { Model.shared.handle(u) } }
                    .keyboardShortcut("o")
                Button("Add Installed Program…") { if let u = Pick.existing() { Model.shared.addExisting(u) } }
            }
            CommandGroup(replacing: .help) {
                Button("WinApps Guide") { Guide.show() }.keyboardShortcut("?")
            }
        }
    }
}

// MARK: - Guia (GUIDE.md / GUIA.md: os mesmos arquivos do repositório, embutidos no app)

enum Guide {
    static var windows: [String: NSWindow] = [:]

    static func show() { show(resource: UILang.isPT ? "GUIA" : "GUIDE", fallback: UILang.isPT ? "GUIDE" : "GUIA", title: L("WinApps Guide")) }
    static func showLicenses() {
        show(resource: UILang.isPT ? "LICENCAS" : "LICENSES", fallback: UILang.isPT ? "LICENSES" : "LICENCAS", title: L("Credits and Licenses"))
    }

    static func show(resource: String, fallback: String, title: String) {
        if let w = windows[resource] { w.makeKeyAndOrderFront(nil); return }
        let url = Bundle.main.url(forResource: resource, withExtension: "md") ?? Bundle.main.url(forResource: fallback, withExtension: "md")
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            ?? "# \(title)\n\n" + L("File not found in the app.")
        let w = NSWindow(contentViewController: NSHostingController(rootView: GuideView(blocks: GuideBlock.parse(text))))
        w.title = title
        w.setContentSize(NSSize(width: 720, height: 760))
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        windows[resource] = w
    }
}

// MARK: - Sobre (padrão dos apps do autor: ícone, nome, versão, descrição, licença, links)

enum About {
    static var window: NSWindow?

    static func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let host = NSHostingController(rootView: AboutView())
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.contentViewController = host
        w.setContentSize(NSSize(width: 560, height: 440))
        w.title = L("About WinApps")
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }

    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "200"
        return String(format: L("Version %@ (%@)"), short, build)
    }
}

struct AboutView: View {
    // "-WinAppsShowLicenses YES" ao abrir (capturas de tela): já mostra a folha de licenças
    @StateObject private var showsLicenses: Flag = {
        let f = Flag(); f.on = UserDefaults.standard.bool(forKey: "WinAppsShowLicenses"); return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .padding(.bottom, 18)
            Text(verbatim: "WinApps")
                .font(.system(size: 24, weight: .semibold))
            Text(About.version)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)
            Text("WinApps runs Windows programs on your Mac as real Mac apps — their own icon in the Dock, menus in the macOS menu bar, Mac window controls — with a compatibility engine kept up to date and fixes you won’t find anywhere else.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 26)
            Text("WinApps is free software under the GNU GPL v3.0. It builds on the open-source projects listed in its licenses.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            HStack(spacing: 18) {
                Link(destination: URL(string: "http://witchmymac.com")!) { Text(verbatim: "witchmymac.com") }
                Button("Open-source licenses") { showsLicenses.on = true }
                    .buttonStyle(.link)
            }
            .font(.system(size: 12))
            .padding(.top, 10)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 12)
        .frame(width: 560, height: 440)
        .sheet(isPresented: $showsLicenses.on) { LicensesSheet() }
    }
}

/// Projetos de código aberto do WinApps, cada um com a licença e o aviso.
struct LicensesSheet: View {
    @Environment(\.dismiss) private var dismiss

    struct Entry: Identifiable {
        let name: String, license: String, notice: String
        var id: String { name }
    }

    static let gplNotice = "This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details."
    static let lgplNotice = "This library is free software; you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation; either version 2.1 of the License, or (at your option) any later version."
    // texto da licença MIT: fica em inglês (a licença exige este aviso)
    static let mitText = """
        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """

    var entries: [Entry] {
        [
            Entry(name: "WinApps", license: "GPL-3.0",
                  notice: "Copyright (C) 2026 Matheus Faria\n" + L("Source code:") + " https://github.com/matthfaria96/winapps\n\n" + L(Self.gplNotice)),
            Entry(name: "Wine", license: "LGPL-2.1+",
                  notice: "Copyright © 1993-2026 the Wine project authors\nhttps://www.winehq.org\n\n"
                    + L("WinApps’ engine is based on Wine. WinApps’ engine patches are also licensed under LGPL-2.1 or later; their source code is in patches/ and programas/*/patches/ and they are built by engine/build-engine.sh.")
                    + "\n\n" + L(Self.lgplNotice)),
            Entry(name: "Wine Staging", license: "LGPL-2.1+",
                  notice: "Copyright © the Wine Staging contributors\nhttps://gitlab.winehq.org/wine/wine-staging\n\n"
                    + L("Patch set on top of Wine, used by WinApps’ engine.") + "\n\n" + L(Self.lgplNotice)),
            Entry(name: "Gcenx macOS Wine builds", license: "LGPL-2.1+",
                  notice: "Copyright © Gcenx and the Wine project authors\nhttps://github.com/Gcenx/macOS_Wine_builds\n\n"
                    + L("macOS packaging of Wine and Wine Staging that WinApps’ engine is built from.")),
            Entry(name: "DXMT", license: "MIT",
                  notice: "Copyright (c) 2023 Feifan He\nhttps://github.com/3Shain/dxmt\n\n"
                    + L("Direct3D 10/11 to Metal translation. WinApps’ modifications are in patches/dxmt/ and are built by engine/build-dxmt.sh.")
                    + "\n\n" + Self.mitText),
            Entry(name: "winetricks", license: "LGPL-2.1+",
                  notice: "Copyright © the winetricks authors\nhttps://github.com/Winetricks/winetricks\n\n"
                    + L("Downloads and installs Windows components (fonts, Visual C++, .NET and others).") + "\n\n" + L(Self.lgplNotice)),
            Entry(name: "cabextract", license: "GPL-2.0+",
                  notice: "Copyright © Stuart Caie\nhttps://www.cabextract.org.uk\n\n"
                    + L("Extracts Microsoft cabinet (.cab) files. This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.")),
            Entry(name: "Microsoft components", license: L("Microsoft licenses"),
                  notice: L("The .NET Framework, Visual C++, WebView2 and the Windows SDK metadata are downloaded from Microsoft’s websites on your Mac, under Microsoft’s licenses. WinApps does not redistribute them.")),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Open-Source Licenses").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("WinApps is built on these open-source projects. Their licenses ask that the notices below accompany the app and that the source code of modified versions be available.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(entries) { e in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(e.name == "Microsoft components" ? L("Microsoft components") : e.name)
                                    .font(.callout.weight(.semibold))
                                Spacer()
                                Text(e.license).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            }
                            Text(e.notice)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.secondary.opacity(0.10)))
                        }
                    }
                    Button("Show Full Credits Document") { Guide.showLicenses() }
                        .buttonStyle(.link).font(.callout)
                }
                .padding(16)
            }
        }
        .frame(width: 520, height: 400)
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


extension CompatDB {
    /// Datas do compat.json vêm como "07/11/2026" (dia/mês/ano): mostra no formato do idioma do app
    /// ("Nov 7, 2026" em inglês, "07/11/2026" em português).
    static func displayDate(_ s: String) -> String {
        let p = DateFormatter(); p.locale = Locale(identifier: "en_US_POSIX"); p.dateFormat = "dd/MM/yyyy"
        guard let d = p.date(from: s) else { return s }
        let f = DateFormatter()
        f.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        f.dateStyle = UILang.isPT ? .short : .medium; f.timeStyle = .none
        if UILang.isPT { f.dateFormat = "dd/MM/yyyy" }
        return f.string(from: d)
    }
}
