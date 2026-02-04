import Foundation

struct Document: Identifiable, Codable {
    let id: Int
    let clientId: UUID?
    let docType: String
    let label: String
    let issuer: String?
    let issuingCountry: String?
    let docNumber: String?
    let issueDate: String?
    let expiryDate: String
    let notes: String?
    let remindersEnabled: Bool
    let status: String
    let createdAt: String?
    let updatedAt: String?
    let daysUntilExpiry: Int
    let urgency: String
    let renewalCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case clientId = "client_id"
        case docType = "doc_type"
        case label
        case issuer
        case issuingCountry = "issuing_country"
        case docNumber = "doc_number"
        case issueDate = "issue_date"
        case expiryDate = "expiry_date"
        case notes
        case remindersEnabled = "reminders_enabled"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case daysUntilExpiry = "days_until_expiry"
        case urgency
        case renewalCount = "renewal_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        clientId = try container.decodeIfPresent(UUID.self, forKey: .clientId)
        docType = try container.decode(String.self, forKey: .docType)
        label = try container.decode(String.self, forKey: .label)
        issuer = try container.decodeIfPresent(String.self, forKey: .issuer)
        issuingCountry = try container.decodeIfPresent(String.self, forKey: .issuingCountry)
        docNumber = try container.decodeIfPresent(String.self, forKey: .docNumber)
        issueDate = try container.decodeIfPresent(String.self, forKey: .issueDate)
        expiryDate = try container.decode(String.self, forKey: .expiryDate)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        remindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? true
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "active"
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        daysUntilExpiry = try container.decodeIfPresent(Int.self, forKey: .daysUntilExpiry) ?? 0
        urgency = try container.decodeIfPresent(String.self, forKey: .urgency) ?? "ok"
        // renewalCount: backend sends STRING "0", not Int
        if let intValue = try? container.decode(Int.self, forKey: .renewalCount) {
            renewalCount = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .renewalCount),
                  let parsed = Int(stringValue) {
            renewalCount = parsed
        } else {
            renewalCount = 0
        }
    }

    var docTypeIcon: String {
        switch docType {
        case "passport": return "airplane"
        case "national_id": return "person.text.rectangle"
        case "drivers_license": return "car"
        case "visa": return "globe"
        case "residence_permit": return "house"
        case "insurance": return "shield"
        case "card": return "creditcard"
        default: return "doc.text"
        }
    }

    var docTypeLabel: String {
        switch docType {
        case "passport": return "Passport"
        case "national_id": return "National ID"
        case "drivers_license": return "Driver's License"
        case "visa": return "Visa"
        case "residence_permit": return "Residence Permit"
        case "insurance": return "Insurance"
        case "card": return "Card"
        default: return "Other"
        }
    }

    var maskedDocNumber: String? {
        guard let num = docNumber, num.count > 4 else { return docNumber }
        let visible = String(num.suffix(4))
        let masked = String(repeating: "*", count: num.count - 4)
        return masked + visible
    }
}

struct DocumentsResponse: Codable {
    let success: Bool
    let documents: [Document]
    let count: Int?
}

struct SingleDocumentResponse: Codable {
    let success: Bool
    let document: Document?
    let remindersCreated: Int?

    enum CodingKeys: String, CodingKey {
        case success
        case document
        case remindersCreated = "reminders_created"
    }
}

struct CreateDocumentRequest: Encodable {
    let clientId: UUID
    let docType: String
    let label: String
    let issuer: String?
    let issuingCountry: String?
    let docNumber: String?
    let issueDate: String?
    let expiryDate: String
    let notes: String?
    let remindersEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case docType = "doc_type"
        case label
        case issuer
        case issuingCountry = "issuing_country"
        case docNumber = "doc_number"
        case issueDate = "issue_date"
        case expiryDate = "expiry_date"
        case notes
        case remindersEnabled = "reminders_enabled"
    }
}

struct UpdateDocumentRequest: Encodable {
    let id: Int
    let docType: String?
    let label: String?
    let issuer: String?
    let issuingCountry: String?
    let docNumber: String?
    let issueDate: String?
    let expiryDate: String?
    let notes: String?
    let remindersEnabled: Bool?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case docType = "doc_type"
        case label
        case issuer
        case issuingCountry = "issuing_country"
        case docNumber = "doc_number"
        case issueDate = "issue_date"
        case expiryDate = "expiry_date"
        case notes
        case remindersEnabled = "reminders_enabled"
        case status
    }
}

struct RenewDocumentRequest: Encodable {
    let id: Int
    let newExpiryDate: String
    let newDocNumber: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case newExpiryDate = "new_expiry_date"
        case newDocNumber = "new_doc_number"
        case notes
    }
}

struct DeleteDocumentResponse: Codable {
    let success: Bool
    let message: String?
}

struct RecreateRemindersResponse: Codable {
    let success: Bool
    let remindersCreated: Int?

    enum CodingKeys: String, CodingKey {
        case success
        case remindersCreated = "reminders_created"
    }
}

struct DocumentRenewal: Identifiable, Codable {
    let id: Int
    let documentId: Int
    let oldExpiryDate: String
    let newExpiryDate: String
    let oldDocNumber: String?
    let newDocNumber: String?
    let notes: String?
    let renewedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case documentId = "document_id"
        case oldExpiryDate = "old_expiry_date"
        case newExpiryDate = "new_expiry_date"
        case oldDocNumber = "old_doc_number"
        case newDocNumber = "new_doc_number"
        case notes
        case renewedAt = "renewed_at"
    }
}

struct RenewalHistoryResponse: Codable {
    let success: Bool
    let renewals: [DocumentRenewal]
}

enum DocumentType: String, CaseIterable {
    case passport
    case nationalId = "national_id"
    case driversLicense = "drivers_license"
    case visa
    case residencePermit = "residence_permit"
    case insurance
    case card
    case other

    var displayName: String {
        switch self {
        case .passport: return "Passport"
        case .nationalId: return "National ID"
        case .driversLicense: return "Driver's License"
        case .visa: return "Visa"
        case .residencePermit: return "Residence Permit"
        case .insurance: return "Insurance"
        case .card: return "Card"
        case .other: return "Other"
        }
    }
}
