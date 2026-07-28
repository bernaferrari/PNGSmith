import Foundation
import PNGSmithCoreFFI

enum PNGSmithBridgeError: LocalizedError {
    case encodingFailed
    case emptyResponse
    case invalidUTF8
    case coreError(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed: "Could not encode the PNG Smith request."
        case .emptyResponse: "PNG Smith returned no response."
        case .invalidUTF8: "PNG Smith returned an invalid response."
        case .coreError(let message): message
        }
    }
}

enum PNGSmithCore {
    /// Runs CPU-heavy Rust work away from cooperative Swift executors. The
    /// medium priority matches the worker threads used by the compression
    /// libraries and avoids priority inversions during interactive previews.
    static func executeAsync(
        _ request: PNGSmithRequest,
        priority: TaskPriority = .medium
    ) async throws -> PNGSmithResponse {
        try await Task.detached(priority: priority) {
            try execute(request)
        }.value
    }

    static func execute(_ request: PNGSmithRequest) throws -> PNGSmithResponse {
        let requestData = try JSONEncoder().encode(request)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw PNGSmithBridgeError.encodingFailed
        }
        let responsePointer = requestJSON.withCString { pngsmith_execute_json($0) }
        guard let responsePointer else { throw PNGSmithBridgeError.emptyResponse }
        defer { pngsmith_string_free(responsePointer) }
        guard let responseJSON = String(validatingCString: responsePointer) else {
            throw PNGSmithBridgeError.invalidUTF8
        }
        let response = try JSONDecoder().decode(PNGSmithResponse.self, from: Data(responseJSON.utf8))
        guard response.ok else {
            let details = response.results.compactMap(\.error).joined(separator: "\n")
            throw PNGSmithBridgeError.coreError(details.isEmpty ? (response.error ?? "Compression failed.") : details)
        }
        return response
    }
}
