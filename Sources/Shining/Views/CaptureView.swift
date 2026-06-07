import ShiningCore
import SwiftUI

final class CaptureFocusController: ObservableObject {
    @Published private(set) var requestID = 0

    func requestFocus() {
        requestID += 1
    }
}

struct CaptureView: View {
    @ObservedObject var draftStore: CaptureDraftStore
    @ObservedObject var focusController: CaptureFocusController

    let onSave: (NSAttributedString) -> Void
    @State private var focusRequest = 0

    private var canSave: Bool {
        draftStore.hasContent
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                RichTextEditorView(
                    document: draftStore.document,
                    revision: draftStore.revision,
                    focusRequest: focusRequest,
                    textContainerInset: NSSize(width: 6, height: 6)
                ) { document in
                    draftStore.replaceDocument(document)
                }
                    .padding(6)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if !draftStore.hasContent {
                    Text("记录一个想法...")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Spacer()
                Button("保存/append") {
                    save()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!canSave)
            }
        }
        .padding(14)
        .frame(width: 400, height: 300)
        .onAppear {
            focusEditor()
        }
        .onChange(of: focusController.requestID) {
            focusEditor()
        }
    }

    private func save() {
        guard canSave else {
            return
        }

        onSave(draftStore.document)
    }

    private func focusEditor() {
        DispatchQueue.main.async {
            focusRequest += 1
        }
    }
}
