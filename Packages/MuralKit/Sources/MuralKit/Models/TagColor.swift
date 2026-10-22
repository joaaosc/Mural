/// Cor de tag de um cartão, como as tags do Finder. Cada cartão tem no máximo uma.
public enum TagColor: String, Codable, Sendable, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, gray

    public var id: Self { self }
}
