import SwiftData
import SwiftUI

struct ScriptEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var script: Script
    @State private var showingTeleprompter = false

    var body: some View {
        Form {
            Section("Title") {
                TextField("Script title", text: $script.title)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
            }

            Section("Body") {
                ZStack(alignment: .topLeading) {
                    if script.body.isEmpty {
                        Text("Write or paste your script here.")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                    }

                    TextEditor(text: $script.body)
                        .frame(minHeight: 340)
                        .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle(script.title.isEmpty ? "Untitled Script" : script.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    ScriptStore.markUsed(script, in: modelContext)
                    showingTeleprompter = true
                } label: {
                    Label("Open Prompter", systemImage: "play.rectangle.fill")
                }
                .disabled(script.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .fullScreenCover(isPresented: $showingTeleprompter) {
            TeleprompterView(script: script)
        }
        .onChange(of: script.title) {
            ScriptStore.markUpdated(script, in: modelContext)
        }
        .onChange(of: script.body) {
            ScriptStore.markUpdated(script, in: modelContext)
        }
    }
}
