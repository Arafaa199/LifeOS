import SwiftUI
import Combine

struct FoodSearchView: View {
    let onSelect: (FoodSearchResult) -> Void

    @StateObject private var viewModel = FoodSearchViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            if viewModel.isLoading {
                Spacer()
                ProgressView("Searching...")
                Spacer()
            } else if let error = viewModel.errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else if viewModel.results.isEmpty && !viewModel.query.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No results for \"\(viewModel.query)\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if viewModel.results.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.nexusFood.opacity(0.4))
                    Text("Search 2.4M foods by name or brand")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                resultsList
            }
        }
        .background(Color.nexusBackground)
        .navigationTitle("Search Foods")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search foods...", text: $viewModel.query)
                .textFieldStyle(PlainTextFieldStyle())
                .autocorrectionDisabled()

            if !viewModel.query.isEmpty {
                Button(action: { viewModel.query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding()
    }

    private var resultsList: some View {
        List(viewModel.results) { food in
            Button(action: {
                onSelect(food)
                dismiss()
            }) {
                FoodResultRow(food: food)
            }
            .listRowBackground(Color(.systemBackground))
        }
        .listStyle(.plain)
    }
}

struct FoodResultRow: View {
    let food: FoodSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(food.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(2)

            if let brand = food.brand, !brand.isEmpty {
                Text(brand)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                macroLabel("Cal", value: food.calories_per_100g, format: "%.0f", color: .nexusFood)
                macroLabel("P", value: food.protein_per_100g, format: "%.1fg", color: .nexusPrimary)
                macroLabel("C", value: food.carbs_per_100g, format: "%.1fg", color: .nexusWarning)
                macroLabel("F", value: food.fat_per_100g, format: "%.1fg", color: .yellow)
            }
            .font(.caption2)

            if let serving = food.serving_description, !serving.isEmpty {
                Text("Serving: \(serving)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func macroLabel(_ label: String, value: Double?, format: String, color: Color) -> some View {
        if let v = value {
            HStack(spacing: 2) {
                Text(label)
                    .fontWeight(.medium)
                    .foregroundColor(color)
                Text(String(format: format, v))
                    .foregroundColor(.primary)
            }
        }
    }
}

@MainActor
class FoodSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [FoodSearchResult] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var searchCancellable: AnyCancellable?
    private let api = NexusAPI.shared

    init() {
        searchCancellable = $query
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self else { return }
                Task { await self.search(query) }
            }
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await api.searchFoods(query: trimmed, limit: 20)
            results = response.data ?? []
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
    }
}
