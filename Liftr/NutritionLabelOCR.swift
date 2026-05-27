import SwiftUI
import UIKit
import Vision

enum NutritionLabelOCRError: LocalizedError {
    case invalidImage
    case noTextFound
    case visionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not read label clearly. Please adjust lighting or input manually."
        case .noTextFound:
            return "Could not read label clearly. Please adjust lighting or input manually."
        case .visionFailed:
            return "Could not read label clearly. Please adjust lighting or input manually."
        }
    }
}

enum NutritionLabelOCRService {
    static func recognize(from image: UIImage) async throws -> NutritionLabelRecognitionResult {
        let prepared = downscaleIfNeeded(image)
        guard let cgImage = prepared.cgImage else {
            throw NutritionLabelOCRError.invalidImage
        }
        let orientation = CGImagePropertyOrientation(prepared.imageOrientation)
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: NutritionLabelOCRError.visionFailed(error.localizedDescription))
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    continuation.resume(throwing: NutritionLabelOCRError.noTextFound)
                    return
                }
                let elements = observations.compactMap { observation -> NutritionLabelSpatialElement? in
                    guard let raw = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                          !raw.isEmpty else { return nil }
                    let box = observation.boundingBox
                    return NutritionLabelSpatialElement(
                        text: raw,
                        minX: box.minX,
                        minY: 1 - box.maxY,
                        maxX: box.maxX,
                        maxY: 1 - box.minY
                    )
                }
                if elements.count < 5 {
                    continuation.resume(throwing: NutritionLabelOCRError.noTextFound)
                    return
                }
                let mergeTokens = elements.map { element in
                    (text: element.text, cx: element.centerX, cy: element.centerY)
                }
                let merged = mergeTokensIntoLogicalRows(tokens: mergeTokens, yTolerance: 0.035)
#if DEBUG
                if !merged.isEmpty {
                    print("--- [OCR RAW CORPUS START] ---")
                    for (index, line) in merged.enumerated() {
                        print("[\(index)] \(line)")
                    }
                    print("--- [OCR RAW CORPUS END] ---")
                }
#endif
                if merged.isEmpty {
                    continuation.resume(throwing: NutritionLabelOCRError.noTextFound)
                } else {
                    continuation.resume(returning: NutritionLabelRecognitionResult(mergedLines: merged, elements: elements))
                }
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["es", "en", "ca", "pt", "fr", "de", "it"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: NutritionLabelOCRError.visionFailed(error.localizedDescription))
            }
        }
    }

    static func recognizeText(from image: UIImage) async throws -> [String] {
        let result = try await recognize(from: image)
        return result.mergedLines
    }

    private static func mergeTokensIntoLogicalRows(
        tokens: [(text: String, cx: CGFloat, cy: CGFloat)],
        yTolerance: CGFloat
    ) -> [String] {
        let sorted = tokens.sorted { a, b in
            if abs(a.cy - b.cy) > yTolerance { return a.cy < b.cy }
            return a.cx < b.cx
        }
        struct Row {
            var cy: CGFloat
            var items: [(text: String, cx: CGFloat)]
        }
        var rows: [Row] = []
        for token in sorted {
            if var last = rows.last, abs(token.cy - last.cy) <= yTolerance {
                last.items.append((token.text, token.cx))
                let count = CGFloat(last.items.count)
                last.cy = (last.cy * (count - 1) + token.cy) / count
                rows[rows.count - 1] = last
            } else {
                rows.append(Row(cy: token.cy, items: [(token.text, token.cx)]))
            }
        }
        return rows.map { row in
            row.items
                .sorted { $0.cx < $1.cx }
                .map { $0.text }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    private static func downscaleIfNeeded(_ image: UIImage, maxDimension: CGFloat = 2048) -> UIImage {
        let width = image.size.width
        let height = image.size.height
        let maxSide = max(width, height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: width * scale, height: height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

struct ImagePickerBridge: UIViewControllerRepresentable {
    enum Source {
        case camera
        case photoLibrary
    }

    let source: Source
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = source == .camera ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            } else {
                onCancel()
            }
        }
    }
}
