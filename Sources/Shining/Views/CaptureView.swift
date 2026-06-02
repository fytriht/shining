import SwiftUI

struct CaptureView: View {
    let onSave: (String) -> Void

    @FocusState private var isEditorFocused: Bool
    @State private var draft = ""

    private var canSave: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft)
                    .font(.body)
                    .focused($isEditorFocused)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if draft.isEmpty {
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
            isEditorFocused = true
        }
    }

    private func save() {
        guard canSave else {
            return
        }

        onSave(draft)
    }
}
