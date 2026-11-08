# MP3 Tagger — version iOS

Port iOS de **MP3 Tagger** : une petite app iPhone pour éditer les tags ID3 d'un MP3 et
y intégrer une pochette, avant de l'envoyer à un distributeur ou de l'écouter dans Spotify
(fichiers locaux), Apple Musique, VLC, etc.

## Fonctionnalités

- Ouvrir un MP3 depuis Fichiers (ou le partager vers l'app).
- Éditer : titre, artiste, album, artiste de l'album, compositeur, genre, année,
  n° de piste, commentaire.
- Choisir une pochette depuis Photos : elle est recadrée au carré et convertie en
  JPEG 1000×1000, puis intégrée au fichier en ID3v2.3 (frame `APIC`).
- Retirer la pochette.
- Écouter un aperçu du morceau directement dans l'app.
- Partager / exporter le MP3 modifié via la feuille de partage iOS.
- Les fichiers importés restent accessibles dans l'app Fichiers
  (`Sur mon iPhone > MP3 Tagger`).

L'interface reprend l'esthétique du bureau : fond sombre, accents violets, carte
« Morceau », carte « Détails », barre d'actions en bas.

## Architecture

```
mp3-tagger-ios/
├─ core/                     Cœur Rust partagé (lofty + image)
│  ├─ src/lib.rs             API C JSON : mp3tag_read / mp3tag_write / mp3tag_free
│  └─ Cargo.toml             staticlib aarch64-apple-ios
├─ ios/
│  ├─ project.yml            Projet Xcode généré par XcodeGen
│  └─ MP3Tagger/             App SwiftUI
│     ├─ ContentView.swift
│     ├─ TrackStore.swift
│     ├─ TagCore.swift       Pont Swift ↔ Rust
│     ├─ Theme.swift
│     └─ MP3Tagger-Bridging-Header.h
├─ scripts/
│  ├─ build-core.sh          Compile le cœur Rust pour iPhone
│  └─ build-unsigned-ipa.sh  Build local macOS → IPA non signée
└─ .github/workflows/ios.yml Build GitHub Actions → IPA en artefact
```

SwiftUI gère l'interface, les fichiers et la lecture audio. Rust gère tout ce qui touche
aux tags et à l'image, avec la même logique (et le même correctif de pochette) que la
version bureau.

## Obtenir l'IPA via GitHub Actions

1. Onglet **Actions** du dépôt → workflow **Build iOS IPA**.
2. Attendre la fin du job **IPA non signée** (~5 à 10 min).
3. Télécharger l'artefact **MP3Tagger-iOS-unsigned** : il contient
   `MP3Tagger-unsigned.ipa` (+ son SHA-256).

Le workflow se lance à chaque `push` sur `main`, ou manuellement via
**Run workflow**.

## Installer l'IPA (non signée)

Une IPA non signée ne s'installe pas telle quelle sur un iPhone non jailbreaké : iOS
exige une signature Apple. Deux solutions :

### A. Signature avec un Apple ID gratuit (le plus simple)

1. Sur un Mac ou un PC, installer [Sideloadly](https://sideloadly.io) (ou AltStore).
2. Brancher l'iPhone, glisser `MP3Tagger-unsigned.ipa` dans Sideloadly.
3. Saisir son Apple ID ; Sideloadly signe et installe l'app.
4. Sur l'iPhone : **Réglages > Général > VPN et gestion de l'appareil** → faire
   confiance au certificat développeur.

Limite d'un compte gratuit : l'app doit être re-signée tous les **7 jours**.

### B. Compte Apple Developer payant

- Soit re-signer l'IPA avec Sideloadly / AltStore avec le certificat du compte.
- Soit ajouter la signature directement dans GitHub Actions (certificat `.p12`,
  profil de provisionnement et Team ID en secrets), puis produire une IPA signée.
- Soit publier via TestFlight (App Store Connect).

L'identifiant de bundle par défaut est `com.beluga2500.mp3tagger` ; modifie-le dans
`ios/project.yml` si tu utilises ton propre compte.

## Compiler en local (macOS)

Prérequis : Xcode, Rust (`rustup`), [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
./scripts/build-unsigned-ipa.sh
# → build/ipa/MP3Tagger-unsigned.ipa
```

Ou ouvrir `ios/MP3Tagger.xcodeproj` après `xcodegen generate` et lancer sur un iPhone
depuis Xcode (signature automatique avec ton compte Apple).

## Notes techniques

- **Pourquoi Rust ?** La version bureau utilise déjà `lofty`, qui gère proprement les
  tags ID3v2 et les pochettes. On réutilise exactement la même logique pour garantir un
  résultat identique.
- **Correctif pochette** : en ID3v2.3, `lofty 0.21` écrit une frame `APIC` invalide si la
  description de l'image est `None`. Le cœur Rust force donc une description vide
  explicite (`Some("")`), sinon Windows, les lecteurs et l'app elle-même ne voient pas la
  pochette.
- **Formats** : MP3 (ID3v2.3). Les images acceptées sont JPG, PNG et WebP ; la sortie est
  toujours un JPEG carré 1000×1000.
- **Confidentialité** : tout est local, aucune requête réseau.
