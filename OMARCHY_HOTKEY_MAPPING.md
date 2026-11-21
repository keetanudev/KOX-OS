# Omarchy Quattro → CachyOS Hotkey Mapping

Reference: `omacom/omarchy` branch `quattro` — `manual/07-hotkeys.md`,
`manual/04-navigation.md`, `default/hypr/bindings/*.lua`. Status: **exact** =
same keys + same effect · **approx** = same keys, stock-tool substitute ·
**omitted** = not bound, reason given. Terminal = kitty, browser = brave-origin.

## Launching apps

| Omarchy (Quattro) | CachyOS | Command | Status |
|---|---|---|---|
| Super+Return → terminal | Super+Return → kitty | `kitty` | exact |
| Super+Shift+Return → browser | Super+Shift+Return → Brave | `brave-origin` | exact |
| Super+Shift+F → files | Super+Shift+F → Nautilus | `nautilus --new-window` | exact |
| Super+Shift+Alt+F → files in term cwd | Super+Shift+Alt+F → Nautilus in kitty/alacritty cwd, else $HOME | `cachy-nautilus-cwd` | approx |
| Super+Shift+B → browser | Super+Shift+B → Brave | `brave-origin` | exact |
| Super+Shift+Alt+B → private | Super+Shift+Alt+B → incognito | `brave-origin --incognito` | exact |
| Super+Shift+N → Neovim | Super+Shift+N → micro | `kitty -e micro` | approx |
| Super+Ctrl+T → activity | Super+Ctrl+T → btop | `kitty -e btop` | approx |
| Tmux/Herdr/Spotify/Docker/Signal/Obsidian/1Password/webapps/AI | — | — | omitted (apps not installed; out of scope by design) |

## Menus / system

| Omarchy (Quattro) | CachyOS | Command | Status |
|---|---|---|---|
| Super+Space → Omarchy menu | Super+Space → fuzzel | `cachy-launcher` | approx |
| Super+Escape → system menu | Super+Escape → powermenu | `cachy-powermenu` (lock/suspend/reboot/poweroff/logout) | approx |
| Super+K → keybindings | Super+K → this file in pager | `kitty -e less ~/OMARCHY_HOTKEY_MAPPING.md` | approx |
| Super+Ctrl+L → lock | Super+Ctrl+L → session lock (no locker UI) | `loginctl lock-session` | approx |
| Super+Ctrl+Q / XF86Calculator → calc | — | — | omitted (no calculator installed) |
| Super+Ctrl+Shift+Space → theme menu | same | `cachy-theme` (GTK + border + waybar accent + wallpaper, live) | approx |
| Super+Ctrl+Space → wallpaper menu | same | `cachy-wallpaper` (user dir + CachyOS stock, persisted) | approx |
| — (extra) | Super+Ctrl+Shift+C → cursor menu | `cachy-cursor` (live via hyprctl setcursor + gsettings) | extra |
| Audio/Bluetooth/Wifi/Display/Power panels, emoji, transcode, AI agent, reminders, notices | — | — | omitted (Omarchy-shell-specific; no equivalents installed) |

## Navigation / tiling

| Omarchy (Quattro) | CachyOS | Implementation | Status |
|---|---|---|---|
| Super+W / Super+Q close | Super+W / Super+Q close | `window.close()` | exact |
| Ctrl+Alt+Del close all | Ctrl+Alt+Del close all | hyprctl+python3 kill loop | exact (function) |
| Super+T float toggle | Super+T float toggle | `window.float(toggle)` | exact |
| Super+F fullscreen | Super+F fullscreen | `window.fullscreen(fullscreen)` | exact |
| Super+Alt+F full width | Super+Alt+F maximized | `window.fullscreen(maximized)` | exact |
| Super+Ctrl+F tiled fullscreen | — | — | omitted (Omarchy helper script) |
| Super+J toggle split | Super+J togglesplit | `layout(togglesplit)` | exact |
| Super+P pseudo | Super+P pseudo | `window.pseudo()` | exact |
| Super+O pop (float+pin) | Super+O pin toggle (pair with Super+T) | `hyprctl dispatch pin` | approx |
| Super+L layout toggle | — | — | omitted (Omarchy helper; fragile to fake) |
| Super+arrows focus / Super+Shift+arrows swap | same | `focus` / `window.swap` | exact |
| Super+1..0 switch, Super+Shift+1..0 move, Super+Shift+Alt+1..0 silent move | same | `focus` / `window.move` (+follow=false) | exact |
| Super+Tab / Super+Shift+Tab / Super+Ctrl+Tab next/prev/former | same | `focus(e+1 / e-1 / previous)` | exact |
| Super+S / Super+Grave scratchpad, Super+Alt+S / Super+Shift+Grave send | same | `workspace.toggle_special(scratchpad)` / move to special | exact |
| Alt+Tab / Alt+Shift+Tab cycle | Alt+Tab cycle | `window.cycle_next()` | approx |
| Super+scroll workspace, Super+LMB drag, Super+RMB resize | same | focus e±1 / drag / resize | exact |
| Super+G group, Super+Alt+G ungroup, Super+Alt+Tab group cycle | same (guarded on DSP group API) | `group.toggle/next/prev` | exact* (*skipped cleanly if API absent) |
| Resize Super+Minus/Equal (±Shift/Alt/Ctrl steps) | — | — | omitted (kept out to limit risk; easy follow-up) |
| Monitor moves, scaling steps, zoom-reset | zoom only: Super+Ctrl+Z in, Super+Ctrl+Alt+Z reset | cursor.zoom_factor | approx/partial |

## Clipboard (universal)

| Omarchy (Quattro) | CachyOS | Implementation | Status |
|---|---|---|---|
| Super+C / V / X copy/paste/cut | Super+C / V / X | synthetic key events via `send_key_state` (same technique as Omarchy), guarded | exact* (*skipped if API absent) |
| Super+Ctrl+V clipboard manager | Super+Ctrl+V history picker | `cachy-clipboard` (cliphist+fuzzel) | approx |

## Capture

| Omarchy (Quattro) | CachyOS | Command | Status |
|---|---|---|---|
| Super+Ctrl+C capture menu | Super+Ctrl+C region shot | `cachy-screenshot region` (grim+slurp → ~/Pictures/Screenshots + clipboard + notify) | approx |
| Print screenshot | Print fullscreen shot | `cachy-screenshot fullscreen` | approx |
| Alt+Print screenrecord | Alt+Print record toggle | `cachy-screenrecord` (wf-recorder + slurp → ~/Videos) | approx |
| Super+Print color picker | Super+Print picker | `hyprpicker -a` | exact |
| OCR/webcam overlays/dictation/URL/video-download | — | — | omitted (Omarchy-specific tooling) |

## Audio / brightness / media

| Omarchy (Quattro) | CachyOS | Command | Status |
|---|---|---|---|
| Vol up/down/mute, mic mute | same XF86 keys | `wpctl … @DEFAULT_AUDIO_SINK@/@DEFAULT_AUDIO_SOURCE@` | exact (function) |
| Brightness up/down | same XF86 keys | `brightnessctl -e4 -n2 set ±5%` | exact (function) |
| Shift+Brightness max/min; Alt+keys 1% steps; Alt+Vol 1% steps | same modifiers | wpctl 1% / brightnessctl 1% / 100% | exact (function) |
| Next/Play/Pause/Prev | same XF86 keys | `playerctl …` | exact (function) |
| Keyboard-backlight keys, touchpad toggles, eject, output/source switch | — | — | omitted (no kbd-backlight/touchpad-toggle need verified on this hw; switchers were Omarchy scripts) |

## Notifications / toggles

| Omarchy (Quattro) | CachyOS | Command | Status |
|---|---|---|---|
| Super+, dismiss latest | Super+, dismiss | `makoctl dismiss -a last` | approx |
| Super+Shift+, dismiss all | Super+Shift+, dismiss all | `makoctl dismiss -a` | exact |
| Super+Ctrl+, silence toggle | Super+Ctrl+, DND toggle | `makoctl mode -t do-not-disturb` | approx |
| Notification history/invoke | — | — | omitted (mako has `makoctl list/history`; no key bound — bind on demand) |
| Super+Shift+Space bar toggle | Super+Shift+Space waybar toggle | SIGUSR1 toggle / launch fallback | approx |
| Idle/nightlight/display/ fullscreen-desktop/gaps/transparency toggles | — | — | omitted (Omarchy toggle framework; no daemons installed for these) |
