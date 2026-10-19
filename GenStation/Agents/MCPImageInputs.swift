// MCPImageInputs.swift
// Decode + encode agent-supplied input images for MCP i2i/i2v (WS-7.1 Phase B).
// macOS only. Isolated from the UI's asyncGenerate; reuses only the standalone
// ImageProcessor. Supports base64 and ImgBB public-URL submission; binary/mask
// are out of scope (models needing binary are rejected upstream).

#if os(macOS)
import Foundation
import ImageIO
import GenStationCore

struct MCPImageInputError: Error { let index: Int; let reason: String }

enum MCPImageInputs {
    /// Decode/inspect locally before approval; no hosting or provider requests.
    static func validate(_ specs: [String]) throws {
        var total = 0
        for (index, spec) in specs.enumerated() {
            let data = try decodeSpec(spec, index: index)
            total += data.count
            guard total <= 20_000_000,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = values[kCGImagePropertyPixelWidth] as? Int, let height = values[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 16_384, height <= 16_384, width * height <= 64_000_000 else {
                throw MCPImageInputError(index: index, reason: "Images must decode, total at most 20 MB, and each contain at most 64 megapixels.")
            }
        }
    }

    /// `specs` are agent-supplied `data:<mime>;base64,<...>` data URIs (file paths are
    /// rejected — see decodeSpec). Returns image-reference strings suitable to place in
    /// the request body: `data:<mime>;base64,<...>` for base64, or a public URL for
    /// ImgBB. Throws MCPImageInputError with the offending index on any failure.
    static func build(from specs: [String], model: CatalogModel, appState: AppState) async throws -> [String] {
        // Resolve the submission method the same way the UI does, then constrain to
        // what MCP supports (base64 or public URL). Binary-only models are rejected.
        let wantURL = appState.settings.imageSubmissionMethod == .imgBB && model.acceptsPublicURL
        let canBase64 = model.acceptsBase64
        guard wantURL || canBase64 else {
            throw MCPImageInputError(index: 0,
                reason: "Model '\(model.id)' needs binary image submission, which MCP does not support yet.")
        }

        var refs: [String] = []
        for (i, spec) in specs.enumerated() {
            let data = try decodeSpec(spec, index: i)
            guard let image = PlatformImage(platformData: data) else {
                throw MCPImageInputError(index: i, reason: "Not a decodable image.")
            }
            guard let processed = processImageForUpload(
                    image: image, originalData: data, format: "jpeg", isBase64: !wantURL) else {
                throw MCPImageInputError(index: i, reason: "Failed to process image for upload.")
            }
            if wantURL {
                refs.append(try await uploadToImgBB(processed.data, apiKey: appState.settings.imgbbApiKey, index: i))
            } else {
                refs.append("data:\(processed.mimeType);base64,\(processed.data.base64EncodedString())")
            }
        }
        return refs
    }

    /// Decodes a `data:<mime>;base64,<...>` URI to its bytes. File paths are
    /// intentionally NOT accepted: an agent — not the user — supplies these specs,
    /// so honoring arbitrary paths would let a request read any user-readable file
    /// (and, under ImgBB submission, publish it to a public URL). Callers must
    /// inline the image bytes as a base64 data URI.
    private static func decodeSpec(_ spec: String, index: Int) throws -> Data {
        guard spec.utf8.count <= 28_000_000, spec.hasPrefix("data:image/") else {
            throw MCPImageInputError(index: index,
                reason: "input_images entries must be base64 data URIs (data:<mime>;base64,<...>). File paths are not accepted.")
        }
        guard let comma = spec.firstIndex(of: ","), spec[..<comma].hasSuffix(";base64"),
              let data = Data(base64Encoded: String(spec[spec.index(after: comma)...])) else {
            throw MCPImageInputError(index: index, reason: "Malformed base64 data URI.")
        }
        return data
    }

    /// Replicates the UI's inline ImgBB upload (600s expiry). Kept local to avoid
    /// touching asyncGenerate; ~15 lines of intentional duplication.
    private static func uploadToImgBB(_ data: Data, apiKey: String, index: Int) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard ImgBBClient.isPlausibleKey(key) else {
            throw MCPImageInputError(index: index, reason: "ImgBB API key missing or invalid; add one in GenStation or switch submission method to Base64.")
        }
        let url = ImgBBClient.uploadURL(apiKey: key)
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"\r\n\r\n".data(using: .utf8)!)
        body.append(data.base64EncodedString().data(using: .utf8)!)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        guard let (respData, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(ImgBBClient.UploadResponse.self, from: respData),
              let link = decoded.data?.url else {
            throw MCPImageInputError(index: index, reason: "ImgBB upload failed.")
        }
        return link
    }
}
#endif
