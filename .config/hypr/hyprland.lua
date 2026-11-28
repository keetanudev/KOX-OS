-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- KOX OS — Hyprland entrypoint (Lua)                     --
-- Loaded by Hyprland at startup                          --
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- Emergency-mode guard: register a terminal bind before any module loads.
-- A reload during a dotfile update could otherwise land after Hyprland
-- cleared its bind registry but before the normal keymap was registered,
-- leaving zero binds and tripping Emergency Mode. This bind exists from
-- the first line of the config and is removed only once bindings.lua
-- confirms the normal keymap registered.
local rescueBind
do
    local ok, bind = pcall(hl.bind, "SUPER + SHIFT + ESCAPE",
        hl.dsp.exec_cmd((os.getenv("HOME") or "/root") .. "/.local/bin/kox-terminal"),
        { description = "KOX rescue terminal (config recovery)" })
    if ok then
        rescueBind = bind
    else
        print("[hyprland] could not register the rescue bind: " .. tostring(bind))
    end
end

-- Modular split, per AGENTS.md:
-- monitors | input | looknfeel | bindings | autostart
-- Each module is isolated so one broken file cannot abort the whole
-- config load (and take the rescue bind down with it).
local modules = { "monitors", "input", "looknfeel", "bindings", "autostart", "rules" }
local modulesOk = true
for _, module in ipairs(modules) do
    local ok, err = pcall(require, module)
    if not ok then
        modulesOk = false
        print("[hyprland] failed to load " .. module .. ": " .. tostring(err))
    end
end

-- Keep the rescue bind unless every module loaded and bindings.lua reports
-- at least one successful bind. A partially loaded config stays usable.
local registeredBinds = tonumber(KOX_BINDINGS_REGISTERED) or 0
if modulesOk and registeredBinds > 0 then
    if rescueBind then
        local ok, err = pcall(function() rescueBind:remove() end)
        if not ok then
            print("[hyprland] could not remove the rescue bind: " .. tostring(err))
        end
    end
else
    print(string.format(
        "[hyprland] keeping rescue bind SUPER+SHIFT+ESCAPE (modules_ok=%s, binds=%d)",
        tostring(modulesOk), registeredBinds))
end

-- Unset Hyprland branding
hl.config({
    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        -- Do not let XDG activation requests (such as portal dialogs)
        -- steal focus from the current tiled workflow.
        focus_on_activate        = false,
    },
})
