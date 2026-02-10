import Foundation
import os

private let logger = Logger(subsystem: "com.nexus.app", category: "healthkit-validator")

/// HealthKitValueValidator provides range validation for health metrics
/// Filters out invalid readings according to physiological bounds
struct HealthKitValueValidator {

    // MARK: - Validation Ranges

    private static let ValidationRanges = (
        weight: (min: 20.0, max: 300.0),          // kg
        hrv: (min: 1.0, max: 300.0),              // ms (RMSSD)
        heartRate: (min: 25.0, max: 250.0),       // bpm
        restingHeartRate: (min: 25.0, max: 250.0),// bpm
        recoveryScore: (min: 0.0, max: 100.0),    // unitless (%)
        spO2: (min: 70.0, max: 100.0),            // %
        sleep: (min: 0.0, max: 1440.0)            // minutes (24h max)
    )

    // MARK: - Public Validation Methods

    /// Validates a weight sample in kilograms
    /// - Parameter value: Weight in kg
    /// - Returns: Valid weight or nil if outside valid range
    static func validateWeight(_ value: Double) -> Double? {
        guard isInRange(value, min: ValidationRanges.weight.min, max: ValidationRanges.weight.max) else {
            logger.warning("Invalid weight reading filtered: \(value, privacy: .public) kg (valid range: \(ValidationRanges.weight.min)-\(ValidationRanges.weight.max) kg)")
            return nil
        }
        return value
    }

    /// Validates HRV (Heart Rate Variability) sample in milliseconds (RMSSD)
    /// - Parameter value: HRV in ms
    /// - Returns: Valid HRV or nil if outside valid range
    static func validateHRV(_ value: Double) -> Double? {
        guard isInRange(value, min: ValidationRanges.hrv.min, max: ValidationRanges.hrv.max) else {
            logger.warning("Invalid HRV reading filtered: \(value, privacy: .public) ms (valid range: \(ValidationRanges.hrv.min)-\(ValidationRanges.hrv.max) ms)")
            return nil
        }
        return value
    }

    /// Validates heart rate sample in beats per minute
    /// - Parameter value: Heart rate in bpm
    /// - Returns: Valid heart rate or nil if outside valid range
    static func validateHeartRate(_ value: Double) -> Double? {
        guard isInRange(value, min: ValidationRanges.heartRate.min, max: ValidationRanges.heartRate.max) else {
            logger.warning("Invalid heart rate reading filtered: \(value, privacy: .public) bpm (valid range: \(ValidationRanges.heartRate.min)-\(ValidationRanges.heartRate.max) bpm)")
            return nil
        }
        return value
    }

    /// Validates resting heart rate sample in beats per minute
    /// - Parameter value: Resting heart rate in bpm
    /// - Returns: Valid resting heart rate or nil if outside valid range
    static func validateRestingHeartRate(_ value: Double) -> Double? {
        guard isInRange(value, min: ValidationRanges.restingHeartRate.min, max: ValidationRanges.restingHeartRate.max) else {
            logger.warning("Invalid resting heart rate reading filtered: \(value, privacy: .public) bpm (valid range: \(ValidationRanges.restingHeartRate.min)-\(ValidationRanges.restingHeartRate.max) bpm)")
            return nil
        }
        return value
    }

    /// Validates recovery score (typically 0-100 scale)
    /// - Parameter value: Recovery score
    /// - Returns: Valid recovery score or nil if outside valid range
    static func validateRecoveryScore(_ value: Double) -> Double? {
        guard isInRange(value, min: ValidationRanges.recoveryScore.min, max: ValidationRanges.recoveryScore.max) else {
            logger.warning("Invalid recovery score reading filtered: \(value, privacy: .public) (valid range: \(ValidationRanges.recoveryScore.min)-\(ValidationRanges.recoveryScore.max))")
            return nil
        }
        return value
    }

    /// Validates blood oxygen saturation (SpO2) percentage
    /// - Parameter value: SpO2 in percentage
    /// - Returns: Valid SpO2 or nil if outside valid range
    static func validateSpO2(_ value: Double) -> Double? {
        guard isInRange(value, min: ValidationRanges.spO2.min, max: ValidationRanges.spO2.max) else {
            logger.warning("Invalid SpO2 reading filtered: \(value, privacy: .public)% (valid range: \(ValidationRanges.spO2.min)-\(ValidationRanges.spO2.max)%)")
            return nil
        }
        return value
    }

    /// Validates sleep duration in minutes
    /// - Parameter value: Sleep duration in minutes
    /// - Returns: Valid sleep duration or nil if outside valid range
    static func validateSleep(_ value: Double) -> Double? {
        guard isInRange(value, min: ValidationRanges.sleep.min, max: ValidationRanges.sleep.max) else {
            logger.warning("Invalid sleep duration filtered: \(value, privacy: .public) minutes (valid range: \(ValidationRanges.sleep.min)-\(ValidationRanges.sleep.max) minutes)")
            return nil
        }
        return value
    }

    /// Generic validator for quantity samples by type identifier
    /// - Parameters:
    ///   - value: The metric value
    ///   - typeIdentifier: HK type identifier string
    /// - Returns: Valid value or nil if outside valid range
    static func validateQuantitySample(_ value: Double, typeIdentifier: String) -> Double? {
        switch typeIdentifier {
        case "HKQuantityTypeIdentifierBodyMass":
            return validateWeight(value)
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN":
            return validateHRV(value)
        case "HKQuantityTypeIdentifierHeartRate":
            return validateHeartRate(value)
        case "HKQuantityTypeIdentifierRestingHeartRate":
            return validateRestingHeartRate(value)
        case "HKQuantityTypeIdentifierOxygenSaturation":
            return validateSpO2(value)
        default:
            // No validation for other types (steps, calories, etc.)
            return value
        }
    }

    // MARK: - Private Helpers

    private static func isInRange(_ value: Double, min: Double, max: Double) -> Bool {
        return value >= min && value <= max
    }
}
