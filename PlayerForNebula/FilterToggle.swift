import SwiftUI

struct FilterToggle: View {
    let title: String
    var exclusivity: Exclusivity?
    let isOn: Bool
    let action: () -> Void

    init(_ title: String, exclusivity: Exclusivity? = nil, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.exclusivity = exclusivity
        self.isOn = isOn
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let exclusivity {
                    ExclusivityIcon(exclusivity: exclusivity, size: 12)
                }
                Text(title)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
