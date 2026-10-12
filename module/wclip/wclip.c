/*
 * wclip - Windows clipboard tool
 *
 * Usage:
 *   wclip paste [--detect]    Paste clipboard to stdout
 *   wclip copy                Copy stdin to clipboard
 *
 * paste: detects CF_DIB (image), CF_HDROP (file), CF_UNICODETEXT (text)
 *   --detect: only print type string (image/file/text/empty), no data
 *
 * copy: reads stdin, detects BMP magic -> CF_DIB, otherwise -> CF_UNICODETEXT
 */

#include <windows.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <io.h>
#include <wchar.h>

/* ── UTF conversion helpers ── */

static char *utf16_to_utf8(const wchar_t *wstr) {
    if (!wstr) return NULL;
    int len = WideCharToMultiByte(CP_UTF8, 0, wstr, -1, NULL, 0, NULL, NULL);
    if (len <= 0) return NULL;
    char *out = (char *)malloc((size_t)len);
    if (!out) return NULL;
    if (WideCharToMultiByte(CP_UTF8, 0, wstr, -1, out, len, NULL, NULL) <= 0) {
        free(out);
        return NULL;
    }
    return out;
}

static wchar_t *utf8_to_utf16(const char *str) {
    if (!str) return NULL;
    int len = MultiByteToWideChar(CP_UTF8, 0, str, -1, NULL, 0);
    if (len <= 0) return NULL;
    wchar_t *out = (wchar_t *)malloc((size_t)len * sizeof(wchar_t));
    if (!out) return NULL;
    if (MultiByteToWideChar(CP_UTF8, 0, str, -1, out, len) <= 0) {
        free(out);
        return NULL;
    }
    return out;
}

/* ── CRLF → LF normalization ── */

static void normalize_lf_inplace(char *text) {
    if (!text) return;
    char *src = text, *dst = text;
    while (*src) {
        if (src[0] == '\r' && src[1] == '\n') {
            *dst++ = '\n';
            src += 2;
        } else {
            *dst++ = *src++;
        }
    }
    *dst = '\0';
}

/* ── Dynamic buffer for reading stdin ── */

typedef struct {
    unsigned char *data;
    size_t len;
    size_t cap;
} Buffer;

static void buf_init(Buffer *b) {
    b->cap = 4096;
    b->data = (unsigned char *)malloc(b->cap);
    b->len = 0;
}

static void buf_append(Buffer *b, const unsigned char *chunk, size_t n) {
    while (b->len + n > b->cap) {
        b->cap *= 2;
        b->data = (unsigned char *)realloc(b->data, b->cap);
    }
    memcpy(b->data + b->len, chunk, n);
    b->len += n;
}

static void buf_free(Buffer *b) {
    free(b->data);
    b->data = NULL;
    b->len = b->cap = 0;
}

/* ── Clipboard type detection ── */

typedef enum {
    CB_IMAGE,
    CB_FILE,
    CB_TEXT,
    CB_EMPTY
} ClipType;

static ClipType detect_clipboard_type(void) {
    if (IsClipboardFormatAvailable(CF_DIB))
        return CB_IMAGE;
    if (IsClipboardFormatAvailable(CF_HDROP))
        return CB_FILE;
    if (IsClipboardFormatAvailable(CF_UNICODETEXT))
        return CB_TEXT;
    return CB_EMPTY;
}

static const char *clip_type_str(ClipType t) {
    switch (t) {
        case CB_IMAGE: return "image";
        case CB_FILE:  return "file";
        case CB_TEXT:  return "text";
        default:       return "empty";
    }
}

/* ── Paste: text ── */

static int paste_text(void) {
    if (!OpenClipboard(NULL)) return 1;
    HANDLE h = GetClipboardData(CF_UNICODETEXT);
    if (!h) { CloseClipboard(); return 1; }
    wchar_t *wtext = (wchar_t *)GlobalLock(h);
    if (!wtext) { CloseClipboard(); return 1; }
    char *utf8 = utf16_to_utf8(wtext);
    GlobalUnlock(h);
    CloseClipboard();
    if (!utf8) return 1;
    normalize_lf_inplace(utf8);
    _setmode(_fileno(stdout), _O_BINARY);
    size_t len = strlen(utf8);
    fwrite(utf8, 1, len, stdout);
    free(utf8);
    return 0;
}

/* ── Paste: image (CF_DIB → BMP file) ── */

#pragma pack(push, 1)
typedef struct {
    unsigned short bfType;
    unsigned int   bfSize;
    unsigned short bfReserved1;
    unsigned short bfReserved2;
    unsigned int   bfOffBits;
} BMPFileHeader;
#pragma pack(pop)

static int paste_image(void) {
    if (!OpenClipboard(NULL)) return 1;
    HANDLE h = GetClipboardData(CF_DIB);
    if (!h) { CloseClipboard(); return 1; }
    void *dib = GlobalLock(h);
    if (!dib) { CloseClipboard(); return 1; }
    SIZE_T dib_size = GlobalSize(h);

    /* Build BMP file header */
    BITMAPINFOHEADER *bi = (BITMAPINFOHEADER *)dib;
    unsigned int color_table_size = 0;
    if (bi->biBitCount <= 8) {
        unsigned int colors = bi->biClrUsed ? bi->biClrUsed : (1u << bi->biBitCount);
        color_table_size = colors * sizeof(RGBQUAD);
    }

    BMPFileHeader fh;
    fh.bfType = 0x4D42; /* "BM" */
    fh.bfSize = (unsigned int)(sizeof(BMPFileHeader) + dib_size);
    fh.bfReserved1 = 0;
    fh.bfReserved2 = 0;
    fh.bfOffBits = (unsigned int)(sizeof(BMPFileHeader) + sizeof(BITMAPINFOHEADER) + color_table_size);

    _setmode(_fileno(stdout), _O_BINARY);
    fwrite(&fh, 1, sizeof(fh), stdout);
    fwrite(dib, 1, dib_size, stdout);
    fflush(stdout);

    GlobalUnlock(h);
    CloseClipboard();
    return 0;
}

/* ── Paste: file (CF_HDROP) ── */

static int paste_file(void) {
    if (!OpenClipboard(NULL)) return 1;
    HANDLE h = GetClipboardData(CF_HDROP);
    if (!h) { CloseClipboard(); return 1; }

    HDROP hDrop = (HDROP)h;
    UINT count = DragQueryFileW(hDrop, 0xFFFFFFFF, NULL, 0);

    _setmode(_fileno(stdout), _O_BINARY);

    for (UINT i = 0; i < count; i++) {
        UINT pathlen = DragQueryFileW(hDrop, i, NULL, 0);
        wchar_t *wpath = (wchar_t *)malloc((pathlen + 1) * sizeof(wchar_t));
        if (!wpath) continue;
        DragQueryFileW(hDrop, i, wpath, pathlen + 1);

        HANDLE fh = CreateFileW(wpath, GENERIC_READ, FILE_SHARE_READ, NULL,
                                OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        free(wpath);
        if (fh == INVALID_HANDLE_VALUE) continue;

        unsigned char buf[8192];
        DWORD bytesRead;
        while (ReadFile(fh, buf, sizeof(buf), &bytesRead, NULL) && bytesRead > 0) {
            fwrite(buf, 1, bytesRead, stdout);
        }
        CloseHandle(fh);
    }
    fflush(stdout);
    CloseClipboard();
    return 0;
}

/* ── Copy: text (stdin → CF_UNICODETEXT) ── */

static int copy_text(const unsigned char *data, size_t len) {
    /* Ensure null termination for UTF-8 string */
    char *text = (char *)malloc(len + 1);
    if (!text) return 1;
    memcpy(text, data, len);
    text[len] = '\0';

    wchar_t *wtext = utf8_to_utf16(text);
    free(text);
    if (!wtext) return 1;

    size_t wbytes = (wcslen(wtext) + 1) * sizeof(wchar_t);
    HGLOBAL hmem = GlobalAlloc(GMEM_MOVEABLE, wbytes);
    if (!hmem) { free(wtext); return 1; }

    void *dst = GlobalLock(hmem);
    if (!dst) { GlobalFree(hmem); free(wtext); return 1; }
    memcpy(dst, wtext, wbytes);
    GlobalUnlock(hmem);
    free(wtext);

    if (!OpenClipboard(NULL)) { GlobalFree(hmem); return 1; }
    EmptyClipboard();
    if (!SetClipboardData(CF_UNICODETEXT, hmem)) {
        CloseClipboard();
        GlobalFree(hmem);
        return 1;
    }
    CloseClipboard();
    return 0;
}

/* ── Copy: BMP image (stdin → CF_DIB) ── */

static int copy_image_bmp(const unsigned char *data, size_t len) {
    /* Skip 14-byte BMP file header, rest is DIB */
    if (len <= 14) return 1;
    const unsigned char *dib = data + 14;
    size_t dib_size = len - 14;

    HGLOBAL hmem = GlobalAlloc(GMEM_MOVEABLE, dib_size);
    if (!hmem) return 1;

    void *dst = GlobalLock(hmem);
    if (!dst) { GlobalFree(hmem); return 1; }
    memcpy(dst, dib, dib_size);
    GlobalUnlock(hmem);

    if (!OpenClipboard(NULL)) { GlobalFree(hmem); return 1; }
    EmptyClipboard();
    if (!SetClipboardData(CF_DIB, hmem)) {
        CloseClipboard();
        GlobalFree(hmem);
        return 1;
    }
    CloseClipboard();
    return 0;
}

/* ── Read all stdin ── */

static Buffer read_stdin_all(void) {
    Buffer b;
    buf_init(&b);
    _setmode(_fileno(stdin), _O_BINARY);
    unsigned char chunk[8192];
    size_t n;
    while ((n = fread(chunk, 1, sizeof(chunk), stdin)) > 0) {
        buf_append(&b, chunk, n);
    }
    return b;
}

/* ── Usage ── */

static void usage(void) {
    fprintf(stderr, "Usage: wclip paste [--detect]\n"
                    "       wclip copy\n");
}

/* ── Main ── */

int main(int argc, char **argv) {
    SetConsoleOutputCP(65001);
    SetConsoleCP(65001);

    if (argc < 2) { usage(); return 1; }

    if (strcmp(argv[1], "paste") == 0) {
        int detect = 0;
        for (int i = 2; i < argc; i++) {
            if (strcmp(argv[i], "--detect") == 0) detect = 1;
        }

        ClipType t = detect_clipboard_type();

        if (detect) {
            printf("%s\n", clip_type_str(t));
            return 0;
        }

        switch (t) {
            case CB_TEXT:  return paste_text();
            case CB_IMAGE: return paste_image();
            case CB_FILE:  return paste_file();
            case CB_EMPTY:
                fprintf(stderr, "wclip: clipboard is empty\n");
                return 1;
        }
    } else if (strcmp(argv[1], "copy") == 0) {
        Buffer b = read_stdin_all();
        if (b.len == 0) {
            buf_free(&b);
            fprintf(stderr, "wclip: no input\n");
            return 1;
        }

        int rc;
        /* Check BMP magic: "BM" (0x42 0x4D) */
        if (b.len > 14 && b.data[0] == 0x42 && b.data[1] == 0x4D) {
            rc = copy_image_bmp(b.data, b.len);
        } else {
            rc = copy_text(b.data, b.len);
        }
        buf_free(&b);
        return rc;
    } else {
        usage();
        return 1;
    }

    return 0;
}
