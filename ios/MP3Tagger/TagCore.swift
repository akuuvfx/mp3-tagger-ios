import Foundation

// MARK: - Structures échangées avec le cœur Rust

struct TrackInfo: Decodable {
    let path: String
    let title: String
    let artist: String
    let album: String
    let albumArtist: String
    let composer: String
    let genre: String
    let year: String
    let track: String
    let comment: String
    let coverBase64: String?
    let durationSeconds: Double?
}

struct TagWriteRequest: Encodable {
    let path: String
    let title: String
    let artist: String
    let album: String
    let albumArtist: String
    let composer: String
    let genre: String
    let year: String
    let track: String
    let comment: String
    let coverSourcePath: String?
    let removeCover: Bool
}

private struct ReadResponse: Decodable {
    let ok: Bool
    let error: String?
    let track: TrackInfo?
}

private struct WriteResponse: Decodable {
    let ok: Bool
    let error: String?
}

enum TagCoreError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

// MARK: - Pont Swift ↔ Rust

enum TagCore {
    static func read(path: String) throws -> TrackInfo {
        let response: ReadResponse = try call(path: path, function: mp3tag_read)
        guard response.ok, let track = response.track else {
            throw TagCoreError.message(response.error ?? "Lecture impossible.")
        }
        return track
    }

    static func write(_ request: TagWriteRequest) throws {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(request),
              let json = String(data: data, encoding: .utf8) else {
            throw TagCoreError.message("Requête invalide.")
        }

        let response: WriteResponse = try call(json: json, function: mp3tag_write)
        guard response.ok else {
            throw TagCoreError.message(response.error ?? "Écriture impossible.")
        }
    }

    // MARK: Helpers

    private static func call<T: Decodable>(
        path: String,
        function: (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    ) throws -> T {
        try path.withCString { cPath in
            try decode(function(cPath))
        }
    }

    private static func call<T: Decodable>(
        json: String,
        function: (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    ) throws -> T {
        try json.withCString { cJson in
            try decode(function(cJson))
        }
    }

    private static func decode<T: Decodable>(_ pointer: UnsafeMutablePointer<CChar>?) throws -> T {
        guard let pointer else {
            throw TagCoreError.message("Réponse vide du cœur Rust.")
        }
        defer { mp3tag_free(pointer) }

        let json = String(cString: pointer)
        guard let data = json.data(using: .utf8) else {
            throw TagCoreError.message("Réponse illisible.")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw TagCoreError.message("Réponse inattendue : \(error.localizedDescription)")
        }
    }
}
