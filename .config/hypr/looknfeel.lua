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

-- Shared motion language: OutExpo for small layer surfaces and OutCubic for
-- window/workspace movement. Hyprland speed 2 is approximately 200 ms.
hl.curve("koxOutExpo", {
    type = "bezier",
    points = { { 0.16, 1.0 }, { 0.3, 1.0 } },
})
hl.curve("koxOutCubic", {
    type = "bezier",
    points = { { 0.215, 0.61 }, { 0.355, 1.0 } },
})

for _, leaf in ipairs({ "windows", "windowsIn", "windowsOut", "workspaces" }) do
    hl.animation({
        leaf = leaf,
        enabled = true,
        speed = 2,
        bezier = "koxOutCubic",
        style = "slide",
    })
end

-- Layer surfaces include Fuzzel and Mako. The effect itself is Hyprland's
-- fade; its timing and curve come from the shared layer animation leaf.
for _, namespace in ipairs({ "fuzzel", "mako" }) do
    hl.layer_rule({ match = { namespace = namespace }, animation = "fade" })
end
hl.animation({
    leaf = "layers",
    enabled = true,
    speed = 2,
    bezier = "koxOutExpo",
    style = "fade",
})
