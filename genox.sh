#!/usr/bin/bash
# ==============================================================================
# genox.sh — FFmpeg batch video transcoder (entry point)
# Pure-bash TUI (no whiptail, no extra installs required)
# Dependencies: ffmpeg, ffprobe, file, awk, tput — all ship with any Linux distro
# ==============================================================================

set -euo pipefail

# Resolve the directory this script lives in so lib/ can be found regardless
# of where the user calls genox.sh from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load modules in dependency order
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/terminal.sh"
source "$SCRIPT_DIR/lib/tui.sh"
source "$SCRIPT_DIR/lib/notify.sh"
source "$SCRIPT_DIR/lib/hw.sh"
source "$SCRIPT_DIR/lib/codecs.sh"
source "$SCRIPT_DIR/lib/queue.sh"
source "$SCRIPT_DIR/lib/settings.sh"
source "$SCRIPT_DIR/lib/cli.sh"
source "$SCRIPT_DIR/lib/main.sh"

main "$@"
