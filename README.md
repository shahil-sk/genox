# GENOX

<div align="center">

<img src="https://github.com/user-attachments/assets/eace69ca-8bd4-4053-b783-6c34ca1e3ba5" width="180" alt="genox logo" />

### FFmpeg-powered batch transcoder for DaVinci Resolve workflows

Fast, GPU-aware, and fully terminal-native.

![bash](https://img.shields.io/badge/Pure-Bash-black?style=flat-square\&logo=gnubash)
![ffmpeg](https://img.shields.io/badge/Powered%20by-FFmpeg-red?style=flat-square\&logo=ffmpeg)
![gpu](https://img.shields.io/badge/GPU-NVENC%20%7C%20VAAPI-green?style=flat-square)
![license](https://img.shields.io/badge/License-MIT-white?style=flat-square)

</div>

---

## What is GENOX?

GENOX fixes one of the most annoying parts of editing on Linux:

* Resolve Free struggles with H.264/H.265
* Resolve exports huge DNxHR/ProRes files
* Batch transcoding with raw ffmpeg is painful

GENOX automates the entire workflow.

| Workflow | Purpose                                                       |
| -------- | ------------------------------------------------------------- |
| Import   | Convert camera footage into Resolve-friendly editing codecs   |
| Render   | Compress Resolve exports into delivery-ready formats          |
| Presets  | One-click profiles for YouTube, archive, proxy, and streaming |


## Features

* Modern terminal UI
* Real-time progress widgets
* Batch queue processing
* Automatic codec detection
* NVENC + VAAPI acceleration
* Smart audio handling
* Headless/CLI mode
* Plugin + hook support
* Queue archiving
* Structured logging


## Workflow Modes

### Import

For editing inside DaVinci Resolve.

| Input                     | Output    |
| ------------------------- | --------- |
| H.264 / H.265 / AV1 / VP9 | DNxHR HQX |
| H.264 / H.265             | MPEG-4    |

### Render

For final delivery/export.

| Input          | Output |
| -------------- | ------ |
| DNxHR / ProRes | H.264  |
| DNxHR / ProRes | H.265  |
| DNxHR / ProRes | AV1    |


## Presets

| Preset         | Use Case                 |
| -------------- | ------------------------ |
| YouTube Upload | H.264 + AAC              |
| Archive Master | DNxHR HQX + PCM          |
| Proxy Edit     | Fast lightweight proxies |
| Web Streaming  | AV1 + Opus               |


## Hardware Acceleration

GENOX automatically detects:

* NVIDIA NVENC
* Intel/AMD VAAPI
* CPU fallback

Priority:

```text
NVENC → VAAPI → CPU
```


## Architecture

```text
genox/
├── genox.sh
├── lib/
│   ├── tui.sh
│   ├── queue.sh
│   ├── codecs.sh
│   ├── hw.sh
│   ├── settings.sh
│   └── main.sh
├── presets/
└── plugins/
```


## Installation

### Arch Linux

```bash
sudo pacman -S ffmpeg
```

### Ubuntu / Debian

```bash
sudo apt install ffmpeg
```

### Fedora

```bash
sudo dnf install ffmpeg
```


## Usage

```bash
chmod +x genox.sh
./genox.sh
```

### Headless Mode

```bash
./genox.sh \
  --no-tui \
  --input ~/Videos/queue \
  --output ~/Videos/rendered
```


## Folder Layout

```text
~/Videos/
├── convert_queue/
│   └── archive/
└── converted/
```


## Why GENOX?

| Traditional ffmpeg Workflow | GENOX                    |
| --------------------------- | ------------------------ |
| Manual commands             | Interactive workflow     |
| Single-file conversion      | Batch queue engine       |
| No GPU logic                | Automatic acceleration   |
| Raw terminal spam           | Clean live interface     |
| Generic transcoding         | Resolve-focused pipeline |


## License

MIT License

Copyright (c) 2026 Shahil Ahmed
