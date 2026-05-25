import Foundation
import SwiftData

@Model
final class Script {
    @Attribute(.unique) var id: UUID
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?

    @Relationship(deleteRule: .cascade) var settings: PrompterSettings

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        settings: PrompterSettings = PrompterSettings()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.settings = settings
    }

    func markUpdated() {
        updatedAt = Date()
    }

    func markUsed() {
        lastUsedAt = Date()
    }
}

extension Script {
    static var sampleScripts: [Script] {
        [
            Script(
                title: "Welcome Read",
                body: """
                Welcome to SmartCue.

                This sample script is here so you can open the teleprompter immediately, tune the reading size, adjust the scroll speed, and see how the display feels in portrait or landscape.

                A calm pace usually lands around short paragraphs, clean line breaks, and enough margin for your eyes to travel without strain.
                """
            ),
            Script(
                title: "Product Update",
                body: """
                Good morning everyone.

                Today we are walking through the latest product update, the customer problems it solves, and what the team should expect next.

                The headline is simple: we made the everyday workflow faster, reduced the number of manual steps, and created a cleaner foundation for the next release.

                Thank you for the thoughtful feedback that shaped this work.
                """
            ),
            Script(
                title: "Interview Opener",
                body: """
                Thanks for joining me today.

                I want to start with the story behind the work, then move into the decisions that shaped it, and finally talk about what surprised you along the way.

                Let us begin with the moment you realized this was worth building.
                """
            )
        ]
    }
}
