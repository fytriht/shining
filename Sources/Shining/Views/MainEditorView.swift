import ShiningCore
import SwiftUI

struct MainEditorView: View {
    @ObservedObject var store: IdeaStore
    @State private var focusRequest = 0

    var body: some View {
        RichTextEditorView(
            document: store.document,
            revision: store.revision,
            focusRequest: focusRequest
        ) { document in
            store.replaceDocument(document)
        }
            .padding(12)
            .frame(minWidth: 520, minHeight: 360)
            .background(Color(nsColor: .textBackgroundColor))
            .onAppear {
                focusRequest += 1
            }
    }
}
