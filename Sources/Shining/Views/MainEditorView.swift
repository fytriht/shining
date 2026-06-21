import Foundation
import ShiningCore
import SwiftUI

struct RichTextEditorFocusRequest {
    static let none = RichTextEditorFocusRequest(id: 0, selectedRange: nil)

    let id: Int
    let selectedRange: NSRange?
}

final class EditorFocusController: ObservableObject {
    @Published private(set) var request = RichTextEditorFocusRequest.none

    func requestFocus(selectedRange: NSRange? = nil) {
        request = RichTextEditorFocusRequest(
            id: request.id + 1,
            selectedRange: selectedRange
        )
    }
}

struct MainEditorView: View {
    @ObservedObject var store: IdeaStore
    @ObservedObject var focusController: EditorFocusController

    var body: some View {
        RichTextEditorView(
            document: store.document,
            revision: store.revision,
            focusRequest: focusController.request
        ) { document in
            store.replaceDocument(document)
        }
            .padding(0)
            .frame(minWidth: 520, minHeight: 360)
            .background(.thickMaterial)
            .containerBackground(.thickMaterial, for: .window)
    }
}
