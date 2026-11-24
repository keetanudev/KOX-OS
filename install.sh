#!/usr/bin/env bash
# =============================================================================
#  KOX OS installer
#
#  Deploys the KOX OS desktop on a fresh Artix Linux (OpenRC) or Arch Linux
#  (systemd) installation.
#  Run it as your normal user from the root of the KOX-OS repository:
#
#      ./install.sh
#
#  The installer is idempotent: existing configuration is backed up, pacman
#  uses --needed, and every appended shell block is guarded by a marker.
#  The init system is detected automatically; KOX_INIT=openrc|systemd is a
#  test override and must still match the detected distro family.
# =============================================================================
set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Presentation
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
    RESET=$'\033[0m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    RED=$'\033[91m'
    GREEN=$'\033[92m'
    YELLOW=$'\033[93m'
    BLUE=$'\033[94m'
    MAGENTA=$'\033[95m'
    CYAN=$'\033[96m'
    WHITE=$'\033[97m'
    PINK=$'\033[38;5;212m'
else
    RESET='' BOLD='' DIM='' RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' WHITE='' PINK=''
fi

WARNINGS=0

info() { printf '%s[ INFO ]%s %s\n' "$BLUE" "$RESET" "$*"; }
ok()   { printf '%s[  OK  ]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { WARNINGS=$((WARNINGS + 1)); printf '%s[ WARN ]%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
fail() { printf '%s[ FAIL ]%s %s\n' "$RED" "$RESET" "$*" >&2; }
die()  { fail "$*"; exit 1; }
step() { printf '\n%s%s[ STEP ]%s %s%s%s\n' "$BOLD" "$MAGENTA" "$RESET" "$BOLD" "$*" "$RESET"; }

trap 'printf "\n%s[ FAIL ]%s Unexpected error on line %s: %s\n" "$RED" "$RESET" "$LINENO" "$BASH_COMMAND" >&2' ERR

print_banner() {
    printf '\n%s%s' "$PINK" "$BOLD"
    cat <<'BANNER'
  ██╗  ██╗ ██████╗ ██╗  ██╗
  ██║ ██╔╝██╔═══██╗╚██╗██╔╝
  █████╔╝ ██║   ██║ ╚███╔╝
  ██╔═██╗ ██║   ██║ ██╔██╗
  ██║  ██╗╚██████╔╝██╔╝ ██╗
  ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝
BANNER
    printf '%s\n' "$RESET"
    printf '  %s%s%s\n' "$DIM" "${PLATFORM_LABEL:-Linux + Hyprland}" "$RESET"
    printf '  %sThe official KOX OS installer%s\n' "$DIM" "$RESET"
}

# -----------------------------------------------------------------------------
# Locate the repository and the target account
# -----------------------------------------------------------------------------
SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
if command -v readlink >/dev/null 2>&1; then
    SCRIPT_SOURCE="$(readlink -f -- "$SCRIPT_SOURCE" 2>/dev/null || printf '%s' "$SCRIPT_SOURCE")"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"
REPO_DIR="$SCRIPT_DIR"

TARGET_USER="$(id -un)"
TARGET_HOME="${HOME:-}"
if [[ -z "$TARGET_HOME" ]]; then
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
fi
PROFILE_FILE="$TARGET_HOME/.bash_profile"
WALLPAPER_DIR="$TARGET_HOME/Pictures/Wallpapers"

BACKUP_DIR=""
KOX_USER_NAME=""
SUDO_KEEPALIVE_PID=""
PLATFORM_LABEL=""
DISTRO_ID=""
DISTRO_LIKE=""
DISTRO_FAMILY=""
INIT_SYSTEM=""
SYSTEMD_RUNNING=0

PATH_BEGIN="# >>> KOX OS PATH >>>"
PATH_END="# <<< KOX OS PATH <<<"
AUTOLOGIN_BEGIN="# >>> KOX OS autologin >>>"
AUTOLOGIN_END="# <<< KOX OS autologin <<<"

# -----------------------------------------------------------------------------
# Packages
#
# Notes:
#   - Artix splits OpenRC init scripts into *-openrc packages; Arch gets the
#     units from the main packages and uses systemd-logind instead of elogind.
#   - pipewire-pulse has no OpenRC user service here; KOX starts it at session
#     login through kox-pulse-autostart. On systemd the socket units cover it.
#   - swww and inter-font are intentionally not listed: they are absent from
#     the configured Artix repositories, and KOX uses hyprpaper and the bundled
#     font set instead, so the shared list stays portable.
#   - Every name below is also present in the Arch official repositories
#     (verified against archlinux.org on 2026-11-24).
# -----------------------------------------------------------------------------
PACKAGES_COMMON=(
    # Compositor and session
    hyprland
    hyprpaper
    hyprlock
    xorg-xwayland

    # Desktop shell
    waybar
    kitty
    fuzzel
    mako
    quickshell

    # KOX panels and scaling engine
    python
    python-gobject
    python-cairo
    gtk3
    gtk-layer-shell
    dconf

    # Audio
    pipewire
    pipewire-pulse
    pipewire-alsa
    wireplumber
    libpulse

    # Networking
    networkmanager
    wpa_supplicant

    # Bluetooth
    bluez
    bluez-utils
    blueman

    # Power and hardware
    power-profiles-daemon
    upower
    udiskie
    brightnessctl

    # Session services and portals
    dbus
    polkit
    polkit-gnome
    xdg-desktop-portal
    xdg-desktop-portal-gtk
    xdg-desktop-portal-hyprland

    # Utilities used by KOX and its pickers
    jq
    ffmpeg
    grim
    slurp
    hyprpicker
    wl-clipboard
    cliphist
    libnotify
    xdg-utils
    git

    # Keybind/panel surface (Super+Space/D, Super+Escape, Super+Shift+F,
    # audio/media keys, Print capture/record, Super+Shift+N/CTRL+T, ...)
    playerctl
    wf-recorder
    nautilus
    micro
    btop

    # Fonts
    ttf-jetbrains-mono-nerd
    ttf-nerd-fonts-symbols
    noto-fonts
)

PACKAGES_OPENRC=(
    pipewire-openrc
    wireplumber-openrc
    networkmanager-openrc
    bluez-openrc
    power-profiles-daemon-openrc
    dbus-openrc
    elogind
    elogind-openrc
)

PACKAGES_SYSTEMD=()

PACKAGES=()

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
start_sudo_keepalive() {
    # Keep the sudo timestamp fresh during the long package installation.
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null || exit 0; sleep 50; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'stop_sudo_keepalive' EXIT
}

stop_sudo_keepalive() {
    if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        SUDO_KEEPALIVE_PID=""
    fi
}

check_internet() {
    local url

    if command -v curl >/dev/null 2>&1; then
        for url in https://artixlinux.org https://archlinux.org; do
            if curl -fsSL --max-time 10 -o /dev/null "$url" 2>/dev/null; then
                return 0
            fi
        done
    fi

    if command -v wget >/dev/null 2>&1; then
        for url in https://artixlinux.org https://archlinux.org; do
            if wget -q --spider --timeout=10 "$url" 2>/dev/null; then
                return 0
            fi
        done
    fi

    # Last resorts that do not depend on curl/wget being installed yet.
    if command -v timeout >/dev/null 2>&1; then
        if timeout 6 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443' 2>/dev/null; then
            return 0
        fi
    fi
    if command -v ping >/dev/null 2>&1; then
        if ping -c 1 -W 3 1.1.1.1 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

service_enabled() {
    if [[ "$INIT_SYSTEM" == systemd ]]; then
        local state root_arg=()
        (( SYSTEMD_RUNNING )) || root_arg=(--root=/)
        state="$(systemctl "${root_arg[@]}" is-enabled "$1" 2>/dev/null || true)"
        [[ "$state" == enabled || "$state" == static ||
            "$state" == alias || "$state" == indirect ]]
        return
    fi

    rc-update show 2>/dev/null |
        awk -v svc="$1" '$1 == svc { found = 1 } END { exit(found ? 0 : 1) }'
}

user_service_enabled() {
    if [[ "$INIT_SYSTEM" == systemd ]]; then
        systemctl --user is-enabled --quiet "$1" 2>/dev/null
        return
    fi

    rc-update --user show 2>/dev/null |
        awk -v svc="$1" '$1 == svc { found = 1 } END { exit(found ? 0 : 1) }'
}

find_system_service() {
    local candidate unit root_arg=()
    if [[ "$INIT_SYSTEM" == systemd ]]; then
        (( SYSTEMD_RUNNING )) || root_arg=(--root=/)
        for candidate in "$@"; do
            unit="${candidate%.service}.service"
            if systemctl "${root_arg[@]}" list-unit-files --no-legend --no-pager "$unit" 2>/dev/null |
                awk -v u="$unit" '$1 == u { found = 1 } END { exit(found ? 0 : 1) }'; then
                printf '%s\n' "${unit%.service}"
                return 0
            fi
        done
        return 1
    fi

    for candidate in "$@"; do
        if [[ -x "/etc/init.d/$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

enable_system_unit_offline() {
    # systemd is not PID 1 here (image/chroot provisioning). `--root=/`
    # writes the wants symlinks without contacting a manager.
    sudo systemctl --root=/ --no-reload enable "$1"
}

ensure_system_service() {
    local label="$1"
    shift
    local svc

    if ! svc="$(find_system_service "$@")"; then
        if [[ "$INIT_SYSTEM" == systemd ]]; then
            warn "No systemd unit found for $label (tried: $*)."
        else
            warn "No OpenRC init script found for $label (tried: $*)."
        fi
        return 0
    fi

    if service_enabled "$svc"; then
        info "$svc is already enabled."
    else
        info "Enabling $svc ..."
        if [[ "$INIT_SYSTEM" == systemd ]]; then
            if (( SYSTEMD_RUNNING )); then
                if sudo systemctl enable "$svc" >/dev/null 2>&1; then
                    ok "$svc enabled."
                else
                    warn "Could not enable $svc."
                fi
            elif enable_system_unit_offline "$svc" >/dev/null 2>&1; then
                ok "$svc enabled for the next boot."
            else
                warn "Could not enable $svc offline."
            fi
        elif sudo rc-update add "$svc" default >/dev/null 2>&1; then
            ok "$svc enabled in the default runlevel."
        else
            warn "Could not enable $svc."
        fi
    fi

    if [[ "$INIT_SYSTEM" == systemd ]] && (( ! SYSTEMD_RUNNING )); then
        info "Offline install: $svc starts on the next boot."
        return 0
    fi

    if [[ "$INIT_SYSTEM" == systemd ]]; then
        if systemctl is-active --quiet "$svc"; then
            ok "$svc is already running."
        else
            info "Starting $svc ..."
            if sudo systemctl start "$svc" >/dev/null 2>&1; then
                ok "$svc started."
            else
                warn "Could not start $svc. Check: sudo systemctl status $svc"
            fi
        fi
        return 0
    fi

    if sudo rc-service "$svc" status >/dev/null 2>&1; then
        ok "$svc is already running."
    else
        info "Starting $svc ..."
        if sudo rc-service "$svc" start >/dev/null 2>&1; then
            ok "$svc started."
        else
            warn "Could not start $svc. Check: sudo rc-service $svc start"
        fi
    fi
}

ensure_user_service() {
    local svc="$1"
    local label="${2:-$1}"

    if [[ "$INIT_SYSTEM" == systemd ]]; then
        if (( ! SYSTEMD_RUNNING )); then
            info "Offline install: $label starts with the first Hyprland login via kox-pulse-autostart."
            return 0
        fi

        if user_service_enabled "$svc"; then
            info "$label user unit is already enabled."
        else
            info "Enabling $label user unit ..."
            if systemctl --user enable "$svc" >/dev/null 2>&1; then
                ok "$label user unit enabled."
            else
                warn "Could not enable the $label user unit."
            fi
        fi

        if systemctl --user is-active --quiet "$svc"; then
            ok "$label user unit is already running."
        else
            info "Starting $label user unit ..."
            if systemctl --user start "$svc" >/dev/null 2>&1; then
                ok "$label user unit started."
            else
                warn "Could not start the $label user unit. Check: systemctl --user status $svc"
            fi
        fi
        return 0
    fi

    if [[ ! -x "/etc/user/init.d/$svc" ]]; then
        warn "No OpenRC user service found for $label ($svc)."
        return 0
    fi

    if user_service_enabled "$svc"; then
        info "$svc user service is already enabled."
    else
        info "Enabling $svc user service ..."
        if rc-update --user add "$svc" default >/dev/null 2>&1; then
            ok "$svc user service enabled."
        else
            warn "Could not enable the $svc user service."
        fi
    fi

    if rc-service --user "$svc" status >/dev/null 2>&1; then
        ok "$svc user service is already running."
    else
        info "Starting $svc user service ..."
        if rc-service --user "$svc" start >/dev/null 2>&1; then
            ok "$svc user service started."
        else
            warn "Could not start the $svc user service. Check: rc-service --user $svc start"
        fi
    fi
}

# -----------------------------------------------------------------------------
# Platform detection
#
# KOX ships one tree that runs on the Artix/OpenRC development box and on the
# Arch/systemd SATA machine. Detect the init system instead of assuming either:
# running from an Arch ISO or a chroot has systemd installed but not PID 1, so
# service setup has an explicit offline path.
# -----------------------------------------------------------------------------
detect_platform() {
    [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release."
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-}"
    DISTRO_LIKE="${ID_LIKE:-}"

    case "${DISTRO_ID} ${DISTRO_LIKE}" in
        *artix*) DISTRO_FAMILY=artix ;;
        *arch*)  DISTRO_FAMILY=arch ;;
        *)
            die "KOX OS supports Artix Linux (OpenRC) and Arch Linux (systemd); detected: ${PRETTY_NAME:-unknown}."
            ;;
    esac

    case "${KOX_INIT:-auto}" in
        auto)
            if [[ -d /run/systemd/system ]]; then
                INIT_SYSTEM=systemd
            elif command -v rc-update >/dev/null 2>&1 &&
                command -v rc-service >/dev/null 2>&1; then
                INIT_SYSTEM=openrc
            elif command -v systemctl >/dev/null 2>&1; then
                INIT_SYSTEM=systemd
            else
                die "Could not determine the init system (neither OpenRC nor systemd found)."
            fi
            ;;
        openrc|systemd)
            INIT_SYSTEM="$KOX_INIT"
            ;;
        *)
            die "KOX_INIT must be 'auto', 'openrc' or 'systemd'."
            ;;
    esac

    if [[ "$INIT_SYSTEM" == systemd ]]; then
        command -v systemctl >/dev/null 2>&1 ||
            die "systemd (systemctl) is required but was not found."
        SYSTEMD_RUNNING=0
        [[ -d /run/systemd/system ]] && SYSTEMD_RUNNING=1
        PLATFORM_LABEL="${PRETTY_NAME:-Arch Linux} + Hyprland + systemd"
    else
        command -v rc-update >/dev/null 2>&1 ||
            die "OpenRC (rc-update) is required but was not found."
        command -v rc-service >/dev/null 2>&1 ||
            die "OpenRC (rc-service) is required but was not found."
        PLATFORM_LABEL="${PRETTY_NAME:-Artix Linux} + Hyprland + OpenRC"
    fi

    # Each distro keeps the init it ships. A mixed pairing installs a desktop
    # that looks complete but cannot start its services.
    if [[ "$DISTRO_FAMILY" == arch && "$INIT_SYSTEM" != systemd ]]; then
        die "Arch Linux is supported with systemd only (KOX_INIT=$INIT_SYSTEM)."
    fi
    if [[ "$DISTRO_FAMILY" == artix && "$INIT_SYSTEM" != openrc ]]; then
        die "Artix Linux is supported with OpenRC only (KOX_INIT=$INIT_SYSTEM)."
    fi

    PACKAGES=("${PACKAGES_COMMON[@]}")
    if [[ "$INIT_SYSTEM" == openrc ]]; then
        PACKAGES+=("${PACKAGES_OPENRC[@]}")
    else
        PACKAGES+=("${PACKAGES_SYSTEMD[@]}")
    fi
}

# -----------------------------------------------------------------------------
# Installer stages
# -----------------------------------------------------------------------------
preflight() {
    step "Pre-flight checks"

    # Only the fresh-install path prompts (for the display name). `kox update`
    # sets KOX_ASSUME_DEFAULTS=1 and must work from a non-interactive context.
    if [[ "${KOX_ASSUME_DEFAULTS:-0}" != "1" ]]; then
        [[ -t 0 ]] || die "This installer is interactive. Run it directly from a terminal."
    fi
    [[ "${EUID:-$(id -u)}" -ne 0 ]] || die "Do not run this installer as root. Run it as your normal user; it will ask for sudo when needed."
    [[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || die "Could not determine the home directory for $TARGET_USER."
    ok "Running as non-root user: $TARGET_USER"

    command -v sudo >/dev/null 2>&1 || die "sudo is required but was not found."
    command -v pacman >/dev/null 2>&1 || die "pacman is required but was not found."

    [[ -n "$INIT_SYSTEM" ]] || die "Platform detection did not run."
    ok "$PLATFORM_LABEL detected"

    [[ -d "$REPO_DIR/.config" ]] || die "Repository is incomplete: missing $REPO_DIR/.config"
    [[ -d "$REPO_DIR/.local" ]] || die "Repository is incomplete: missing $REPO_DIR/.local"
    [[ -d "$REPO_DIR/.local/bin" ]] || die "Repository is incomplete: missing $REPO_DIR/.local/bin"
    [[ -r "$REPO_DIR/.config/kox-pickers/kox-coverflow.qml" ]] ||
        die "Repository is incomplete: missing $REPO_DIR/.config/kox-pickers/kox-coverflow.qml (theme picker would fall back to fuzzel)"
    [[ -r "$REPO_DIR/.local/bin/kox-pickers/kox-coverflow" ]] ||
        die "Repository is incomplete: missing $REPO_DIR/.local/bin/kox-pickers/kox-coverflow"
    [[ -r "$REPO_DIR/.local/bin/kox-pickers/kox-theme" ]] ||
        die "Repository is incomplete: missing $REPO_DIR/.local/bin/kox-pickers/kox-theme"
    [[ -r "$REPO_DIR/.local/bin/kox-pickers/kox-wallpaper" ]] ||
        die "Repository is incomplete: missing $REPO_DIR/.local/bin/kox-pickers/kox-wallpaper"
    [[ -d "$REPO_DIR/wallpapers" ]] ||
        die "Repository is incomplete: missing $REPO_DIR/wallpapers (theme previews and wallpapers would be blank)"

    # Fail before touching the live system if the theme table references an
    # image the repository does not ship. This is the check that would have
    # caught the original fresh-install regression.
    if [[ -r "$REPO_DIR/.local/bin/kox-pickers/kox-theme" ]]; then
        local wall missing_walls=()
        while IFS= read -r wall; do
            [[ -r "$REPO_DIR/wallpapers/$wall" ]] || missing_walls+=("$wall")
        done < <(grep -oE 'Pictures/Wallpapers/[^|"]+' \
            "$REPO_DIR/.local/bin/kox-pickers/kox-theme" 2>/dev/null |
            sed 's|.*/||' | sort -u)
        if ((${#missing_walls[@]} > 0)); then
            die "Repository is incomplete: missing wallpaper(s): ${missing_walls[*]}"
        fi
    fi

    ok "KOX OS repository found at $REPO_DIR"

    info "Requesting sudo privileges ..."
    if ! sudo -v; then
        die "sudo authentication failed."
    fi
    ok "sudo access confirmed"

    if check_internet; then
        ok "Internet connection is active"
    else
        die "No internet connection detected. Connect to the network and run the installer again."
    fi
}

ask_user_name() {
    step "User configuration"

    # `kox update` re-runs this installer to deploy the pulled dotfiles;
    # there is nothing to ask in that mode, so accept the account default.
    if [[ "${KOX_ASSUME_DEFAULTS:-0}" == "1" ]]; then
        KOX_USER_NAME="$TARGET_USER"
        ok "Welcome, $KOX_USER_NAME."
        return 0
    fi

    local entered=""
    info "Installing for account: $TARGET_USER"
    printf '  %sFull name%s [%s]: ' "$BOLD" "$RESET" "$TARGET_USER"
    if ! read -r entered; then
        entered=""
    fi

    # Trim leading and trailing whitespace.
    entered="${entered#"${entered%%[![:space:]]*}"}"
    entered="${entered%"${entered##*[![:space:]]}"}"
    KOX_USER_NAME="${entered:-$TARGET_USER}"
    [[ -n "${KOX_USER_NAME//[[:space:]]/}" ]] || KOX_USER_NAME="$TARGET_USER"

    ok "Welcome, $KOX_USER_NAME."
}

install_packages() {
    step "Installing the KOX OS stack"

    info "Compositor: Hyprland, portals and XWayland"
    info "Shell: Waybar, Quickshell, kitty, fuzzel and mako"
    info "Services: PipeWire, NetworkManager, BlueZ and power-profiles-daemon"
    info "Installing ${#PACKAGES[@]} packages. This can take a while ..."

    if sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"; then
        ok "All packages are installed."
    else
        die "Package installation failed. Fix the pacman error above (a full 'sudo pacman -Syu' may be needed), then run the installer again."
    fi
}

backup_existing_configs() {
    step "Backing up existing configuration"

    local base="$TARGET_HOME/.config-backup-$(date +%s)"
    local candidate="$base"
    local n=1
    while [[ -e "$candidate" ]]; do
        candidate="${base}-${n}"
        n=$((n + 1))
    done
    BACKUP_DIR="$candidate"
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"

    local backed_up=0

    if [[ -e "$TARGET_HOME/.config" || -L "$TARGET_HOME/.config" ]]; then
        info "Saving ~/.config ..."
        cp -a "$TARGET_HOME/.config" "$BACKUP_DIR/config"
        backed_up=1
    fi

    if [[ -e "$PROFILE_FILE" || -L "$PROFILE_FILE" ]]; then
        cp -a "$PROFILE_FILE" "$BACKUP_DIR/bash_profile"
        backed_up=1
    fi

    if [[ -d "$TARGET_HOME/.local/bin" ]]; then
        local entry name
        while IFS= read -r -d '' entry; do
            name="$(basename "$entry")"
            if [[ -e "$TARGET_HOME/.local/bin/$name" || -L "$TARGET_HOME/.local/bin/$name" ]]; then
                mkdir -p "$BACKUP_DIR/local-bin"
                cp -a "$TARGET_HOME/.local/bin/$name" "$BACKUP_DIR/local-bin/$name"
                backed_up=1
            fi
        done < <(find "$REPO_DIR/.local/bin" -mindepth 1 -maxdepth 1 -print0)
    fi

    if ((backed_up)); then
        ok "Existing configuration backed up to $BACKUP_DIR"
    else
        rmdir "$BACKUP_DIR" 2>/dev/null || true
        BACKUP_DIR=""
        info "No existing configuration needed backing up."
    fi
}

# Deploy a directory tree without ever leaving a destination file missing.
#
# `cp -aT --remove-destination` unlinks each destination before recreating it.
# Hyprland watches its Lua config and reloads when a file changes; a reload
# landing in that gap cleared the keybind registry, failed to reopen
# hyprland.lua, and tripped Emergency Mode during `kox update`.
#
# Stage a complete copy inside the destination (same filesystem, even when
# ~/.config is a symlink), then rename each staged entry over its target.
# rename(2) is atomic, so a watcher always sees either the old inode or the
# new one -- never a missing path.
deploy_tree() {
    local src="$1" dst="$2" label="$3"
    local stage="" rel entry

    _deploy_tree_fail() {
        [[ -n "$stage" ]] && rm -rf -- "$stage"
        die "$*"
    }

    [[ -d "$src" ]] || _deploy_tree_fail "Cannot deploy $label: $src is not a directory."
    mkdir -p -- "$dst" || _deploy_tree_fail "Cannot create $dst."

    stage="$(mktemp -d -- "$dst/.kox-deploy.XXXXXX")" ||
        _deploy_tree_fail "Could not create a staging directory under $dst."
    # Also covers an unexpected `set -e` exit. The explicit cleanup in
    # _deploy_tree_fail avoids a second removal on the normal die path.
    trap 'rm -rf -- "$stage"; trap - RETURN' RETURN

    if ! cp -a -- "$src/." "$stage/"; then
        _deploy_tree_fail "Could not stage $label in $stage."
    fi

    # sort -z visits parents before children, so destination directories
    # exist before their contents are renamed into place.
    while IFS= read -r -d '' entry; do
        rel="${entry#"$stage"/}"

        if [[ -d "$entry" && ! -L "$entry" ]]; then
            if [[ -e "$dst/$rel" && ! -d "$dst/$rel" ]]; then
                rm -f -- "$dst/$rel"
            fi
            mkdir -p -- "$dst/$rel" ||
                _deploy_tree_fail "Could not create directory: $dst/$rel"
            continue
        fi

        mkdir -p -- "$(dirname -- "$dst/$rel")" ||
            _deploy_tree_fail "Could not create parent directory for: $dst/$rel"

        # A file replacing a directory is rare, but make it deterministic
        # instead of letting mv fail halfway through the deployment.
        if [[ -d "$dst/$rel" && ! -L "$dst/$rel" ]]; then
            rm -rf -- "$dst/$rel"
        fi

        if ! mv -fT -- "$entry" "$dst/$rel"; then
            _deploy_tree_fail "Could not deploy $label entry: $rel"
        fi
    done < <(find "$stage" -mindepth 1 -print0 | sort -z)

    # Apply directory modes last: a read-only source directory must not
    # block the file renames above.
    while IFS= read -r -d '' entry; do
        rel="${entry#"$stage"/}"
        chmod --reference="$entry" -- "$dst/$rel" 2>/dev/null || true
        touch -r "$entry" -- "$dst/$rel" 2>/dev/null || true
    done < <(find "$stage" -mindepth 1 -type d -print0 | sort -zr)

    rm -rf -- "$stage"
    trap - RETURN
}

reload_hyprland_if_running() {
    step "Reloading Hyprland"

    if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || ! command -v hyprctl >/dev/null 2>&1; then
        info "No running Hyprland session detected; the new config applies at next login."
        return 0
    fi

    if ! hyprctl reload >/dev/null 2>&1; then
        warn "Hyprland is running but could not be reloaded; log out and back in to apply the new configuration."
        return 0
    fi

    local errors
    errors="$(hyprctl configerrors 2>&1 || true)"
    # hyprctl prints an empty string when the config is clean.
    if [[ -n "${errors//[[:space:]]/}" ]]; then
        warn "Hyprland reported configuration errors after deployment:"
        printf '%s\n' "$errors" | sed 's/^/         /' >&2
        warn "If the session is unusable, SUPER + SHIFT + ESCAPE opens a rescue kitty terminal."
    else
        ok "Hyprland reloaded with a clean configuration."
    fi
}

deploy_dotfiles() {
    step "Deploying KOX OS dotfiles"

    mkdir -p "$TARGET_HOME/.config" "$TARGET_HOME/.local/bin"

    info "Installing ~/.config ..."
    deploy_tree "$REPO_DIR/.config" "$TARGET_HOME/.config" "~/.config"

    # The shipped dotfiles are authored at UI scale 10 (Waybar height 24,
    # theme-scale.css 10px, kitty 8pt, fuzzel 12, mako 10). Seed the scale
    # state on first install so the first boot's `kox-scale apply` is a
    # byte-level no-op; on updates this file is live-only, so a user's
    # chosen scale is preserved.
    if [[ ! -e "$TARGET_HOME/.config/kox/ui-scale" ]]; then
        mkdir -p "$TARGET_HOME/.config/kox"
        printf '10\n' > "$TARGET_HOME/.config/kox/ui-scale"
        chmod 644 "$TARGET_HOME/.config/kox/ui-scale"
    fi

    info "Installing ~/.local ..."
    deploy_tree "$REPO_DIR/.local" "$TARGET_HOME/.local" "~/.local"

    ok "Dotfiles deployed to $TARGET_HOME"

    # Catch a broken config now, while the installer is still running and
    # the rescue bind from hyprland.lua is available, rather than on the
    # next reload or boot.
    reload_hyprland_if_running
}

deploy_wallpapers() {
    step "Installing wallpapers"

    if [[ ! -d "$REPO_DIR/wallpapers" ]]; then
        warn "Repository has no wallpapers/ directory; the theme previews and default wallpaper will be missing."
        return 0
    fi

    mkdir -p "$WALLPAPER_DIR"

    local src name dst count=0 skipped=0
    for src in "$REPO_DIR"/wallpapers/*; do
        [[ -f "$src" ]] || continue
        name="$(basename -- "$src")"
        dst="$WALLPAPER_DIR/$name"

        # The collection is user-visible; never clobber a file the user has
        # put there. A zero-byte leftover is treated as missing so a failed
        # earlier copy can heal.
        if [[ -s "$dst" ]]; then
            skipped=$((skipped + 1))
            continue
        fi

        if cp --preserve=mode,timestamps -- "$src" "$dst"; then
            chmod 644 -- "$dst" 2>/dev/null || true
            count=$((count + 1))
        else
            warn "Could not install wallpaper: $name"
        fi
    done

    if ((count > 0)); then
        ok "$count wallpaper(s) installed in $WALLPAPER_DIR."
    fi
    if ((skipped > 0)); then
        info "$skipped wallpaper(s) already present; left untouched."
    fi
    if ((count == 0 && skipped == 0)); then
        warn "No wallpaper files found in $REPO_DIR/wallpapers."
    fi
}

make_scripts_executable() {
    step "Setting executable permissions"

    local dir="$TARGET_HOME/.local/bin"
    if [[ ! -d "$dir" ]]; then
        warn "~/.local/bin does not exist; no scripts to mark executable."
        return 0
    fi

    if [[ ! -d "$dir/kox-pickers" ]]; then
        info "No ~/.local/bin/kox-pickers directory present; skipping picker scripts."
    fi

    local file count=0
    while IFS= read -r -d '' file; do
        if [[ "$(head -c 2 "$file" 2>/dev/null)" == "#!" ]]; then
            chmod +x -- "$file"
            count=$((count + 1))
        fi
    done < <(find "$dir" -type f -print0)

    ok "$count script(s) marked executable (including kox-pickers/ and kox-widgets/ when present)."
}

clear_stale_kitty_cache() {
    # Kitty stores the last OS-window state here. A pre-fix cache says
    # "maximized", which made new terminals open fullscreen even after
    # remember_window_size was disabled. It is pure cache: safe to drop.
    local cache="$TARGET_HOME/.cache/kitty/main.json"
    if [[ -f "$cache" ]]; then
        rm -f -- "$cache"
        info "Cleared kitty's stale window-state cache."
    fi
}

restore_user_choices() {
    step "Restoring saved appearance"

    local pickers="$TARGET_HOME/.local/bin/kox-pickers"
    local state="$TARGET_HOME/.config/kox/pickers"

    if [[ -s "$state/theme" || -s "$state/accent" ]]; then
        if [[ -x "$pickers/kox-theme" ]]; then
            info "Re-applying the saved theme ..."
            # KOX_REPO lets accent-only restores find themes/<name>.css even
            # when the repository is not at the default ~/KOX-OS path.
            if KOX_REPO="$REPO_DIR" "$pickers/kox-theme" --restore; then
                ok "Theme restored."
            else
                warn "Could not restore the saved theme."
            fi
        else
            warn "kox-theme is missing; the saved theme was not restored."
        fi
    else
        info "No saved theme; keeping the shipped defaults."
    fi

    if [[ -s "$state/wallpaper" ]]; then
        if [[ -x "$pickers/kox-wallpaper" ]]; then
            info "Re-applying the saved wallpaper ..."
            if "$pickers/kox-wallpaper" --restore; then
                ok "Wallpaper restored."
            else
                warn "Could not restore the saved wallpaper."
            fi
        else
            warn "kox-wallpaper is missing; the saved wallpaper was not restored."
        fi
    fi

    if [[ -s "$state/cursor" ]]; then
        if [[ -x "$pickers/kox-cursor" ]]; then
            info "Re-applying the saved cursor ..."
            if "$pickers/kox-cursor" --restore; then
                ok "Cursor restored."
            else
                warn "Could not restore the saved cursor."
            fi
        else
            warn "kox-cursor is missing; the saved cursor was not restored."
        fi
    fi
}

verify_deploy() {
    step "Verifying appearance deployment"

    local failed=0
    local qml="$TARGET_HOME/.config/kox-pickers/kox-coverflow.qml"
    local kitty="$TARGET_HOME/.config/kitty/kitty.conf"
    local paper="$TARGET_HOME/.config/hypr/hyprpaper.conf"
    local theme_script="$TARGET_HOME/.local/bin/kox-pickers/kox-theme"

    if [[ -r "$qml" ]]; then
        ok "Theme picker QML is installed."
    else
        warn "Missing $qml; kox theme would fall back to fuzzel."
        failed=1
    fi

    if grep -qE '^[[:space:]]*remember_window_size[[:space:]]+no' "$kitty" 2>/dev/null; then
        ok "Kitty will not restore a maximized window."
    else
        warn "kitty.conf does not disable remembered window size; kitty may open fullscreen."
        failed=1
    fi

    if grep -qE '^[[:space:]]*path[[:space:]]*=[[:space:]]*.*Pictures/Wallpapers/' "$paper" 2>/dev/null; then
        ok "Hyprpaper points at the wallpaper collection."
    else
        warn "hyprpaper.conf does not point into ~/Pictures/Wallpapers."
        failed=1
    fi

    if [[ -r "$theme_script" ]]; then
        local wall missing_walls=()
        while IFS= read -r wall; do
            [[ -r "$WALLPAPER_DIR/$wall" ]] || missing_walls+=("$wall")
        done < <(grep -oE 'Pictures/Wallpapers/[^|"]+' "$theme_script" 2>/dev/null |
            sed 's|.*/||' | sort -u)
        if ((${#missing_walls[@]} == 0)); then
            ok "All theme wallpapers are present."
        else
            warn "Missing theme wallpaper(s): ${missing_walls[*]}"
            failed=1
        fi
    else
        warn "kox-theme is missing; could not verify the wallpaper collection."
        failed=1
    fi

    if ((failed == 0)); then
        ok "Appearance deployment verified."
    else
        warn "Appearance deployment has gaps; see the warnings above."
    fi
}

ensure_path_block() {
    if grep -qF "$PATH_BEGIN" "$PROFILE_FILE"; then
        info "PATH block already present in ~/.bash_profile."
        return 0
    fi

    {
        printf '\n%s\n' "$PATH_BEGIN"
        printf '%s\n' \
            '# Put KOX user scripts on PATH for login shells.' \
            'case ":$PATH:" in' \
            '    *":$HOME/.local/bin:"*) ;;' \
            '    *) export PATH="$HOME/.local/bin:$PATH" ;;' \
            'esac'
        printf '%s\n' "$PATH_END"
    } >>"$PROFILE_FILE"

    ok "Added ~/.local/bin to PATH in ~/.bash_profile."
}

ensure_autologin_block() {
    if grep -qF "$AUTOLOGIN_BEGIN" "$PROFILE_FILE" ||
        grep -qF "KOX OS - start the Wayland session automatically at login." "$PROFILE_FILE"; then
        # Older installs appended the block with a legacy `exec Hyprland`
        # (pre-watchdog): upgrade it in place so the next boot goes through
        # the watchdog launcher, matching the current block.
        local legacy_word cond_word new_word
        legacy_word=$(grep -m1 -oE "exec [A-Za-z-]+$" "$PROFILE_FILE" | sed -e 's/^exec //' || true)
        cond_word=$(grep -m1 -oE "command -v [A-Za-z-]+" "$PROFILE_FILE" | sed -e 's/^command -v //' || true)
        new_word=$(ls /usr/bin 2>/dev/null | grep -iE "^start-hyp" | head -n 1 || true)
        if [[ -n "$legacy_word" && -n "$new_word" && "$legacy_word" != "$new_word" ]]; then
            info "Updating legacy autologin block: ${legacy_word} -> ${new_word} ..."
            sed -i -e "s/exec ${legacy_word}$/exec ${new_word}/" "$PROFILE_FILE"
            if [[ -n "$cond_word" ]]; then
                sed -i -e "s/command -v ${cond_word} /command -v ${new_word} /" "$PROFILE_FILE"
            fi
            ok "Autologin block updated."
        else
            info "Hyprland autologin block already present; leaving it untouched."
        fi
        return 0
    fi

    {
        printf '\n%s\n' "$AUTOLOGIN_BEGIN"
        cat <<'EOF'
# KOX OS - start the Wayland session automatically at login.
# Fires only when: it is a real login on tty1 ($(tty) is /dev/tty1, so
# terminal emulators and SSH can never trigger this), no Wayland/X display
# is already set, Hyprland is installed, and KOX_NO_SESSION is unset
# (export KOX_NO_SESSION=1 for a plain console login on tty1).
# exec replaces the login shell: quitting Hyprland drops back to the TTY
# login prompt, and tty2..6 always remain plain consoles.
if [[ "$(tty)" == "/dev/tty1" ]] \
   && [[ -z "$WAYLAND_DISPLAY" && -z "$DISPLAY" ]] \
   && [[ -z "$KOX_NO_SESSION" ]] \
   && command -v start-hyprland >/dev/null 2>&1
then
    # KOX OS: launch via the proper watchdog launcher (no boot warning).
    exec start-hyprland
fi
EOF
        printf '%s\n' "$AUTOLOGIN_END"
    } >>"$PROFILE_FILE"

    ok "Added guarded TTY1 Hyprland autologin to ~/.bash_profile."
}

configure_shell() {
    step "Configuring login shell and autologin"

    touch "$PROFILE_FILE"
    if [[ ! -s "$PROFILE_FILE" ]]; then
        printf '%s\n' '[[ -f ~/.bashrc ]] && . ~/.bashrc' >"$PROFILE_FILE"
    fi

    ensure_path_block
    ensure_autologin_block

    ok "Shell configuration complete."
}

configure_bluez_autoenable() {
    # BlueZ powers adapters on at boot only when AutoEnable is true; the
    # packaged file ships it commented. Make it explicit so the Bluetooth
    # widget is not stuck on "off" after a fresh install.
    if [[ -f /etc/bluetooth/main.conf ]] &&
        ! grep -qE '^[[:space:]]*AutoEnable=true' /etc/bluetooth/main.conf; then
        sudo sed -i 's/^#AutoEnable=true/AutoEnable=true/' /etc/bluetooth/main.conf
        ok "BlueZ AutoEnable=true."
    fi
}

setup_services() {
    if [[ "$INIT_SYSTEM" == systemd ]]; then
        step "Enabling systemd system services"

        ensure_system_service "NetworkManager" NetworkManager
        ensure_system_service "Bluetooth" bluetooth
        ensure_system_service "Power Profiles Daemon" power-profiles-daemon
        # D-Bus is socket-activated by systemd; there is no unit to enable.

        if [[ -e /etc/systemd/system/multi-user.target.wants/connman.service ]]; then
            info "Disabling connman (NetworkManager owns the network stack) ..."
            if (( SYSTEMD_RUNNING )); then
                sudo systemctl disable --now connman >/dev/null 2>&1 || true
            else
                sudo systemctl --root=/ disable connman >/dev/null 2>&1 || true
            fi
            ok "connman disabled."
        fi

        configure_bluez_autoenable

        step "Enabling PipeWire user services"

        export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        if [[ ! -d "$XDG_RUNTIME_DIR" ]]; then
            info "Creating $XDG_RUNTIME_DIR ..."
            if sudo install -d -m 0700 -o "$(id -u)" -g "$(id -g)" "$XDG_RUNTIME_DIR"; then
                ok "Created $XDG_RUNTIME_DIR."
            else
                warn "Could not create $XDG_RUNTIME_DIR; user services may fail."
            fi
        fi

        if (( SYSTEMD_RUNNING )); then
            ensure_user_service pipewire.socket "PipeWire socket"
            ensure_user_service pipewire-pulse.socket "PipeWire Pulse socket"
            ensure_user_service wireplumber.service "WirePlumber"
        else
            info "Offline install: PipeWire user units start at the first Hyprland login via kox-pulse-autostart."
        fi
        return 0
    fi

    step "Enabling OpenRC system services"

    ensure_system_service "D-Bus" dbus
    ensure_system_service "NetworkManager" NetworkManager
    ensure_system_service "Bluetooth" bluetoothd bluetooth
    ensure_system_service "Power Profiles Daemon" power-profiles-daemon

    # Artix's live environment ships connman. Left enabled it races
    # NetworkManager for wlan0/eth0, and the Waybar Wi-Fi widget (nmcli)
    # then sees no usable interface. NetworkManager is the supported stack.
    if [[ -e /etc/runlevels/default/connmand ]]; then
        info "Disabling connmand (NetworkManager owns the network stack) ..."
        sudo rc-update del connmand default >/dev/null 2>&1 || true
        sudo rc-service connmand stop >/dev/null 2>&1 || true
        ok "connmand disabled."
    fi

    configure_bluez_autoenable

    step "Enabling PipeWire user services"

    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    if [[ ! -d "$XDG_RUNTIME_DIR" ]]; then
        info "Creating $XDG_RUNTIME_DIR ..."
        if sudo install -d -m 0700 -o "$(id -u)" -g "$(id -g)" "$XDG_RUNTIME_DIR"; then
            ok "Created $XDG_RUNTIME_DIR."
        else
            warn "Could not create $XDG_RUNTIME_DIR; user services may fail."
        fi
    fi

    if [[ -x /etc/user/init.d/dbus ]]; then
        if rc-service --user dbus status >/dev/null 2>&1; then
            ok "Session D-Bus is already running."
        elif rc-service --user dbus start >/dev/null 2>&1; then
            ok "Session D-Bus started."
        else
            warn "Could not start the session D-Bus service."
        fi
    else
        warn "No session D-Bus OpenRC user service found."
    fi

    ensure_user_service pipewire "PipeWire"
    ensure_user_service wireplumber "WirePlumber"

    if [[ -x /etc/user/init.d/pipewire-pulse ]]; then
        ensure_user_service pipewire-pulse "PipeWire Pulse"
    else
        warn "No OpenRC user service for pipewire-pulse; KOX starts it via kox-pulse-autostart inside Hyprland."
    fi
}

setup_groups() {
    step "Configuring user groups"

    local wanted=(wheel network audio video storage)
    local present=() missing=()
    local group

    for group in "${wanted[@]}"; do
        if getent group "$group" >/dev/null 2>&1; then
            present+=("$group")
        else
            missing+=("$group")
        fi
    done
    if ((${#missing[@]})); then
        warn "Missing system group(s): ${missing[*]}"
    fi
    if ((${#present[@]} == 0)); then
        return 0
    fi

    local current needed=()
    current="$(id -nG "$TARGET_USER" 2>/dev/null || true)"
    for group in "${present[@]}"; do
        if ! grep -qw -- "$group" <<<"$current"; then
            needed+=("$group")
        fi
    done

    if ((${#needed[@]} == 0)); then
        ok "$TARGET_USER is already a member of: ${present[*]}"
        return 0
    fi

    local csv
    csv="$(IFS=,; printf '%s' "${needed[*]}")"
    if sudo usermod -aG "$csv" "$TARGET_USER"; then
        ok "Added $TARGET_USER to: ${needed[*]}"
        info "Group changes take effect after you log out or reboot."
    else
        warn "Could not add $TARGET_USER to: ${needed[*]}"
    fi
}

install_system_files() {
    step "Installing KOX system configuration"

    local rule_src="$REPO_DIR/etc/polkit-1/rules.d/49-kox-network.rules"
    local rule_dst="/etc/polkit-1/rules.d/49-kox-network.rules"

    # NetworkManager's stock polkit rule only allows the wheel group, and
    # KOX runs no polkit authentication agent inside the Hyprland session.
    # Without this rule every Wi-Fi connect/forget from the panel fails with
    # "Insufficient privileges". The network group is the intended gate.
    if [[ -f "$rule_src" ]]; then
        if sudo install -Dm644 -o root -g root "$rule_src" "$rule_dst"; then
            ok "Installed NetworkManager polkit rule."
        else
            warn "Could not install the NetworkManager polkit rule."
        fi
    else
        warn "Missing $rule_src; Wi-Fi management may require authentication."
    fi

    # Arch/systemd only: some Arch logind policies require interactive
    # authentication for suspend/power-off/reboot and the Hyprland session
    # runs no polkit agent, so the power menu silently does nothing. The
    # rule allows these actions for local sessions (an explicit, defensive
    # counterpart to the default policy).
    if [[ "$INIT_SYSTEM" == systemd && "$DISTRO_FAMILY" == arch ]]; then
        local lr_src="$REPO_DIR/etc/polkit-1/rules.d/10-kox-login1-noauth.rules"
        local lr_dst="/etc/polkit-1/rules.d/10-kox-login1-noauth.rules"
        if [[ -f "$lr_src" ]]; then
            if sudo install -Dm644 -o root -g root "$lr_src" "$lr_dst"; then
                ok "Installed Arch logind polkit rule (power menu)."
            else
                warn "Could not install the Arch logind polkit rule."
            fi
        fi
    fi
}

print_final() {
    printf '\n  %s%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$PINK" "$BOLD" "$RESET"
    printf '  %s%s  KOX OS  ·  INSTALLED%s\n' "$PINK" "$BOLD" "$RESET"
    printf '  %s%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$PINK" "$BOLD" "$RESET"
    printf '\n  %sWelcome, %s.%s\n\n' "$BOLD" "$KOX_USER_NAME" "$RESET"
    printf '  %sReboot to start your new desktop:%s\n' "$DIM" "$RESET"
    printf '    %s%ssudo reboot%s\n\n' "$BOLD" "$CYAN" "$RESET"
    printf '  On reboot, log in on %sTTY1%s and Hyprland will start automatically.\n' "$BOLD" "$RESET"
    printf '  TTY2-TTY6 remain plain consoles if you ever need to troubleshoot.\n'
    printf '  After login, run %skox doctor%s to verify the installation.\n' "$BOLD" "$RESET"

    if [[ -n "$BACKUP_DIR" ]]; then
        printf '\n  Your previous configuration was backed up to:\n'
        printf '    %s%s%s\n' "$CYAN" "$BACKUP_DIR" "$RESET"
    fi

    if ((WARNINGS == 1)); then
        printf '\n  %s1 non-fatal warning was reported above.%s\n' "$YELLOW" "$RESET"
    elif ((WARNINGS > 1)); then
        printf '\n  %s%d non-fatal warnings were reported above.%s\n' "$YELLOW" "$WARNINGS" "$RESET"
    fi

    printf '\n  %s%sKOX OS is ready.%s\n\n' "$GREEN" "$BOLD" "$RESET"
}

main() {
    detect_platform
    print_banner
    preflight
    start_sudo_keepalive
    ask_user_name
    install_packages
    backup_existing_configs
    deploy_dotfiles
    deploy_wallpapers
    make_scripts_executable
    clear_stale_kitty_cache
    restore_user_choices
    configure_shell
    setup_services
    setup_groups
    install_system_files
    verify_deploy
    print_final
}

# Allow the test suite to source the helpers without running the installer.
if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    main "$@"
fi
