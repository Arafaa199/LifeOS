import Foundation
import SwiftUI
import PhotosUI
import Combine

// Service for photo-based food logging using Claude Vision
@MainActor
class PhotoFoodLogger: ObservableObject {
    static let shared = PhotoFoodLogger()

    @Published var isProcessing = false
    @Published var lastResult: PhotoLogResult?

    func clearLastResult() {
        lastResult = nil
    }

    struct PhotoLogResult {
        let success: Bool
        let description: String
        let estimatedCalories: Int?
        let estimatedProtein: Double?
        let message: String
    }

    private var baseURL: String {
        UserDefaults.standard.string(forKey: "webhookBaseURL") ?? "https://n8n.rfanw"
    }

    // Log food from photo data
    func logFoodFromPhoto(_ imageData: Data, additionalContext: String? = nil) async throws -> NexusResponse {
        isProcessing = true
        defer { isProcessing = false }

        guard let url = URL(string: "\(baseURL)/webhook/nexus-photo-food") else {
            throw APIError.invalidURL
        }

        // Create multipart form data
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add image data (using safe string append)
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"photo\"; filename=\"food.jpg\"\r\n")
        body.appendString("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.appendString("\r\n")

        // Add source field
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"source\"\r\n\r\n")
        body.appendString("ios-photo\r\n")

        // Add context if provided
        if let context = additionalContext, !context.isEmpty {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"context\"\r\n\r\n")
            body.appendString("\(context)\r\n")
        }

        body.appendString("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let nexusResponse = try decoder.decode(NexusResponse.self, from: data)

        // Update last result for UI
        lastResult = PhotoLogResult(
            success: nexusResponse.success,
            description: nexusResponse.message ?? "Food logged",
            estimatedCalories: nexusResponse.data?.calories,
            estimatedProtein: nexusResponse.data?.protein,
            message: nexusResponse.message ?? "Logged from photo"
        )

        return nexusResponse
    }

    // Compress image for upload
    func compressImage(_ image: UIImage, maxSizeKB: Int = 500) -> Data? {
        var compression: CGFloat = 0.8
        let maxBytes = maxSizeKB * 1024

        guard var imageData = image.jpegData(compressionQuality: compression) else {
            return nil
        }

        while imageData.count > maxBytes && compression > 0.1 {
            compression -= 0.1
            if let newData = image.jpegData(compressionQuality: compression) {
                imageData = newData
            }
        }

        return imageData
    }

    // Resize image before compression
    func resizeImage(_ image: UIImage, maxDimension: CGFloat = 1024) -> UIImage {
        let size = image.size
        let ratio = min(maxDimension / size.width, maxDimension / size.height)

        if ratio >= 1 {
            return image
        }

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - SwiftUI Photo Picker View

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss
    var sourceType: UIImagePickerController.SourceType = .camera

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PhotoPicker

        init(_ parent: PhotoPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - PhotosUI Picker for iOS 16+

@available(iOS 16.0, *)
struct PhotosPickerView: View {
    @Binding var selectedImage: UIImage?
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            Label("Choose from Library", systemImage: "photo.on.rectangle")
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        selectedImage = image
                    }
                }
            }
        }
    }
}
