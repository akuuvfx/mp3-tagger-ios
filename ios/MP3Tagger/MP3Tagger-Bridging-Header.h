#ifndef MP3Tagger_Bridging_Header_h
#define MP3Tagger_Bridging_Header_h

// API C exposée par le cœur Rust (core/src/lib.rs).
// Toutes les fonctions renvoient du JSON UTF-8 alloué par Rust : il faut
// impérativement le libérer avec mp3tag_free.

char *mp3tag_read(const char *path);
char *mp3tag_write(const char *request_json);
void mp3tag_free(char *value);

#endif /* MP3Tagger_Bridging_Header_h */
