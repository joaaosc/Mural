import AppKit
import SwiftUI

/// A aba Geral dos Ajustes: abrir o Mural ao iniciar a sessão e sair do app.
///
/// Sair fica aqui porque, sem janela aberta, o Mural sai do Dock e da barra de menus do app: o ícone e esta janela são
/// os caminhos que sobram.
struct GeneralSettingsView: View {
    let loginItem: LoginItemModel

    var body: some View {
        @Bindable var loginItem = loginItem
        Form {
            Section {
                Toggle("Abrir ao Iniciar Sessão", isOn: $loginItem.isOn)
                    .accessibilityIdentifier("settings-login-item")
                // Se o macOS recusou o pedido, o interruptor volta sozinho, e o motivo aparece embaixo dele.
                if let message = loginItem.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                // Registrado, mas a pessoa ainda precisa permitir o Mural nos Ajustes do Sistema.
                if loginItem.needsApproval {
                    Button("Permitir nos Ajustes do Sistema…", action: loginItem.openSystemSettings)
                }
            } footer: {
                Text("Aberto assim, o Mural fica só no ícone da barra de menus, sem janela.")
            }

            Section {
                Button("Sair do Mural", action: quit)
                    .accessibilityIdentifier("settings-quit")
            } footer: {
                Text("Sem janela aberta, o Mural continua no ícone da barra de menus; daqui ele fecha de vez.")
            }
        }
        .formStyle(.grouped)
        // A pessoa pode ter mudado a opção nos Ajustes do Sistema desde a última vez.
        .onAppear(perform: loginItem.refresh)
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

#Preview("Geral") {
    GeneralSettingsView(loginItem: .shared)
        .frame(width: 500)
}
