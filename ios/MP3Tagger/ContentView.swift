import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var store = TrackStore()
    @State private var showImporter = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    trackCard
                    detailsCard
                    fileCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.mp3],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    store.open(url: url)
                }
            case .failure(let error):
                store.report("Import impossible : \(error.localizedDescription)")
            }
        }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        store.setCover(image)
                    }
                } else {
                    await MainActor.run {
                        store.report("Image illisible.")
                    }
                }
            }
        }
        .tint(Theme.accent)
    }

    // MARK: - En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("MP3 Tagger")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text("Prépare tes sons avant de les diffuser")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Morceau

    private var trackCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    coverPicker
                    VStack(spacing: 10) {
                        field("Titre", $store.title)
                        field("Artiste", $store.artist)
                        field("Album", $store.album)
                    }
                }

                if store.coverImage != nil {
                    Button {
                        photoItem = nil
                        store.clearCover()
                    } label: {
                        Label("Retirer la pochette", systemImage: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var coverPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.field)

                if let image = store.coverImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 122, height: 122)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    VStack(spacing: 7) {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text("Miniature")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .frame(width: 122, height: 122)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Détails

    private var detailsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Détails")
                    .font(.system(size: 16, weight: .semibold))

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    alignment: .leading,
                    spacing: 12
                ) {
                    field("Artiste de l'album", $store.albumArtist)
                    field("Compositeur", $store.composer)
                    field("Genre", $store.genre)
                    field("Année", $store.year, keyboard: .numberPad)
                    field("N° de piste", $store.track, keyboard: .numberPad)
                }

                field("Commentaire", $store.comment)
            }
        }
    }

    // MARK: - Fichier

    private var fileCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Fichier")
                    .font(.system(size: 16, weight: .semibold))

                if let url = store.fileURL {
                    Text(url.lastPathComponent)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 12) {
                        if store.duration > 0 {
                            Label(durationText(store.duration), systemImage: "clock")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        }

                        Spacer(minLength: 8)

                        ShareLink(item: url) {
                            Label("Partager", systemImage: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                } else {
                    Text("Aucun fichier. Utilise « Ouvrir » pour choisir un MP3 dans Fichiers.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    // MARK: - Barre d'actions

    private var bottomBar: some View {
        VStack(spacing: 9) {
            Text(store.status)
                .font(.system(size: 12))
                .foregroundStyle(store.statusIsError ? Theme.error : Theme.ok)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button {
                    store.togglePlayback()
                } label: {
                    Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Theme.field))
                }
                .buttonStyle(.plain)
                .disabled(!store.hasFile)
                .opacity(store.hasFile ? 1 : 0.4)

                Button {
                    showImporter = true
                } label: {
                    Label("Ouvrir", systemImage: "folder")
                }
                .buttonStyle(PillButtonStyle())

                Spacer(minLength: 0)

                Button {
                    store.save()
                } label: {
                    if store.isSaving {
                        ProgressView()
                            .tint(Color(hex: 0x0C0C14))
                    } else {
                        Label("Enregistrer", systemImage: "checkmark")
                    }
                }
                .buttonStyle(PillButtonStyle(primary: true))
                .disabled(!store.hasFile || store.isSaving)
                .opacity(store.hasFile ? 1 : 0.4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            Theme.side
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Composants

    private func field(
        _ label: String,
        _ text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.muted)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .font(.system(size: 15))
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Theme.field)
                )
        }
    }

    private func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
