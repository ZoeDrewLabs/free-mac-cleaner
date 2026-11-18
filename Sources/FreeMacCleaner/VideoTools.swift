import Foundation
import AVFoundation
import VideoToolbox

/// Nível de compressão de um vídeo.
enum CompressMode: String, CaseIterable, Hashable, Identifiable {
    case skip, normal, light, strong
    var id: String { rawValue }

    var title: String {
        switch self {
        case .skip: "Não comprimir"
        case .normal: "Padrão (sem perda visível)"
        case .light: "Leve: ~25% menor, perde pouca qualidade"
        case .strong: "Forte: ~50% menor, perde qualidade"
        }
    }
}

/// O que fazer com o original depois que a versão comprimida é conferida.
enum ReplacePolicy: Hashable {
    /// Mantém o original; a versão nova fica ao lado como "nome (comprimido)".
    case keepOriginal
    /// A versão nova assume o nome e o lugar do original; o original vai para a Lixeira.
    case replaceToTrash
    /// A versão nova assume o nome e o lugar do original; o original é apagado de vez (libera espaço na hora).
    case replaceAndDelete
}

/// Informações de um vídeo, lidas sem alterar o arquivo.
struct VideoInfo: Hashable {
    var width: Int
    var height: Int
    var fps: Double
    var duration: Double          // segundos
    var videoBitrate: Double      // bits por segundo
    var codec: String             // "H.264", "HEVC", "ProRes"…
    var hdr: Bool
    var fileSize: Int64
    var audioRate: Double = 0     // bitrate de áudio que será usado (0 = sem áudio)
    var floor: Double             // piso de qualidade para HEVC
    /// Verdadeiro quando o modo padrão não consegue reduzir à metade sem perder qualidade.
    var limited: Bool = false
    var mode: CompressMode = .normal

    /// Bitrate de vídeo que será usado no modo escolhido.
    var targetBitrate: Double {
        switch mode {
        case .skip: videoBitrate
        case .normal: max(videoBitrate * VideoTools.ratio, floor)
        case .light: sizeTarget(0.75, minFraction: 0.3)
        case .strong: sizeTarget(0.5, minFraction: 0.2)
        }
    }

    /// Bitrate de vídeo para o arquivo final ficar com `fraction` do tamanho original.
    private func sizeTarget(_ fraction: Double, minFraction: Double) -> Double {
        let total = Double(fileSize) * fraction * 8 / max(duration, 0.001)
        let video = total - audioRate - 20_000 // ~20 kbps de sobra para o contêiner
        return min(max(video, videoBitrate * minFraction), videoBitrate * 0.9)
    }

    /// Tamanho previsto depois de comprimir.
    var estimatedSize: Int64 {
        if mode == .skip { return fileSize }
        return Int64((targetBitrate + audioRate) * duration / 8)
    }

    /// Tamanho máximo aceito na conferência (fração do original).
    var maxRatio: Double { mode == .light ? 0.92 : 0.75 }

    var resolution: String {
        let short = min(width, height)
        let label = short >= 2100 ? "4K" : short >= 1400 ? "1440p" : short >= 1000 ? "1080p" : short >= 700 ? "720p" : "\(short)p"
        return "\(width)×\(height) (\(label))"
    }
}

/// Sinal de cancelamento compartilhado entre a tela e a compressão.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}

enum VideoError: LocalizedError {
    case unreadable, noVideoTrack, notEnoughSpace, cancelled, failed(String), notSmaller, durationMismatch

    var errorDescription: String? {
        switch self {
        case .unreadable: "O macOS não consegue ler este formato."
        case .noVideoTrack: "Arquivo sem faixa de vídeo."
        case .notEnoughSpace: "Pouco espaço livre no disco para gravar a versão comprimida."
        case .cancelled: "Cancelado."
        case .failed(let why): "Falhou: \(why)"
        case .notSmaller: "A versão comprimida não ficou menor o suficiente; o original foi mantido."
        case .durationMismatch: "A versão comprimida ficou com duração diferente; o original foi mantido."
        }
    }
}

enum VideoTools {
    /// Motivo mostrado enquanto um vídeo "já compacto" está em "Não comprimir".
    static let limitedReason = "Já compacto: escolha Leve ou Forte"

    static let extensions: Set<String> = ["mp4", "mov", "m4v"]
    static let fm = FileManager.default

    /// Alvo: 45% do bitrate original, sem descer abaixo de um piso de qualidade para HEVC.
    static let ratio = 0.45
    static let audioBitrate = 160_000.0
    nonisolated(unsafe) static var fastEncode = true
    nonisolated(unsafe) static var prioritizeSpeed = false

    static func qualityFloor(width: Int, height: Int, fps: Double) -> Double {
        // ~0,035 bit por pixel por quadro: 1080p30 ≈ 2,2 Mbps, 4K30 ≈ 8,7 Mbps.
        Double(width * height) * max(fps, 24) * 0.035
    }

    // MARK: - Leitura

    static func probe(_ url: URL, fileSize: Int64) async -> VideoInfo? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (size, transform, fps, rate, descs) = try? await track.load(.naturalSize, .preferredTransform, .nominalFrameRate, .estimatedDataRate, .formatDescriptions),
              let duration = try? await asset.load(.duration) else { return nil }
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        let w = Int(abs(rect.width).rounded()), h = Int(abs(rect.height).rounded())
        let seconds = duration.seconds
        guard w > 0, h > 0, seconds.isFinite, seconds > 0 else { return nil }

        var codec = "?"
        var hdr = false
        if let desc = descs.first {
            let sub = CMFormatDescriptionGetMediaSubType(desc)
            codec = codecName(sub)
            if let tf = CMFormatDescriptionGetExtension(desc, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String {
                hdr = tf == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
                    || tf == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)
            }
        }
        // Se o arquivo não informa o bitrate, estima pelo tamanho.
        let vRate = rate > 0 ? Double(rate) : Double(fileSize) * 8 / seconds
        // Áudio: mantém o bitrate original (entre 64 e 160 kbps) para não crescer.
        var aRate = 0.0
        if let a = try? await asset.loadTracks(withMediaType: .audio).first {
            let r = Double((try? await a.load(.estimatedDataRate)) ?? 0)
            aRate = min(max(r > 0 ? r : audioBitrate, 64_000), audioBitrate)
        }
        var info = VideoInfo(width: w, height: h, fps: Double(fps), duration: seconds, videoBitrate: vRate,
                             codec: codec, hdr: hdr, fileSize: fileSize,
                             floor: qualityFloor(width: w, height: h, fps: Double(fps)))
        info.audioRate = aRate
        info.limited = info.estimatedSize > Int64(Double(fileSize) * 0.6)
        if info.limited { info.mode = .skip }
        return info
    }

    static func codecName(_ code: FourCharCode) -> String {
        let s = String(bytes: [UInt8(code >> 24 & 255), UInt8(code >> 16 & 255), UInt8(code >> 8 & 255), UInt8(code & 255)], encoding: .ascii) ?? "?"
        switch s {
        case "avc1", "avc3": return "H.264"
        case "hvc1", "hev1": return "HEVC"
        case "apcn", "apch", "apcs", "apco", "ap4h", "ap4x": return "ProRes"
        case "av01": return "AV1"
        case "mp4v": return "MPEG-4"
        case "jpeg", "mjpa", "mjpb": return "Motion JPEG"
        default: return s.trimmingCharacters(in: .whitespaces)
        }
    }

    /// Procura vídeos grandes. Arquivos do iCloud ficam de fora.
    static func scan(roots: [URL], minBytes: Int64, progress: @escaping (Int) -> Void) async -> [ScanItem] {
        let found = findVideos(roots: roots, minBytes: minBytes)
        var items: [ScanItem] = []
        for (i, (url, size, date)) in found.enumerated() {
            progress(i + 1)
            var item = ScanItem(url: url, size: size, lastAccess: date, selected: false)
            if let info = await probe(url, fileSize: size) {
                item.video = info
                if info.limited {
                    item.blockedReason = limitedReason
                } else {
                    item.selected = true
                }
            } else {
                item.blockedReason = "Formato não suportado"
            }
            items.append(item)
        }
        return items.sorted { $0.size > $1.size }
    }

    private static func findVideos(roots: [URL], minBytes: Int64) -> [(URL, Int64, Date?)] {
        var found: [(URL, Int64, Date?)] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
                                      .isUbiquitousItemKey, .contentAccessDateKey, .contentModificationDateKey]
        let skip: Set<String> = [Scanner.home.appendingPathComponent("Library").path, Scanner.home.appendingPathComponent(".Trash").path]
        for root in roots {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                        errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in e {
                if skip.contains(url.path) { e.skipDescendants(); continue }
                guard extensions.contains(url.pathExtension.lowercased()),
                      let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                      v.isUbiquitousItem != true else { continue }
                let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                if size >= minBytes { found.append((url, size, v.contentAccessDate ?? v.contentModificationDate)) }
            }
        }
        return found
    }

    // MARK: - Compressão

    /// Comprime um vídeo para HEVC na mesma resolução. Se der tudo certo, o original vai
    /// para a Lixeira e o novo arquivo fica com o mesmo nome. Devolve o novo tamanho.
    static func compress(_ item: ScanItem, policy: ReplacePolicy = .replaceToTrash, cancel: CancelFlag,
                         progress: @escaping (Double) -> Void) async throws -> Int64 {
        guard let info = item.video, info.mode != .skip else { throw VideoError.unreadable }
        let src = item.url
        let ext = src.pathExtension.lowercased()
        let fileType: AVFileType = ext == "mov" ? .mov : .mp4
        let tmp = src.deletingLastPathComponent()
            .appendingPathComponent(".\(src.deletingPathExtension().lastPathComponent).comprimindo.\(ext)")
        removeLeftovers(of: src)

        // Espaço livre para a cópia nova.
        let free = (try? src.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity ?? 0
        if Int64(free) < Int64(Double(info.estimatedSize) * 1.3) + 200_000_000 { throw VideoError.notEnoughSpace }

        let asset = AVURLAsset(url: src)
        guard let vTrack = try await asset.loadTracks(withMediaType: .video).first else { throw VideoError.noVideoTrack }
        let aTrack = try await asset.loadTracks(withMediaType: .audio).first
        let (natural, transform, descs) = try await vTrack.load(.naturalSize, .preferredTransform, .formatDescriptions)
        let duration = try await asset.load(.duration)
        let metadata = (try? await asset.load(.metadata)) ?? []

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: tmp, fileType: fileType)
        writer.metadata = metadata
        // Sem "otimizar para rede": evita regravar o arquivo inteiro no fim.
        writer.shouldOptimizeForNetworkUse = false

        // Vídeo
        let pixelFormat = info.hdr ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let vOut = AVAssetReaderTrackOutput(track: vTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat])
        vOut.alwaysCopiesSampleData = false
        guard reader.canAdd(vOut) else { throw VideoError.unreadable }
        reader.add(vOut)

        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: Int(info.targetBitrate),
            AVVideoExpectedSourceFrameRateKey: max(1, Int(info.fps.rounded())),
            AVVideoProfileLevelKey: info.hdr ? (kVTProfileLevel_HEVC_Main10_AutoLevel as String) : (kVTProfileLevel_HEVC_Main_AutoLevel as String),
        ]
        if info.fps > 0 { compression[AVVideoMaxKeyFrameIntervalKey] = Int(info.fps.rounded()) * 2 }
        if fastEncode {
            // Usa o codificador de hardware no máximo, sem economizar energia.
            compression[kVTCompressionPropertyKey_MaximizePowerEfficiency as String] = false
            compression[kVTCompressionPropertyKey_RealTime as String] = false
        }
        if prioritizeSpeed { compression[kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String] = true }
        var vSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(natural.width),
            AVVideoHeightKey: Int(natural.height),
            AVVideoCompressionPropertiesKey: compression,
        ]
        if let desc = descs.first,
           let p = CMFormatDescriptionGetExtension(desc, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String,
           let t = CMFormatDescriptionGetExtension(desc, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String,
           let m = CMFormatDescriptionGetExtension(desc, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix) as? String {
            vSettings[AVVideoColorPropertiesKey] = [AVVideoColorPrimariesKey: p, AVVideoTransferFunctionKey: t, AVVideoYCbCrMatrixKey: m]
        }
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        vIn.transform = transform
        vIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(vIn) else { throw VideoError.failed("o codificador HEVC recusou as configurações") }
        writer.add(vIn)

        // Áudio (AAC estéreo)
        var aOut: AVAssetReaderTrackOutput?
        var aIn: AVAssetWriterInput?
        if let aTrack {
            let o = AVAssetReaderTrackOutput(track: aTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVNumberOfChannelsKey: 2, AVSampleRateKey: 48_000,
            ])
            let i = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 2, AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: Int(info.audioRate > 0 ? info.audioRate : audioBitrate),
            ])
            i.expectsMediaDataInRealTime = false
            if reader.canAdd(o), writer.canAdd(i) {
                reader.add(o); writer.add(i)
                aOut = o; aIn = i
            }
        }

        guard reader.startReading() else { throw VideoError.failed(reader.error?.localizedDescription ?? "leitura") }
        guard writer.startWriting() else { throw VideoError.failed(writer.error?.localizedDescription ?? "gravação") }
        writer.startSession(atSourceTime: .zero)

        let total = max(duration.seconds, 0.001)
        async let videoDone: Void = pump(vIn, vOut, queue: DispatchQueue(label: "video"), cancel: cancel) { t in
            progress(min(1, t.seconds / total))
        }
        async let audioDone: Void = {
            if let aIn, let aOut { await pump(aIn, aOut, queue: DispatchQueue(label: "audio"), cancel: cancel) { _ in } }
        }()
        _ = await (videoDone, audioDone)

        func abort(_ error: Error) throws -> Never {
            reader.cancelReading()
            writer.cancelWriting()
            try? fm.removeItem(at: tmp)
            throw error
        }

        if cancel.isCancelled { try abort(VideoError.cancelled) }
        if reader.status == .failed { try abort(VideoError.failed(reader.error?.localizedDescription ?? "leitura")) }
        await writer.finishWriting()
        if writer.status != .completed { try abort(VideoError.failed(writer.error?.localizedDescription ?? "gravação")) }

        // Conferência antes de mexer no original.
        let newSize = Scanner.allocatedSize(of: tmp)
        let newDuration = (try? await AVURLAsset(url: tmp).load(.duration).seconds) ?? 0
        if abs(newDuration - duration.seconds) > 1.0 { try abort(VideoError.durationMismatch) }
        if newSize <= 0 || Double(newSize) > Double(item.size) * info.maxRatio { try abort(VideoError.notSmaller) }

        if policy == .keepOriginal {
            let kept = src.deletingLastPathComponent()
                .appendingPathComponent("\(src.deletingPathExtension().lastPathComponent) (comprimido).\(ext)")
            try? fm.removeItem(at: kept)
            try fm.moveItem(at: tmp, to: kept)
            return newSize
        }

        // Troca: novo arquivo no lugar do original, com as mesmas datas.
        let attrs = try? fm.attributesOfItem(atPath: src.path)
        if policy == .replaceToTrash {
            do {
                try fm.trashItem(at: src, resultingItemURL: nil)
            } catch {
                try abort(VideoError.failed("não consegui mover o original para a Lixeira: \(error.localizedDescription)"))
            }
            try fm.moveItem(at: tmp, to: src)
        } else {
            // Apagar de vez: primeiro guarda o original com outro nome, coloca o novo no lugar
            // e só então apaga o original. Se algo falhar no meio, o original volta.
            let backup = src.deletingLastPathComponent()
                .appendingPathComponent(".\(src.deletingPathExtension().lastPathComponent).original.\(ext)")
            try? fm.removeItem(at: backup)
            do {
                try fm.moveItem(at: src, to: backup)
            } catch {
                try abort(VideoError.failed("não consegui trocar o arquivo: \(error.localizedDescription)"))
            }
            do {
                try fm.moveItem(at: tmp, to: src)
            } catch {
                try? fm.moveItem(at: backup, to: src)
                try abort(VideoError.failed("não consegui trocar o arquivo: \(error.localizedDescription)"))
            }
            try? fm.removeItem(at: backup)
        }
        var keep: [FileAttributeKey: Any] = [:]
        if let c = attrs?[.creationDate] { keep[.creationDate] = c }
        if let m = attrs?[.modificationDate] { keep[.modificationDate] = m }
        if !keep.isEmpty { try? fm.setAttributes(keep, ofItemAtPath: src.path) }
        return newSize
    }

    /// Apaga sobras de uma compressão interrompida deste vídeo (".nome.comprimindo.ext" e cópias ".sb-…").
    static func removeLeftovers(of src: URL) {
        let dir = src.deletingLastPathComponent()
        let prefix = ".\(src.deletingPathExtension().lastPathComponent).comprimindo."
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        for n in names where n.hasPrefix(prefix) {
            try? fm.removeItem(at: dir.appendingPathComponent(n))
        }
    }

    /// Passa as amostras do leitor para o gravador até acabar ou ser cancelado.
    private static func pump(_ input: AVAssetWriterInput, _ output: AVAssetReaderOutput, queue: DispatchQueue,
                             cancel: CancelFlag, onSample: @escaping (CMTime) -> Void) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var finished = false
            input.requestMediaDataWhenReady(on: queue) {
                guard !finished else { return }
                while input.isReadyForMoreMediaData {
                    if cancel.isCancelled {
                        finished = true; input.markAsFinished(); cont.resume(); return
                    }
                    guard let sample = output.copyNextSampleBuffer() else {
                        finished = true; input.markAsFinished(); cont.resume(); return
                    }
                    onSample(CMSampleBufferGetPresentationTimeStamp(sample))
                    if !input.append(sample) {
                        finished = true; input.markAsFinished(); cont.resume(); return
                    }
                }
            }
        }
    }
}
