import Foundation
import SwiftUI
import Combine

@MainActor
class DocumentsViewModel: ObservableObject {
    @Published var documents: [Document] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var renewalHistory: [DocumentRenewal] = []
    @Published var isLoadingHistory = false

    private let api = NexusAPI.shared
    private let coordinator = SyncCoordinator.shared
    private var cancellables = Set<AnyCancellable>()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var activeDocuments: [Document] {
        documents.filter { $0.urgency == "ok" }
    }

    var expiringSoon: [Document] {
        documents.filter { $0.urgency == "critical" || $0.urgency == "warning" }
    }

    var expiredDocuments: [Document] {
        documents.filter { $0.urgency == "expired" }
    }

    init() {
        coordinator.$documentsResult
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] docs in
                self?.documents = docs
                self?.isLoading = false
            }
            .store(in: &cancellables)
    }

    func loadDocuments() async {
        isLoading = true
        errorMessage = nil
        do {
            let response: DocumentsResponse = try await api.get("/webhook/nexus-documents")
            documents = response.documents
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @discardableResult
    func createDocument(
        docType: String,
        label: String,
        issuer: String?,
        issuingCountry: String?,
        docNumber: String?,
        issueDate: Date?,
        expiryDate: Date,
        notes: String?,
        remindersEnabled: Bool
    ) async -> Bool {
        errorMessage = nil
        let request = CreateDocumentRequest(
            clientId: UUID(),
            docType: docType,
            label: label,
            issuer: issuer?.isEmpty == true ? nil : issuer,
            issuingCountry: issuingCountry?.isEmpty == true ? nil : issuingCountry,
            docNumber: docNumber?.isEmpty == true ? nil : docNumber,
            issueDate: issueDate.map { Self.dateFormatter.string(from: $0) },
            expiryDate: Self.dateFormatter.string(from: expiryDate),
            notes: notes?.isEmpty == true ? nil : notes,
            remindersEnabled: remindersEnabled
        )
        do {
            let _: SingleDocumentResponse = try await api.post("/webhook/nexus-document", body: request, decoder: JSONDecoder())
            await loadDocuments()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateDocument(
        id: Int,
        docType: String,
        label: String,
        issuer: String?,
        issuingCountry: String?,
        docNumber: String?,
        issueDate: String?,
        expiryDate: String,
        notes: String?,
        remindersEnabled: Bool
    ) async -> Bool {
        errorMessage = nil
        let request = UpdateDocumentRequest(
            id: id,
            docType: docType,
            label: label,
            issuer: issuer,
            issuingCountry: issuingCountry,
            docNumber: docNumber,
            issueDate: issueDate,
            expiryDate: expiryDate,
            notes: notes,
            remindersEnabled: remindersEnabled,
            status: nil
        )
        do {
            let _: SingleDocumentResponse = try await api.post("/webhook/nexus-document-update", body: request, decoder: JSONDecoder())
            await loadDocuments()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteDocument(id: Int) async -> Bool {
        errorMessage = nil
        do {
            let _: DeleteDocumentResponse = try await api.delete("/webhook/nexus-document?id=\(id)")
            documents.removeAll { $0.id == id }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func renewDocument(id: Int, newExpiryDate: Date, newDocNumber: String?, notes: String?) async -> Bool {
        errorMessage = nil
        let request = RenewDocumentRequest(
            id: id,
            newExpiryDate: Self.dateFormatter.string(from: newExpiryDate),
            newDocNumber: newDocNumber?.isEmpty == true ? nil : newDocNumber,
            notes: notes?.isEmpty == true ? nil : notes
        )
        do {
            let _: SingleDocumentResponse = try await api.post("/webhook/nexus-document-renew", body: request, decoder: JSONDecoder())
            await loadDocuments()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func recreateReminders(id: Int) async -> Bool {
        errorMessage = nil
        struct Body: Encodable { let id: Int }
        do {
            let _: RecreateRemindersResponse = try await api.post("/webhook/nexus-document-recreate-reminders", body: Body(id: id), decoder: JSONDecoder())
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func loadRenewalHistory(documentId: Int) async {
        isLoadingHistory = true
        do {
            let response: RenewalHistoryResponse = try await api.get("/webhook/nexus-document-renewals?id=\(documentId)")
            renewalHistory = response.renewals
        } catch {
            renewalHistory = []
        }
        isLoadingHistory = false
    }
}
