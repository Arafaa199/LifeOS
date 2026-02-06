import AppIntents
import Foundation

// Minimal intents for widget buttons - opens app to complete action
// Full Siri intents are in main app: Nexus/Widgets/WidgetIntents.swift

@available(iOS 17.0, *)
struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description = IntentDescription("Log water intake")
    static var openAppWhenRun: Bool = true  // Opens app to complete

    @Parameter(title: "Amount (ml)")
    var amount: Int

    init() {
        self.amount = 250
    }

    init(amount: Int) {
        self.amount = amount
    }

    func perform() async throws -> some IntentResult {
        // Widget opens app - actual logging happens there
        // SharedStorage update happens when app syncs
        return .result()
    }
}
