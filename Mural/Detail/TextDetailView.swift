import MuralKit
import SwiftUI

/// Nota de texto em página de leitura, ou post-it ampliado.
struct TextDetailView: View {
    let item: BoardItem

    var body: some View {
        if item.kind == .sticky {
            Text(item.displayText)
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(Theme.stickyInk)
                .textSelection(.enabled)
                .padding(36)
                .frame(width: 420, height: 420, alignment: .topLeading)
                .background(Theme.sticky(item.stickyColor), in: .rect(cornerRadius: 6))
                .cardShadow()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(item.title)
                        .font(.system(size: 40, weight: .bold))
                    Text(item.text ?? "")
                        .font(.system(.title3, design: .serif))
                        .lineSpacing(5)
                }
                .textSelection(.enabled)
                .frame(maxWidth: 600, alignment: .leading)
                .padding(.top, 110)
                .padding(.bottom, 110)
                .frame(maxWidth: .infinity)
            }
            .discreetScrollIndicators()
        }
    }
}
