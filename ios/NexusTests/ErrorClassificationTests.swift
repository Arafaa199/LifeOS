import XCTest
@testable import Nexus

/// Tests for ErrorClassification (Patch 1: OfflineQueue error classification)
final class ErrorClassificationTests: XCTestCase {

    // MARK: - URLError Classification

    func testNetworkErrorsAreTransient() {
        let networkErrors: [URLError.Code] = [
            .notConnectedToInternet,
            .networkConnectionLost,
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed
        ]

        for code in networkErrors {
            let error = URLError(code)
            let classification = ErrorClassification.classify(error)
            XCTAssertEqual(classification, .transient, "URLError.\(code) should be transient")
            XCTAssertTrue(classification.shouldQueue, "Transient errors should be queued")
        }
    }

    func testAuthURLErrorIsAuthError() {
        let error = URLError(.userAuthenticationRequired)
        let classification = ErrorClassification.classify(error)
        XCTAssertEqual(classification, .authError)
        XCTAssertFalse(classification.shouldQueue, "Auth errors should NOT be queued")
    }

    // MARK: - APIError Classification

    func testServerErrorsAreTransient() {
        let serverCodes = [500, 502, 503, 504]

        for code in serverCodes {
            let error = APIError.serverError(code)
            let classification = ErrorClassification.classify(error)
            XCTAssertEqual(classification, .transient, "Server error \(code) should be transient")
        }
    }

    func testClientErrorsAreClientError() {
        let clientCodes = [400, 404, 422, 429]

        for code in clientCodes {
            let error = APIError.serverError(code)
            let classification = ErrorClassification.classify(error)
            XCTAssertEqual(classification, .clientError, "Client error \(code) should be clientError")
            XCTAssertFalse(classification.shouldQueue)
        }
    }

    func testAuthStatusCodesAreAuthError() {
        let authCodes = [401, 403]

        for code in authCodes {
            let error = APIError.serverError(code)
            let classification = ErrorClassification.classify(error)
            XCTAssertEqual(classification, .authError, "Status \(code) should be authError")
            XCTAssertFalse(classification.shouldQueue)
        }
    }

    func testOfflineIsTrransient() {
        let error = APIError.offline
        let classification = ErrorClassification.classify(error)
        XCTAssertEqual(classification, .transient)
        XCTAssertTrue(classification.shouldQueue)
    }

    func testDecodingErrorIsPermanent() {
        let error = APIError.decodingError
        let classification = ErrorClassification.classify(error)
        XCTAssertEqual(classification, .permanent)
        XCTAssertFalse(classification.shouldQueue)
    }

    func testInvalidURLIsPermanent() {
        let error = APIError.invalidURL
        let classification = ErrorClassification.classify(error)
        XCTAssertEqual(classification, .permanent)
        XCTAssertFalse(classification.shouldQueue)
    }

    // MARK: - ValidationError Classification

    func testValidationErrorsAreClientError() {
        let validationErrors: [ValidationError] = [
            .invalidWaterAmount,
            .invalidWeight,
            .invalidMoodOrEnergy
        ]

        for error in validationErrors {
            let classification = ErrorClassification.classify(error)
            XCTAssertEqual(classification, .clientError, "\(error) should be clientError")
            XCTAssertFalse(classification.shouldQueue, "Validation errors should NOT be queued")
        }
    }

    // MARK: - NexusError Classification

    func testNexusNetworkErrorIsTransient() {
        let urlError = URLError(.timedOut)
        let nexusError = NexusError.network(urlError)
        let classification = ErrorClassification.classify(nexusError)
        XCTAssertEqual(classification, .transient)
    }

    func testNexusOfflineIsTransient() {
        let nexusError = NexusError.offline(queuedItemCount: 5)
        let classification = ErrorClassification.classify(nexusError)
        XCTAssertEqual(classification, .transient)
    }

    func testNexusValidationIsClientError() {
        let nexusError = NexusError.validation(.invalidWeight)
        let classification = ErrorClassification.classify(nexusError)
        XCTAssertEqual(classification, .clientError)
    }

    func testNexusAPIErrorDelegates() {
        let nexusError = NexusError.api(.serverError(503))
        let classification = ErrorClassification.classify(nexusError)
        XCTAssertEqual(classification, .transient)

        let authNexusError = NexusError.api(.serverError(401))
        let authClassification = ErrorClassification.classify(authNexusError)
        XCTAssertEqual(authClassification, .authError)
    }

    // MARK: - User Messages

    func testUserMessagesAreDescriptive() {
        XCTAssertTrue(ErrorClassification.transient.userMessage.contains("retry"))
        XCTAssertTrue(ErrorClassification.clientError.userMessage.lowercased().contains("input"))
        XCTAssertTrue(ErrorClassification.authError.userMessage.lowercased().contains("api key") ||
                      ErrorClassification.authError.userMessage.lowercased().contains("authentication"))
    }
}
