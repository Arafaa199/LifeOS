import SwiftUI
import AVFoundation
import Combine

struct BarcodeScannerView: View {
    let onResult: (FoodSearchResult) -> Void
    let onManualEntry: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = BarcodeScannerModel()

    var body: some View {
        ZStack {
            CameraPreview(session: scanner.session)
                .ignoresSafeArea()

            VStack {
                Spacer()

                if scanner.isLoading {
                    lookupCard {
                        ProgressView("Looking up barcode...")
                            .padding()
                    }
                } else if let food = scanner.foundFood {
                    lookupCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(food.name)
                                .font(.headline)
                                .lineLimit(2)

                            if let brand = food.brand, !brand.isEmpty {
                                Text(brand)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            HStack(spacing: 16) {
                                macroChip("Cal", value: food.calories_per_100g, format: "%.0f")
                                macroChip("Protein", value: food.protein_per_100g, format: "%.1fg")
                                macroChip("Carbs", value: food.carbs_per_100g, format: "%.1fg")
                                macroChip("Fat", value: food.fat_per_100g, format: "%.1fg")
                            }
                            .font(.caption)

                            Button(action: {
                                onResult(food)
                                dismiss()
                            }) {
                                Text("Add to Log")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(NexusTheme.Colors.Semantic.amber)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        }
                        .padding()
                    }
                } else if let barcode = scanner.scannedBarcode, scanner.notFound {
                    lookupCard {
                        VStack(spacing: 12) {
                            Text("Not in database")
                                .font(.headline)
                            Text("Barcode: \(barcode)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button(action: {
                                onManualEntry(barcode)
                                dismiss()
                            }) {
                                Text("Log Manually")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(NexusTheme.Colors.accent)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        }
                        .padding()
                    }
                }
            }
            .padding(.bottom, 40)

            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .padding()
                }
                Spacer()
            }

            if !scanner.isLoading && scanner.foundFood == nil && !scanner.notFound {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.6), lineWidth: 2)
                    .frame(width: 250, height: 120)
            }
        }
        .onAppear { scanner.start() }
        .onDisappear { scanner.stop() }
    }

    private func lookupCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func macroChip(_ label: String, value: Double?, format: String) -> some View {
        if let v = value {
            VStack(spacing: 2) {
                Text(String(format: format, v))
                    .fontWeight(.semibold)
                Text(label)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        context.coordinator.previewLayer = layer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

@MainActor
class BarcodeScannerModel: NSObject, ObservableObject {
    @Published var scannedBarcode: String?
    @Published var foundFood: FoodSearchResult?
    @Published var isLoading = false
    @Published var notFound = false

    let session = AVCaptureSession()
    private let api = NexusAPI.shared
    private var isConfigured = false
    private var lastScannedBarcode: String?

    func start() {
        guard !isConfigured else {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
            return
        }

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        let output = AVCaptureMetadataOutput()

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()

        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean13, .ean8, .upce]

        isConfigured = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
        }
    }

    private func lookup(_ barcode: String) {
        guard barcode != lastScannedBarcode else { return }
        lastScannedBarcode = barcode
        scannedBarcode = barcode
        foundFood = nil
        notFound = false
        isLoading = true

        Task {
            do {
                let response = try await api.lookupBarcode(barcode)
                if let foods = response.data, let first = foods.first {
                    foundFood = first
                } else {
                    notFound = true
                }
            } catch {
                notFound = true
            }
            isLoading = false
        }
    }

    func reset() {
        lastScannedBarcode = nil
        scannedBarcode = nil
        foundFood = nil
        notFound = false
    }
}

extension BarcodeScannerModel: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let barcode = object.stringValue else { return }

        Task { @MainActor in
            self.lookup(barcode)
        }
    }
}
