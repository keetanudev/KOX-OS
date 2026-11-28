# AGENTS.md — KOX OS Master Context

**Read this entire file before changing anything.** It is the persistent brief for OpenCode and any engineer working on KOX OS. When this document and the live system disagree, treat the repo as the source of truth and the live system as the symptom: investigate both before overwriting either.

Last updated: **2026-11-28**. Migration baseline: **`b859001`**; verify current HEAD with `git log`.

---

## 0. Start every session with this

```bash
cd ~/KOX-OS
git status -sb
git log --oneline -5
kox doctor
```

- Work from `~/KOX-OS`. Never develop directly in `~/.config` or `~/.local/bin`; those are deploy targets.
- If the worktree is dirty, stop and commit or stash. `kox update` refuses to run on a dirty tree.
- Read the file you are about to edit, including its comments. Match the existing style.
- Verify every claim with a command before reporting it. “Should work” is not verification.
- **Do not reboot, power off, repartition, format, or change boot configuration without explicit permission.**
- One concern per change. Keep commits atomic.

---

## 1. What KOX OS is

KOX OS is an independently maintained, lightweight, modular Linux desktop built on **Hyprland**, with two supported bases: **Artix Linux (OpenRC)** on the NVMe development box and **Arch/CachyOS (systemd)** on the SATA machine. The shared desktop deliberately avoids monolithic shells in favour of a component-driven stack:

- **Hyprland** configured entirely in **Lua** (`~/.config/hypr/*.lua`).
- **Waybar** as a floating “island” bar with a stable centre notch.
- **Quickshell** for the lockscreen and the visual coverflow pickers.
- **GTK3 layer-shell panels** for Wi-Fi, Bluetooth and battery.
- **`kox-scale`**, a custom UI scaling engine that scales every text surface without touching the compositor.
- **`kox`**, a single CLI for updates, theme, wallpaper, cursor, scale, lock and doctor.
- **Dual-init support** — shared scripts detect OpenRC or systemd. The NVMe stays systemd-free; the Arch SATA machine uses systemd units. One repo serves both.

Target: a fast, self-contained, fresh-installable desktop. Idle RAM budget: **≤ 900 MB**.

---

## 2. This machine — NVMe development box

| Fact | Value |
| --- | --- |
| Hostname | `KOX` |
| OS | Artix Linux rolling, **OpenRC** (no systemd) |
| User | `ved` (uid/gid `1000`), home `/home/ved` |
| Repo | `/home/ved/KOX-OS`, branch `main` |
| Remote | `https://github.com/keetanudev/KOX-OS.git` |
| Disk layout | `/dev/nvme0n1p1` → vfat `/boot` (GRUB); `/dev/nvme0n1p2` → btrfs with subvolumes `@` (`/`) and `@home` (`/home`) |
| Kernel | `linux-lts` 6.18.64-1-lts |
| Compositor | Hyprland 0.57.2 (Lua config) |
| Bar | Waybar 0.16.0 |
| Terminal | kitty 0.50.0 |
| Shell UI | Quickshell 0.3.2 |
| Current theme | `tokyonight` |
| Current accent | `#7aa2f7` (border state `7aa2f7ee`) |
| Current wallpaper | `/home/ved/Pictures/Wallpapers/dark-batman-noir.jpg` (changed from `4.jpg` on 2026-11-28 by choice) |
| Current cursor | `macOS-White` |
| UI scale | `10` |
| Baseline bind count | 116 |

The **SATA machine** (`archest`, Arch/CachyOS + systemd, `/dev/sda`) is the dual-init port target: Arch was installed on 2026-11-24 and KOX is deployed from this same repo. The NVMe remains the Artix/OpenRC development box. The SATA’s previous Artix KOX state (`materia`, `#2ec4b6`) is archived under `~/Documents/KOX-OS/sata-state-2026-11-24/`; do not copy it over the NVMe’s current look.

### Fonts

The lockscreen uses the Nothing dot-matrix face (Ndot 57) and other proprietary community fonts. They are installed **user-level** in `~/.local/share/fonts/ndot/` and are **never committed** to the repo. The bar and GTK panels use **JetBrainsMono Nerd Font** (system package `ttf-jetbrains-mono-nerd`); the Material-style panel glyphs depend on it.

---

## 3. Non-negotiable engineering rules

These are hard constraints. Breaking one is a regression even if the feature “works”.

1. **Dual init, never mixed.** The NVMe is Artix/OpenRC: use OpenRC services and `rc-service --user`; no systemd units. The SATA is Arch/CachyOS/systemd: use `systemctl` and its units. Shared scripts must detect the distro (`install.sh` `detect_platform`, matching `ID_LIKE` including `cachyos`) and the init system (`/run/systemd/system`) and must not hard-code either. Never install systemd on the NVMe or OpenRC on the SATA.
2. **No new polling loops in Waybar.** Prefer native modules, event signals, and the existing watcher state files. The 5-second Wi-Fi/battery/Bluetooth intervals are grandfathered fallbacks, not a pattern to copy.
3. **The repo is the source of truth.** Edit files in `~/KOX-OS`, then deploy with `kox update` or `install.sh`. A fix that exists only in `~/.config` will be lost on the next update.
4. **Atomic deployment only.** Never reintroduce `cp -aT --remove-destination` or any deployment that unlinks a watched config path before recreating it. Use `deploy_tree()`.
5. **Preserve live-only state.** `ui-scale`, picker choices, wallpaper, cursor, GTK settings, and other user state must survive every update.
6. **Never commit font binaries.**
7. **`kox-theme --restore` must not apply the theme’s representative wallpaper.** The saved wallpaper is the user’s choice and is restored separately.
8. **Keep the rescue bind contract.** `SUPER + SHIFT + ESCAPE` must exist before any module loads and may be removed only after all modules load and at least one normal bind registers.
9. **One Waybar instance only.** The shared lock, duplicate collapse, child-fd close, and wait-for-old-bar logic are load-bearing.
10. **NetworkManager owns networking.** `connmand` stays disabled. BlueZ must have `AutoEnable=true`. The `network` group must also have the KOX polkit rule (`etc/polkit-1/rules.d/49-kox-network.rules`); without it, panel Wi-Fi actions fail with `Insufficient privileges` because no polkit agent runs in the Hyprland session.
11. **The repo’s `hyprpaper.conf` uses `~/Pictures/Wallpapers/...`.** The live SATA/NVMe copy may contain an absolute path; that difference is expected and must not be “fixed” in place.
12. **This Hyprland build has no `hyprctl keyword`.** Use `hyprctl eval` for dynamic config. `hyprctl configerrors` prints an empty string when clean.
13. **Do not add a second bar, a second panel daemon, or a second Bluetooth watcher.** All are one-shot or lock-guarded by design.
14. **Test before commit; commit before update.** `kox update` requires a clean worktree and will `exec` the installer.

---

## 4. Repository map

```text
KOX-OS/
├── AGENTS.md                     ← this file
├── README.md                     user-facing overview
├── OMARCHY_HOTKEY_MAPPING.md     Omarchy → KOX keybind mapping reference
├── install.sh                    idempotent installer / deployer
├── .bash_profile                 guarded TTY1 Hyprland autologin
├── themes/                       accent-only palettes (blue.css, pink.css)
├── wallpapers/                   12-image collection (theme previews + hyprpaper)
├── .config/
│   ├── fuzzel/                   launcher + power menu
│   ├── hypr/
│   │   ├── hyprland.lua          entrypoint: rescue bind + module loader
│   │   ├── monitors.lua          outputs, scale, layout
│   │   ├── input.lua             keyboard, touchpad, gestures
│   │   ├── looknfeel.lua         borders, gaps, rounding, theme accent
│   │   ├── bindings.lua          keybinds + KOX_BINDINGS_REGISTERED
│   │   ├── autostart.lua         session-start commands
│   │   ├── rules.lua             window/workspace rules
│   │   ├── defaults.lua          user-selected app roles (browser/terminal/fileManager/editor)
│   │   ├── hyprpaper.conf        portable wallpaper config
│   │   ├── hyprlock.conf         fallback lockscreen
│   │   └── hypridle.conf         idle rules: dim / lock / suspend
│   ├── kitty/kitty.conf          terminal; font_size owned by kox-scale
│   ├── kox-panel/scale.css       generated panel scale
│   ├── kox-pickers/              coverflow QML
│   ├── mako/config               notifications
│   ├── quickshell/               lock.qml, test.qml, pam/lock.conf
│   ├── waybar/                   config.jsonc, style.css, theme-*.css
│   └── wireplumber/              Bluetooth audio policy
└── .local/bin/
    ├── kox                       unified CLI
    ├── kox-lock                  lockscreen wrapper + flock + hyprlock fallback
    ├── kox-osd                   event-driven volume OSD
    ├── kox-panel                 GTK3 layer-shell panels (wifi/bt/battery)
    ├── kox-panel-autostart       guarded panel daemon start
    ├── kox-pulse-autostart       pipewire-pulse guard
    ├── kox-session-env           D-Bus/systemd session environment publisher
    ├── kox-browser               XDG browser router (reads defaults.lua)
    ├── kox-private-browser       incognito window of the configured browser
    ├── kox-terminal              configured terminal launcher (defaults.lua)
    ├── kox-scale                 UI scale engine
    ├── kox-suspend               init-aware suspend (systemctl / loginctl / zzz)
    ├── kox-waybar-autostart      guarded bar start + respawn
    ├── kox-pickers/              kox-theme, kox-wallpaper, kox-cursor, kox-bar, kox-coverflow, kox-clipboard
    └── kox-widgets/              kox-wifi, kox-bluetooth, kox-bt-watcher, kox-power
```

The `cachy-*` scripts are the inherited rice command surface. Keep them working; the keybinds call them.

---

## 5. Architecture contracts

### 5.1 Hyprland Lua session

`hyprland.lua` is the entrypoint. It **must** keep this order:

1. Register the rescue bind `SUPER + SHIFT + ESCAPE` → `kox-terminal` **before any module loads**, via `pcall(hl.bind, ...)`. `kox-terminal` reads `defaults.lua` and falls back to kitty/foot/alacritty, so the rescue path survives a partially broken config.
2. Load modules in order with `pcall(require, ...)`:
   `monitors`, `input`, `looknfeel`, `bindings`, `autostart`, `rules`.
3. Remove the rescue bind **only if every module loaded and `KOX_BINDINGS_REGISTERED > 0`**.
4. Keep it otherwise, and print a diagnostic. A partially loaded config must remain usable.

`bindings.lua` sets `mainMod = "SUPER"`, defines `safe_bind()` with `pcall`, and increments `KOX_BINDINGS_REGISTERED` only on success. A skipped bind must not abort the rest of the keymap.

`looknfeel.lua` reads `~/.config/kox/pickers/theme-border` on every load (`rrggbbaa`, alpha last) and wraps it as `rgba(...)`. If the file is missing, fall back to the shipped default. `kox-theme` writes this file and live-applies via `hyprctl eval`.

`autostart.lua` runs on `hl.on("hyprland.start", ...)` and starts, in order:

1. `kox-waybar-autostart` (bar first — a barless boot is the worst visible defect)
2. `kox-session-env` (dbus activation env, plus `systemctl --user import-environment` on systemd)
3. `KOX_SCALE_BOOT=1 kox-scale apply`
4. `kox-bt-watcher`
5. `kox-pulse-autostart`
6. `kox-panel-autostart`
7. `kox-osd`
8. `mako`
9. `udiskie --automount --no-notify --no-tray`
10. `hyprpaper`
11. `wl-paste --type text --watch cliphist store &` and the image twin (clipboard history)
12. `hypridle` (idle rules from `~/.config/hypr/hypridle.conf`)

Lua API notes:

- Binds use `hl.bind(keys, hl.dsp..., opts)`.
- Dispatchers live under `hl.dsp` (`exec_cmd`, `window.*`, `focus`, `workspace.*`, `layout`, `group.*`).
- Some DSPs are absent in this build; always guard with `pcall` / `safe_bind`.
- Use `hl.config({ ... })` for config merges and `hl.exec_cmd(...)` for commands.
- **No `hyprctl keyword`.** Dynamic changes use `hyprctl eval "hl.config({...})"`.

### 5.2 Waybar island

- `config.jsonc`: top layer, `height: 24` at UI scale 10, all modules centred.
- The **ghost modules** (`custom/bluetooth#ghost`, `custom/wifi#ghost`, `pulseaudio#ghost`, `custom/battery#ghost`, `hyprland/workspaces#ghost`) are invisible width mirrors. They keep the clock notch fixed when the real modules grow. Do not reorder or remove them without re-balancing the notch.
- `style.css` imports `theme-accent.css` and `theme-scale.css`.
- `kox-waybar-autostart` is spawn-first: waits for the Wayland socket, forks the bar, polls liveness at 100 ms, respawns up to 3 times, logs to `/tmp/kox-waybar.log`, and exits. No resident guard.
- Single-instance contract: shared `flock` with `kox-scale`, duplicate collapse, child lock fd closed, wait for the old bar to exit. A scale change must never produce two bars.
- Bluetooth lockstep: `kox-bt-watcher` writes `$XDG_RUNTIME_DIR/kox-bt-state.json` and signals Waybar signal `8` (`SIGRTMIN+8`). Both real and ghost Bluetooth widgets read the same file, so the notch never moves.
- Wi-Fi, battery and Bluetooth retain a 5 s interval only as startup/fallback. Everything else is native/event-driven.

### 5.3 `kox-scale`

- State: `~/.config/kox/ui-scale`, integer **9–20**, reference **11**.
- Curve: `round(ref × scale / 11)`. Scale 11 reproduces the reference look.
- Consumers and reference values:
  - Waybar font `11`, bar height `26`
  - kitty `9pt`
  - fuzzel `13`
  - mako `11`
  - `kox-panel` classes from `PANEL_REFS`
- Writes:
  - `~/.config/waybar/theme-scale.css`
  - `height` in `~/.config/waybar/config.jsonc`
  - `~/.config/kox-panel/scale.css`
  - `font_size` in `kitty.conf`
  - fuzzel size
  - mako font size
  - GTK `text-scaling-factor` via gsettings
- Live apply: Waybar `SIGUSR2`, panel `SIGHUP`, kitty remote socket `unix:@kox-kitty` (fallback `SIGUSR1`), gsettings.
- `kox-scale apply` runs at every session start. On a normal boot it is a byte-level no-op. Its verdict goes to `$XDG_RUNTIME_DIR/kox-scale-boot.log`.
- The installer seeds `10` only when the state file is missing. Never overwrite a user’s chosen scale on update.

### 5.4 Pickers and appearance state

Entry points:

- `kox theme` → coverflow theme picker (fallback: fuzzel)
- `kox theme <name>` → apply a named theme
- `kox wallpaper` → coverflow wallpaper picker
- `kox cursor` → cursor picker
- `kox bar` → bar-style picker (currently a stub)

Coverflow:

- QML: `~/.config/kox-pickers/kox-coverflow.qml`
- Wrapper: `~/.local/bin/kox-pickers/kox-coverflow`
- IPC: environment variables in, a `/tmp` result file out.
- Fallback: fuzzel with preview-card icons if Quickshell or the QML is missing.
- Theme cards are ffmpeg-composited from each theme’s representative wallpaper; missing wallpapers degrade to an accent card, never a blank row.

`kox-theme` owns a seven-step cascade:

1. Waybar accent (`theme-accent.css` + `SIGUSR2`)
2. Fuzzel prompt/selection
3. Mako border (`makoctl reload`)
4. Kitty managed color block + live `kitty @ set-colors`
5. Wallpaper via `kox-wallpaper --set` — **skipped in `--restore` mode**
6. Hyprland border (`theme-border` + `hyprctl eval`)
7. GTK theme + color scheme (gsettings + `gtk-3.0/4.0/settings.ini`)

The built-in coverflow themes are:
`cachy-dark`, `dracula`, `emerald`, `arctic-light`, `ant-dracula`, `nordic`, `orchis`, `materia`, `catppuccin`, `tokyonight`, `everforest`.

Direct accent-only palettes (`kox theme blue`, `kox theme pink`) use `themes/<name>.css` and write `~/.config/kox/pickers/accent`; they have no coverflow card.

### 5.5 Panels and widgets

- `kox-panel` is a GTK3 layer-shell dropdown for Wi-Fi, Bluetooth and battery. `--daemon` is started once by `kox-panel-autostart`, which waits for the Wayland socket.
- `kox-panel` reads `~/.config/kox-panel/scale.css`; `kox-scale` hot-reloads it with `SIGHUP`.
- `kox-widgets/kox-wifi`, `kox-bluetooth` and `kox-power` emit Waybar JSON.
- `kox-bt-watcher` is the single source of Bluetooth state. Do not query BlueZ independently from both bar widgets.
- Bar click opens the matching panel; right-click toggles Wi-Fi/Bluetooth.

### 5.6 Lockscreen

- `kox-lock` takes a non-blocking `flock` on `$XDG_RUNTIME_DIR/kox-lock.lock`; a second press is ignored.
- Primary: Quickshell `~/.config/quickshell/lock.qml` (`WlSessionLock` + `PamContext`).
- PAM policy: `~/.config/quickshell/pam/lock.conf` (user-owned; no `/etc/pam.d` edits).
- Fallback: `hyprlock` if Quickshell, the QML, or the lock exits non-zero.
- Safe test: `KOX_LOCK_DRY=1 quickshell -p ~/.config/quickshell/lock.qml`.

### 5.7 `kox` CLI

| Command | Behaviour |
| --- | --- |
| `kox update` | detect the distro, check out `main` (Artix) or `arch-port` (Arch/CachyOS), `sudo pacman -Syu --noconfirm`, `git pull --ff-only origin <branch>`, then run `install.sh` with `KOX_ASSUME_DEFAULTS=1` and verify the Hyprland animation runtime |
| `kox theme [name]` | coverflow picker, or apply a named theme |
| `kox wallpaper [path]` | coverflow wallpaper picker |
| `kox cursor` | cursor picker |
| `kox bar` | bar-style picker (stub) |
| `kox scale <9-20\|current\|reset\|apply>` | UI scale |
| `kox lock` | exec `kox-lock` |
| `kox clipboard` | clipboard history picker (`kox-pickers/kox-clipboard`, cliphist + fuzzel) |
| `kox default <role> <app>` | set the `browser`, `terminal`, `fileManager` or `editor` role; writes `~/.config/hypr/defaults.lua` and the XDG associations |
| `kox suspend` | lock, then suspend through `kox-suspend` (systemd → `systemctl suspend`, OpenRC → `loginctl suspend`/`zzz`) |
| `kox doctor` | PipeWire, Bluetooth, Waybar and privilege checks |
| `kox help` | command reference |

`kox update` validates before touching the system: git, sudo and pacman present, repo present, `install.sh` present, a known distro (`detect_distro`), and a clean worktree (`git status --porcelain`, including untracked files). It then selects the branch — `main` on Artix, `arch-port` on Arch/CachyOS — before any package or git operation; an unknown distro or a dirty tree aborts without pulling. A failed package update stops before the dotfile pull. After deployment it checks the runtime animation speeds (250 ms windows/workspaces, 200 ms layers), reloads Hyprland once if they are stale, prints any `hyprctl configerrors`, and warns if they still differ.

### 5.8 Installer and deployment

`install.sh` is idempotent and safe to re-run. Flow:

1. Banner, preflight, sudo keepalive, user detection
2. Package installation (`pacman`)
3. Backup existing configs to `~/.config-backup-<epoch>`
4. `deploy_tree()` for `.config` and `.local`
5. Seed `~/.config/kox/ui-scale` only if missing
6. Post-deploy `hyprctl reload` + `hyprctl configerrors` check
7. Deploy wallpapers without clobbering user files
8. Mark scripts executable
9. Clear stale kitty `main.json`
10. Restore saved theme, wallpaper and cursor
11. Configure `~/.bash_profile` (PATH + guarded TTY1 `start-hyprland`)
12. Enable the distro's services (OpenRC runlevels or systemd units); disable `connmand` if present; set BlueZ `AutoEnable=true`
13. Add user to `wheel audio video storage`
14. Verify appearance deployment

`deploy_tree()` contract:

- Stages a copy inside the destination (`mktemp -d -- "$dst/.kox-deploy.XXXXXX"`) so the rename is same-filesystem even when `~/.config` is a symlink.
- Walks the staged tree parent-before-child (`find -print0 | sort -z`).
- Creates directories, then `mv -fT`s each file/symlink over its target. `rename(2)` is atomic: a watcher sees the old inode or the new one, never a missing path.
- Handles file↔directory transitions deterministically.
- Applies directory modes/timestamps last, so read-only source dirs cannot block renames.
- Preserves live-only files (state files, `hyprpaper.conf` absolute path, etc.).
- Cleans the staging tree on failure.

Never replace this with a naive copy. The Emergency Mode incident on 2026-11-22 was caused by exactly that.

### 5.9 Daily-driver essentials

**Clipboard history**

- `autostart.lua` starts two watchers: `wl-paste --type text --watch cliphist store &` and the image twin. `wl-paste --watch` follows one MIME type, so both are needed.
- `kox clipboard` execs `~/.local/bin/kox-pickers/kox-clipboard`. It lists `cliphist list` (`<id>\t<content>`, newest first), shows the text in fuzzel, and restores the picked entry with `cliphist decode <id> | wl-copy` — `cliphist decode` takes the **id**, not the text.
- `SUPER + V` opens the history; plain paste moved to `SUPER + SHIFT + V` so the picker does not steal the paste shortcut. `SUPER + CTRL + V` is an alias for the same picker.
- The bind calls `~/.local/bin/kox-pickers/kox-clipboard` by absolute path (`$HOME` resolved at config load) — not through `PATH`, `~` expansion or the CLI. A bind that silently fails is worse than no bind.
- **fuzzel 1.15 has no `--preview` pane.** Passing it makes fuzzel exit 1 with `error: --preview: invalid option` — the same exit code as a cancelled picker, so `|| exit 0` swallowed the failure and `SUPER + V` looked like a dead bind. The picker now captures fuzzel's stderr and reports it; only a silent exit is treated as a cancel.
- `cachy-clipboard` (inherited alias) delegates to `kox-pickers/kox-clipboard`. The old implementation piped the picked *text* into `cliphist decode`, which only accepts an entry *id*.

**Idle management**

- `hypridle` reads `~/.config/hypr/hypridle.conf`: dim at 2 min, lock at 5 min, lock + suspend at 15 min. Waking up always lands on a locked screen.
- Suspend goes through `~/.local/bin/kox-suspend`, which detects the init system (`systemctl suspend` on systemd, `loginctl suspend` or `zzz` on OpenRC/elogind) and locks the session before suspending.
- `hypridle` and `brightnessctl` are installed by `install.sh` (`PACKAGES_COMMON`).

---

## 6. State files and generated files

| Path | Owner | Meaning |
| --- | --- | --- |
| `~/.config/kox/ui-scale` | `kox-scale` | integer 9–20, reference 11 |
| `~/.config/hypr/defaults.lua` | `kox default` | user-selected app roles; the installer preserves it across deploys |
| `~/.config/kox/pickers/theme` | `kox-theme` | active coverflow theme name |
| `~/.config/kox/pickers/theme-border` | `kox-theme` | `rrggbbaa` border colour read by `looknfeel.lua` |
| `~/.config/kox/pickers/accent` | `kox` / `kox-theme` | accent-only palette name (e.g. `blue`) |
| `~/.config/kox/pickers/wallpaper` | `kox-wallpaper` | absolute path to the saved wallpaper |
| `~/.config/kox/pickers/cursor` | `kox-cursor` | cursor theme name |
| `~/.config/kox/pickers/bar` | `kox-bar` | bar style (stub) |
| `~/.config/waybar/theme-accent.css` | `kox-theme` | generated `@define-color accent_color` |
| `~/.config/waybar/theme-scale.css` | `kox-scale` | generated scale CSS |
| `~/.config/kox-panel/scale.css` | `kox-scale` | generated panel scale CSS |
| `~/.config/kitty/kitty.conf` | `kox-theme` | managed `# BEGIN KOX theme` block |
| `~/.config/gtk-3.0/settings.ini`, `gtk-4.0/settings.ini` | `kox-theme` | GTK theme + dark flag |
| `$XDG_RUNTIME_DIR/kox-bt-state.json` | `kox-bt-watcher` | shared Bluetooth state |
| `/tmp/kox-waybar.log` | `kox-waybar-autostart` | bar boot timeline |
| `$XDG_RUNTIME_DIR/kox-scale-boot.log` | `kox-scale` | per-boot scale verdict |
| `~/.cache/kox/pickers/themes/*.png` | `kox-theme` | generated preview cards |

State files are **live-only**. They are not in the repo and must not be overwritten by deployment.

---

## 7. Deployment and update rules

### Normal update

```bash
cd ~/KOX-OS
git status -sb          # must be clean
kox update
```

`kox update` detects the distro, checks out the matching branch (`main` on Artix/OpenRC, `arch-port` on Arch/CachyOS/systemd), runs `pacman -Syu`, pulls that branch fast-forward, then runs the installer with defaults assumed. The installer deploys the repo over the live config using `deploy_tree()`, restores the saved appearance, and reloads Hyprland if a session is running.

### Branch split

| Branch | Owns |
| --- | --- |
| `main` | the shared desktop **and** the OpenRC baseline — this is what Artix deploys |
| `arch-port` | `main` plus the Arch/CachyOS extras: the Plymouth theme (`plymouth/themes/kox`, `scripts/remove-plymouth.sh`) and `scripts/kox-ai-fallback.sh` |

`main` must stay strictly OpenRC-compatible. Its `install.sh` is identical to `arch-port`'s: the `systemctl` calls sit behind `$INIT_SYSTEM == systemd` guards with OpenRC `rc-update` branches, so nothing Arch-only may be merged into `main` beyond the shared UI.

Shared UI work lands on `main` first and is merged forward into `arch-port`. Do **not** develop shared UI on `arch-port` and leave it there — that is what made the live Artix box run the `arch-port` flavour of `bindings.lua` while `kox update` kept restoring the `main` flavour.

### Manual deploy

```bash
cd ~/KOX-OS
KOX_ASSUME_DEFAULTS=1 bash install.sh
```

### Expected live differences

- `~/.config/hypr/hyprpaper.conf` stores an **absolute** wallpaper path on a live machine. The repo ships `~/Pictures/Wallpapers/...`. This is intentional; do not “sync” it back.
- `~/.config/kox/*`, picker state, GTK settings, cursor state and `~/.config-backup-*` are live-only.
- Generated CSS and `kitty.conf` may contain live values from `kox-scale` / `kox-theme`.

### Cross-machine ownership

When mounting one machine’s disk from the other, the host may not resolve the target user. Use numeric IDs:

```bash
sudo -u '#1000' -g '#1000' ...
# or, when resolvable:
sudo -u ved -g ved ...
```

Verify deployed files on the NVMe are `1000:1000` with the expected modes (`644` for configs, `755` for scripts).

### Backup directories

Each installer run may create `~/.config-backup-<epoch>`. They are recovery artifacts, not repo content. Remove them only with the user’s approval.

---

## 8. Testing and verification

Run the checks that match the change. Do not skip the live check when a live session is available.

### Shell

```bash
bash -n install.sh
bash -n .local/bin/kox
bash -n .local/bin/kox-scale
bash -n .local/bin/kox-pickers/kox-theme
```

### Hyprland config

```bash
Hyprland --verify-config
hyprctl reload
hyprctl configerrors          # empty string means clean
hyprctl binds -j | jq length  # baseline 116
```

For a cross-mounted tree, set `HOME` to the target home before `Hyprland --verify-config`.

### Installer / `deploy_tree`

Sandbox-test at minimum:

- fresh deploy of files, directories, symlinks, broken symlinks, modes
- redeploy preserves live-only files
- file→directory and directory→file transitions
- a concurrent watcher never observes a watched path missing
- deployment through a symlinked destination
- a failed copy leaves the destination untouched

### Emergency-mode guard

Mock the Lua environment and verify:

- healthy modules + >0 binds → rescue bind removed
- one module fails → rescue bind stays
- zero binds → rescue bind stays
- rescue `hl.bind` itself fails → config still loads

### Desktop

```bash
kox doctor
kox theme
kox wallpaper
kox cursor
kox lock          # or KOX_LOCK_DRY=1 quickshell -p ~/.config/quickshell/lock.qml
```

Confirm: one Waybar bar, Wi-Fi/Bluetooth panels, kitty opens normally, coverflow thumbnails, accent intact.

### No-leakage check

When deploying a cross-mounted tree, confirm no `/mnt/...` path leaked into live config:

```bash
grep -RIl '/mnt/' ~/.config ~/.local/bin 2>/dev/null
```

### Honesty rule

A successful `hyprctl reload` is not proof that the desktop looks right. If you did not boot the machine, say so. Runtime verification on the NVMe still requires a boot.

---

## 9. Recovery playbook

### Rescue terminal

`SUPER + SHIFT + ESCAPE` opens kitty from the first line of `hyprland.lua`, before modules load. It is removed only when the normal keymap registers. If a config load fails, this bind should still work.

### If the session is unusable

1. Switch to a TTY: `Ctrl + Alt + F2`.
2. Log in as `ved`.
3. Check the config:

   ```bash
   cd ~/KOX-OS
   Hyprland --verify-config
   ```

4. Restore the last backup if needed:

   ```bash
   ls -dt ~/.config-backup-* | head
   ```

5. Re-deploy:

   ```bash
   KOX_ASSUME_DEFAULTS=1 bash ~/KOX-OS/install.sh
   ```

### Plain console login on tty1

```bash
KOX_NO_SESSION=1
```

The autologin block checks `KOX_NO_SESSION` and leaves tty1 as a console.

### Zero binds / Emergency Mode

- Keep the rescue bind; do not remove it to “clean up” the config.
- Inspect `hyprctl configerrors`.
- Check that `bindings.lua` increments `KOX_BINDINGS_REGISTERED` and that `hyprland.lua` sees a value > 0.
- A single broken module must not take down the rest; `pcall` is mandatory.

### Duplicate Waybar

Check for two processes and the lock:

```bash
pgrep -a waybar
```

The guard and `kox-scale` share a lock. Do not kill the guard or bypass the lock; fix the race instead.

### Kitty opens fullscreen

- `kitty.conf` must contain `remember_window_size no`.
- Remove the stale cache: `rm -f ~/.cache/kitty/main.json`.

### Wi-Fi / Bluetooth

```bash
# Artix/OpenRC
rc-service NetworkManager status
rc-service bluetoothd status
# Arch/systemd
systemctl status NetworkManager
systemctl status bluetooth
# Both
rfkill list
nmcli device status
bluetoothctl show
```

`connmand` must stay disabled. NetworkManager is the only network stack. BlueZ `AutoEnable=true` is required.

### Lockscreen

```bash
KOX_LOCK_DRY=1 quickshell -p ~/.config/quickshell/lock.qml
```

If Quickshell fails, `kox-lock` falls back to `hyprlock`. The session must never be left unlocked.

---

## 10. Current baseline and open work

Current baseline (verify with `git log`):

- Migration baseline: `b859001` (`main == origin/main` at migration time)
- Latest commits:
  - `b859001` — Fix: ship cachy-screenrecord-status companion script
  - `9ebea09` … `74c877f` — panel/widget polish: Material icons, hover fills, accent resolution, ghost-hover fix
  - `fb75b22` — Docs: add AGENTS.md master context
  - `2408f6b` — Preserve saved wallpaper during theme restore
- The NVMe repo was clean at the migration baseline; the NVMe is unmounted and ready to boot.
- Live code matches the repo. The only live differences are the five appearance-generated files (fuzzel, hyprpaper, kitty, mako, theme-accent) that carry the current theme.
- NVMe appearance: `tokyonight`, accent `#7aa2f7`, wallpaper `dark-batman-noir.jpg`, cursor `macOS-White`, `ui-scale=10`.
- Ndot lockscreen fonts are installed at `~/.local/share/fonts/ndot/` and visible to fontconfig.
- SATA is being wiped for Arch. Its KOX state, legacy scripts and OpenCode history are archived under `~/Documents/KOX-OS/`.

### Pending NVMe boot verification

After booting the NVMe:

```bash
kox doctor
```

Then confirm:

1. Exactly one Waybar bar.
2. Wi-Fi and Bluetooth work from the bar panels.
3. `kitty` opens tiled/normal, not fullscreen.
4. `kox theme` opens the coverflow picker with `tokyonight` active.
5. `kox wallpaper` opens the coverflow picker with thumbnails.
6. `kox update` completes without Emergency Mode and preserves `tokyonight`, wallpaper `dark-batman-noir.jpg`, cursor `macOS-White` and scale `10`.
7. `SUPER + SHIFT + ESCAPE` is not needed in a healthy session but remains available.

### Reports and artifacts

- Latest written report: `~/Documents/KOX-OS/KOX-OS-Report-2026-11-22.md`
- Migration archive: `~/Documents/KOX-OS/` — README, SATA KOX state, legacy scripts, OpenCode history, package list and checksums.
- Emergency Mode diagnosis: `~/Documents/KOX-OS/Panic.md`
- A copy of the latest report is also at `~/Documents/ved/KOX-OS-Report-2026-11-22.md`.

---

## 11. Working agreement

### Commit style

Use the existing prefix style:

```text
Fix: ...
Feat: ...
Chore: ...
```

Keep each commit to one concern. Include the “why” in the body when the change is non-obvious. Push to `origin main` after verifying.

### Definition of done

A change is done only when:

1. The repo is edited (not just the live config).
2. The relevant syntax/config checks pass.
3. The live deployment path has been exercised (`kox update` or `install.sh`) when safe.
4. The user-visible state is preserved (theme, accent, wallpaper, cursor, scale).
5. `git status` is clean and the commit is pushed.
6. The final report states exactly what was verified and what still needs a reboot.

### Communication

- Be concise and concrete.
- Report commands and their results, not intentions.
- Call out uncertainty and unverified runtime behaviour explicitly.
- Ask before destructive actions: reboot, poweroff, partition, format, delete backups, force-push.
- Never claim the NVMe “works” without booting it.

---

## 12. Copy-paste bootstrap prompt

If this file is not auto-loaded, paste this at the start of a session:

```text
You are the lead engineer for KOX OS, working in ~/KOX-OS on the NVMe development machine (Artix Linux OpenRC, Hyprland Lua, user ved). Read ~/KOX-OS/AGENTS.md in full before doing anything. It contains the architecture, hard constraints, state files, deployment rules, testing matrix and recovery playbook.

Rules: edit the repo, never only the live config; never use cp -aT --remove-destination; preserve live-only state (theme, accent, wallpaper, cursor, ui-scale); keep the rescue bind contract; dual init — OpenRC on the NVMe, systemd on the Arch/CachyOS SATA machine, detect instead of hard-coding; no new Waybar polling loops; do not reboot or repartition without asking. Verify with bash -n, Hyprland --verify-config, hyprctl reload/configerrors, and kox doctor. Commit atomically and push to origin main. Report exactly what changed, what you verified, and what still needs a boot.
```
