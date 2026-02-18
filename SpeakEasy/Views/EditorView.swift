import SwiftUI

/// Raw text editor for editing the extracted PDF text before processing.
struct EditorView: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14))
            .padding(4)
            .contentMargins(.bottom, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
