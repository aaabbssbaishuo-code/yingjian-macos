import CoreGraphics
import Vision

enum OCRError: Error {
    case requestFailed
}

struct OCRResult {
    let paragraphs: [String]

    var fullText: String {
        paragraphs.joined(separator: "\n\n")
    }
}

private struct OCRLine {
    let box: CGRect
    let text: String
}

struct OCRService {
    func recognizeEnglish(in image: CGImage) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if error != nil {
                    continuation.resume(throwing: OCRError.requestFailed)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations
                    .compactMap { observation -> OCRLine? in
                        guard let candidate = observation.topCandidates(1).first else {
                            return nil
                        }
                        let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard text.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil else {
                            return nil
                        }
                        return OCRLine(box: observation.boundingBox, text: text)
                    }
                    .sorted { lhs, rhs in
                        let verticalDistance = abs(lhs.box.midY - rhs.box.midY)
                        if verticalDistance < 0.025 {
                            return lhs.box.minX < rhs.box.minX
                        }
                        return lhs.box.midY > rhs.box.midY
                    }

                continuation.resume(returning: OCRResult(
                    paragraphs: Self.groupIntoParagraphs(lines)
                ))
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func groupIntoParagraphs(_ lines: [OCRLine]) -> [String] {
        guard let first = lines.first else { return [] }

        var groups: [[OCRLine]] = [[first]]

        for line in lines.dropFirst() {
            guard let previous = groups.last?.last else { continue }

            let verticalGap = max(0, previous.box.minY - line.box.maxY)
            let referenceHeight = max(previous.box.height, line.box.height)
            let leftAlignment = abs(previous.box.minX - line.box.minX)
            let horizontalOverlap = min(previous.box.maxX, line.box.maxX)
                - max(previous.box.minX, line.box.minX)
            let sharesColumn = horizontalOverlap > 0
                || leftAlignment < max(previous.box.width, line.box.width) * 0.18
            let isClose = verticalGap <= max(0.012, referenceHeight * 0.62)

            if sharesColumn && isClose {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }

        return groups
            .map { group in
                group.map(\.text).joined(separator: " ")
            }
            .filter { !$0.isEmpty }
    }
}
