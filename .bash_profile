#
# ~/.bash_profile
#

[[ -f ~/.bashrc ]] && . ~/.bashrc


# Added by Antigravity CLI installer
export PATH="/home/artix/.local/bin:$PATH"

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
   && command -v Hyprland >/dev/null 2>&1
then
    exec Hyprland
fi
