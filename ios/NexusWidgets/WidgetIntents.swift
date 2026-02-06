import AppIntents
import Foundation

// MARK: - Quick Water Log Intent

@available(iOS 17.0, *)
struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description = IntentDescription("Log water intake to Nexus")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount (ml)", description: "Amount of water in milliliters")
    var amount: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) ml of water")
    }

    init() {
        self.amount = 250
    }

    init(amount: Int) {
        self.amount = amount
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0, amount <= 10000 else {
            return .result(dialog: "Please enter a valid amount between 1 and 10,000 ml.")
        }

        do {
            let response = try await NexusAPI.shared.logWater(amountML: amount)
            if response.success {
                let totalWater = response.data?.total_water_ml ?? amount
                return .result(dialog: "Logged \(amount) ml of water. Total today: \(totalWater) ml.")
            } else {
                return .result(dialog: "Failed to log water: \(response.message ?? "Unknown error")")
            }
        } catch {
            return .result(dialog: "Could not connect to Nexus: \(error.localizedDescription)")
        }
    }
}

// MARK: - Mood Log Intent

@available(iOS 17.0, *)
struct LogMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Mood"
    static var description = IntentDescription("Log your mood and energy level to Nexus")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Mood Score", description: "Your mood from 1 (lowest) to 10 (highest)")
    var moodScore: Int

    @Parameter(title: "Energy Level", description: "Your energy from 1 (lowest) to 10 (highest)", default: 5)
    var energyLevel: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Log mood \(\.$moodScore) with energy \(\.$energyLevel)")
    }

    init() {
        self.moodScore = 5
        self.energyLevel = 5
    }

    init(moodScore: Int, energyLevel: Int = 5) {
        self.moodScore = moodScore
        self.energyLevel = energyLevel
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard (1...10).contains(moodScore) else {
            return .result(dialog: "Please enter a mood score between 1 and 10.")
        }
        guard (1...10).contains(energyLevel) else {
            return .result(dialog: "Please enter an energy level between 1 and 10.")
        }

        do {
            let response = try await NexusAPI.shared.logMood(mood: moodScore, energy: energyLevel, notes: nil)
            if response.success {
                return .result(dialog: "Logged mood \(moodScore)/10 with energy \(energyLevel)/10.")
            } else {
                return .result(dialog: "Failed to log mood: \(response.message ?? "Unknown error")")
            }
        } catch {
            return .result(dialog: "Could not connect to Nexus: \(error.localizedDescription)")
        }
    }
}

// MARK: - Weight Log Intent

@available(iOS 17.0, *)
struct LogWeightIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Weight"
    static var description = IntentDescription("Log your body weight to Nexus")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Weight (kg)", description: "Your weight in kilograms")
    var weightKg: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Log weight \(\.$weightKg) kg")
    }

    init() {
        self.weightKg = 70.0
    }

    init(weightKg: Double) {
        self.weightKg = weightKg
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard weightKg > 0, weightKg <= 500 else {
            return .result(dialog: "Please enter a valid weight between 1 and 500 kg.")
        }

        do {
            let response = try await NexusAPI.shared.logWeight(kg: weightKg)
            if response.success {
                return .result(dialog: "Logged weight: \(String(format: "%.1f", weightKg)) kg.")
            } else {
                return .result(dialog: "Failed to log weight: \(response.message ?? "Unknown error")")
            }
        } catch {
            return .result(dialog: "Could not connect to Nexus: \(error.localizedDescription)")
        }
    }
}

// MARK: - Start Fast Intent

@available(iOS 17.0, *)
struct StartFastIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Fast"
    static var description = IntentDescription("Start a fasting session in Nexus")
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Start a fast")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let response = try await NexusAPI.shared.startFast()
            if response.effectiveSuccess {
                return .result(dialog: "Fasting session started. Good luck!")
            } else {
                let errorMsg = response.error ?? response.result?.error ?? "Unknown error"
                return .result(dialog: "Failed to start fast: \(errorMsg)")
            }
        } catch {
            return .result(dialog: "Could not connect to Nexus: \(error.localizedDescription)")
        }
    }
}

// MARK: - Break Fast Intent

@available(iOS 17.0, *)
struct BreakFastIntent: AppIntent {
    static var title: LocalizedStringResource = "Break Fast"
    static var description = IntentDescription("End your fasting session in Nexus")
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Break your fast")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let response = try await NexusAPI.shared.breakFast()
            if response.effectiveSuccess {
                if let duration = response.effectiveDurationHours {
                    let hours = Int(duration)
                    let minutes = Int((duration - Double(hours)) * 60)
                    return .result(dialog: "Fast completed! Duration: \(hours)h \(minutes)m. Well done!")
                }
                return .result(dialog: "Fast completed! Well done!")
            } else {
                let errorMsg = response.error ?? response.result?.error ?? "Unknown error"
                return .result(dialog: "Failed to break fast: \(errorMsg)")
            }
        } catch {
            return .result(dialog: "Could not connect to Nexus: \(error.localizedDescription)")
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
            return .result(dialog: IntentDialog("Please provide a food description"))
        }

        do {
            let response = try await NexusAPI.shared.logFood(foodDescription)

            if response.success {
                return .result(dialog: IntentDialog("Logged: \(foodDescription)"))
            } else {
                return .result(dialog: IntentDialog("Failed to log food"))
            }
        } catch {
            return .result(dialog: IntentDialog("Error: \(error.localizedDescription)"))
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
            return .result(dialog: IntentDialog("Please provide a description"))
        }

        do {
            let response = try await NexusAPI.shared.logUniversal(text)

            if response.success {
                return .result(dialog: IntentDialog(stringLiteral: response.message ?? "Logged successfully"))
            } else {
                return .result(dialog: IntentDialog(stringLiteral: response.message ?? "Failed to log"))
            }
        } catch {
            return .result(dialog: IntentDialog("Error: \(error.localizedDescription)"))
        }
    }
}

// MARK: - App Shortcuts Provider

@available(iOS 17.0, *)
struct NexusAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Water logging
        AppShortcut(
            intent: LogWaterIntent(amount: 250),
            phrases: [
                "Log water in \(.applicationName)",
                "Add water to \(.applicationName)",
                "Track water in \(.applicationName)"
            ],
            shortTitle: "Log Water",
            systemImageName: "drop.fill"
        )

        // Food logging
        AppShortcut(
            intent: LogFoodIntent(),
            phrases: [
                "Log food in \(.applicationName)",
                "Add meal to \(.applicationName)",
                "Track food in \(.applicationName)"
            ],
            shortTitle: "Log Food",
            systemImageName: "fork.knife"
        )

        // Mood logging
        AppShortcut(
            intent: LogMoodIntent(),
            phrases: [
                "Log mood in \(.applicationName)",
                "Track my mood in \(.applicationName)",
                "Record mood in \(.applicationName)"
            ],
            shortTitle: "Log Mood",
            systemImageName: "face.smiling"
        )

        // Weight logging
        AppShortcut(
            intent: LogWeightIntent(),
            phrases: [
                "Log weight in \(.applicationName)",
                "Track weight in \(.applicationName)",
                "Record weight in \(.applicationName)"
            ],
            shortTitle: "Log Weight",
            systemImageName: "scalemass"
        )

        // Start fasting
        AppShortcut(
            intent: StartFastIntent(),
            phrases: [
                "Start my fast in \(.applicationName)",
                "Begin fasting in \(.applicationName)",
                "Start fasting in \(.applicationName)"
            ],
            shortTitle: "Start Fast",
            systemImageName: "timer"
        )

        // Break fasting
        AppShortcut(
            intent: BreakFastIntent(),
            phrases: [
                "Break my fast in \(.applicationName)",
                "End my fast in \(.applicationName)",
                "Stop fasting in \(.applicationName)"
            ],
            shortTitle: "Break Fast",
            systemImageName: "checkmark.circle"
        )

        // Universal logging
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
    }
}
