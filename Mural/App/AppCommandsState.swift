import Observation

/// Estado ligado aos comandos de menu (por exemplo, Arquivo › Importar…).
@Observable
final class AppCommandsState {
    var isImporterPresented = false
}
