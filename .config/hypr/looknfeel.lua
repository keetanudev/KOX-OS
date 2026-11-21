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
