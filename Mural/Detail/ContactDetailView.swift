import AppKit
import MuralKit
import SwiftUI

/// Página de um contato: foto, nome, organização, telefones e e-mails, cada um com "Copiar" e um botão que abre a ligação
/// (`tel:`) ou a mensagem (`mailto:`) no app padrão. Mostra o que o vCard trouxe; o Mural não consulta o app Contatos.
struct ContactDetailView: View {
    let item: BoardItem

    var body: some View {
        let contact = item.contact
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let contact {
                    ContactAvatar(contact: contact, diameter: 96, maxPixelSize: 480)
                }
                Text(contact?.displayName ?? item.title)
                    .font(.system(size: 40, weight: .bold))
                    .textSelection(.enabled)
                if let organization = contact?.organization, !organization.isEmpty, organization != contact?.displayName {
                    Text(organization).font(.title3).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let contact {
                    section("Telefones", values: contact.phones, scheme: "tel")
                    section("E-mails", values: contact.emails, scheme: "mailto")
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.top, 100)
            .padding(.bottom, 110)
            .frame(maxWidth: .infinity)
        }
        .discreetScrollIndicators()
    }

    @ViewBuilder
    private func section(_ title: String, values: [LabeledValue], scheme: String) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                ForEach(Array(values.enumerated()), id: \.offset) { _, entry in
                    row(entry, scheme: scheme)
                }
            }
        }
    }

    private func row(_ entry: LabeledValue, scheme: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let label = entry.label, !label.isEmpty {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
                Text(entry.value).font(.body).textSelection(.enabled)
            }
            Spacer(minLength: 12)
            Button("Copiar") { copy(entry.value) }
                .accessibilityLabel("Copiar \(entry.value)")
            if let url = scheme == "tel" ? ContactDialing.telURL(entry.value) : ContactDialing.mailURL(entry.value) {
                Button(scheme == "tel" ? "Ligar" : "Escrever") { NSWorkspace.shared.open(url) }
                    .accessibilityLabel("\(scheme == "tel" ? "Ligar para" : "Escrever para") \(entry.value)")
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
