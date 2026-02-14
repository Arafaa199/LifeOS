import SwiftUI

/// Meal confirmation UX - frictionless yes/skip for inferred meals
/// No text input, no editing, just binary confirmation
struct MealConfirmationView: View {
    let meal: InferredMeal
    let onConfirm: () -> Void
    let onSkip: () -> Void

    @State private var isSubmitting = false
    @State private var offset: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            // Meal icon
            mealIcon

            VStack(alignment: .leading, spacing: 4) {
                // Meal type and time
                HStack {
                    Text(meal.mealType.capitalized)
                        .font(.headline)
                    Text(meal.mealTime)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Confidence indicator
                confidenceBar

                // Signals summary
                Text(signalsSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Action buttons (only show if not submitting)
            if !isSubmitting {
                HStack(spacing: 8) {
                    // Skip button
                    Button(action: {
                        isSubmitting = true
                        onSkip()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(NexusTheme.Colors.Semantic.red)
                            .frame(width: 32, height: 32)
                            .background(NexusTheme.Colors.Semantic.red.opacity(0.1))
                            .clipShape(Circle())
                    }

                    // Confirm button
                    Button(action: {
                        isSubmitting = true
                        onConfirm()
                    }) {
                        Image(systemName: "checkmark")
                            .foregroundColor(NexusTheme.Colors.Semantic.green)
                            .frame(width: 32, height: 32)
                            .background(NexusTheme.Colors.Semantic.green.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            } else {
                ProgressView()
            }
        }
        .padding()
        .background(NexusTheme.Colors.card)
        .cornerRadius(12)
        .offset(x: offset)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    offset = gesture.translation.width
                }
                .onEnded { gesture in
                    if gesture.translation.width > 100 {
                        // Swipe right = confirm
                        withAnimation {
                            offset = 500
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isSubmitting = true
                            onConfirm()
                        }
                    } else if gesture.translation.width < -100 {
                        // Swipe left = skip
                        withAnimation {
                            offset = -500
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isSubmitting = true
                            onSkip()
                        }
                    } else {
                        // Return to center
                        withAnimation {
                            offset = 0
                        }
                    }
                }
        )
    }

    private var mealIcon: some View {
        Image(systemName: iconName)
            .font(.title2)
            .foregroundColor(iconColor)
            .frame(width: 44, height: 44)
            .background(iconColor.opacity(0.1))
            .clipShape(Circle())
    }

    private var confidenceBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(NexusTheme.Colors.cardAlt)
                    .frame(height: 4)

                Rectangle()
                    .fill(confidenceColor)
                    .frame(width: geometry.size.width * CGFloat(meal.confidence), height: 4)
            }
        }
        .frame(height: 4)
    }

    private var iconName: String {
        switch meal.mealType.lowercased() {
        case "breakfast":
            return "sunrise.fill"
        case "lunch":
            return "sun.max.fill"
        case "dinner":
            return "moon.stars.fill"
        default:
            return "fork.knife"
        }
    }

    private var iconColor: Color {
        switch meal.mealType.lowercased() {
        case "breakfast":
            return NexusTheme.Colors.Semantic.amber
        case "lunch":
            return .yellow
        case "dinner":
            return NexusTheme.Colors.accent
        default:
            return .gray
        }
    }

    private var confidenceColor: Color {
        if meal.confidence >= 0.7 {
            return NexusTheme.Colors.Semantic.green
        } else if meal.confidence >= 0.4 {
            return NexusTheme.Colors.Semantic.amber
        } else {
            return NexusTheme.Colors.Semantic.red
        }
    }

    private var signalsSummary: String {
        let signals = meal.signalsUsed
        var parts: [String] = []

        if let source = signals["source"] as? String {
            parts.append(source.replacingOccurrences(of: "_", with: " "))
        }

        if let merchant = signals["merchant"] as? String {
            parts.append(merchant)
        }

        if let hoursAtHome = signals["hours_at_home"] as? Double {
            parts.append("\(String(format: "%.1f", hoursAtHome))h home")
        }

        if let tvOff = signals["tv_off"] as? Bool, tvOff {
            parts.append("TV off")
        }

        return parts.joined(separator: " · ")
    }
}

// MARK: - Data Model

struct InferredMeal: Identifiable, Codable {
    var id: String { "\(mealDate)-\(mealTime)" }
    let mealDate: String
    let mealTime: String
    let mealType: String
    let confidence: Double
    let inferenceSource: String
    let signalsUsed: [String: Any]

    enum CodingKeys: String, CodingKey {
        case mealDate = "meal_date"
        case mealTime = "meal_time"
        case mealType = "meal_type"
        case confidence
        case inferenceSource = "inference_source"
        case signalsUsed = "signals_used"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mealDate = try container.decode(String.self, forKey: .mealDate)
        mealTime = try container.decode(String.self, forKey: .mealTime)
        mealType = try container.decode(String.self, forKey: .mealType)
        confidence = try container.decode(Double.self, forKey: .confidence)
        inferenceSource = try container.decode(String.self, forKey: .inferenceSource)

        // Decode signals_used as generic JSON
        if let signalsDict = try? container.decode([String: AnyCodable].self, forKey: .signalsUsed) {
            signalsUsed = signalsDict.mapValues { $0.value }
        } else {
            signalsUsed = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mealDate, forKey: .mealDate)
        try container.encode(mealTime, forKey: .mealTime)
        try container.encode(mealType, forKey: .mealType)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(inferenceSource, forKey: .inferenceSource)
        // Note: signalsUsed encoding omitted for brevity
    }
}

// Helper for decoding Any type in JSON
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else {
            try container.encodeNil()
        }
    }
}

#Preview {
    let sampleMeal = try! JSONDecoder().decode(
        InferredMeal.self,
        from: """
        {
            "meal_date": "2026-01-25",
            "meal_time": "12:30:00",
            "meal_type": "lunch",
            "confidence": 0.6,
            "inference_source": "home_cooking",
            "signals_used": {
                "source": "home_location",
                "tv_off": true,
                "tv_hours": 0.0,
                "hours_at_home": 0.89
            }
        }
        """.data(using: .utf8)!
    )

    MealConfirmationView(
        meal: sampleMeal,
        onConfirm: { print("Confirmed") },
        onSkip: { print("Skipped") }
    )
    .padding()
}
