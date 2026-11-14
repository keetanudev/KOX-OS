-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- KOX OS — Autostart                         --
-- Runs once per Hyprland session             --
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

hl.on("hyprland.start", function()
    -- Status bar FIRST: a barless boot is the most visible defect a
    -- session can have, and the bar needs nothing but the Wayland socket.
    -- The guard is spawn-first with instant bounded respawn (its own
    -- milestone log lands in /tmp/kox-waybar.log) and re-derives its
    -- env; kox-scale apply below handles a bar that is already running.
    hl.exec_cmd("kox-waybar-autostart")

    -- Export session env into dbus activation env (OpenRC: no systemd import)
    hl.exec_cmd("dbus-update-activation-environment --all")

    -- UI scale: re-apply the stored state once per session. Consumer
    -- configs persist on disk, so on a normal boot this is a byte-level
    -- no-op (~100 ms); it exists so drift (engine curve changes, manual
    -- edits) self-heals at every boot instead of showing as a stale UI.
    -- KOX_SCALE_BOOT=1 tags the run so its verdict is written to the
    -- per-boot log ($XDG_RUNTIME_DIR/kox-scale-boot.log).
    hl.exec_cmd("KOX_SCALE_BOOT=1 kox-scale apply")

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
