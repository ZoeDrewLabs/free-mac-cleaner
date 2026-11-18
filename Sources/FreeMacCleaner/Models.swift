import Foundation

/// Seções da barra lateral.
enum Section: String, CaseIterable, Identifiable, Hashable {
    case overview, temp, caches, logs, xcode, devTools, downloads, largeFiles, oldFiles, trash, icloud, disks, videos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Tudo"
        case .videos: "Comprimir vídeos"
        case .temp: "Arquivos temporários"
        case .disks: "Temporários em discos externos"
        case .caches: "Caches de apps"
        case .logs: "Logs"
        case .xcode: "Xcode e simuladores"
        case .devTools: "Caches de ferramentas"
        case .downloads: "Downloads antigos"
        case .largeFiles: "Arquivos grandes"
        case .oldFiles: "Arquivos esquecidos"
        case .trash: "Lixeira"
        case .icloud: "Remover downloads do iCloud"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.stack.3d.up"
        case .videos: "film.stack"
        case .temp: "clock.arrow.circlepath"
        case .disks: "externaldrive.badge.xmark"
        case .caches: "archivebox"
        case .logs: "doc.text"
        case .xcode: "hammer"
        case .devTools: "shippingbox"
        case .downloads: "arrow.down.circle"
        case .largeFiles: "externaldrive"
        case .oldFiles: "clock.badge.questionmark"
        case .trash: "trash"
        case .icloud: "icloud.and.arrow.down"
        }
    }

    /// O que acontece com os itens desta seção.
    var actionLabel: String {
        switch self {
        case .icloud: "Remover download"
        case .trash: "Apagar de vez"
        default: "Lixeira"
        }
    }

    var explanation: String {
        switch self {
        case .overview:
            "Tudo o que foi encontrado no Mac e no iCloud, em uma lista só: temporários, caches, arquivos grandes, esquecidos e downloads do iCloud. O que está no Mac vai para a Lixeira; o que está no iCloud só tem o download removido e continua na nuvem. SSDs e HDs externos têm varredura separada, em Discos."
        case .videos:
            "Converte vídeos grandes para HEVC (H.265) na mesma resolução, ocupando cerca de metade do espaço, e confere cada um antes de mexer no original. Vídeos que já estão compactos podem usar os níveis Leve (~25% menor) ou Forte (~50% menor), com alguma perda de qualidade."
        case .temp:
            "Arquivos temporários no SSD do Mac: a pasta temporária do sistema, downloads que não terminaram (.crdownload, .part), arquivos .tmp e travas do Office (~$) com mais de 3 dias. Vão para a Lixeira."
        case .disks:
            "Lixo em SSDs e discos externos: arquivos temporários, downloads incompletos, arquivos \"._\" órfãos do macOS e a lixeira do próprio disco. O que já está na lixeira do disco é apagado de vez; o resto vai para a Lixeira."
        case .caches:
            "Arquivos temporários que os apps recriam sozinhos. Vão para a Lixeira."
        case .logs:
            "Registros antigos de apps e do sistema do seu usuário. Vão para a Lixeira."
        case .xcode:
            "DerivedData, arquivos de Archive, suporte a aparelhos antigos e caches de simulador. Vão para a Lixeira."
        case .devTools:
            "Caches de npm, Gradle, CocoaPods, pip e afins. São baixados de novo quando precisar. Vão para a Lixeira."
        case .downloads:
            "Itens da pasta Downloads sem abrir há muito tempo. Revise antes de marcar. Vão para a Lixeira."
        case .largeFiles:
            "Arquivos grandes na sua pasta pessoal, fora do iCloud. Revise antes de marcar. Vão para a Lixeira."
        case .oldFiles:
            "Arquivos na sua pasta pessoal que ninguém abre há muito tempo, fora do iCloud. Revise antes de marcar. Vão para a Lixeira."
        case .trash:
            "O que já está na Lixeira. Esvaziar apaga de vez e não pode ser desfeito."
        case .icloud:
            "Tira do disco a cópia local de arquivos do iCloud Drive. Nada é apagado da nuvem: o arquivo fica com o ícone de nuvem e é baixado de novo quando você abrir."
        }
    }

    static var cleanup: [Section] { [.temp, .caches, .logs, .xcode, .devTools, .downloads, .largeFiles, .oldFiles, .trash] }
    /// Seções que entram em "Tudo": só o Mac e o iCloud. Discos externos e a Lixeira ficam de fora.
    static var global: [Section] { [.temp, .caches, .logs, .xcode, .devTools, .downloads, .largeFiles, .oldFiles, .icloud] }
}

/// Um item encontrado na varredura (arquivo ou pasta).
struct ScanItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let lastAccess: Date?
    var selected: Bool
    /// Motivo de o item não poder ser processado (ex.: ainda subindo para o iCloud).
    var blockedReason: String? = nil
    /// Só para a tela de vídeos.
    var video: VideoInfo? = nil

    var name: String { url.lastPathComponent }
    /// Já está na lixeira de um disco externo: só resta apagar de vez.
    var inVolumeTrash: Bool { url.path.contains("/.Trashes/") }
    var parentPath: String {
        url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

/// Tipos de arquivo para o filtro do iCloud.
enum FileKind: String, CaseIterable, Identifiable {
    case all = "Todos"
    case video = "Vídeos"
    case image = "Imagens"
    case audio = "Áudio"
    case document = "Documentos"
    case archive = "Compactados e instaladores"

    var id: String { rawValue }

    func matches(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        switch self {
        case .all: return true
        case .video: return ["mp4", "mov", "m4v", "avi", "mkv", "webm"].contains(ext)
        case .image: return ["jpg", "jpeg", "png", "heic", "gif", "webp", "tiff", "psd", "raw", "dng"].contains(ext)
        case .audio: return ["mp3", "m4a", "wav", "aiff", "flac", "aac"].contains(ext)
        case .document: return ["pdf", "docx", "doc", "pptx", "xlsx", "pages", "key", "numbers", "txt", "epub"].contains(ext)
        case .archive: return ["zip", "dmg", "pkg", "rar", "7z", "tar", "gz", "iso", "apk", "xip"].contains(ext)
        }
    }
}

enum Fmt {
    static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func size(_ n: Int64) -> String { bytes.string(fromByteCount: n) }

    static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier: "pt_BR")
        return f
    }()
}


/// Páginas da barra lateral.
enum Page: Hashable {
    case home
    case section(Section)
    case volume(String) // caminho de montagem do disco
}

/// Um disco montado (SSD interno, SSD externo, pen drive…).
struct VolumeInfo: Identifiable, Hashable {
    let url: URL
    let name: String
    let total: Int64
    let free: Int64
    let format: String
    let isInternal: Bool
    let isRoot: Bool
    var id: String { url.path }
    var used: Int64 { max(0, total - free) }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    var symbol: String { isRoot ? "internaldrive" : (isInternal ? "internaldrive.fill" : "externaldrive") }
}
