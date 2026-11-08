import AVFoundation
import Combine
import Foundation
import UIKit

final class TrackStore: NSObject, ObservableObject, AVAudioPlayerDelegate {

    // MARK: - Métadonnées affichées

    @Published var fileURL: URL?
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var albumArtist = ""
    @Published var composer = ""
    @Published var genre = ""
    @Published var year = ""
    @Published var track = ""
    @Published var comment = ""

    // MARK: - Pochette

    @Published var coverImage: UIImage?
    /// Vrai si l'utilisateur vient de choisir une nouvelle image.
    private(set) var coverChanged = false
    /// Vrai si l'utilisateur a retiré la pochette existante.
    private(set) var removeCover = false

    // MARK: - État

    @Published var status = "Ouvre un MP3 pour commencer."
    @Published var statusIsError = false
    @Published var isPlaying = false
    @Published var isSaving = false
    @Published var duration: Double = 0

    private var player: AVAudioPlayer?

    var hasFile: Bool { fileURL != nil }

    // MARK: - Ouverture / import

    /// Importe le fichier choisi dans le dossier Documents de l'app, puis le charge.
    func open(url: URL) {
        stopPlayback()

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try FileManager.default.createDirectory(
                at: tracksDirectory,
                withIntermediateDirectories: true
            )
            let destination = uniqueDestination(for: url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: destination)
            load(path: destination)
        } catch {
            report("Import impossible : \(error.localizedDescription)")
        }
    }

    func load(path: URL) {
        stopPlayback()

        do {
            let info = try TagCore.read(path: path.path)

            fileURL = path
            title = info.title
            artist = info.artist
            album = info.album
            albumArtist = info.albumArtist
            composer = info.composer
            genre = info.genre
            year = info.year
            track = info.track
            comment = info.comment
            duration = info.durationSeconds ?? 0

            if let base64 = info.coverBase64,
               let data = Data(base64Encoded: base64),
               let image = UIImage(data: data) {
                coverImage = image
            } else {
                coverImage = nil
            }

            coverChanged = false
            removeCover = false
            succeeded("Fichier chargé.")
        } catch {
            report(error.localizedDescription)
        }
    }

    // MARK: - Pochette

    func setCover(_ image: UIImage) {
        coverImage = image
        coverChanged = true
        removeCover = false
    }

    func clearCover() {
        coverImage = nil
        coverChanged = false
        removeCover = true
    }

    // MARK: - Enregistrement

    func save() {
        guard let url = fileURL else {
            report("Ouvre d'abord un MP3.")
            return
        }

        stopPlayback()
        isSaving = true
        defer { isSaving = false }

        // La pochette choisie est écrite dans un fichier temporaire : le cœur
        // Rust la recadre en carré 1000x1000 et l'intègre au tag ID3v2.3.
        var temporaryCoverPath: String?
        if coverChanged, let image = coverImage {
            guard let data = image.jpegData(compressionQuality: 0.95) else {
                report("Pochette impossible à convertir.")
                return
            }
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("cover-\(UUID().uuidString).jpg")
            do {
                try data.write(to: temporaryURL)
                temporaryCoverPath = temporaryURL.path
            } catch {
                report("Pochette impossible à préparer : \(error.localizedDescription)")
                return
            }
        }

        defer {
            if let temporaryCoverPath {
                try? FileManager.default.removeItem(atPath: temporaryCoverPath)
            }
        }

        let request = TagWriteRequest(
            path: url.path,
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            composer: composer,
            genre: genre,
            year: year,
            track: track,
            comment: comment,
            coverSourcePath: temporaryCoverPath,
            removeCover: removeCover
        )

        do {
            try TagCore.write(request)
            coverChanged = false
            removeCover = false
            succeeded("Enregistré : \(url.lastPathComponent)")
        } catch {
            report(error.localizedDescription)
        }
    }

    // MARK: - Aperçu audio

    func togglePlayback() {
        if isPlaying {
            stopPlayback()
            return
        }

        guard let url = fileURL else {
            report("Ouvre d'abord un MP3.")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()

            guard player.play() else {
                throw TagCoreError.message("Lecture audio impossible.")
            }

            self.player = player
            isPlaying = true
        } catch {
            report("Lecture impossible : \(error.localizedDescription)")
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if self.player === player {
            self.player = nil
            isPlaying = false
        }
    }

    // MARK: - Messages

    func report(_ message: String) {
        status = message
        statusIsError = true
    }

    private func succeeded(_ message: String) {
        status = message
        statusIsError = false
    }

    // MARK: - Chemins

    private var tracksDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tracks", isDirectory: true)
    }

    private func uniqueDestination(for filename: String) -> URL {
        let sanitized = Self.sanitize(filename)
        let nsName = sanitized as NSString
        let base = nsName.deletingPathExtension
        let ext = nsName.pathExtension.isEmpty ? "mp3" : nsName.pathExtension

        var candidate = tracksDirectory
            .appendingPathComponent("\(base).\(ext)")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = tracksDirectory
                .appendingPathComponent("\(base) \(index).\(ext)")
            index += 1
        }
        return candidate
    }

    private static func sanitize(_ filename: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let cleaned = filename
            .components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "morceau.mp3" : cleaned
    }
}
