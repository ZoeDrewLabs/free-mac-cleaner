import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var selection: Page? = .home {
        didSet {
            guard oldValue != selection, !navigatingHistory, let old = oldValue else { return }
            backStack.append(old)
            forwardStack.removeAll()
        }
    }
    @Published var backStack: [Page] = []
    @Published var forwardStack: [Page] = []
    @Published var volumes: [VolumeInfo] = Volumes.list()
    private var navigatingHistory = false
    @Published var confirmingGlobal = false
    @Published var confirmingVolume = false
    @Published var confirming: Section? = nil
    @Published var results: [Section: [ScanItem]] = [:]
    @Published var scanning: Set<Section> = []
    @Published var permissionDenied: Set<Section> = []
    @Published var progressCount = 0

    // Ajustes das varreduras
    @Published var largeFileMinMB = 500
    @Published var downloadsMinDays = 90
    @Published var oldFilesMinDays = 180
    @Published var oldFilesMinMB = 10

    // Vídeos
    @Published var videoMinMB = 200
    @Published var videoFolder: String? = UserDefaults.standard.string(forKey: "videoFolder") {
        didSet { UserDefaults.standard.set(videoFolder, forKey: "videoFolder") }
    }
    @Published var compressing = false
    /// Codificador em velocidade máxima (~35% mais rápido, diferença de qualidade quase invisível).
    @Published var videoFastMode = UserDefaults.standard.object(forKey: "videoFastMode") as? Bool ?? true {
        didSet { UserDefaults.standard.set(videoFastMode, forKey: "videoFastMode") }
    }
    /// Pasta escolhida na lista de pastas de vídeos (nil = todas).
    @Published var videoFolderFilter: String? = nil
    @Published var compressIndex = 0
    @Published var compressTotal = 0
    @Published var compressName = ""
    @Published var compressProgress = 0.0
    @Published var confirmingCompress = false
    /// true = "Comprimir e substituir"; false = "Comprimir e manter original".
    @Published var compressReplace = true
    private var compressCancel = CancelFlag()
    private var testAutoCompress = false
    @Published var showingDonate = false
    @Published var pixCopied = false
    /// Situação de cada vídeo no lote atual (ou no último lote), pelo caminho do arquivo.
    @Published var videoJobs: [URL: VideoJob] = [:]
    /// Quanto o lote já economizou até agora.
    @Published var compressSaved: Int64 = 0
    @Published var compressDone = 0

    enum VideoJob: Equatable {
        case queued
        case running(Double)
        case done(old: Int64, new: Int64)
        case failed(String)
        case cancelled
    }

    // Filtros do iCloud
    @Published var icloudMinMB: Double = 10
    @Published var icloudMinDays = 0
    @Published var icloudKind: FileKind = .all
    @Published var icloudSearch = ""
    @Published var icloudSkippedProjects: [URL] = []
    @Published var icloudAlreadyInCloud = 0

    // Pastas protegidas (nunca entram na lista do iCloud)
    @Published var protectedFolders: [String] {
        didSet { UserDefaults.standard.set(protectedFolders, forKey: "protectedFolders") }
    }
    @Published var protectProjects: Bool {
        didSet { UserDefaults.standard.set(protectProjects, forKey: "protectProjects") }
    }

    @Published var disk: (free: Int64, total: Int64) = Actions.diskFree()
    @Published var lastMessage: String?
    @Published var busy = false

    init() {
        let d = UserDefaults.standard
        if let saved = d.stringArray(forKey: "protectedFolders") {
            protectedFolders = saved
        } else {
            protectedFolders = []
        }
        protectProjects = d.object(forKey: "protectProjects") as? Bool ?? true

        // Abertura direta numa tela (usada para testes: --args -startPage videos -startVideoFolder <pasta>).
        switch d.string(forKey: "startPage") {
        case "videos":
            selection = .section(.videos)
            if let f = d.string(forKey: "startVideoFolder") {
                videoFolder = f
                if d.integer(forKey: "startVideoMinMB") > 0 { videoMinMB = d.integer(forKey: "startVideoMinMB") }
                // Teste do lote: comprime tudo que for encontrado, apagando cada original ao terminar.
                testAutoCompress = d.string(forKey: "testAutoCompress") == "delete"
                DispatchQueue.main.async { self.scan(.videos) }
            }
        case "donate": DispatchQueue.main.async { self.showingDonate = true }
        case "overview": selection = .section(.overview)
        case "caches": selection = .section(.caches)
        default: break
        }
    }

    // MARK: - Navegação

    func goBack() {
        guard let prev = backStack.popLast() else { return }
        if let cur = selection { forwardStack.append(cur) }
        navigatingHistory = true
        selection = prev
        navigatingHistory = false
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let cur = selection { backStack.append(cur) }
        navigatingHistory = true
        selection = next
        navigatingHistory = false
    }

    // MARK: - Visão geral ("Tudo")

    struct Row: Identifiable {
        let section: Section
        let item: ScanItem
        var id: UUID { item.id }
    }

    func overviewRows() -> [Row] {
        Section.global.flatMap { s in visibleItems(s).map { Row(section: s, item: $0) } }
            .sorted { $0.item.size > $1.item.size }
    }

    /// Selecionados em todas as seções, sem repetir o mesmo caminho.
    func globalSelected() -> [Row] {
        var seen = Set<String>()
        var rows: [Row] = []
        for s in Section.global {
            for item in selectedVisible(s) where seen.insert(item.url.standardizedFileURL.path).inserted {
                rows.append(Row(section: s, item: item))
            }
        }
        // Se uma pasta e algo dentro dela estão marcados, basta a pasta.
        let paths = rows.map { $0.item.url.standardizedFileURL.path }
        return rows.filter { r in
            let p = r.item.url.standardizedFileURL.path
            return !paths.contains { $0 != p && p.hasPrefix($0 + "/") }
        }
    }

    /// Itens que podem ser marcados na tela atual (os bloqueados ficam de fora).
    func pageSelectable() -> [(Section, ScanItem)] {
        let pairs: [(Section, ScanItem)]
        switch selection {
        case .home, .section(.overview), nil:
            pairs = Section.global.flatMap { s in visibleItems(s).map { (s, $0) } }
        case .section(let s):
            pairs = visibleItems(s).map { (s, $0) }
        case .volume(let path):
            guard let v = volumes.first(where: { $0.id == path }) else { return [] }
            let s: Section = v.isRoot ? .temp : .disks
            pairs = items(on: v).map { (s, $0) }
        }
        return pairs.filter { $0.1.blockedReason == nil }
    }

    func pageAllSelected() -> Bool {
        let p = pageSelectable()
        return !p.isEmpty && p.allSatisfy { $0.1.selected }
    }

    func selectPage(_ value: Bool) {
        let bySection = Dictionary(grouping: pageSelectable(), by: { $0.0 })
        for (s, pairs) in bySection {
            let ids = Set(pairs.map { $0.1.id })
            results[s] = results[s]?.map { item in
                var it = item
                if ids.contains(it.id) { it.selected = value }
                return it
            }
        }
    }

    func selectAllGlobal(_ value: Bool) {
        for s in Section.global { selectAllVisible(s, value) }
    }

    func refreshVolumes() {
        volumes = Volumes.list()
        disk = Actions.diskFree()
    }

    /// Itens encontrados em um disco específico.
    func items(on volume: VolumeInfo) -> [ScanItem] {
        if volume.isRoot { return results[.temp] ?? [] }
        let prefix = volume.url.path.hasSuffix("/") ? volume.url.path : volume.url.path + "/"
        return (results[.disks] ?? []).filter { $0.url.path.hasPrefix(prefix) }
    }

    func scanEverything() {
        refreshVolumes()
        for s in Section.cleanup { scan(s) }
        scan(.icloud)
    }

    func performGlobal() {
        let rows = globalSelected()
        guard !rows.isEmpty else { return }
        let local = rows.filter { $0.section != .icloud }.map(\.item)
        let cloud = rows.filter { $0.section == .icloud }.map(\.item)
        busy = true
        Task.detached(priority: .userInitiated) {
            let a = Actions.moveToTrash(local)
            let b = Actions.evict(cloud)
            await MainActor.run {
                var msg = "Movidos para a Lixeira: \(a.done) itens · \(Fmt.size(a.freed))"
                msg += "\nDownloads do iCloud removidos: \(b.done) arquivos · \(Fmt.size(b.freed))"
                msg += "\nTotal liberado: \(Fmt.size(a.freed + b.freed))"
                let failures = a.failures + b.failures
                if !failures.isEmpty {
                    msg += "\n\n\(failures.count) não puderam ser processados:"
                    for (name, why) in failures.prefix(8) { msg += "\n• \(name): \(why)" }
                    if failures.count > 8 { msg += "\n…" }
                }
                self.lastMessage = msg
                self.busy = false
                self.refreshVolumes()
                let touched = Set(rows.map(\.section))
                for s in touched { self.scan(s) }
                if !local.isEmpty { self.scan(.trash) }
            }
        }
    }

    // MARK: - Itens visíveis

    func visibleItems(_ section: Section) -> [ScanItem] {
        let items = results[section] ?? []
        if section == .videos, let f = videoFolderFilter {
            return items.filter { $0.url.deletingLastPathComponent().path == f }
        }
        guard section == .icloud else { return items }
        let minBytes = Int64(icloudMinMB * 1_000_000)
        let limit = Date().addingTimeInterval(-Double(icloudMinDays) * 86_400)
        let q = icloudSearch.lowercased()
        return items.filter { item in
            item.size >= minBytes
                && (icloudMinDays == 0 || (item.lastAccess ?? .distantPast) < limit)
                && icloudKind.matches(item.url)
                && (q.isEmpty || item.url.path.lowercased().contains(q))
        }
    }

    func selectedVisible(_ section: Section) -> [ScanItem] {
        visibleItems(section).filter { $0.selected && $0.blockedReason == nil }
    }

    func total(_ section: Section) -> Int64 {
        (results[section] ?? []).reduce(0) { $0 + $1.size }
    }

    func setSelected(_ id: UUID, in section: Section, _ value: Bool) {
        guard var list = results[section], let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].selected = value
        results[section] = list
    }

    func selectAllVisible(_ section: Section, _ value: Bool) {
        let ids = Set(visibleItems(section).filter { $0.blockedReason == nil }.map(\.id))
        results[section] = results[section]?.map { item in
            var it = item
            if ids.contains(it.id) { it.selected = value }
            return it
        }
    }

    // MARK: - Varreduras

    func scan(_ section: Section) {
        guard !scanning.contains(section) else { return }
        if section == .videos {
            if compressing { return }
            videoJobs = [:]
        }
        scanning.insert(section)
        progressCount = 0
        let largeMB = largeFileMinMB, days = downloadsMinDays, oldDays = oldFilesMinDays, oldMB = oldFilesMinMB
        let prot = protectedFolders, projects = protectProjects

        Task.detached(priority: .userInitiated) {
            if section == .videos {
                var roots: [URL]
                if let folder = await MainActor.run(body: { self.videoFolder }) {
                    roots = [URL(fileURLWithPath: folder)]
                } else {
                    roots = [Scanner.home] + Volumes.list().filter { !$0.isRoot }.map(\.url)
                }
                let minBytes = Int64(await MainActor.run { self.videoMinMB }) * 1_000_000
                let items = await VideoTools.scan(roots: roots, minBytes: minBytes) { n in
                    Task { @MainActor in self.progressCount = n }
                }
                await MainActor.run {
                    self.results[.videos] = items
                    if let f = self.videoFolderFilter, !items.contains(where: { $0.url.deletingLastPathComponent().path == f }) {
                        self.videoFolderFilter = nil
                    }
                    self.scanning.remove(.videos)
                    if self.testAutoCompress {
                        self.testAutoCompress = false
                        self.compressSelected(policy: .replaceAndDelete)
                    }
                }
                return
            }
            if section == .icloud {
                let out = ICloudScanner.scan(protected: prot, protectProjects: projects) { n in
                    Task { @MainActor in self.progressCount = n }
                }
                await MainActor.run {
                    self.results[.icloud] = out.items
                    self.icloudSkippedProjects = out.skippedProjects
                    self.icloudAlreadyInCloud = out.alreadyInCloud
                    self.scanning.remove(.icloud)
                }
            } else {
                let r = Scanner.scan(section, largeFileMinMB: largeMB, downloadsMinDays: days,
                                     oldFilesMinDays: oldDays, oldFilesMinMB: oldMB)
                await MainActor.run {
                    self.results[section] = r.items
                    if r.permissionDenied { self.permissionDenied.insert(section) } else { self.permissionDenied.remove(section) }
                    self.scanning.remove(section)
                }
            }
        }
    }

    func scanAllCleanup() {
        for s in Section.cleanup { scan(s) }
    }

    // MARK: - Ações

    // MARK: - Vídeos

    func compressSelected(policy: ReplacePolicy) {
        let items = selectedVisible(.videos)
        guard !items.isEmpty, !compressing else { return }
        compressing = true
        compressTotal = items.count
        compressIndex = 0
        compressSaved = 0
        compressDone = 0
        videoJobs = Dictionary(uniqueKeysWithValues: items.map { ($0.url, VideoJob.queued) })
        compressCancel = CancelFlag()
        let cancel = compressCancel
        VideoTools.prioritizeSpeed = videoFastMode
        Task {
            var failures: [(String, String)] = []
            for (i, item) in items.enumerated() {
                if cancel.isCancelled { break }
                compressIndex = i + 1
                compressName = item.name
                compressProgress = 0
                videoJobs[item.url] = .running(0)
                do {
                    // Um vídeo por vez: termina, confere, troca/apaga o original e só então passa ao próximo.
                    let newSize = try await VideoTools.compress(item, policy: policy, cancel: cancel) { p in
                        Task { @MainActor in
                            guard p - self.compressProgress >= 0.005 || p >= 1 else { return }
                            self.compressProgress = p
                            self.videoJobs[item.url] = .running(p)
                        }
                    }
                    compressSaved += item.size - newSize
                    compressDone += 1
                    videoJobs[item.url] = .done(old: item.size, new: newSize)
                    markCompressed(item.id)
                    refreshVolumes()
                } catch VideoError.cancelled {
                    videoJobs[item.url] = .cancelled
                } catch {
                    videoJobs[item.url] = .failed(error.localizedDescription)
                    failures.append((item.name, error.localizedDescription))
                }
            }
            for (url, job) in videoJobs where job == .queued { videoJobs[url] = .cancelled }
            let saved = compressSaved
            var msg = "Vídeos comprimidos: \(compressDone) de \(items.count)."
            switch policy {
            case .keepOriginal:
                msg += "\n\nAs versões comprimidas foram salvas ao lado dos originais, com \"(comprimido)\" no nome. Os originais não foram mexidos."
                msg += " Quando estiver satisfeito(a) com as versões novas, use \"Comprimir e substituir\" ou apague os originais para ganhar \(Fmt.size(saved))."
            case .replaceToTrash:
                msg += " \(Fmt.size(saved)) economizados."
                msg += "\n\nOs originais estão na Lixeira (no caso de SSD/HD externo, na lixeira do próprio disco). Esvazie a Lixeira no Finder para liberar o espaço."
            case .replaceAndDelete:
                msg += " \(Fmt.size(saved)) liberados. Os originais foram apagados um a um, assim que cada vídeo ficou pronto."
            }
            if !failures.isEmpty {
                msg += "\n\n\(failures.count) não foram comprimidos:"
                for (n, why) in failures.prefix(8) { msg += "\n• \(n): \(why)" }
            }
            compressing = false
            lastMessage = msg
            refreshVolumes()
            scan(.trash)
        }
    }

    /// Tamanho atual do vídeo: o novo, se já foi comprimido neste lote.
    func currentSize(_ item: ScanItem) -> Int64 {
        if case .done(_, let new) = videoJobs[item.url] { return new }
        return item.size
    }

    /// Depois de comprimido, o vídeo sai da seleção e não pode ser comprimido de novo neste lote.
    private func markCompressed(_ id: UUID) {
        guard var list = results[.videos], let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].selected = false
        list[i].blockedReason = "Já comprimido"
        results[.videos] = list
    }

    func cancelCompression() { compressCancel.cancel() }

    /// Muda o nível de compressão de um vídeo "já compacto".
    func setVideoMode(_ id: UUID, _ mode: CompressMode) {
        guard var list = results[.videos], let i = list.firstIndex(where: { $0.id == id }) else { return }
        apply(mode, to: &list[i])
        results[.videos] = list
    }

    /// Aplica um nível a todos os vídeos "já compactos" da pasta atual (ou de todas).
    func setLimitedMode(_ mode: CompressMode) {
        let f = videoFolderFilter
        results[.videos] = results[.videos]?.map { item in
            var it = item
            if it.video?.limited == true, f == nil || it.url.deletingLastPathComponent().path == f {
                apply(mode, to: &it)
            }
            return it
        }
    }

    private func apply(_ mode: CompressMode, to item: inout ScanItem) {
        guard item.video?.limited == true else { return }
        if case .done = videoJobs[item.url] { return }
        // AV1 já é mais eficiente que HEVC: o nível Forte não chega à metade, então vira Leve.
        var mode = mode
        if mode == .strong, item.video?.codec == "AV1" { mode = .light }
        item.video?.mode = mode
        if mode == .skip {
            item.blockedReason = VideoTools.limitedReason
            item.selected = false
        } else {
            item.blockedReason = nil
            item.selected = true
        }
    }

    struct VideoGroup { let path: String; let items: [ScanItem] }

    /// Vídeos agrupados pela pasta onde estão, maiores primeiro.
    func videoGroups() -> [VideoGroup] {
        Dictionary(grouping: results[.videos] ?? [], by: { $0.url.deletingLastPathComponent().path })
            .map { VideoGroup(path: $0.key, items: $0.value.sorted { $0.size > $1.size }) }
            .sorted { $0.items.reduce(0) { $0 + $1.size } > $1.items.reduce(0) { $0 + $1.size } }
    }

    /// Marca/desmarca os vídeos de uma pasta (nil = todas), pulando os bloqueados.
    func setVideosSelected(in folder: String?, _ value: Bool) {
        results[.videos] = results[.videos]?.map { item in
            var it = item
            if it.blockedReason == nil, folder == nil || it.url.deletingLastPathComponent().path == folder {
                it.selected = value
            }
            return it
        }
    }

    func perform(_ section: Section, only: [ScanItem]? = nil) {
        let items = only ?? selectedVisible(section)
        guard !items.isEmpty else { return }
        busy = true
        Task.detached(priority: .userInitiated) {
            let rep: Actions.Report
            switch section {
            case .icloud: rep = Actions.evict(items)
            case .trash: rep = Actions.deletePermanently(items)
            default: rep = Actions.moveToTrash(items)
            }
            await MainActor.run {
                let verb = section == .icloud ? "Downloads removidos" : (section == .trash ? "Apagados" : "Movidos para a Lixeira")
                var msg = "\(verb): \(rep.done) itens · \(Fmt.size(rep.freed)) liberados."
                if !rep.failures.isEmpty {
                    msg += "\n\(rep.failures.count) não puderam ser processados:"
                    for (name, why) in rep.failures.prefix(8) { msg += "\n• \(name): \(why)" }
                    if rep.failures.count > 8 { msg += "\n…" }
                }
                self.lastMessage = msg
                self.busy = false
                self.refreshVolumes()
                self.scan(section)
                // O que vai para a Lixeira passa a aparecer lá.
                if section != .icloud && section != .trash { self.scan(.trash) }
            }
        }
    }
}
