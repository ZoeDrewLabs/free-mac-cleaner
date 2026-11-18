import SwiftUI

/// Coloca os itens lado a lado e quebra para a linha de baixo quando não cabem.
/// Evita que filtros e botões empurrem a tela para fora (e escondam a barra lateral).
struct FlowLayout: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for (index, size) in row.items {
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var items: [(Int, CGSize)] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, view) in subviews.enumerated() {
            var size = view.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            let needed = rows[rows.count - 1].items.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append((i, size))
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// Rodapé com botões à esquerda, resumo e ações à direita.
/// Numa janela estreita, as ações descem para uma segunda linha em vez de estourar a largura.
struct AdaptiveBar<Leading: View, Summary: View, Actions: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var summary: Summary
    @ViewBuilder var actions: Actions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                leading
                Spacer(minLength: 8)
                summary
                actions
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    leading
                    Spacer(minLength: 8)
                    summary
                }
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    actions
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) { leading }
                summary
                FlowLayout(spacing: 10) { actions }
            }
        }
    }
}
