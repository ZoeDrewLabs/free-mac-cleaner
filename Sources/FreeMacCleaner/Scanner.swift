import Foundation

/// Resultado de uma varredura de uma seção.
struct ScanResult {
    var items: [ScanItem] = []
    /// Verdadeiro quando o macOS negou acesso a alguma pasta (falta Acesso Total ao Disco).
    var permissionDenied = false
}

/// Varreduras de leitura. Nada aqui apaga ou altera arquivos.
enum Scanner {
    static let fm = FileManager.default
    static let home = URL(fileURLWithPath: NSHomeDirectory())
    static let mobileDocuments = home.appendingPathComponent("Library/Mobile Documents")

    /// Pastas de cache de ferramentas de desenvolvimento (mostradas em "Caches de ferramentas").
    static let devToolPaths: [String] = [
        ".npm/_cacache",
        ".gradle/caches",
        ".gradle/wrapper/dists",
        ".cache/pip",
        ".cargo/registry/cache",
        ".android/cache",
        "Library/Caches/Homebrew",
        "Library/Caches/CocoaPods",
        "Library/Caches/pip",
        "Library/Caches/Yarn",
        "Library/Caches/go-build",
        "Library/Caches/org.swift.swiftpm",
        "Library/Caches/pnpm",
    ]

    /// Caches que nunca devem ser tocados (usados pelo iCloud e pelo sistema).
    static let protectedCacheNames: Set<String> = [
        "com.apple.bird", "CloudKit", "com.apple.nsurlsessiond", "com.apple.akd",
        "com.apple.containermanagerd", "FamilyCircle", "com.apple.ap.adprivacyd",
        "io.github.zoedrewlabs.FreeMacCleaner",
    ]

    // MARK: - Tamanhos

    /// Espaço realmente ocupado no disco por um arquivo ou pasta.
    static func allocatedSize(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
        guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        if v.isDirectory != true {
            return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        for case let f as URL in e {
            if let r = try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) {
                total += Int64(r.totalFileAllocatedSize ?? r.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    static func lastAccess(_ url: URL) -> Date? {
        let v = try? url.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey])
        return v?.contentAccessDate ?? v?.contentModificationDate
    }

    static func isInICloud(_ url: URL) -> Bool {
        if url.path.hasPrefix(mobileDocuments.path) { return true }
        return (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true
    }

    /// Lista os filhos diretos de uma pasta como itens com tamanho.
    static func children(of dir: URL, preselect: Bool, minSize: Int64 = 1, skip: (URL) -> Bool = { _ in false }) -> ScanResult {
        var result = ScanResult()
        do {
            let list = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])
            for url in list where !skip(url) && url.lastPathComponent != ".DS_Store" {
                let size = allocatedSize(of: url)
                if size >= minSize {
                    result.items.append(ScanItem(url: url, size: size, lastAccess: lastAccess(url), selected: preselect))
                }
            }
        } catch let error as NSError {
            if error.code == NSFileReadNoPermissionError || error.domain == NSPOSIXErrorDomain {
                result.permissionDenied = true
            }
        }
        return result
    }

    // MARK: - Seções de limpeza

    static func scan(_ section: Section, largeFileMinMB: Int = 500, downloadsMinDays: Int = 90,
                     oldFilesMinDays: Int = 180, oldFilesMinMB: Int = 10) -> ScanResult {
        var r: ScanResult
        switch section {
        case .caches:
            let devNames = Set(devToolPaths.filter { $0.hasPrefix("Library/Caches/") }.map { ($0 as NSString).lastPathComponent })
            r = children(of: home.appendingPathComponent("Library/Caches"), preselect: true, minSize: 1_000_000) { url in
                let n = url.lastPathComponent
                return protectedCacheNames.contains(n) || devNames.contains(n)
            }

        case .logs:
            r = children(of: home.appendingPathComponent("Library/Logs"), preselect: true, minSize: 100_000)

        case .xcode:
            r = ScanResult()
            let dirs = [
                "Library/Developer/Xcode/DerivedData",
                "Library/Developer/Xcode/Archives",
                "Library/Developer/Xcode/iOS DeviceSupport",
                "Library/Developer/Xcode/watchOS DeviceSupport",
                "Library/Developer/Xcode/macOS DeviceSupport",
                "Library/Developer/CoreSimulator/Caches",
            ]
            for d in dirs {
                let dir = home.appendingPathComponent(d)
                guard fm.fileExists(atPath: dir.path) else { continue }
                // Archives podem ser necessários para enviar à App Store: não vêm marcados.
                let sub = children(of: dir, preselect: !d.hasSuffix("Archives"), minSize: 1_000_000)
                r.items += sub.items
                r.permissionDenied = r.permissionDenied || sub.permissionDenied
            }

        case .devTools:
            r = ScanResult()
            for p in devToolPaths {
                let url = home.appendingPathComponent(p)
                guard fm.fileExists(atPath: url.path) else { continue }
                let size = allocatedSize(of: url)
                if size > 1_000_000 {
                    r.items.append(ScanItem(url: url, size: size, lastAccess: lastAccess(url), selected: true))
                }
            }

        case .downloads:
            let limit = Date().addingTimeInterval(-Double(downloadsMinDays) * 86_400)
            r = children(of: home.appendingPathComponent("Downloads"), preselect: false) { url in
                isInICloud(url) || (lastAccess(url) ?? .distantPast) > limit
            }

        case .largeFiles:
            r = largeFiles(minBytes: Int64(largeFileMinMB) * 1_000_000)

        case .oldFiles:
            r = oldFiles(minBytes: Int64(oldFilesMinMB) * 1_000_000, minDays: oldFilesMinDays)

        case .trash:
            r = children(of: home.appendingPathComponent(".Trash"), preselect: false)

        case .temp:
            r = tempFiles()

        case .disks:
            r = ScanResult()
            for v in Volumes.list() where !v.isRoot {
                r.items += externalJunk(on: v.url)
            }

        case .icloud, .overview, .videos:
            r = ScanResult() // iCloud usa ICloudScanner; "Tudo" junta as outras seções
        }
        r.items.sort { $0.size > $1.size }
        return r
    }

    // MARK: - Temporários

    static let tempExtensions: Set<String> = ["tmp", "temp", "crdownload", "part", "partial", "download", "opdownload", "dmp"]

    static func looksTemporary(_ url: URL) -> Bool {
        let n = url.lastPathComponent
        if n.hasPrefix("~$") { return true }              // trava do Office
        if n == "Thumbs.db" || n == "desktop.ini" { return true } // lixo do Windows
        return tempExtensions.contains(url.pathExtension.lowercased())
    }

    static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    /// Temporários do SSD do Mac (só do seu usuário; o sistema fica intocado).
    static func tempFiles() -> ScanResult {
        var r = ScanResult()
        let limit = Date().addingTimeInterval(-3 * 86_400)
        let uid = getuid()

        // 1. Pasta temporária do usuário ($TMPDIR) e /tmp, /var/tmp.
        let tmpDirs = [URL(fileURLWithPath: NSTemporaryDirectory()), URL(fileURLWithPath: "/private/tmp"), URL(fileURLWithPath: "/private/var/tmp")]
        for dir in tmpDirs {
            guard let list = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]) else { continue }
            for url in list {
                let n = url.lastPathComponent
                // Coisas do sistema e de apps abertos ficam: com.apple.*, sockets, travas e itens recentes.
                if n.hasPrefix("com.apple.") || n.hasPrefix(".") || n.hasSuffix(".lock") || n.hasSuffix(".sock") { continue }
                // Bancos de dados podem estar abertos por um app em execução.
                if [".db", "-shm", "-wal", ".sqlite", ".sqlite3", "-journal"].contains(where: { n.hasSuffix($0) }) { continue }
                guard let v = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]),
                      v.isSymbolicLink != true, v.isRegularFile == true || v.isDirectory == true else { continue }
                guard let owner = (try? fm.attributesOfItem(atPath: url.path))?[.ownerAccountID] as? NSNumber,
                      owner.uint32Value == uid else { continue }
                guard modified(url) < limit else { continue }
                let size = allocatedSize(of: url)
                if size > 0 { r.items.append(ScanItem(url: url, size: size, lastAccess: lastAccess(url), selected: true)) }
            }
        }

        // 2. Downloads incompletos, .tmp e travas do Office na pasta pessoal (fora de Biblioteca e iCloud).
        let keys: [URLResourceKey] = [.isRegularFileKey, .isUbiquitousItemKey, .contentModificationDateKey]
        let skip = [home.appendingPathComponent("Library").path, home.appendingPathComponent(".Trash").path]
        if let e = fm.enumerator(at: home, includingPropertiesForKeys: keys,
                                 options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) {
            for case let url as URL in e {
                if skip.contains(url.path) { e.skipDescendants(); continue }
                guard looksTemporary(url),
                      let v = try? url.resourceValues(forKeys: Set(keys)),
                      v.isUbiquitousItem != true,
                      (v.contentModificationDate ?? .distantPast) < limit else { continue }
                let size = allocatedSize(of: url)
                r.items.append(ScanItem(url: url, size: size, lastAccess: lastAccess(url), selected: true))
            }
        }
        return r
    }

    /// Lixo em um disco externo.
    static func externalJunk(on volume: URL) -> [ScanItem] {
        var items: [ScanItem] = []
        let limit = Date().addingTimeInterval(-86_400)
        let systemDirs: Set<String> = [".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100", ".git", ".vol", ".PKInstallSandboxManager"]
        guard let e = fm.enumerator(at: volume, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                                    options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { return items }
        for case let url as URL in e {
            let n = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if isDir {
                if systemDirs.contains(n) { e.skipDescendants(); continue }
                if n == ".Trashes" {
                    // Lixeira do disco: o que você já jogou fora mas ainda ocupa espaço nele.
                    let mine = url.appendingPathComponent(String(getuid()))
                    let sub = children(of: mine, preselect: true)
                    items += sub.items
                    e.skipDescendants(); continue
                }
                if n == ".TemporaryItems" {
                    let size = allocatedSize(of: url)
                    if size > 0 { items.append(ScanItem(url: url, size: size, lastAccess: lastAccess(url), selected: true)) }
                    e.skipDescendants(); continue
                }
                if looksTemporary(url) && modified(url) < limit {
                    items.append(ScanItem(url: url, size: allocatedSize(of: url), lastAccess: lastAccess(url), selected: true))
                    e.skipDescendants()
                }
                continue
            }
            if n == ".DS_Store" { continue }
            if n.hasPrefix("._") {
                // Só os "._" órfãos (o arquivo original não existe mais).
                let original = url.deletingLastPathComponent().appendingPathComponent(String(n.dropFirst(2)))
                if !fm.fileExists(atPath: original.path) {
                    items.append(ScanItem(url: url, size: allocatedSize(of: url), lastAccess: nil, selected: true))
                }
                continue
            }
            if looksTemporary(url) && modified(url) < limit {
                items.append(ScanItem(url: url, size: allocatedSize(of: url), lastAccess: lastAccess(url), selected: true))
            }
        }
        return items
    }

    /// Arquivos da pasta pessoal (fora de Biblioteca e iCloud) sem abrir há muito tempo.
    static func oldFiles(minBytes: Int64, minDays: Int) -> ScanResult {
        var r = ScanResult()
        let limit = Date().addingTimeInterval(-Double(minDays) * 86_400)
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isUbiquitousItemKey,
                                      .contentAccessDateKey, .contentModificationDateKey]
        let skipDirs = [home.appendingPathComponent("Library").path, home.appendingPathComponent(".Trash").path]
        guard let e = fm.enumerator(at: home, includingPropertiesForKeys: keys,
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                    errorHandler: { _, _ in true }) else { return r }
        for case let url as URL in e {
            if skipDirs.contains(url.path) { e.skipDescendants(); continue }
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                  v.isUbiquitousItem != true else { continue }
            let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            guard size >= minBytes else { continue }
            // Vale a data mais recente entre abrir e modificar.
            let last = max(v.contentAccessDate ?? .distantPast, v.contentModificationDate ?? .distantPast)
            if last < limit {
                r.items.append(ScanItem(url: url, size: size, lastAccess: last, selected: false))
            }
        }
        return r
    }

    static func largeFiles(minBytes: Int64) -> ScanResult {
        var r = ScanResult()
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isUbiquitousItemKey]
        let skipDirs = [home.appendingPathComponent("Library").path, home.appendingPathComponent(".Trash").path]
        guard let e = fm.enumerator(at: home, includingPropertiesForKeys: keys,
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                    errorHandler: { _, _ in true }) else { return r }
        for case let url as URL in e {
            if skipDirs.contains(url.path) { e.skipDescendants(); continue }
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            if v.isUbiquitousItem == true { continue }
            let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            if size >= minBytes {
                r.items.append(ScanItem(url: url, size: size, lastAccess: lastAccess(url), selected: false))
            }
        }
        return r
    }
}

// MARK: - iCloud

enum ICloudScanner {
    static let fm = FileManager.default

    /// Arquivos que indicam uma pasta de projeto com código: protegida por padrão.
    static let projectMarkers: Set<String> = [
        ".git", "Package.swift", "project.godot", "package.json", "build.gradle",
        "build.gradle.kts", "Podfile", "Cargo.toml", "CMakeLists.txt", "pubspec.yaml",
    ]

    /// Onde procurar: o iCloud Drive e as pastas "Documents" dos apps (Pages, Keynote…).
    /// Dados internos de apps (Safari, Mail, Notas) ficam de fora.
    static func roots() -> [URL] {
        let md = Scanner.mobileDocuments
        var list = [md.appendingPathComponent("com~apple~CloudDocs")]
        if let containers = try? fm.contentsOfDirectory(at: md, includingPropertiesForKeys: nil) {
            for c in containers where c.lastPathComponent != "com~apple~CloudDocs" {
                let docs = c.appendingPathComponent("Documents")
                if fm.fileExists(atPath: docs.path) { list.append(docs) }
            }
        }
        return list
    }

    static func isProjectFolder(_ dir: URL) -> Bool {
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return false }
        return names.contains { projectMarkers.contains($0) || $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
    }

    struct Output {
        var items: [ScanItem] = []
        var skippedProjects: [URL] = []
        var alreadyInCloud = 0
    }

    /// Lista arquivos do iCloud que estão baixados neste Mac.
    static func scan(protected: [String], protectProjects: Bool, progress: @escaping (Int) -> Void) -> Output {
        var out = Output()
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isRegularFileKey, .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsUploadedKey,
            .ubiquitousItemIsUploadingKey, .ubiquitousItemHasUnresolvedConflictsKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
            .contentAccessDateKey, .contentModificationDateKey,
        ]
        var seen = 0
        for root in roots() {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                        errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in e {
                seen += 1
                if seen % 500 == 0 { progress(seen) }
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }

                if v.isDirectory == true {
                    if protected.contains(where: { url.path == $0 || url.path.hasPrefix($0 + "/") }) {
                        e.skipDescendants(); continue
                    }
                    if protectProjects && isProjectFolder(url) {
                        out.skippedProjects.append(url)
                        e.skipDescendants()
                    }
                    continue // pacotes (.app, .pages…) são pulados pelo enumerador
                }
                guard v.isRegularFile == true, v.isUbiquitousItem == true else { continue }

                let status = v.ubiquitousItemDownloadingStatus
                guard status == .current || status == .downloaded else {
                    out.alreadyInCloud += 1
                    continue
                }
                let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                guard size >= 100_000 else { continue }

                var item = ScanItem(url: url, size: size,
                                    lastAccess: v.contentAccessDate ?? v.contentModificationDate,
                                    selected: false)
                if v.ubiquitousItemHasUnresolvedConflicts == true {
                    item.blockedReason = "Conflito de versões"
                } else if v.ubiquitousItemIsUploaded != true || v.ubiquitousItemIsUploading == true {
                    item.blockedReason = "Ainda enviando para a nuvem"
                }
                out.items.append(item)
            }
        }
        progress(seen)
        out.items.sort { $0.size > $1.size }
        return out
    }
}

// MARK: - Ações

enum Actions {
    struct Report {
        var done = 0
        var freed: Int64 = 0
        var failures: [(String, String)] = []
    }

    /// Move para a Lixeira (pode ser desfeito pelo Finder).
    static func moveToTrash(_ items: [ScanItem]) -> Report {
        var rep = Report()
        for item in items {
            do {
                if item.inVolumeTrash {
                    try FileManager.default.removeItem(at: item.url)
                } else {
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                }
                rep.done += 1
                rep.freed += item.size
            } catch {
                rep.failures.append((item.name, error.localizedDescription))
            }
        }
        return rep
    }

    /// Apaga de vez (usado só para esvaziar a Lixeira).
    static func deletePermanently(_ items: [ScanItem]) -> Report {
        var rep = Report()
        for item in items {
            do {
                try FileManager.default.removeItem(at: item.url)
                rep.done += 1
                rep.freed += item.size
            } catch {
                rep.failures.append((item.name, error.localizedDescription))
            }
        }
        return rep
    }

    /// Remove a cópia local de arquivos do iCloud. Não apaga nada da nuvem.
    static func evict(_ items: [ScanItem]) -> Report {
        var rep = Report()
        for item in items {
            // Confere de novo na hora: o arquivo pode ter mudado desde a varredura.
            let v = try? item.url.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey,
                                                           .ubiquitousItemHasUnresolvedConflictsKey])
            guard v?.ubiquitousItemIsUploaded == true, v?.ubiquitousItemIsUploading != true,
                  v?.ubiquitousItemHasUnresolvedConflicts != true else {
                rep.failures.append((item.name, "Ainda não está 100% na nuvem; pulado por segurança."))
                continue
            }
            do {
                try FileManager.default.evictUbiquitousItem(at: item.url)
                rep.done += 1
                rep.freed += item.size
            } catch {
                rep.failures.append((item.name, error.localizedDescription))
            }
        }
        return rep
    }

    static func diskFree() -> (free: Int64, total: Int64) {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (v?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(v?.volumeTotalCapacity ?? 0))
    }
}


// MARK: - Discos

enum Volumes {
    static func list() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedFormatDescriptionKey,
                                      .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsReadOnlyKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var out: [VolumeInfo] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsLocal == true, v.volumeIsBrowsable != false else { continue }
            let isRoot = url.path == "/"
            if !isRoot && v.volumeIsReadOnly == true { continue }
            let free = isRoot ? (v.volumeAvailableCapacityForImportantUsage ?? 0) : Int64(v.volumeAvailableCapacity ?? 0)
            out.append(VolumeInfo(url: url,
                                  name: isRoot ? "SSD do Mac (\(v.volumeLocalizedName ?? "Macintosh HD"))" : (v.volumeLocalizedName ?? url.lastPathComponent),
                                  total: Int64(v.volumeTotalCapacity ?? 0), free: free,
                                  format: v.volumeLocalizedFormatDescription ?? "",
                                  isInternal: v.volumeIsInternal ?? false, isRoot: isRoot))
        }
        return out.sorted { ($0.isRoot ? 0 : 1, $0.name) < ($1.isRoot ? 0 : 1, $1.name) }
    }
}
