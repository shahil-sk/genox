# genox

> **FFmpeg-powered batch video transcoder for DaVinci Resolve workflows.**  
> A pure-bash TUI that converts entire folders of videos — no extra installs beyond `ffmpeg`, `ffprobe`, `file`, and `awk`.

---

## What is genox?

`genox.sh` solves a very specific and frustrating problem: **DaVinci Resolve is picky about video codecs**.

Resolve refuses to import common delivery codecs like H.264 and H.265 (HEVC) without a paid Studio licence on Linux, and it exports in high-quality editing formats like DNxHR or ProRes that are huge and not ready to share directly.

`genox` handles **both directions** of that problem:

| Direction | When to use | What it does |
|---|---|---|
| **Import** | Before editing in Resolve | Converts H.264 / H.265 / AV1 / VP9 → DNxHR, AV1, or MPEG-4 (Resolve-compatible) |
| **Render** | After exporting from Resolve | Converts DNxHR / ProRes → H.264, H.265, or AV1 for sharing/upload |

It also ships with quick **Presets** for common workflows: YouTube upload, archival master, proxy edit, and web streaming.

---

## How it works

genox/
├── genox.sh          ← entry point (sources lib/* in order, calls main)
└── lib/
    ├── config.sh     ← global defaults, load_config, save_config
    ├── terminal.sh   ← ANSI colours, cursor helpers, log()
    ├── tui.sh        ← all TUI primitives (box, menu, input, progress, scroll, splash)
    ├── notify.sh     ← notify_success, notify_error
    ├── hw.sh         ← detect_hw_encoders, hw_video_enc, check_dependencies
    ├── codecs.sh     ← apply_import_codec, apply_render_codec, apply_preset, helpers
    ├── queue.sh      ← check_disk_space, _encode_file, process_queue, view_log
    ├── settings.sh   ← handle_settings (TUI settings screen)
    ├── cli.sh        ← parse_args
    └── main.sh       ← main() — init + interactive menu loop
    
    
1. You drop video files into the **input queue folder** (`~/Videos/convert_queue` by default).
2. You run the script, pick a workflow from the interactive TUI menu.
3. The script uses `ffprobe` to detect each file's codec, container, frame rate, and audio format.
4. It skips files that don't match the expected input codec (so it never re-encodes already-converted files).
5. `ffmpeg` encodes the matching files one-by-one, with a **real-time progress bar** per file.
6. Converted files land in the **output folder** (`~/Videos/converted` by default).
7. Desktop notifications (`notify-send`) report progress and completion.

### Hardware acceleration

The script auto-detects NVIDIA NVENC and Intel/AMD VAAPI encoders and uses them when available — falling back to software CPU encoding if not. You can force a specific mode in Settings.

### Audio handling

- If the source audio is PCM (uncompressed), it is **copied as-is** — no re-encoding.
- If the source audio is AAC or anything else, it's converted to **16-bit PCM** for import mode (best for editing) or **AAC 192k / Opus 128k** for render/delivery mode.

---

## Requirements

| Tool | Purpose | Bundled with |
|---|---|---|
| `ffmpeg` | Encoding engine | Install separately (see below) |
| `ffprobe` | Codec/frame-rate detection | Ships with ffmpeg |
| `file` | MIME-type detection | `util-linux` / every Linux distro |
| `awk` | Math & text processing | `gawk`/`mawk` / every Linux distro |
| `tput` | Terminal colours & layout | `ncurses` / every Linux distro |

### Install ffmpeg

```bash
# Ubuntu / Debian
sudo apt install ffmpeg

# Arch Linux
sudo pacman -S ffmpeg

# Fedora
sudo dnf install ffmpeg

# macOS (Homebrew)
brew install ffmpeg
```

---

## How to use

### 1. Make the script executable

```bash
chmod +x genox.sh
```

### 2. Run it

```bash
./genox.sh
```

You'll be greeted with an interactive TUI menu.

### 3. Pick your workflow

```
┌─── Video Batch Converter ───────────────────────────────────────┐
│                                                                  │
│  Input : ~/Videos/convert_queue                                  │
│  Output: ~/Videos/converted                                      │
│  HW: auto | Move: false | Dry: false                             │
│                                                                  │
│  > Import -- editing codec (DNxHR / AV1 / MPEG-4)               │
│    Render -- delivery codec (H.264 / H.265 / AV1)               │
│    Presets -- quick profiles                                     │
│    Settings                                                      │
│    View Log                                                      │
│    Exit                                                          │
└──────────────────────────────────────────────────────────────────┘
```

Navigate with **arrow keys** or **number keys**, press **Enter** to select, **Q** to go back.

### 4. Available modes

#### Import (before editing in DaVinci Resolve)

| Option | Input codecs accepted | Output |
|---|---|---|
| DNxHR HQX | h264, hevc, av1, vp9 | 10-bit YUV422, `.mov` |
| AV1 | h264, hevc, vp9 | 10-bit YUV420, `.mp4` |
| MPEG-4 Part 2 | h264, hevc, av1, vp9 | lossy, `.mov` (legacy) |

#### Render (after exporting from DaVinci Resolve)

| Option | Input codecs accepted | Output |
|---|---|---|
| H.264 CRF 20 | dnxhd, prores | `.mp4` |
| H.265 CRF 20 | dnxhd, prores | `.mov` |
| AV1 CRF 25 | dnxhd, prores | `.mp4` |

#### Quick Presets

| Preset | Best for | Output |
|---|---|---|
| YouTube Upload | Sharing online | H.264 CRF18, AAC 192k, `.mp4` |
| Archive Master | Long-term storage | DNxHR HQX 10-bit, PCM, `.mov` |
| Proxy Edit | Fast offline editing | H.264 CRF28 ultrafast, `.mp4` |
| Web Streaming | Web embeds | AV1 CRF30, Opus, `.webm` |

### 5. Settings

From the **Settings** menu you can change:
- Input and output directory paths
- Hardware acceleration mode (`auto` / `nvenc` / `vaapi` / `none`)
- Whether to move source files to an `archive/` subfolder after encode
- A custom post-conversion shell hook (e.g., to auto-upload or notify)
- Dry-run mode (simulate without actually encoding)

Settings are saved to `~/.config/video-convert/config` and loaded on next launch.

### 6. Headless / CLI mode (no TUI)

For use in scripts or cron jobs:

```bash
./genox.sh --no-tui --input /path/to/videos --output /path/to/out
```

Full CLI options:

```
-i, --input  DIR    Input queue directory
-o, --output DIR    Output directory
--hw  MODE          auto | nvenc | vaapi | none
--dry-run           Simulate without encoding
--no-tui            Headless / cron mode
--move              Move source to archive/ after success
--hook CMD          Post-encode hook ($INPUT and $OUTPUT available)
-h, --help          Show help
```

---

## What to do with the final exported video

Once you've exported from DaVinci Resolve (DNxHR or ProRes `.mov`) and run it through `genox` in **Render** mode, you'll have a compressed delivery file in `~/Videos/converted/`.

| Platform | Recommended preset | Notes |
|---|---|---|
| **YouTube** | YouTube Upload (H.264 CRF18) | H.264 + AAC `.mp4` — maximum compatibility, fast processing by YouTube |
| **Vimeo** | YouTube Upload or H.265 CRF20 | Vimeo accepts H.265; slightly smaller file for same quality |
| **Instagram / TikTok** | YouTube Upload (H.264 CRF18) | These platforms re-encode anyway; H.264 `.mp4` is safest |
| **Archive / long-term storage** | Archive Master preset | Lossless-quality DNxHR `.mov` — keep this alongside the Resolve project |
| **Web embed** | Web Streaming (AV1 CRF30) | Smallest file size for `<video>` tags; best for bandwidth-sensitive sites |
| **Client delivery** | H.264 CRF18 or H.265 CRF20 | Both play on any modern device without extra software |

> **Tip:** Always keep the original Resolve export (DNxHR/ProRes) as your master. The compressed delivery file is for distribution — re-compress from the master if you ever need a different format.

---

## Folder structure

```
~/Videos/
├── convert_queue/      ← Drop input videos here
│   └── archive/        ← Source files moved here after encode (if --move enabled)
└── converted/          ← Converted output files land here
```

Both folders are created automatically on first run.

---

## Logs

A timestamped log file is created in `~/Videos/` on every run:
```
~/Videos/convert_log_20260504_193000.log
```
You can also view the latest log from within the TUI via **View Log**.

---

## License

MIT
