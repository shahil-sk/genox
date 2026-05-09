<div align="center">
<h1>GENOX</h1>
<img src="https://github.com/user-attachments/assets/eace69ca-8bd4-4053-b783-6c34ca1e3ba5" width="180" alt="genox logo" />

### FFmpeg-powered batch transcoder for DaVinci Resolve workflows

Fast, GPU-aware, and fully terminal-native. <a href="https://shahil-sk.github.io/genox/">Try_Web_Here</a>

![bash](https://img.shields.io/badge/Pure-Bash-black?style=flat-square\&logo=gnubash)
![ffmpeg](https://img.shields.io/badge/Powered%20by-FFmpeg-red?style=flat-square\&logo=ffmpeg)
![gpu](https://img.shields.io/badge/GPU-NVENC%20%7C%20VAAPI-green?style=flat-square)
![license](https://img.shields.io/badge/License-MIT-white?style=flat-square)

</div>

---

## What is GENOX? 
GENOX is a Resolve-focused FFmpeg workflow generator built for Linux editors.

DaVinci Resolve Free on Linux has limited codec support, especially with H.264, H.265 (HEVC), and AAC audio. GENOX simplifies the process of converting footage into Resolve-friendly formats by automatically generating ready-to-run FFmpeg commands.

Instead of manually writing complex transcoding commands, GENOX provides an interactive workflow for importing, proxy generation, rendering, and final delivery compression.

## Problems GENOX Solves
- Fix unsupported codecs in DaVinci Resolve
- Fix missing timeline audio caused by AAC incompatibility
- Convert H.264 / H.265 footage into editable formats
- Compress massive DNxHR or ProRes exports
- Batch-generate FFmpeg commands instantly
- Simplify Linux-based Resolve workflows

### Core Workflow Modes

| Workflow  | Purpose                                              |
| --------- | ---------------------------------------------------- |
| Import    | Convert camera footage into Resolve-friendly codecs  |
| Render    | Compress Resolve exports into delivery-ready formats |
| Proxy     | Generate lightweight proxy media for smooth editing  |
| Archive   | Create high-quality archival masters                 |
| Streaming | Encode optimized web delivery formats                |


## Features

- Modern terminal UI
- Real-time progress widgets
- Batch queue processing
- Automatic codec detection
- NVIDIA NVENC acceleration
- Intel/AMD VAAPI acceleration
- CPU fallback support
- Smart audio transcoding
- Headless / automation mode
- Plugin + hook system
- Queue archiving
- Structured logging
- Resolve-focused preset engine
- Lightweight pure Bash architecture


## Workflow Modes

### Import

Optimized for editing inside DaVinci Resolve.

| Input Codec   | Output Codec |
| ------------- | ------------ |
| H.264         | DNxHR HQX    |
| H.265 / HEVC  | DNxHR HQX    |
| AV1           | DNxHR HQX    |
| VP9           | DNxHR HQX    |
| H.264 / H.265 | MPEG-4       |

#### Ideal For
- Camera footage, OBS recordings, iPhone videos, Mirrorless cameras, Screen captures

### Render

Optimized for final export and delivery.

| Input  | Output |
| ------ | ------ |
| DNxHR  | H.264  |
| DNxHR  | H.265  |
| DNxHR  | AV1    |
| ProRes | H.264  |
| ProRes | H.265  |
| ProRes | AV1    |

#### Ideal For
- YouTube uploads, Client delivery, Streaming platforms, Social media exports, Web distribution

## Built-in Presets

| Preset         | Codec Profile             | Use Case                       |
| -------------- | ------------------------- | ------------------------------ |
| YouTube Upload | H.264 + AAC               | Standard uploads and delivery  |
| Archive Master | DNxHR HQX + PCM           | High-quality long-term storage |
| Proxy Edit     | Low bitrate intermediates | Faster editing performance     |
| Web Streaming  | AV1 + Opus                | Efficient modern streaming     |
| Resolve Import | ProRes / DNxHR            | Resolve-compatible ingest      |


## Hardware Acceleration

GENOX automatically detects and prioritizes available hardware encoders.

Supported acceleration methods:

- NVIDIA NVENC
- Intel VAAPI
- AMD VAAPI
- CPU software encoding fallback

Priority order:
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
Perfect for automation, servers, or scripting workflows.
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

| Traditional FFmpeg Workflow | GENOX                    |
| --------------------------- | ------------------------ |
| Manual command writing      | Interactive workflow     |
| Single-file conversion      | Batch queue engine       |
| No GPU management           | Automatic acceleration   |
| Raw terminal output         | Clean live interface     |
| Generic transcoding         | Resolve-focused pipeline |
| Complex setup               | Preset-driven workflow   |

## Design Philosophy

GENOX is built around three principles:

Fast transcoding workflows
Minimal terminal friction
Professional Resolve compatibility

No bloated GUI. No unnecessary abstraction. Just efficient transcoding pipelines for Linux creators.

## License

MIT License

Copyright (c) 2026 Shahil Ahmed
