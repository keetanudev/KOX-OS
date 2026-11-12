-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- KOX OS — Autostart                         --
-- Runs once per Hyprland session             --
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

hl.on("hyprland.start", function()
    -- Export session env into dbus activation env (OpenRC: no systemd import)
    hl.exec_cmd("dbus-update-activation-environment --all")

    -- Status bar
    hl.exec_cmd("waybar")

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
