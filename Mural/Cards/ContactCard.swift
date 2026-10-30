import MuralKit
import SwiftUI

/// Círculo da pessoa: a foto reduzida, se o arquivo está na pasta de prévias; sem ela, as iniciais sobre um fundo neutro.
struct ContactAvatar: View {
    let contact: ContactSnapshot
    var diameter: CGFloat
    var maxPixelSize = ContactAvatar.thumbnailMaxPixelSize

    /// Tamanho em pixels em que a foto é decodificada; o mesmo que o renderizador de capas pré-aquece.
    static let thumbnailMaxPixelSize = 160

    @Environment(\.linkPreviewFiles) private var files

    var body: some View {
        Circle()
            .fill(Theme.paper.mix(with: .black, by: 0.08))
            .overlay { content }
            .clipShape(.circle)
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if let name = contact.thumbnailFile, let url = files?.existingURL(for: name) {
            ThumbnailView(url: url, kind: .image, maxPixelSize: maxPixelSize)
        } else {
            Text(contact.initials)
                .font(.system(size: diameter * 0.4, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// Contato em miniatura: foto ou iniciais, nome, organização e o telefone principal (na falta dele, o e-mail).
/// As fontes são fixas, como nas outras miniaturas.
struct ContactCard: View {
    let contact: ContactSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ContactAvatar(contact: contact, diameter: 28)
            Text(contact.displayName)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(2)
            if let organization = contact.organization, !organization.isEmpty, organization != contact.displayName {
                Text(organization).font(.system(size: 7)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let reach = contact.primaryPhone ?? contact.primaryEmail {
                Text(reach).font(.system(size: 6.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .paperSheet()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["Contato", contact.displayName]
        if let organization = contact.organization, !organization.isEmpty, organization != contact.displayName {
            parts.append(organization)
        }
        if let reach = contact.primaryPhone ?? contact.primaryEmail { parts.append(reach) }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
private struct ContactCardRow: View {
    var body: some View {
        HStack(spacing: 16) {
            ContactCard(
                contact: ContactSnapshot(
                    givenName: "Fulana", familyName: "de Tal", organization: "Empresa",
                    phones: [LabeledValue(label: "celular", value: "+55 21 99999-0000")])
            )
            .frame(width: 160, height: 96)
            ContactCard(contact: ContactSnapshot(organization: "Marcenaria Silva", emails: [LabeledValue(value: "contato@silva.example")]))
                .frame(width: 160, height: 96)
        }
        .padding(24)
        .background(Theme.canvas)
    }
}

#Preview("Contatos, claro", traits: .fixedLayout(width: 400, height: 150)) {
    ContactCardRow().preferredColorScheme(.light)
}

#Preview("Contatos, escuro", traits: .fixedLayout(width: 400, height: 150)) {
    ContactCardRow().preferredColorScheme(.dark)
}
#endif
