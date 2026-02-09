import Combine
import Foundation

@MainActor
class FinancialPositionViewModel: ObservableObject {
    @Published var position: FinancialPositionResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = FinanceAPI.shared

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            position = try await api.fetchFinancialPosition()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
