#!/usr/bin/env bash
#
# remove-plymouth.sh — revert plymouth boot-splash changes on
# Artix Linux (OpenRC). Safe to re-run; every step is best-effort.
#
# System revert only; does not touch ~/.config or ~/KOX-OS.
#
# Usage (as root or via sudo), from a working TTY — NOT the broken tty1:
#   sudo bash ~/KOX-OS/scripts/remove-plymouth.sh
#   sudo bash ~/KOX-OS/scripts/remove-plymouth.sh --uninstall   # also: pacman -Rns plymouth
#
# Rebuilds grub.cfg and the initramfs. Does NOT reboot; reboot manually
# after reviewing the output. Pre-edit backups are written next to the
# modified files as *.kox-remove-plymouth.<timestamp>.bak
set -uo pipefail

UNINSTALL=0
for arg in "$@"; do
    case "$arg" in
        -u|--uninstall) UNINSTALL=1 ;;
        -h|--help) printf 'usage: %s [--uninstall]\n' "$0"; exit 0 ;;
        *) printf 'error: unknown argument: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    printf 'error: run as root, e.g. sudo bash %s\n' "$0" >&2
    exit 1
fi

log()  { printf '[*] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }

MKINITCPIO=/etc/mkinitcpio.conf
GRUB=/etc/default/grub
GRUBCFG=/boot/grub/grub.cfg
TS=$(date +%Y%m%d%H%M%S 2>/dev/null || echo backup)

backup() {
    [[ -f $1 ]] || return 0
    cp -a -- "$1" "$1.kox-remove-plymouth.$TS.bak" \
        && log "backup: $1.kox-remove-plymouth.$TS.bak"
}

# --- 1. Stop + disable plymouth services (OpenRC; systemd no-op fallback) ---
log "stopping + disabling plymouth services"

for svc in plymouth plymouth-quit plymouth-quit-wait plymouth-shutdown; do
    if command -v rc-service >/dev/null 2>&1; then
        rc-service "$svc" stop >/dev/null 2>&1 || true
    fi
    if command -v rc-update >/dev/null 2>&1; then
        for runlevel in sysinit boot default shutdown; do
            rc-update del "$svc" "$runlevel" >/dev/null 2>&1 || true
        done
    fi
done

if command -v systemctl >/dev/null 2>&1; then
    for unit in plymouth-start plymouth-read-write plymouth-quit plymouth-quit-wait plymouth-kexec; do
        systemctl disable --now "$unit.service" >/dev/null 2>&1 || true
    done
fi

# Ask a running daemon to quit, then kill it.
if command -v plymouth >/dev/null 2>&1; then
    plymouth quit >/dev/null 2>&1 || true
fi
if command -v pkill >/dev/null 2>&1; then
    pkill -x plymouthd >/dev/null 2>&1 || true
fi

# --- 2. Remove service files + stale runlevel symlinks ----------------------
if [[ -d /etc/init.d ]]; then
    for f in /etc/init.d/plymouth*; do
        [[ -e $f || -L $f ]] || continue
        rm -f -- "$f" && log "removed service file $f"
    done
fi
for rl in /etc/runlevels/*; do
    [[ -d $rl ]] || continue
    for f in "$rl"/*plymouth*; do
        [[ -e $f || -L $f ]] || continue
        rm -f -- "$f" && log "removed runlevel link $f"
    done
done

# --- 3. mkinitcpio: drop 'plymouth' from HOOKS ------------------------------
if [[ -f $MKINITCPIO ]]; then
    if grep -qE '^HOOKS=\(.*plymouth' "$MKINITCPIO"; then
        backup "$MKINITCPIO"
        hooks_line=$(grep -E '^HOOKS=\(' "$MKINITCPIO" | tail -n1)
        inside=${hooks_line#*(}; inside=${inside%)*}
        new=()
        for hook in $inside; do
            [[ $hook == plymouth ]] && continue
            new+=("$hook")
        done
        new_line="HOOKS=(${new[*]})"
        awk -v repl="$new_line" '
            /^HOOKS=\(/ && !done { print repl; done=1; next }
            { print }
        ' "$MKINITCPIO" > "$MKINITCPIO.kox-tmp.$$" \
            && mv -f -- "$MKINITCPIO.kox-tmp.$$" "$MKINITCPIO"
        log "mkinitcpio: $new_line"
    else
        log "mkinitcpio: no plymouth hook found"
    fi
else
    warn "$MKINITCPIO not found"
fi

# --- 4. GRUB: remove 'splash' from GRUB_CMDLINE_LINUX_DEFAULT ---------------
if [[ -f $GRUB ]]; then
    if grep -qE '^GRUB_CMDLINE_LINUX_DEFAULT=.*splash' "$GRUB"; then
        backup "$GRUB"
        tmp="$GRUB.kox-tmp.$$"
        sed -E \
            -e '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/(^|[[:space:]])splash([[:space:]]|"|$)/\1\2/' \
            -e '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/[[:space:]]{2,}/ /g' \
            -e '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/"[[:space:]]*"/""/g' \
            -e '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/"[[:space:]]+/"/g' \
            -e '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/[[:space:]]+"/"/g' \
            "$GRUB" > "$tmp" && mv -f -- "$tmp" "$GRUB"
        log "grub: removed 'splash' from GRUB_CMDLINE_LINUX_DEFAULT"
    else
        log "grub: no 'splash' in GRUB_CMDLINE_LINUX_DEFAULT"
    fi
else
    warn "$GRUB not found"
fi

# --- 5. Clean plymouth config + kox theme leftovers -------------------------
rm -rf /etc/plymouth
rm -rf /usr/share/plymouth/themes/kox
log "cleaned /etc/plymouth and kox plymouth theme leftovers"

# --- 6. Rebuild GRUB + initramfs --------------------------------------------
if command -v grub-mkconfig >/dev/null 2>&1; then
    if grub-mkconfig -o "$GRUBCFG"; then
        log "rebuilt $GRUBCFG"
    else
        warn "grub-mkconfig failed"
    fi
else
    warn "grub-mkconfig not found"
fi

if command -v mkinitcpio >/dev/null 2>&1; then
    if mkinitcpio -P; then
        log "rebuilt initramfs (mkinitcpio -P)"
    else
        warn "mkinitcpio -P failed"
    fi
else
    warn "mkinitcpio not found"
fi

# --- 7. Restore console state (best effort) ---------------------------------
if command -v kbd_mode >/dev/null 2>&1; then kbd_mode -a || true; fi
if command -v reset >/dev/null 2>&1; then reset || true; fi

# --- 8. Optional: uninstall package -----------------------------------------
if (( UNINSTALL )); then
    if command -v pacman >/dev/null 2>&1; then
        if pacman -Q plymouth >/dev/null 2>&1; then
            if pacman -Rns --noconfirm plymouth; then
                log "uninstalled plymouth"
            else
                warn "pacman -Rns plymouth failed"
            fi
        else
            log "plymouth package not installed"
        fi
    fi
fi

# --- Repo cleanup hint (not applied here) -----------------------------------
cat <<'EOF'

Repo cleanup (optional; review + commit separately on KOX-OS):
  - git -C ~/KOX-OS revert <plymouth-commit>          # undo repo changes
  - or remove 'plymouth' from PACKAGES_COMMON in ~/KOX-OS/install.sh
  - remove ~/KOX-OS/plymouth/ (draft theme)
EOF

log "done. reboot manually when ready (no reboot performed)."
