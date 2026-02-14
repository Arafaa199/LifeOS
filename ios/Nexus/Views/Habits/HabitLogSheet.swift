import SwiftUI

struct HabitLogSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onCreate: (CreateHabitRequest) async -> Bool

    @State private var name = ""
    @State private var category = "health"
    @State private var frequency = "daily"
    @State private var targetCount = 1
    @State private var icon = "circle"
    @State private var color = "#4FC3F7"
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let categories = ["health", "fitness", "productivity", "mindfulness"]
    private let frequencies = ["daily", "weekly"]
    private let icons = [
        "drop.fill", "leaf.fill", "figure.run", "figure.martial.arts",
        "scalemass", "fork.knife", "book.fill", "brain.head.profile",
        "bed.double.fill", "heart.fill", "pills.fill", "sun.max.fill",
        "moon.fill", "pencil", "checkmark.circle", "star.fill"
    ]
    private let colors = [
        "#4FC3F7", "#FF7043", "#66BB6A", "#AB47BC",
        "#FFA726", "#EF5350", "#42A5F5", "#26A69A"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit") {
                    TextField("Name", text: $name)

                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat.capitalized).tag(cat)
                        }
                    }

                    Picker("Frequency", selection: $frequency) {
                        ForEach(frequencies, id: \.self) { freq in
                            Text(freq.capitalized).tag(freq)
                        }
                    }

                    Stepper("Target: \(targetCount)", value: $targetCount, in: 1...20)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(icons, id: \.self) { ic in
                            Button {
                                icon = ic
                            } label: {
                                Image(systemName: ic)
                                    .font(.system(size: 20))
                                    .foregroundColor(icon == ic ? NexusTheme.Colors.accent : NexusTheme.Colors.textSecondary)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        icon == ic
                                            ? NexusTheme.Colors.accent.opacity(0.15)
                                            : Color.clear
                                    )
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.vertical, NexusTheme.Spacing.xs)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(colors, id: \.self) { hex in
                            Button {
                                color = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: color == hex ? 3 : 0)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(NexusTheme.Colors.accent, lineWidth: color == hex ? 2 : 0)
                                    )
                            }
                        }
                    }
                    .padding(.vertical, NexusTheme.Spacing.xs)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(NexusTheme.Colors.Semantic.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        isSubmitting = true
        errorMessage = nil
        let request = CreateHabitRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            category: category,
            frequency: frequency,
            targetCount: targetCount,
            icon: icon,
            color: color
        )
        Task {
            let success = await onCreate(request)
            if !success {
                errorMessage = "Failed to create habit"
                isSubmitting = false
            }
        }
    }
}

#Preview {
    HabitLogSheet { _ in true }
}
