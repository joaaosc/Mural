import AppKit
import MuralKit
import SwiftUI

/// Filtragem e ordem dos lembretes na folha de escolha. Funções puras, para testar sem tela.
enum ReminderPickerFilter {
    /// Lembretes a mostrar: concluídos só se pedido, busca por título (sem diferenciar maiúsculas
    /// e acentos) e não concluídos primeiro, mantendo a ordem de cada grupo.
    static func visible(_ snapshots: [ReminderSnapshot], query: String, showCompleted: Bool) -> [ReminderSnapshot] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = snapshots.filter { snapshot in
            (showCompleted || !snapshot.isCompleted) && (term.isEmpty || snapshot.title.localizedStandardContains(term))
        }
        return matches.filter { !$0.isCompleted } + matches.filter(\.isCompleted)
    }
}

/// Folha para escolher lembretes do app Lembretes e pôr um cartão de cada no mural.
struct ReminderPickerSheet: View {
    let session: BoardWindowSession
    @Environment(\.dismiss) private var dismiss

    @State private var access: RemindersAccess
    @State private var lists: [ReminderList] = []
    @State private var selectedListID: String?
    @State private var loaded: [ReminderSnapshot] = []
    @State private var showCompleted = false
    @State private var query = ""
    /// Escolhidos, na ordem da marcação; vale entre listas.
    @State private var chosen: [ReminderSnapshot] = []

    init(session: BoardWindowSession) {
        self.session = session
        _access = State(initialValue: session.reminders.access)
    }

    private var visible: [ReminderSnapshot] {
        ReminderPickerFilter.visible(loaded, query: query, showCompleted: showCompleted)
    }

    var body: some View {
        VStack(spacing: 0) {
            switch access {
            case .notDetermined: notDetermined
            case .denied: denied
            case .granted: picker
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 420)
        .task(id: access) {
            guard access == .granted else { return }
            lists = session.reminders.lists()
            if selectedListID == nil { selectedListID = lists.first?.id }
        }
        .task(id: selectedListID) { await loadSelectedList() }
    }

    // MARK: Sem acesso

    private var notDetermined: some View {
        message(
            "Para escolher lembretes, o Mural precisa de acesso ao app Lembretes.", button: "Permitir acesso"
        ) {
            Task { access = await session.reminders.requestAccess() }
        }
    }

    private var denied: some View {
        message(
            "O acesso ao Lembretes está desligado. Ative o Mural em Ajustes do Sistema › Privacidade e Segurança › Lembretes.",
            button: "Abrir Ajustes do Sistema"
        ) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func message(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button(button, action: action)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Escolha

    private var picker: some View {
        HStack(spacing: 0) {
            List(lists, selection: $selectedListID) { list in
                Label {
                    Text(list.title)
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(Color(hex: list.colorHex))
                }
                .tag(list.id)
            }
            .frame(width: 170)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    TextField("Buscar por título", text: $query).textFieldStyle(.roundedBorder)
                    Toggle("Mostrar concluídos", isOn: $showCompleted).toggleStyle(.checkbox)
                }
                .padding(10)
                if visible.isEmpty {
                    ContentUnavailableView("Nenhum lembrete", systemImage: "checklist")
                } else {
                    List(visible, id: \.identifier) { snapshot in
                        Toggle(isOn: binding(for: snapshot)) {
                            Text(snapshot.title).strikethrough(snapshot.isCompleted)
                        }
                        .toggleStyle(.checkbox)
                        .accessibilityLabel(snapshot.title)
                    }
                }
            }
        }
    }

    private func binding(for snapshot: ReminderSnapshot) -> Binding<Bool> {
        Binding(
            get: { chosen.contains { $0.identifier == snapshot.identifier } },
            set: { isOn in
                chosen.removeAll { $0.identifier == snapshot.identifier }
                if isOn { chosen.append(snapshot) }
            })
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancelar", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Adicionar (\(chosen.count))") {
                session.addReminders(chosen)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(chosen.isEmpty)
        }
        .padding(12)
    }

    private func loadSelectedList() async {
        guard access == .granted, let id = selectedListID else {
            loaded = []
            return
        }
        let result = await session.reminders.reminders(inList: id, includingCompleted: true)
        guard !Task.isCancelled else { return }
        loaded = result
    }
}

extension Color {
    /// Cor `#RRGGBB`; sem valor ou inválido, a cor de destaque do sistema.
    fileprivate init(hex: String?) {
        let digits = hex?.drop { $0 == "#" } ?? ""
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .accentColor
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
