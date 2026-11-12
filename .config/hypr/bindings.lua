-- bindings.lua: Omarchy Quattro-inspired keyboard workflow on CachyOS.
-- Reference: omacom/omarchy branch quattro, manual/07-hotkeys.md +
-- default/hypr/bindings/{applications,tiling,clipboard,media,utilities}.lua
-- Rule: Omarchy-specific commands (omarchy-*, omarchy-shell, walkers/menus)
-- are substituted with stock Linux equivalents or omitted (see
-- ~/OMARCHY_HOTKEY_MAPPING.md). pcall-guarded binds skip cleanly if a Lua
-- DSP API is absent in this Hyprland build instead of breaking the config.

local mainMod = "SUPER"
local terminal = "kitty"
local browser = "brave-origin"
local files = "nautilus --new-window"
local editor = terminal .. " -e micro"
local monitor = terminal .. " -e btop"
-- home is resolved at runtime so this config is portable across users/machines
local home = os.getenv("HOME") or "/root"

local function safe_bind(keys, action, opts)
  local ok, err = pcall(hl.bind, keys, action, opts)
  if not ok then
    print("[bindings] skipped '" .. keys .. "': " .. tostring(err))
  end
end

------------------
---- APP LAUNCH ---
------------------
-- Omarchy: Super+Return terminal / Super+Shift+Return browser (exact function)
safe_bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
safe_bind(mainMod .. " + SHIFT + Return", hl.dsp.exec_cmd(browser))
safe_bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd(browser))
safe_bind(mainMod .. " + SHIFT + ALT + B", hl.dsp.exec_cmd(browser .. " --incognito"))
-- Omarchy: Super+Shift+F files / Super+Shift+Alt+F files-in-term-cwd (exact)
safe_bind(mainMod .. " + SHIFT + F", hl.dsp.exec_cmd(files))
safe_bind(mainMod .. " + SHIFT + ALT + F", hl.dsp.exec_cmd("cachy-nautilus-cwd"))
-- Approx: editor (micro) / activity (btop) replace Neovim/Omarchy panels
safe_bind(mainMod .. " + SHIFT + N", hl.dsp.exec_cmd(editor))
safe_bind(mainMod .. " + CTRL + T", hl.dsp.exec_cmd(monitor))

------------------
---- MENUS --------
------------------
-- Approx: fuzzel replaces the Omarchy menu; powermenu script replaces system menu
safe_bind(mainMod .. " + Space", hl.dsp.exec_cmd("cachy-launcher"))
safe_bind(mainMod .. " + Escape", hl.dsp.exec_cmd("cachy-powermenu"))
-- Approx: keybinding reference opens in the terminal (Super+K in Omarchy)
safe_bind(mainMod .. " + K", hl.dsp.exec_cmd(terminal .. " -e less " .. home .. "/OMARCHY_HOTKEY_MAPPING.md"))

------------------
---- WINDOWS ------
------------------
safe_bind(mainMod .. " + W", hl.dsp.window.close())
safe_bind(mainMod .. " + Q", hl.dsp.window.close())
-- Close all windows: python+hyprctl replaces the omarchy helper script.
-- NOTE: Hyprland 0.56 uses Lua dispatch; legacy `dispatch closewindow` is rejected.
safe_bind("CTRL + ALT + Delete", hl.dsp.exec_cmd("cachy-close-all"))
safe_bind(mainMod .. " + T", hl.dsp.window.float({ action = "toggle" }))
safe_bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
safe_bind(mainMod .. " + ALT + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
safe_bind(mainMod .. " + J", hl.dsp.layout("togglesplit")) -- dwindle toggle, same as Omarchy
safe_bind(mainMod .. " + P", hl.dsp.window.pseudo())
-- Approx: pin toggle stands in for Omarchy's pop (float+pin) helper.
-- NOTE: Lua dispatch syntax (Hyprland 0.56 rejects legacy `dispatch pin`).
safe_bind(mainMod .. " + O", hl.dsp.exec_cmd("hyprctl dispatch 'hl.dsp.window.pin()'"))

-- Focus / swap with arrows
safe_bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
safe_bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
safe_bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
safe_bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))
safe_bind(mainMod .. " + SHIFT + left", hl.dsp.window.swap({ direction = "l" }))
safe_bind(mainMod .. " + SHIFT + right", hl.dsp.window.swap({ direction = "r" }))
safe_bind(mainMod .. " + SHIFT + up", hl.dsp.window.swap({ direction = "u" }))
safe_bind(mainMod .. " + SHIFT + down", hl.dsp.window.swap({ direction = "d" }))

-- Workspaces 1-10, move-with-follow, move-silent (exact layout as Omarchy)
for i = 1, 10 do
  local key = i % 10
  safe_bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
  safe_bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
  safe_bind(mainMod .. " + SHIFT + ALT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }))
end

-- Workspace cycling: next / previous / former (exact)
safe_bind(mainMod .. " + Tab", hl.dsp.focus({ workspace = "e+1" }))
safe_bind(mainMod .. " + SHIFT + Tab", hl.dsp.focus({ workspace = "e-1" }))
safe_bind(mainMod .. " + CTRL + Tab", hl.dsp.focus({ workspace = "previous" }))

-- Scratchpad (exact)
safe_bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("scratchpad"))
safe_bind(mainMod .. " + grave", hl.dsp.workspace.toggle_special("scratchpad"))
safe_bind(mainMod .. " + ALT + S", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))
safe_bind(mainMod .. " + SHIFT + grave", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))

-- Alt+Tab window cycling on workspace (approx of Omarchy's cycle+raise)
if hl.dsp.window.cycle_next then
  safe_bind("ALT + Tab", hl.dsp.window.cycle_next())
  safe_bind("ALT + SHIFT + Tab", hl.dsp.window.cycle_next({ next = false }))
end

-- Mouse window management + workspace scroll (exact)
safe_bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
safe_bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
safe_bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
safe_bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Grouping (exact if the DSP group API exists in this build)
if hl.dsp.group then
  safe_bind(mainMod .. " + G", hl.dsp.group.toggle())
  safe_bind(mainMod .. " + ALT + G", hl.dsp.window.move({ out_of_group = true }))
  safe_bind(mainMod .. " + ALT + Tab", hl.dsp.group.next())
  safe_bind(mainMod .. " + ALT + SHIFT + Tab", hl.dsp.group.prev())
end

------------------
---- CLIPBOARD ----
------------------
-- Universal copy/cut/paste: same technique as Omarchy (synthetic key events
-- via send_key_state), guarded so a missing API only skips these three binds.
if hl.dsp.send_key_state and hl.dispatch and hl.timer then
  local function send_once(mods, key)
    return function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
      hl.timer(function()
        hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
      end, { timeout = 50, type = "oneshot" })
    end
  end
  safe_bind(mainMod .. " + C", send_once("CTRL", "C"))
  safe_bind(mainMod .. " + V", send_once("CTRL", "V"))
  safe_bind(mainMod .. " + X", send_once("CTRL", "X"))
end
-- Approx: cliphist+fuzzel picker replaces the Omarchy clipboard panel
safe_bind(mainMod .. " + CTRL + V", hl.dsp.exec_cmd("cachy-clipboard"))

------------------
---- CAPTURE ------
------------------
-- Approx: grim+slurp replaces omarchy-capture; Print=fullscreen,
-- Super+Ctrl+C=region (for keyboards without Print), Alt+Print=record toggle
safe_bind("Print", hl.dsp.exec_cmd("cachy-screenshot fullscreen"))
safe_bind(mainMod .. " + CTRL + C", hl.dsp.exec_cmd("cachy-screenshot region"))
safe_bind("ALT + Print", hl.dsp.exec_cmd("cachy-screenrecord"))
safe_bind(mainMod .. " + Print", hl.dsp.exec_cmd("hyprpicker -a"))

------------------
---- AUDIO/MEDIA --
------------------
-- Native wpctl/playerctl/brightnessctl replace omarchy-* scripts (same effect)
-- NOTE (2026-09-22): Evision RGB Keyboard (USB 320f:505b) sends BOGUS HID
-- consumer reports alongside normal key reports: physical "p" also emits
-- XF86AudioLowerVolume, physical "\" also emits XF86AudioRaiseVolume, and
-- physical "]" also emits XF86AudioPause/Play. Kernel hid-evision only
-- filters 320f:5041, so this 505b unit uses hid-generic with no filtering
-- (verified via /sys/bus/hid/devices/0003:320F:505B.* -> hid-generic).
-- 2026-09-23 update: volume knob NEEDS Raise/LowerVolume, but ghost p/\ share
-- the identical scancode+keycode (c00ea/VOLUMEDOWN, c00e9/VOLUMEUP on event5),
-- so hwdb cannot separate them. Fix: route through cachy-vol, which drops
-- the action only when cachy-kb-watch saw the matching event4 letter within
-- 0.25s (ghost), and passes knob turns through. Same for play-pause via
-- cachy-media (ghost "]"). Wrappers fail open (knob works) if the watcher
-- has no state yet (e.g. before `input` group re-login).
safe_bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("cachy-vol up"), { locked = true, repeating = true })
safe_bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("cachy-vol down"), { locked = true, repeating = true })
safe_bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, repeating = true })
safe_bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, repeating = true })
safe_bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
safe_bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })
-- Omarchy precise/shortcut variants: Alt=1% steps, Shift=min/max
safe_bind("ALT + XF86AudioRaiseVolume", hl.dsp.exec_cmd("cachy-vol up1"), { locked = true, repeating = true })
safe_bind("ALT + XF86AudioLowerVolume", hl.dsp.exec_cmd("cachy-vol down1"), { locked = true, repeating = true })
safe_bind("ALT + XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 1%+"), { locked = true, repeating = true })
safe_bind("ALT + XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 1%-"), { locked = true, repeating = true })
safe_bind("SHIFT + XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 100%"), { locked = true, repeating = true })
safe_bind("SHIFT + XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 1"), { locked = true, repeating = true })
safe_bind("XF86AudioNext", hl.dsp.exec_cmd("cachy-media next"), { locked = true })
safe_bind("XF86AudioPause", hl.dsp.exec_cmd("cachy-media play-pause"), { locked = true })
safe_bind("XF86AudioPlay", hl.dsp.exec_cmd("cachy-media play-pause"), { locked = true })
safe_bind("XF86AudioPrev", hl.dsp.exec_cmd("cachy-media previous"), { locked = true })
safe_bind("SHIFT + XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })

------------------
---- TOGGLES ------
------------------
-- Approx: mako modes replace the Omarchy notification-silencing toggle
safe_bind(mainMod .. " + comma", hl.dsp.exec_cmd("makoctl dismiss -a last"), { description = "Dismiss notification" })
safe_bind(mainMod .. " + SHIFT + comma", hl.dsp.exec_cmd("makoctl dismiss -a"))
safe_bind(mainMod .. " + CTRL + comma", hl.dsp.exec_cmd("makoctl mode -t do-not-disturb"))
-- Approx: SIGUSR1 toggles waybar (Omarchy toggles its own bar the same way)
safe_bind(mainMod .. " + SHIFT + Space", hl.dsp.exec_cmd("sh -c 'pgrep -x waybar >/dev/null && pkill -USR1 waybar || waybar'"))
-- Omarchy-style pickers: wallpaper (Super+Ctrl+Space) and theme (Super+Ctrl+Shift+Space)
safe_bind(mainMod .. " + CTRL + Space", hl.dsp.exec_cmd("cachy-wallpaper"))
safe_bind(mainMod .. " + CTRL + SHIFT + Space", hl.dsp.exec_cmd("cachy-theme"))
-- Cursor selector (extra beyond Omarchy parity)
safe_bind(mainMod .. " + CTRL + SHIFT + C", hl.dsp.exec_cmd("cachy-cursor"))
-- Bar style selector (extra beyond Omarchy parity): switches the Waybar
-- layout/look between the styles in ~/.config/waybar/styles.
safe_bind(mainMod .. " + CTRL + SHIFT + B", hl.dsp.exec_cmd("cachy-bar"))
-- Lock the session with the Ryoku orbital clock lockscreen (quickshell).
-- cachy-lock runs the orbital QML lock and falls back to the rice's stock
-- hyprlock (~/.config/hypr/hyprlock.conf) if the bundle is unavailable.
-- Wired 2026-10-20; previous bind was plain `hyprlock`.
safe_bind(mainMod .. " + CTRL + L", hl.dsp.exec_cmd("cachy-lock"))
-- Zoom in/out (same idea as Omarchy cursor zoom)
if hl.get_config then
  safe_bind(mainMod .. " + CTRL + Z", function()
    local zoom = hl.get_config("cursor.zoom_factor") or 1
    hl.config({ cursor = { zoom_factor = zoom + 1 } })
  end)
  safe_bind(mainMod .. " + CTRL + ALT + Z", function()
    hl.config({ cursor = { zoom_factor = 1 } })
  end)
end

------------------
---- KOX EXTRAS --
------------------
-- KOX OS additions beyond the rice set (non-conflicting):
--   Super+D: second launcher bind (cachy-launcher is `exec fuzzel`)
safe_bind(mainMod .. " + D", hl.dsp.exec_cmd("cachy-launcher"))
--   Super+M: exit the compositor
safe_bind(mainMod .. " + M", hl.dsp.exit())
