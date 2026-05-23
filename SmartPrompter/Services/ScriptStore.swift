import Foundation
import SwiftData

@MainActor
enum ScriptStore {
    static func seedSamplesIfNeeded(in modelContext: ModelContext) {
        var descriptor = FetchDescriptor<Script>()
        descriptor.fetchLimit = 1

        do {
            let existingScripts = try modelContext.fetch(descriptor)
            guard existingScripts.isEmpty else { return }

            Script.sampleScripts.forEach { modelContext.insert($0) }
            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed sample scripts: \(error)")
        }
    }

    @discardableResult
    static func createScript(in modelContext: ModelContext) -> Script {
        let script = Script(
            title: "Untitled Script",
            body: ""
        )

        modelContext.insert(script)
        save(modelContext)
        return script
    }

    static func delete(_ script: Script, in modelContext: ModelContext) {
        modelContext.delete(script)
        save(modelContext)
    }

    static func markUpdated(_ script: Script, in modelContext: ModelContext) {
        script.markUpdated()
        save(modelContext)
    }

    static func markUsed(_ script: Script, in modelContext: ModelContext) {
        script.markUsed()
        save(modelContext)
    }

    static func save(_ modelContext: ModelContext) {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save SmartPrompter data: \(error)")
        }
    }
}
