import SwiftUI

extension View {
    /// `onChange` two-parameter form requires macOS 14; Ventura uses the legacy API.
    /// Avoid `@ViewBuilder` + `if #available` (can break modifier chains on 13.x).
    func onValueChange<V: Equatable>(_ value: V, perform action: @escaping (V) -> Void) -> some View {
        modifier(ValueChangeModifier(value: value, action: action))
    }
}

private struct ValueChangeModifier<V: Equatable>: ViewModifier {
    let value: V
    let action: (V) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            content.onChange(of: value, perform: action)
        }
    }
}
