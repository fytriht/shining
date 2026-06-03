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

    let onSave: (String) -> Void

    @FocusState private var isEditorFocused: Bool

    private var canSave: Bool {
        !draftStore.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draftStore.text)
                    .font(.body)
                    .focused($isEditorFocused)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if draftStore.text.isEmpty {
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

        onSave(draftStore.text)
    }

    private func focusEditor() {
        DispatchQueue.main.async {
            isEditorFocused = true
        }
    }
}
