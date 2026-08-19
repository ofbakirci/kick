import SwiftUI

extension Color {
    static let kickAccent = Color(red: 0.96, green: 0.39, blue: 0.12)
    static let kickAccentEnd = Color(red: 1.00, green: 0.58, blue: 0.16)
    static let kickProminentAccent = Color(red: 0.72, green: 0.20, blue: 0.04)
    static let kickActionLabel = Color.black.opacity(0.84)
    static let kickManualBackground = Color.orange.opacity(0.10)
}

struct KickCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

extension View {
    func kickCard() -> some View {
        modifier(KickCardModifier())
    }
}
