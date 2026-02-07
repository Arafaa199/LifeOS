import Foundation
import SwiftUI
import Combine
import os

@MainActor
class DocumentsViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.nexus.lifeos", category: "documents")
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
            logger.info("Fetched \(response.documents.count) documents")
        } catch let decodingError as DecodingError {
            switch decodingError {
            case .typeMismatch(let type, let context):
                logger.error("Decode TypeMismatch: expected \(String(describing: type)), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .keyNotFound(let key, let context):
                logger.error("Decode KeyNotFound: \(key.stringValue), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .valueNotFound(let type, let context):
                logger.error("Decode ValueNotFound: \(String(describing: type)), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .dataCorrupted(let context):
                logger.error("Decode DataCorrupted: \(context.debugDescription)")
            @unknown default:
                logger.error("Decode unknown error: \(decodingError.localizedDescription)")
            }
            errorMessage = "Failed to parse documents"
        } catch {
            logger.error("Fetch error: \(error.localizedDescription)")
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
            let response: SingleDocumentResponse = try await api.post("/webhook/nexus-document", body: request, decoder: JSONDecoder())
            logger.info("Created document id=\(response.document?.id ?? -1)")

            if let newDoc = response.document {
                documents.append(newDoc)
            }

            await loadDocuments()
            return true  // Success - POST worked
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
            let response: SingleDocumentResponse = try await api.post("/webhook/nexus-document-update", body: request, decoder: JSONDecoder())
            logger.info("Updated document id=\(response.document?.id ?? id)")

            if let updatedDoc = response.document,
               let index = documents.firstIndex(where: { $0.id == id }) {
                documents[index] = updatedDoc
            }

            await loadDocuments()
            return true  // Success - POST worked
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
            let response: SingleDocumentResponse = try await api.post("/webhook/nexus-document-renew", body: request, decoder: JSONDecoder())
            logger.info("Renewed document id=\(response.document?.id ?? id)")

            if let renewedDoc = response.document,
               let index = documents.firstIndex(where: { $0.id == id }) {
                documents[index] = renewedDoc
            }

            await loadDocuments()
            return true  // Success - POST worked
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
            logger.error("Failed to load renewal history: \(error.localizedDescription)")
            renewalHistory = []
        }
        isLoadingHistory = false
    }
}
