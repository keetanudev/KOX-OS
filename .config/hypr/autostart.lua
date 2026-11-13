-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- KOX OS — Autostart                         --
-- Runs once per Hyprland session             --
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

hl.on("hyprland.start", function()
    -- Export session env into dbus activation env (OpenRC: no systemd import)
    hl.exec_cmd("dbus-update-activation-environment --all")

    -- UI scale: re-apply the stored state once per session. Consumer
    -- configs persist on disk, so on a normal boot this is a byte-level
    -- no-op (~100 ms); it exists so drift (engine curve changes, manual
    -- edits) self-heals at every boot instead of showing as a stale UI.
    hl.exec_cmd("kox-scale apply")

    -- Status bar: guarded start (one-shot supervisor — waybar has been
    -- seen to lose the cold-boot race and die silently while every other
    -- autostart item survived; the guard waits for the Wayland socket,
    -- retries bounded, then exits. No daemon.)
    hl.exec_cmd("kox-waybar-autostart")

    -- Bluetooth widget daemon: polls BT state, writes one JSON state file
    -- and signals waybar so both BT widgets re-render in lockstep (keeps
    -- the clock notch perfectly still across connect/disconnect).
    hl.exec_cmd("kox-bt-watcher")

    -- Audio: pipewire-pulse (PulseAudio compatibility socket). pipewire +
    -- wireplumber come up as OpenRC user services; the wrapper guards against
    -- a second instance and waits for the pipewire core socket first.
    hl.exec_cmd("kox-pulse-autostart")

    -- Panel daemon: bar-anchored dropdowns for wifi / bluetooth / battery
    -- (the wrapper waits for the Wayland socket, then execs kox-panel --daemon)
    hl.exec_cmd("kox-panel-autostart")

    -- Volume OSD: minimal thin white bar just below the bar on every
    -- default-sink change (knob, cachy-vol keys, panel slider). Event-driven
    -- via one pactl subscribe stream, frame-synced ease, hides ~1.6s after
    -- the last change.
    hl.exec_cmd("kox-osd")

    -- Notification daemon
    hl.exec_cmd("mako")

    -- Removable drives: automount, no tray, no notifications
    hl.exec_cmd("udiskie --automount --no-notify --no-tray")

    -- Wallpaper daemon
    hl.exec_cmd("hyprpaper")
end)
