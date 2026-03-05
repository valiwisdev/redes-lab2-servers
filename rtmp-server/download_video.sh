#!/bin/bash
# =============================================================================
#  download_video.sh — Download YouTube videos for the RTMP server
#
#  Usage:
#    bash download_video.sh                  (interactive mode)
#    bash download_video.sh --list           (list downloaded videos)
#    bash download_video.sh --delete         (delete a video)
# =============================================================================

set -e

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m';  YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m';   MAGENTA='\033[0;35m'
BOLD='\033[1m';    DIM='\033[2m';       NC='\033[0m'

info()    { echo -e "  ${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "  ${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "  ${RED}[ERROR]${NC} $*"; }
step()    { echo -e "\n  ${BOLD}${BLUE}▶ $*${NC}"; }
divider() { echo -e "  ${DIM}────────────────────────────────────────────────${NC}"; }

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIDEOS_DIR="$SCRIPT_DIR/videos"
mkdir -p "$VIDEOS_DIR"

# =============================================================================
#  DEPENDENCY HELPERS
# =============================================================================

# ── Silent status checks ──────────────────────────────────────────────────────
deps_installed() {
    command -v yt-dlp &>/dev/null && command -v ffmpeg &>/dev/null
}

dep_status_line() {
    local ytdlp_s ffmpeg_s
    if command -v yt-dlp &>/dev/null; then
        ytdlp_s="${GREEN}yt-dlp $(yt-dlp --version 2>/dev/null)${NC}"
    else
        ytdlp_s="${RED}yt-dlp not installed${NC}"
    fi
    if command -v ffmpeg &>/dev/null; then
        ffmpeg_s="${GREEN}ffmpeg $(ffmpeg -version 2>&1 | awk '/ffmpeg version/{print $3}')${NC}"
    else
        ffmpeg_s="${RED}ffmpeg not installed${NC}"
    fi
    echo -e "  ${DIM}${ytdlp_s}  |  ${ffmpeg_s}${NC}"
}

# ── Install both dependencies ─────────────────────────────────────────────────
install_deps() {
    echo ""
    step "Installing dependencies (yt-dlp + ffmpeg)..."
    echo ""

    # ── ffmpeg ────────────────────────────────────────────────────────────────
    if command -v ffmpeg &>/dev/null; then
        ok "ffmpeg already installed: $(ffmpeg -version 2>&1 | awk '/ffmpeg version/{print $3}')"
    else
        step "Installing ffmpeg..."
        if command -v apt-get &>/dev/null; then
            apt-get update -qq && apt-get install -y -q ffmpeg
        elif command -v yum &>/dev/null; then
            yum install -y -q ffmpeg
        else
            error "Unsupported package manager — install ffmpeg manually."
        fi
        command -v ffmpeg &>/dev/null \
            && ok "ffmpeg installed." \
            || error "ffmpeg installation failed."
    fi

    # ── yt-dlp ────────────────────────────────────────────────────────────────
    if command -v yt-dlp &>/dev/null; then
        ok "yt-dlp already installed: $(yt-dlp --version)"
    else
        step "Installing yt-dlp..."
        if command -v pip3 &>/dev/null; then
            pip3 install -q yt-dlp
        elif command -v pip &>/dev/null; then
            pip install -q yt-dlp
        else
            local bin_path="/usr/local/bin/yt-dlp"
            curl -fsSL "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" \
                -o "$bin_path"
            chmod +x "$bin_path"
        fi
        command -v yt-dlp &>/dev/null \
            && ok "yt-dlp installed: $(yt-dlp --version)" \
            || error "yt-dlp installation failed. Try: pip3 install yt-dlp"
    fi
}

# ── Gate: call at the top of any action that needs the deps ───────────────────
# Returns 1 and prints a message if deps are missing, so the caller can return
# immediately back to the menu without doing any work.
require_deps() {
    if ! deps_installed; then
        echo ""
        error "Dependencies are not installed."
        info  "Select option ${BOLD}a) Install dependencies${NC} from the menu first."
        echo ""
        read -rp "  Press Enter to return to menu..." _
        return 1
    fi
}

# =============================================================================
#  LIST VIDEOS
# =============================================================================
list_videos() {
    local existing=()
    while IFS= read -r -d '' f; do
        existing+=("$f")
    done < <(find "$VIDEOS_DIR" -maxdepth 1 -name "*.mp4" -print0 2>/dev/null | sort -z)

    if [[ ${#existing[@]} -eq 0 ]]; then
        warn "No videos found in: $VIDEOS_DIR"
        return 1
    fi

    echo ""
    echo -e "  ${BOLD}Videos available in ${CYAN}$VIDEOS_DIR${NC}:${NC}"
    echo ""
    divider

    local i=1
    for f in "${existing[@]}"; do
        local name size
        name=$(basename "$f")
        size=$(du -sh "$f" 2>/dev/null | cut -f1)
        printf "   ${BOLD}%2d)${NC}  ${GREEN}%-50s${NC}  ${DIM}%s${NC}\n" "$i" "$name" "$size"
        ((i++))
    done

    divider
    echo ""
    return 0
}

# =============================================================================
#  PICK A VIDEO (used by installer)
# =============================================================================
# Prints the chosen filename to stdout (last line).
# Returns 1 if no videos exist.
pick_video() {
    local files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "$VIDEOS_DIR" -maxdepth 1 -name "*.mp4" -print0 2>/dev/null | sort -z)

    if [[ ${#files[@]} -eq 0 ]]; then
        warn "No videos found in: $VIDEOS_DIR"
        echo ""
        read -rp "  Download one now? (Y/n): " dl
        if [[ ! "$dl" =~ ^[nN]$ ]]; then
            download_interactive
            # Retry pick after download
            pick_video
            return $?
        fi
        return 1
    fi

    echo ""
    echo -e "  ${BOLD}Select a video to stream:${NC}"
    echo ""
    divider

    local i=1
    for f in "${files[@]}"; do
        local name size
        name=$(basename "$f")
        size=$(du -sh "$f" 2>/dev/null | cut -f1)
        printf "   ${BOLD}%2d)${NC}  ${GREEN}%-50s${NC}  ${DIM}%s${NC}\n" "$i" "$name" "$size"
        ((i++))
    done

    printf "   ${BOLD}%2d)${NC}  ${CYAN}Download a new video from YouTube${NC}\n" "$i"
    divider
    echo ""

    local choice
    while true; do
        read -rp "  → Select [1-$i]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if (( choice >= 1 && choice < i )); then
                # Return chosen filename via last echo (caller uses command substitution)
                PICKED_VIDEO=$(basename "${files[$((choice-1))]}")
                return 0
            elif (( choice == i )); then
                download_interactive
                # Re-run pick after download
                pick_video
                return $?
            fi
        fi
        warn "Please enter a number between 1 and $i."
    done
}

# =============================================================================
#  DOWNLOAD
# =============================================================================
download_interactive() {
    require_deps || return 1

    echo ""
    echo -e "  ${BOLD}${MAGENTA}YouTube Video Downloader${NC}"
    echo -e "  ${DIM}Downloads are saved to: $VIDEOS_DIR${NC}"
    echo ""
    divider
    echo ""

    while true; do
        read -rp "  YouTube URL (or 'q' to cancel): " url
        [[ "$url" =~ ^[qQ]$ || -z "$url" ]] && { info "Download cancelled."; return 0; }

        # Validate it looks like a URL
        if [[ ! "$url" =~ ^https?:// ]]; then
            warn "Please enter a full URL starting with http:// or https://"
            continue
        fi

        echo ""
        local fmt="bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best[height<=720][ext=mp4]/best[height<=720]"
        info "Format: 720p MP4"

        # Sanitize filename: use video title, replace spaces with underscores
        local out_tmpl="$VIDEOS_DIR/%(title)s.%(ext)s"

        step "Fetching video info..."
        local title
        title=$(yt-dlp --no-playlist --get-title "$url" 2>/dev/null || echo "unknown")
        info "Title: $title"
        echo ""

        read -rp "  Custom filename? (leave blank to use video title): " custom_name
        if [[ -n "$custom_name" ]]; then
            # Strip extension if provided, we'll add it
            custom_name="${custom_name%.mp4}"
            out_tmpl="$VIDEOS_DIR/${custom_name}.%(ext)s"
        fi

        step "Downloading..."
        echo ""

        if yt-dlp \
            --no-playlist \
            --format "$fmt" \
            --merge-output-format mp4 \
            --output "$out_tmpl" \
            --progress \
            --restrict-filenames \
            "$url"; then

            echo ""
            ok "Download complete!"
            list_videos
        else
            error "Download failed. Check the URL and try again."
        fi

        echo ""
        read -rp "  Download another video? (y/N): " again
        [[ "$again" =~ ^[yY]$ ]] || break
    done
}

# =============================================================================
#  DELETE VIDEO
# =============================================================================
delete_video() {
    require_deps || return 1
    if ! list_videos; then return; fi

    local files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "$VIDEOS_DIR" -maxdepth 1 -name "*.mp4" -print0 2>/dev/null | sort -z)

    read -rp "  → Select video number to delete (or q to cancel): " choice
    [[ "$choice" =~ ^[qQ]$ || -z "$choice" ]] && return

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#files[@]} )); then
        local target="${files[$((choice-1))]}"
        read -rp "  Delete '$(basename "$target")'? (y/N): " confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
            rm -f "$target"
            ok "Deleted: $(basename "$target")"
        else
            info "Cancelled."
        fi
    else
        warn "Invalid selection."
    fi
}

# =============================================================================
#  ENTRY POINT
# =============================================================================
case "${1:-}" in
    --list)   list_videos   ;;
    --delete) delete_video  ;;
    --pick)
        # Used by installer: sets PICKED_VIDEO and exports it
        pick_video
        if [[ -n "${PICKED_VIDEO:-}" ]]; then
            echo "__PICKED__:${PICKED_VIDEO}"
        fi
        ;;
    *)
        # Standalone interactive mode
        while true; do
            echo ""
            echo -e "  ${BOLD}${MAGENTA}╔══════════════════════════════════════════╗${NC}"
            echo -e "  ${BOLD}${MAGENTA}║${NC}  ${BOLD}YouTube → RTMP Video Downloader${NC}       ${BOLD}${MAGENTA}║${NC}"
            echo -e "  ${BOLD}${MAGENTA}╚══════════════════════════════════════════╝${NC}"
            echo ""
            dep_status_line
            echo ""
            divider
            echo -e "   ${BOLD}a)${NC}  Install dependencies       ${DIM}yt-dlp + ffmpeg${NC}"
            divider
            echo -e "   ${BOLD}b)${NC}  Download a YouTube video"
            echo -e "   ${BOLD}c)${NC}  List downloaded videos"
            echo -e "   ${BOLD}d)${NC}  Delete a video"
            divider
            echo -e "   ${BOLD}q)${NC}  Quit"
            echo ""
            read -rp "  → Option: " opt
            case "$opt" in
                a) install_deps ;;
                b) download_interactive ;;
                c) list_videos ;;
                d) delete_video ;;
                q|Q|"") exit 0 ;;
                *) warn "Unknown option." ;;
            esac

            echo ""; divider
            read -rp "  Press Enter to continue..." _
        done
        ;;
esac
