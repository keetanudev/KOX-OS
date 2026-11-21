#!/usr/bin/env bash
# =============================================================================
#  KOX OS installer
#
#  Deploys the KOX OS desktop on a fresh Artix Linux (OpenRC) installation.
#  Run it as your normal user from the root of the KOX-OS repository:
#
#      ./install.sh
#
#  The installer is idempotent: existing configuration is backed up, pacman
#  uses --needed, and every appended shell block is guarded by a marker.
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
    printf '  %sArtix Linux + Hyprland + OpenRC%s\n' "$DIM" "$RESET"
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

BACKUP_DIR=""
KOX_USER_NAME=""
SUDO_KEEPALIVE_PID=""

PATH_BEGIN="# >>> KOX OS PATH >>>"
PATH_END="# <<< KOX OS PATH <<<"
AUTOLOGIN_BEGIN="# >>> KOX OS autologin >>>"
AUTOLOGIN_END="# <<< KOX OS autologin <<<"

# -----------------------------------------------------------------------------
# Packages
#
# Notes:
#   - Artix splits OpenRC init scripts into *-openrc packages.
#   - pipewire-pulse has no OpenRC user service here; KOX starts it at session
#     login through kox-pulse-autostart.
#   - swww and inter-font are intentionally not listed: they are not available
#     in the configured Artix repositories.
# -----------------------------------------------------------------------------
PACKAGES=(
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

    # Audio
    pipewire
    pipewire-pulse
    pipewire-alsa
    pipewire-openrc
    wireplumber
    wireplumber-openrc
    libpulse

    # Networking
    networkmanager
    networkmanager-openrc
    wpa_supplicant

    # Bluetooth
    bluez
    bluez-utils
    bluez-openrc
    blueman

    # Power and hardware
    power-profiles-daemon
    power-profiles-daemon-openrc
    upower
    udiskie
    brightnessctl

    # Session services and portals
    dbus
    dbus-openrc
    elogind
    elogind-openrc
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
    rc-update show 2>/dev/null |
        awk -v svc="$1" '$1 == svc { found = 1 } END { exit(found ? 0 : 1) }'
}

user_service_enabled() {
    rc-update --user show 2>/dev/null |
        awk -v svc="$1" '$1 == svc { found = 1 } END { exit(found ? 0 : 1) }'
}

find_system_service() {
    local candidate
    for candidate in "$@"; do
        if [[ -x "/etc/init.d/$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

ensure_system_service() {
    local label="$1"
    shift
    local svc

    if ! svc="$(find_system_service "$@")"; then
        warn "No OpenRC init script found for $label (tried: $*)."
        return 0
    fi

    if service_enabled "$svc"; then
        info "$svc is already enabled."
    else
        info "Enabling $svc ..."
        if sudo rc-update add "$svc" default >/dev/null 2>&1; then
            ok "$svc enabled in the default runlevel."
        else
            warn "Could not enable $svc."
        fi
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
# Installer stages
# -----------------------------------------------------------------------------
preflight() {
    step "Pre-flight checks"

    [[ -t 0 ]] || die "This installer is interactive. Run it directly from a terminal."
    [[ "${EUID:-$(id -u)}" -ne 0 ]] || die "Do not run this installer as root. Run it as your normal user; it will ask for sudo when needed."
    [[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || die "Could not determine the home directory for $TARGET_USER."
    ok "Running as non-root user: $TARGET_USER"

    command -v sudo >/dev/null 2>&1 || die "sudo is required but was not found."
    command -v pacman >/dev/null 2>&1 || die "pacman is required but was not found."
    command -v rc-update >/dev/null 2>&1 || die "OpenRC (rc-update) is required but was not found."
    command -v rc-service >/dev/null 2>&1 || die "OpenRC (rc-service) is required but was not found."

    [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release."
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ "${ID:-}" == "artix" ]] || die "KOX OS targets Artix Linux (detected: ${PRETTY_NAME:-unknown})."
    ok "Artix Linux detected: ${PRETTY_NAME:-Artix Linux}"

    [[ -d "$REPO_DIR/.config" ]] || die "Repository is incomplete: missing $REPO_DIR/.config"
    [[ -d "$REPO_DIR/.local" ]] || die "Repository is incomplete: missing $REPO_DIR/.local"
    [[ -d "$REPO_DIR/.local/bin" ]] || die "Repository is incomplete: missing $REPO_DIR/.local/bin"
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

deploy_dotfiles() {
    step "Deploying KOX OS dotfiles"

    mkdir -p "$TARGET_HOME/.config" "$TARGET_HOME/.local/bin"

    info "Installing ~/.config ..."
    cp -aT --remove-destination "$REPO_DIR/.config" "$TARGET_HOME/.config"

    info "Installing ~/.local ..."
    cp -aT --remove-destination "$REPO_DIR/.local" "$TARGET_HOME/.local"

    ok "Dotfiles deployed to $TARGET_HOME"
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

setup_services() {
    step "Enabling OpenRC system services"

    ensure_system_service "D-Bus" dbus
    ensure_system_service "NetworkManager" NetworkManager
    ensure_system_service "Bluetooth" bluetoothd bluetooth
    ensure_system_service "Power Profiles Daemon" power-profiles-daemon

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

    local wanted=(wheel audio video storage)
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
    print_banner
    preflight
    start_sudo_keepalive
    ask_user_name
    install_packages
    backup_existing_configs
    deploy_dotfiles
    make_scripts_executable
    configure_shell
    setup_services
    setup_groups
    print_final
}

main "$@"
