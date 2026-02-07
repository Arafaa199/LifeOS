import SwiftUI

struct NutritionHistoryView: View {
    @StateObject private var viewModel = NutritionViewModel()
    @State private var showDatePicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                dateSelector
                totalsCard
                foodTimelineSection
                waterSection
                logFoodButton
            }
            .padding()
        }
        .background(NexusTheme.Colors.background)
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadHistory()
        }
        .refreshable {
            await viewModel.loadHistory()
        }
    }

    // MARK: - Date Selector

    private var dateSelector: some View {
        HStack {
            Button {
                viewModel.setDate(Calendar.current.date(byAdding: .day, value: -1, to: viewModel.selectedDate) ?? viewModel.selectedDate)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.accentColor)
            }
            .accessibilityLabel("Previous day")

            Spacer()

            Button {
                showDatePicker.toggle()
            } label: {
                Text(formattedDate)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .sheet(isPresented: $showDatePicker) {
                NavigationView {
                    DatePicker(
                        "Select Date",
                        selection: $viewModel.selectedDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Select Date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showDatePicker = false
                                Task {
                                    await viewModel.loadHistory()
                                }
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }

            Spacer()

            Button {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: viewModel.selectedDate) ?? viewModel.selectedDate
                if tomorrow <= Date() {
                    viewModel.setDate(tomorrow)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(isToday ? .secondary : .accentColor)
            }
            .disabled(isToday)
            .accessibilityLabel("Next day")
        }
        .padding()
        .background(NexusTheme.Colors.card)
        .cornerRadius(12)
    }

    private var formattedDate: String {
        if isToday {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: viewModel.selectedDate)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(viewModel.selectedDate)
    }

    // MARK: - Totals Card

    private var totalsCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                totalItem(value: "\(viewModel.dailyTotals?.calories ?? 0)", label: "Calories", icon: "flame.fill", color: NexusTheme.Colors.Semantic.amber)
                totalItem(value: String(format: "%.1fg", viewModel.dailyTotals?.protein_g ?? 0), label: "Protein", icon: "circle.grid.cross.fill", color: NexusTheme.Colors.Semantic.purple)
            }

            HStack(spacing: 20) {
                totalItem(value: String(format: "%.1fg", viewModel.dailyTotals?.carbs_g ?? 0), label: "Carbs", icon: "leaf.fill", color: NexusTheme.Colors.Semantic.green)
                totalItem(value: String(format: "%.1fg", viewModel.dailyTotals?.fat_g ?? 0), label: "Fat", icon: "drop.fill", color: .yellow)
            }

            Divider()

            HStack {
                Image(systemName: "drop.fill")
                    .foregroundColor(NexusTheme.Colors.Semantic.blue)
                Text("\(viewModel.dailyTotals?.water_ml ?? 0) ml water")
                    .font(.subheadline)
                Spacer()
                Text("\(viewModel.dailyTotals?.meals_logged ?? 0) meals logged")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(NexusTheme.Colors.card)
        .cornerRadius(16)
    }

    private func totalItem(value: String, label: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Food Timeline

    private var foodTimelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meals")
                .font(.headline)

            if viewModel.foodEntries.isEmpty {
                emptyState(message: "No meals logged", icon: "fork.knife")
            } else {
                ForEach(viewModel.foodEntriesByMeal, id: \.0) { mealType, entries in
                    mealGroupSection(mealType: mealType, entries: entries)
                }
            }
        }
    }

    private func mealGroupSection(mealType: String, entries: [FoodLogEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mealType)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            ForEach(entries) { entry in
                foodEntryRow(entry)
            }
        }
    }

    private func foodEntryRow(_ entry: FoodLogEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.sourceIcon)
                .foregroundColor(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.description ?? "Food entry")
                    .font(.subheadline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let calories = entry.calories, calories > 0 {
                        Text("\(calories) cal")
                            .font(.caption)
                            .foregroundColor(NexusTheme.Colors.Semantic.amber)
                    }

                    if let protein = entry.protein_g, protein > 0 {
                        Text("\(Int(protein))g protein")
                            .font(.caption)
                            .foregroundColor(NexusTheme.Colors.Semantic.purple)
                    }

                    Spacer()

                    Text(entry.formattedTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(NexusTheme.Colors.card)
        .cornerRadius(10)
    }

    // MARK: - Water Section

    private var waterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Water")
                    .font(.headline)

                Spacer()

                NavigationLink(destination: WaterLogView()) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(NexusTheme.Colors.Semantic.blue)
                }
            }

            if viewModel.waterEntries.isEmpty {
                emptyState(message: "No water logged", icon: "drop")
            } else {
                VStack(spacing: 6) {
                    ForEach(viewModel.waterEntries) { entry in
                        HStack {
                            Image(systemName: "drop.fill")
                                .foregroundColor(NexusTheme.Colors.Semantic.blue)
                                .frame(width: 24)

                            Text("\(entry.amount_ml) ml")
                                .font(.subheadline)

                            Spacer()

                            Text(entry.formattedTime)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(NexusTheme.Colors.card)
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    // MARK: - Log Food Button

    private var logFoodButton: some View {
        NavigationLink(destination: FoodLogView(viewModel: DashboardViewModel())) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Log Food")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .cornerRadius(12)
        }
        .padding(.top, 8)
    }

    // MARK: - Empty State

    private func emptyState(message: String, icon: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 24)
            Spacer()
        }
        .background(NexusTheme.Colors.card)
        .cornerRadius(12)
    }
}

#Preview {
    NavigationView {
        NutritionHistoryView()
    }
}
