/// Onde está o teclado do painel da barra de menus.
///
/// O painel abre na vitrine, sem nenhuma maneira de colar escolhida: ali Return abre o mural do centro. Tab mostra as
/// maneiras de colar (a última, sempre, abre o editor de texto). ⇧Tab volta uma etapa e Esc volta
/// direto à vitrine. ← → trocam de mural em qualquer etapa, porque a vitrine continua à vista.
enum PanelStage: Equatable, Sendable {
    /// A vitrine: escolher qual mural abrir (ou em qual colar com ⌘V).
    case boards
    /// As maneiras de colar o que está copiado no mural do centro.
    case paste
}
