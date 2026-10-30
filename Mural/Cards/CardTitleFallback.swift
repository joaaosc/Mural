import SwiftUI

/// O que um cartão de música ou de link mostra quando o cartão perdeu os dados (um mural de fora, danificado): o papel com o
/// título.
struct CardTitleFallback: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(2)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: Theme.cardCorner)
                    .fill(Theme.paper)
                    .cardShadow()
            }
    }
}
