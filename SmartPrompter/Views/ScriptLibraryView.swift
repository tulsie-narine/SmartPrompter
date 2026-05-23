import SwiftData
import SwiftUI

struct ScriptLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Script.updatedAt, order: .reverse) private var scripts: [Script]

    @State private var searchText = ""
    @State private var createdScript: Script?

    private var displayedScripts: [Script] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return scripts }

        return scripts.filter { script in
            script.title.localizedCaseInsensitiveContains(query)
                || script.body.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if displayedScripts.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Scripts" : "No Results",
                        systemImage: searchText.isEmpty ? "doc.text" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Create your first script to get started." : "Try another title or phrase.")
                    )
                } else {
                    List {
                        ForEach(displayedScripts) { script in
                            NavigationLink {
                                ScriptEditorView(script: script)
                            } label: {
                                ScriptRowView(script: script)
                            }
                        }
                        .onDelete(perform: deleteScripts)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("SmartPrompter")
            .searchable(text: $searchText, prompt: "Search scripts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: createScript) {
                        Label("New Script", systemImage: "plus")
                    }
                }
            }
            .task {
                ScriptStore.seedSamplesIfNeeded(in: modelContext)
            }
            .sheet(item: $createdScript) { script in
                NavigationStack {
                    ScriptEditorView(script: script)
                }
            }
        }
    }

    private func createScript() {
        createdScript = ScriptStore.createScript(in: modelContext)
    }

    private func deleteScripts(at offsets: IndexSet) {
        let scriptsToDelete = offsets.map { displayedScripts[$0] }
        scriptsToDelete.forEach { ScriptStore.delete($0, in: modelContext) }
    }
}

private struct ScriptRowView: View {
    let script: Script

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(script.title.isEmpty ? "Untitled Script" : script.title)
                .font(.headline)
                .lineLimit(1)

            Text(script.bodyPreview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label(script.updatedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")

                if let lastUsedAt = script.lastUsedAt {
                    Label(lastUsedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "play.circle")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}

private extension Script {
    var bodyPreview: String {
        let preview = body
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return preview.isEmpty ? "No script body yet." : preview
    }
}
