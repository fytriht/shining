import Foundation
import ShiningCore
import SwiftUI

struct MainEditorView: View {
    @ObservedObject var store: JournalStore
    @ObservedObject var focusController: EditorFocusController

    var body: some View {
        JournalEditorView(
            document: store.document,
            revision: store.revision,
            focusRequest: focusController.request,
            attachmentURL: store.attachmentURL(for:),
            importImageFile: store.importImageFile(_:),
            importImage: store.importImage(_:originalFilename:)
        ) { document in
            store.replaceDocument(document)
        }
            .padding(12)
            .frame(minWidth: 520, minHeight: 360)
            .background(Color(nsColor: .textBackgroundColor))
    }
}
