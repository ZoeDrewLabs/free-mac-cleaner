import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

/// Dados de doação do projeto.
enum Donate {
    static let pixKey = "54.913.468/0001-04"
    static let pixKeyDigits = "54913468000104"
    static let livePix = URL(string: "https://livepix.gg/zoedrewerro404")!
    static let repo = URL(string: "https://github.com/ZoeDrewLabs/free-mac-cleaner")!
}

/// Botão "Doar" que abre a janela de doação.
struct DonateButton: View {
    @EnvironmentObject private var state: AppState
    var prominent = false

    var body: some View {
        Button { state.showingDonate = true } label: {
            Label("Doar", systemImage: "heart.fill")
                .frame(maxWidth: prominent ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .tint(.pink)
        .help("Apoie o projeto com uma doação")
    }
}

struct DonateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    // @State não compila só com as Command Line Tools; o estado fica no AppState.
    private var copied: Bool { state.pixCopied }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.pink)
            Text("Apoie o Free Mac Cleaner")
                .font(.title2.bold())
            Text("O app é grátis e de código aberto. Se ele liberou espaço no seu Mac, considere fazer uma doação para manter o projeto vivo.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 24) {
                // Pix
                VStack(spacing: 10) {
                    Label("Pix (CNPJ)", systemImage: "brazilianrealsign.circle.fill")
                        .font(.headline)
                    Text(Donate.pixKey)
                        .font(.title3.monospacedDigit())
                        .textSelection(.enabled)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Donate.pixKeyDigits, forType: .string)
                        state.pixCopied = true
                    } label: {
                        Label(copied ? "Chave copiada!" : "Copiar chave Pix", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    Text("Cole no app do seu banco, em Pix → Pagar com chave.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 220)

                Divider().frame(height: 200)

                // LivePix
                VStack(spacing: 10) {
                    Label("LivePix", systemImage: "link")
                        .font(.headline)
                    if let qr = QRCode.image(for: Donate.livePix.absoluteString) {
                        Image(nsImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 120, height: 120)
                            .padding(6)
                            .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    }
                    Button {
                        NSWorkspace.shared.open(Donate.livePix)
                    } label: {
                        Label("Abrir LivePix", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                }
                .frame(width: 220)
            }

            HStack {
                Link("Código no GitHub", destination: Donate.repo)
                    .font(.callout)
                Spacer()
                Button("Fechar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(width: 560)
        .onDisappear { state.pixCopied = false }
    }
}

enum QRCode {
    static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
