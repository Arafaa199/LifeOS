import AppIntents
import Foundation
import os

// MARK: - Meal Type Enum for App Intents

@available(iOS 17.0, *)
enum MealTypeIntent: String, AppEnum, CaseIterable {
    case breakfast = "breakfast"
    case lunch = "lunch"
    case dinner = "dinner"
    case snack = "snack"

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Meal Type")
    }

    static var caseDisplayRepresentations: [MealTypeIntent: DisplayRepresentation] {
        [
            .breakfast: DisplayRepresentation(title: "Breakfast", subtitle: "Morning meal"),
            .lunch: DisplayRepresentation(title: "Lunch", subtitle: "Midday meal"),
            .dinner: DisplayRepresentation(title: "Dinner", subtitle: "Evening meal"),
            .snack: DisplayRepresentation(title: "Snack", subtitle: "Between meals")
        ]
    }

    var displayName: String {
        rawValue.capitalized
    }
}

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
        // No default - user must provide actual weight to avoid logging incorrect data
        self.weightKg = 0.0
    }

    init(weightKg: Double) {
        self.weightKg = weightKg
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard weightKg >= 20, weightKg <= 500 else {
            return .result(dialog: "Please enter your actual weight (20-500 kg).")
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
    static var description = IntentDescription("Log what you ate to Nexus")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Food Description", description: "What did you eat?")
    var foodDescription: String

    @Parameter(title: "Meal Type", description: "Which meal is this?", default: .snack)
    var mealType: MealTypeIntent

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$foodDescription) as \(\.$mealType)")
    }

    init() {
        self.foodDescription = ""
        self.mealType = .snack
    }

    init(foodDescription: String, mealType: MealTypeIntent = .snack) {
        self.foodDescription = foodDescription
        self.mealType = mealType
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let logger = Logger(subsystem: "com.nexus", category: "LogFoodIntent")
        let trimmed = foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            logger.warning("Empty food description")
            return .result(dialog: "Please tell me what you ate")
        }

        guard trimmed.count >= 2 else {
            logger.warning("Description too short: \(trimmed)")
            return .result(dialog: "Please provide more detail about what you ate")
        }

        logger.info("Logging '\(trimmed)' as \(mealType.rawValue)")

        do {
            let response = try await NexusAPI.shared.logFood(
                trimmed,
                foodId: nil,
                mealType: mealType.rawValue
            )

            if response.success {
                logger.info("Successfully logged food")
                return .result(dialog: "Logged \(trimmed) as \(mealType.displayName)")
            } else {
                let errorMsg = response.message ?? "Unknown error"
                logger.error("API returned failure: \(errorMsg)")
                return .result(dialog: "Failed to log food: \(errorMsg)")
            }
        } catch {
            logger.error("Network error: \(error.localizedDescription)")
            return .result(dialog: "Could not connect to Nexus: \(error.localizedDescription)")
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

// MARK: - Log Expense Intent

@available(iOS 17.0, *)
struct LogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Expense"
    static var description = IntentDescription("Log an expense to Nexus")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Description", description: "What did you spend on?")
    var expenseDescription: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log expense: \(\.$expenseDescription)")
    }

    init() {
        self.expenseDescription = ""
    }

    init(expenseDescription: String) {
        self.expenseDescription = expenseDescription
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let logger = Logger(subsystem: "com.nexus", category: "LogExpenseIntent")
        let trimmed = expenseDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= 2 else {
            return .result(dialog: "Please describe what you spent on, e.g. 'coffee 15 AED'")
        }

        logger.info("Logging expense: '\(trimmed)'")

        do {
            let response = try await NexusAPI.shared.logExpense(trimmed)
            if response.success {
                if let amount = response.data?.totalSpent {
                    return .result(dialog: "Logged expense: \(trimmed). Total spent today: \(String(format: "%.0f", amount)) \(response.data?.currency ?? "AED").")
                }
                return .result(dialog: "Logged expense: \(trimmed).")
            } else {
                return .result(dialog: "Failed to log expense: \(response.message ?? "Unknown error")")
            }
        } catch {
            logger.error("Network error: \(error.localizedDescription)")
            return .result(dialog: "Could not connect to Nexus: \(error.localizedDescription)")
        }
    }
}

// MARK: - Check Recovery Intent

@available(iOS 17.0, *)
struct CheckRecoveryIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Recovery"
    static var description = IntentDescription("Get your WHOOP recovery score from Nexus")
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Check recovery score")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let response = try await NexusAPI.shared.refreshWHOOP()
            if response.success, let recovery = response.recovery {
                let score = Int(recovery)
                let label: String
                if score >= 67 { label = "Green — well recovered" }
                else if score >= 34 { label = "Yellow — moderate recovery" }
                else { label = "Red — take it easy" }
                return .result(dialog: "Recovery: \(score)%. \(label).")
            } else {
                return .result(dialog: "Could not fetch recovery. \(response.message ?? "Try again later.")")
            }
        } catch {
            return .result(dialog: "Could not connect to Nexus: \(error.localizedDescription)")
        }
    }
}

// MARK: - Budget Status Intent

@available(iOS 17.0, *)
struct CheckBudgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Budget"
    static var description = IntentDescription("Get your budget status from Nexus")
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Check budget status")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let response = try await NexusAPI.shared.fetchBudgets()
            guard response.success, let budgets = response.data?.budgets, !budgets.isEmpty else {
                return .result(dialog: "No budgets configured yet.")
            }

            let lines = budgets.prefix(5).map { budget -> String in
                let spent = budget.spent ?? 0
                let remaining = budget.remaining ?? (budget.budgetAmount - spent)
                let pct = budget.budgetAmount > 0 ? Int(spent / budget.budgetAmount * 100) : 0
                let warning = pct >= 90 ? " ⚠" : ""
                return "\(budget.category): \(Int(remaining)) left (\(pct)%)\(warning)"
            }

            return .result(dialog: "Budget status:\n\(lines.joined(separator: "\n"))")
        } catch {
            return .result(dialog: "Could not connect to Nexus: \(error.localizedDescription)")
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
                "Log \(\.$mealType) in \(.applicationName)",
                "Add meal to \(.applicationName)",
                "Track food in \(.applicationName)",
                "I ate in \(.applicationName)"
            ],
            shortTitle: "Log Food",
            systemImageName: "leaf.fill"
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

        // Log expense
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Log expense in \(.applicationName)",
                "Add expense to \(.applicationName)",
                "I spent in \(.applicationName)",
                "Track spending in \(.applicationName)"
            ],
            shortTitle: "Log Expense",
            systemImageName: "creditcard.fill"
        )

        // Check recovery
        AppShortcut(
            intent: CheckRecoveryIntent(),
            phrases: [
                "Check recovery in \(.applicationName)",
                "What's my recovery in \(.applicationName)",
                "How recovered am I in \(.applicationName)"
            ],
            shortTitle: "Check Recovery",
            systemImageName: "heart.fill"
        )

        // Check budget
        AppShortcut(
            intent: CheckBudgetIntent(),
            phrases: [
                "Check budget in \(.applicationName)",
                "Budget status in \(.applicationName)",
                "How much have I spent in \(.applicationName)"
            ],
            shortTitle: "Check Budget",
            systemImageName: "chart.bar.fill"
        )
    }
}
