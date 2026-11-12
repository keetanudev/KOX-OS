-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- KOX OS — Look and feel                     --
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 5,
        border_size = 2,

        col = {
            active_border   = "rgba(8a8588ee)",
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
