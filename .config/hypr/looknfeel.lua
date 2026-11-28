-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- KOX OS — Look and feel                     --
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- Theme border accent: kox-theme (step 6) writes the active theme's border
-- color in Hyprland's rgba(rrggbbaa) hex form to
-- ~/.config/kox/pickers/theme-border. Read it here so `kox theme <name>`
-- recolors window borders on the next hyprctl reload. Falls back to the
-- stock gray when the file is missing or malformed. pcall-guarded: a
-- sandboxed io must never break the config load.
local themeBorder = "rgba(8a8588ee)"
do
    local ok, fh = pcall(io.open,
        (os.getenv("HOME") or "/root") .. "/.config/kox/pickers/theme-border", "r")
    if ok and fh then
        local v = fh:read("*l")
        fh:close()
        if v and v:match("^%x%x%x%x%x%x%x%x$") then
            themeBorder = "rgba(" .. v .. ")"
        end
    end
end

hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 5,
        border_size = 2,

        col = {
            active_border   = themeBorder,
            inactive_border = "rgba(584e51aa)",
        },

        layout = "dwindle",
    },

    decoration = {
        rounding = 6,

        shadow = {
            enabled = false,
        },

        blur = {
            enabled = false,
        },
    },
})

-- Shared motion language: OutExpo for small layer surfaces and softer
-- OutCubic for window/workspace movement. Speeds are in 100 ms units.
hl.curve("koxOutExpo", {
    type = "bezier",
    points = { { 0.16, 1.0 }, { 0.3, 1.0 } },
})
hl.curve("koxOutCubic", {
    type = "bezier",
    points = { { 0.05, 0.9 }, { 0.1, 1.0 } },
})

for _, leaf in ipairs({ "windows", "windowsIn", "windowsOut", "workspaces" }) do
    hl.animation({
        leaf = leaf,
        enabled = true,
        speed = 2.5,
        bezier = "koxOutCubic",
        style = "slide",
    })
end

-- Fuzzel fades quickly; Mako slides in from the right and exits the same way.
-- Layer rules inherit the shared 200 ms speed and OutExpo curve below.
hl.layer_rule({ match = { namespace = "fuzzel" }, animation = "fade" })
hl.layer_rule({ match = { namespace = "notifications" }, animation = "slide right" })
hl.animation({
    leaf = "layers",
    enabled = true,
    speed = 2,
    bezier = "koxOutExpo",
    style = "fade",
})
