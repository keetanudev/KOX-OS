-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- KOX OS — Hyprland entrypoint (Lua)                     --
-- Loaded by Hyprland at startup                          --
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- Modular split, per AGENTS.md:
-- monitors | input | looknfeel | bindings | autostart
require("monitors")
require("input")
require("looknfeel")
require("bindings")
require("autostart")

-- Unset Hyprland branding
hl.config({
    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
    },
})
