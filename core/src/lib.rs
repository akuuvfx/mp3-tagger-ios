//! Cœur de MP3 Tagger pour iOS.
//!
//! Expose une petite API C (JSON in / JSON out) utilisée par l'app SwiftUI :
//! - `mp3tag_read`  : lit les métadonnées + la pochette d'un MP3
//! - `mp3tag_write` : écrit les métadonnées + la pochette dans un MP3
//! - `mp3tag_free`  : libère une chaîne renvoyée par les deux fonctions ci-dessus

use std::ffi::{c_char, CStr, CString};
use std::io::Cursor;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::{Path, PathBuf};

use base64::Engine as _;
use image::imageops::FilterType;
use image::{DynamicImage, GenericImageView, ImageFormat};
use lofty::config::WriteOptions;
use lofty::picture::{Picture, PictureType};
use lofty::prelude::*;
use lofty::tag::{ItemKey, Tag, TagType};
use serde::{Deserialize, Serialize};

/// Taille de sortie de la pochette (carré).
const COVER_SIZE: u32 = 1000;

#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
struct TrackInfo {
    path: String,
    title: String,
    artist: String,
    album: String,
    album_artist: String,
    composer: String,
    genre: String,
    year: String,
    track: String,
    comment: String,
    cover_base64: Option<String>,
    duration_seconds: Option<f64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WriteRequest {
    path: String,
    #[serde(default)]
    title: String,
    #[serde(default)]
    artist: String,
    #[serde(default)]
    album: String,
    #[serde(default)]
    album_artist: String,
    #[serde(default)]
    composer: String,
    #[serde(default)]
    genre: String,
    #[serde(default)]
    year: String,
    #[serde(default)]
    track: String,
    #[serde(default)]
    comment: String,
    /// Chemin local (bac à sable iOS) vers l'image choisie par l'utilisateur.
    #[serde(default)]
    cover_source_path: Option<String>,
    /// Supprime la pochette existante (ignoré si `cover_source_path` est fourni).
    #[serde(default)]
    remove_cover: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ReadResponse {
    ok: bool,
    error: Option<String>,
    track: Option<TrackInfo>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct WriteResponse {
    ok: bool,
    error: Option<String>,
}

// ---------------------------------------------------------------- logique

/// Recadre au carré, redimensionne et convertit en JPEG.
fn prepare_cover(bytes: &[u8]) -> Result<Vec<u8>, String> {
    let img = image::load_from_memory(bytes).map_err(|e| format!("Image illisible : {e}"))?;
    let (w, h) = img.dimensions();
    let side = w.min(h);
    let cropped = img
        .crop_imm((w - side) / 2, (h - side) / 2, side, side)
        .resize_exact(COVER_SIZE, COVER_SIZE, FilterType::Lanczos3);
    let rgb = DynamicImage::ImageRgb8(cropped.to_rgb8());
    let mut out = Vec::new();
    rgb.write_to(&mut Cursor::new(&mut out), ImageFormat::Jpeg)
        .map_err(|e| format!("Encodage JPEG impossible : {e}"))?;
    Ok(out)
}

fn read_info(path: &Path) -> Result<TrackInfo, String> {
    let tagged = lofty::read_from_path(path).map_err(|e| format!("Lecture impossible : {e}"))?;

    let mut info = TrackInfo {
        path: path.display().to_string(),
        duration_seconds: Some(tagged.properties().duration().as_secs_f64()),
        ..Default::default()
    };

    if let Some(t) = tagged.tag(TagType::Id3v2).or_else(|| tagged.primary_tag()) {
        info.title = t.title().map(|s| s.to_string()).unwrap_or_default();
        info.artist = t.artist().map(|s| s.to_string()).unwrap_or_default();
        info.album = t.album().map(|s| s.to_string()).unwrap_or_default();
        info.genre = t.genre().map(|s| s.to_string()).unwrap_or_default();
        info.comment = t.comment().map(|s| s.to_string()).unwrap_or_default();
        info.year = t.year().map(|y| y.to_string()).unwrap_or_default();
        info.track = t.track().map(|n| n.to_string()).unwrap_or_default();
        info.album_artist = t
            .get_string(&ItemKey::AlbumArtist)
            .unwrap_or_default()
            .to_string();
        info.composer = t
            .get_string(&ItemKey::Composer)
            .unwrap_or_default()
            .to_string();

        if let Some(pic) = t.pictures().first() {
            let engine = base64::engine::general_purpose::STANDARD;
            info.cover_base64 = Some(engine.encode(pic.data()));
        }
    }

    if info.title.is_empty() {
        if let Some(stem) = path.file_stem() {
            info.title = stem.to_string_lossy().to_string();
        }
    }

    Ok(info)
}

fn set_or_remove(tag: &mut Tag, key: ItemKey, value: &str) {
    if value.trim().is_empty() {
        tag.remove_key(&key);
    } else {
        tag.insert_text(key, value.trim().to_string());
    }
}

fn write_tags(req: &WriteRequest) -> Result<(), String> {
    let path = Path::new(&req.path);
    if req.path.trim().is_empty() {
        return Err("Aucun fichier sélectionné.".into());
    }
    if !path.exists() {
        return Err("Le fichier n'existe plus.".into());
    }

    let tagged = lofty::read_from_path(path).map_err(|e| format!("Lecture impossible : {e}"))?;
    let mut tag: Tag = tagged
        .tag(TagType::Id3v2)
        .cloned()
        .unwrap_or_else(|| Tag::new(TagType::Id3v2));

    let title = req.title.trim();
    let artist = req.artist.trim();
    let album = req.album.trim();
    let genre = req.genre.trim();
    let comment = req.comment.trim();

    if title.is_empty() {
        tag.remove_title();
    } else {
        tag.set_title(title.to_string());
    }
    if artist.is_empty() {
        tag.remove_artist();
    } else {
        tag.set_artist(artist.to_string());
    }
    if album.is_empty() {
        tag.remove_album();
    } else {
        tag.set_album(album.to_string());
    }
    if genre.is_empty() {
        tag.remove_genre();
    } else {
        tag.set_genre(genre.to_string());
    }
    if comment.is_empty() {
        tag.remove_comment();
    } else {
        tag.set_comment(comment.to_string());
    }

    set_or_remove(&mut tag, ItemKey::AlbumArtist, &req.album_artist);
    set_or_remove(&mut tag, ItemKey::Composer, &req.composer);

    match req.year.trim().parse::<u32>() {
        Ok(y) => tag.set_year(y),
        Err(_) => tag.remove_year(),
    }
    match req.track.trim().parse::<u32>() {
        Ok(n) => tag.set_track(n),
        Err(_) => tag.remove_track(),
    }

    if let Some(cover_path) = &req.cover_source_path {
        let bytes = std::fs::read(cover_path).map_err(|e| format!("Image illisible : {e}"))?;
        let jpeg = prepare_cover(&bytes)?;

        tag.remove_picture_type(PictureType::CoverFront);
        let mut cursor = Cursor::new(jpeg.as_slice());
        let mut pic =
            Picture::from_reader(&mut cursor).map_err(|e| format!("Pochette invalide : {e}"))?;
        pic.set_pic_type(PictureType::CoverFront);
        // Description explicitement vide (et non `None`).
        // En ID3v2.3, lofty 0.21 convertit la description UTF-8 en UTF-16 :
        // avec `None`, il n'écrit qu'un seul octet 0x00 comme terminateur,
        // ce qui produit une frame APIC invalide (pochette illisible par
        // Windows, les lecteurs, et même par lofty au rechargement).
        pic.set_description(Some(String::new()));
        tag.push_picture(pic);
    } else if req.remove_cover {
        tag.remove_picture_type(PictureType::CoverFront);
    }

    // ID3v2.3 : meilleure compatibilité (Spotify, Windows, lecteurs variés)
    tag.save_to_path(path, WriteOptions::default().use_id3v23(true))
        .map_err(|e| format!("Écriture impossible : {e}"))?;

    Ok(())
}

// ---------------------------------------------------------------- FFI

fn path_from_c(path: *const c_char) -> Result<PathBuf, String> {
    if path.is_null() {
        return Err("Chemin manquant.".into());
    }
    let s = unsafe { CStr::from_ptr(path) }
        .to_str()
        .map_err(|_| "Chemin invalide (UTF-8 attendu).".to_string())?;
    if s.is_empty() {
        return Err("Chemin vide.".into());
    }
    Ok(PathBuf::from(s))
}

fn json_from_c(json: *const c_char) -> Result<String, String> {
    if json.is_null() {
        return Err("Requête manquante.".into());
    }
    let s = unsafe { CStr::from_ptr(json) }
        .to_str()
        .map_err(|_| "Requête invalide (UTF-8 attendu).".to_string())?;
    Ok(s.to_string())
}

fn to_c_json<T: Serialize>(value: &T, fallback: &str) -> *mut c_char {
    let json = serde_json::to_string(value).unwrap_or_else(|_| fallback.to_string());
    match CString::new(json) {
        Ok(c) => c.into_raw(),
        Err(_) => CString::new(fallback)
            .expect("la chaîne de secours ne contient pas de NUL")
            .into_raw(),
    }
}

/// Lit un MP3. Renvoie toujours une chaîne JSON allouée (à libérer avec `mp3tag_free`).
#[no_mangle]
pub extern "C" fn mp3tag_read(path: *const c_char) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| {
        match path_from_c(path).and_then(|p| read_info(&p)) {
            Ok(track) => ReadResponse {
                ok: true,
                error: None,
                track: Some(track),
            },
            Err(error) => ReadResponse {
                ok: false,
                error: Some(error),
                track: None,
            },
        }
    }));

    let response = result.unwrap_or_else(|_| ReadResponse {
        ok: false,
        error: Some("Erreur interne pendant la lecture.".into()),
        track: None,
    });
    to_c_json(
        &response,
        "{\"ok\":false,\"error\":\"Erreur interne pendant la lecture.\",\"track\":null}",
    )
}

/// Écrit les tags d'un MP3. `request` est un objet JSON UTF-8.
/// Renvoie toujours une chaîne JSON allouée (à libérer avec `mp3tag_free`).
#[no_mangle]
pub extern "C" fn mp3tag_write(request: *const c_char) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let parsed = json_from_c(request).and_then(|json| {
            let req: WriteRequest =
                serde_json::from_str(&json).map_err(|e| format!("Requête invalide : {e}"))?;
            write_tags(&req)
        });

        match parsed {
            Ok(()) => WriteResponse {
                ok: true,
                error: None,
            },
            Err(error) => WriteResponse {
                ok: false,
                error: Some(error),
            },
        }
    }));

    let response = result.unwrap_or_else(|_| WriteResponse {
        ok: false,
        error: Some("Erreur interne pendant l'enregistrement.".into()),
    });
    to_c_json(
        &response,
        "{\"ok\":false,\"error\":\"Erreur interne pendant l'enregistrement.\"}",
    )
}

/// Libère une chaîne renvoyée par `mp3tag_read` ou `mp3tag_write`.
#[no_mangle]
pub extern "C" fn mp3tag_free(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(value));
    }
}
