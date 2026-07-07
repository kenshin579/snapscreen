import Vision
import CoreGraphics

/// Vision 온디바이스 OCR 래퍼. 이미지 → 인식 텍스트(비동기).
public enum TextRecognizer {
    /// 이미지를 OCR해 완료 핸들러로 결과 문자열을 돌려준다.
    /// 무거운 인식은 백그라운드에서 수행하고 콜백은 메인 액터에서 호출한다.
    public static func recognize(_ image: CGImage,
                                 completion: @escaping @MainActor (Result<String, Error>) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                Task { @MainActor in completion(.failure(error)) }
                return
            }
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let lines = observations.compactMap { obs -> (text: String, minY: Double)? in
                guard let top = obs.topCandidates(1).first else { return nil }
                return (top.string, Double(obs.boundingBox.minY))
            }
            let text = joinedText(lines)
            Task { @MainActor in completion(.success(text)) }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                Task { @MainActor in completion(.failure(error)) }
            }
        }
    }

    /// (텍스트, 정규화 boundingBox minY) 목록을 위→아래(minY 내림차순)로 정렬해 줄바꿈 결합. 순수 함수.
    public static func joinedText(_ lines: [(text: String, minY: Double)]) -> String {
        lines.sorted { $0.minY > $1.minY }.map(\.text).joined(separator: "\n")
    }
}
