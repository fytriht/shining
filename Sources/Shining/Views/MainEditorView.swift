import ShiningCore
import SwiftUI

struct MainEditorView: View {
    @ObservedObject var store: IdeaStore
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        TextEditor(text: $store.text)
            .font(.body)
            .focused($isEditorFocused)
            .scrollContentBackground(.hidden)
            .padding(12)
            .frame(minWidth: 520, minHeight: 360)
            .background(Color(nsColor: .textBackgroundColor))
            .onAppear {
                isEditorFocused = true
            }
            .onChange(of: store.text) {
                store.save()
            }
    }
}
