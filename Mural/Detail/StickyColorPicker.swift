import MuralKit
import SwiftUI

/// As cinco cores de post-it, como bolinhas; a escolhida ganha um anel.
struct StickyColorPicker: View {
    @Binding var selection: StickyColor

    var body: some View {
        HStack(spacing: 12) {
            ForEach(StickyColor.allCases, id: \.self) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(Theme.sticky(color))
                        .frame(width: 26, height: 26)
                        .overlay {
                            Circle()
                                .strokeBorder(.primary.opacity(selection == color ? 0.8 : 0.15), lineWidth: selection == color ? 2 : 1)
                        }
                        .padding(3)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help(color.displayName)
                .accessibilityLabel(color.displayName)
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cor do post-it")
    }
}

#Preview {
    @Previewable @State var color = StickyColor.pink
    StickyColorPicker(selection: $color)
        .padding(30)
        .background(Theme.page)
}
