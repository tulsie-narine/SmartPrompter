import SwiftData
import SwiftUI

@main
struct SmartPrompterApp: App {
    private let modelContainer: ModelContainer = {
        let schema = Schema([
            Script.self,
            PrompterSettings.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create SmartPrompter model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ScriptLibraryView()
        }
        .modelContainer(modelContainer)
    }
}
