import AppIntents
import Foundation

// MARK: - Quick Water Log Intent

@available(iOS 17.0, *)
struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description = IntentDescription("Quickly log water intake")

    @Parameter(title: "Amount (ml)")
    var amount: Int

    init() {
        self.amount = 250
    }

    init(amount: Int) {
        self.amount = amount
    }

    func perform() async throws -> some IntentResult {
        // Log water via API
        do {
            let response = try await NexusAPI.shared.logWater(amount)

            if response.success {
                return .result(dialog: "Logged \(amount)ml of water")
            } else {
                return .result(dialog: "Failed to log water")
            }
        } catch {
            return .result(dialog: "Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Quick Food Log Intent

@available(iOS 17.0, *)
struct LogFoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Food"
    static var description = IntentDescription("Quickly log a meal or snack")

    @Parameter(title: "Description")
    var foodDescription: String

    init() {
        self.foodDescription = ""
    }

    init(foodDescription: String) {
        self.foodDescription = foodDescription
    }

    func perform() async throws -> some IntentResult {
        guard !foodDescription.isEmpty else {
            return .result(dialog: "Please provide a food description")
        }

        do {
            let response = try await NexusAPI.shared.logFood(foodDescription)

            if response.success {
                return .result(dialog: "Logged: \(foodDescription)")
            } else {
                return .result(dialog: "Failed to log food")
            }
        } catch {
            return .result(dialog: "Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Universal Log Intent

@available(iOS 17.0, *)
struct UniversalLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Log to Nexus"
    static var description = IntentDescription("Log anything to Nexus with natural language")

    @Parameter(title: "What did you do?")
    var text: String

    init() {
        self.text = ""
    }

    init(text: String) {
        self.text = text
    }

    func perform() async throws -> some IntentResult {
        guard !text.isEmpty else {
            return .result(dialog: "Please provide a description")
        }

        do {
            let response = try await NexusAPI.shared.logUniversal(text)

            if response.success {
                return .result(dialog: response.message ?? "Logged successfully")
            } else {
                return .result(dialog: response.message ?? "Failed to log")
            }
        } catch {
            return .result(dialog: "Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - App Shortcuts Provider

@available(iOS 17.0, *)
struct NexusAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWaterIntent(amount: 250),
            phrases: [
                "Log water in \(.applicationName)",
                "Add water to \(.applicationName)",
                "I drank water"
            ],
            shortTitle: "Log Water",
            systemImageName: "drop.fill"
        )

        AppShortcut(
            intent: UniversalLogIntent(),
            phrases: [
                "Log to \(.applicationName)",
                "Add entry to \(.applicationName)",
                "Track in \(.applicationName)"
            ],
            shortTitle: "Log to Nexus",
            systemImageName: "plus.circle.fill"
        )

        AppShortcut(
            intent: LogFoodIntent(),
            phrases: [
                "Log food in \(.applicationName)",
                "Add meal to \(.applicationName)",
                "I ate \(\.$foodDescription)"
            ],
            shortTitle: "Log Food",
            systemImageName: "fork.knife"
        )
    }
}
