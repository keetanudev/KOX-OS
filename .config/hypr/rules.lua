-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- KOX OS — Window rules                     --
-- Loaded from hyprland.lua (require("rules"))   --
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Rules are evaluated top to bottom, named first.
-- Match props: class | initial_class | title | initial_title | xwayland |
-- float | modal | xdg_tag | content | workspace ... (RE2 regex, not PCRE —
-- no lookaheads/backrefs; use (?i) for case-insensitive).
-- Effects used: float | center | size. Static effects match on the window's
-- initial_title/class as captured when the window is opened.

-----------------------
---- CALCULATOR   -----
-----------------------
-- Calculator tiled into the layout is useless; it should open as a small
-- floating, centered window. gnome-calculator clamps to its own minimum if
-- asked for less, so the requested size only needs to be "small".
hl.window_rule({
    name   = "float-calculator",
    match  = { class = "org.gnome.Calculator" },
    float  = true,
    center = true,
    size   = "420 640",
})

-----------------------
---- BROWSER NOTIFICATIONS ----
-----------------------
-- Chromium's Wayland popup windows for Web Notifications (WhatsApp Web,
-- Slack, Google Meet timers, ...) are created with NO window identity:
-- `hyprctl clients` shows class "" and title "" for them (hyprwm/Hyprland#7054:
-- "the notifications i'm seeing have no identifiers"). They tile as new
-- windows on every message. Float them and anchor the window bottom-right,
-- the same zone as mako toasts (mako's default gravity is bottom-right).
-- The match excludes anything that is floating/fullscreen/pinned so real
-- app windows never match.
hl.window_rule({
    name   = "float-chrome-notifications",
    match  = {
        class      = "^$",
        xwayland   = false,
        fullscreen = false,
        pin        = false,
    },
    float  = true,
    move   = { "monitor_w - window_w", "monitor_h - window_h" },
})

-----------------------
---- MODAL DIALOGS ----
-----------------------
-- True OS-level modal dialogs (confirmations, "are you sure", auth prompts)
-- float and center instead of splitting the layout. Deliberately NOT given a
-- size — the dialog's natural size wins.
hl.window_rule({
    name   = "float-modals",
    match  = { modal = true },
    float  = true,
    center = true,
})

-----------------------
---- FILE MANAGER -----
-----------------------
-- REVERT (2026-11-12): the earlier rule floated *every* Nautilus window,
-- which is not what was asked for. Nautilus stays tiled by default again.
--
-- Portal open/save dialogs share this class. Keep them predictable and
-- centered, while preventing activation requests from stealing focus.
hl.window_rule({
    name              = "float-portal-file-dialogs",
    match             = { class = "^xdg-desktop-portal-gtk$" },
    float             = true,
    center            = true,
    size              = "800 600",
    focus_on_activate = false,
})

---------------------------
---- AUTHENTICATION   -----
---------------------------
-- Authentication must be focused so the password can be entered immediately.
hl.window_rule({
    name   = "float-polkit-authentication",
    match  = { class = "^polkit-gnome-authentication-agent-1$" },
    float  = true,
    center = true,
    size   = "480 280",
})

-----------------------
---- SYSTEM UTILITIES --
-----------------------
for _, class in ipairs({
    "^blueman-manager$",
    "^nm-connection-editor$",
    "^pavucontrol$",
}) do
    hl.window_rule({
        name   = "float-utility-" .. class:gsub("[^%w]", ""),
        match  = { class = class },
        float  = true,
        center = true,
        size   = "800 600",
    })
end

-------------------------
---- WEBSITE LOGINS -----
-------------------------
-- Website login popups (Google/GitHub/etc. OAuth) are ordinary browser
-- windows with the same WM class as the parent — Hyprland has no prop for
-- "opened as a popup". Two workable options:
--
--   1. (active now, usually sufficient) the float-modals rule above catches
--      XDG-modal login dialogs — Firefox and Chromium mark in-window
--      auth dialogs as modal when they are real child dialogs.
--
--   2. Title-based matching — brittle because titles change, but the only
--      lever for true top-level OAuth popups. Uncomment, adjust the regex to
--      what `hyprctl clients` shows for *your* popup (open it, run the
--      command, copy title), and reload:
--
-- hl.window_rule({
--     name   = "float-login-popups-brave",
--     match  = { class = "brave-origin", title = "(?i)(sign.?in|log.?in|sign in|log in|authenticat|2-?step|verification)" },
--     float  = true,
--     center = true,
--     size   = "520 680",
-- })
-- hl.window_rule({
--     name   = "float-login-popups-firefox",
--     match  = { class = "firefox", title = "(?i)(sign.?in|log.?in|sign in|log in|authenticat|2-?step|verification)" },
--     float  = true,
--     center = true,
--     size   = "520 680",
-- })

-----------------------
---- TERMINALS    -----
-----------------------
-- Belt-and-suspenders for the kitty state-restore bug (kitty #10442):
-- Hyprland reports tiled windows as "maximized"; kitty's remember_window_size
-- saves that on exit and requests it back at the next launch, so every new
-- kitty opened fullscreen over the whole workspace. kitty.conf now sets
-- remember_window_size no (root cause); this rule additionally zeroes the
-- fullscreen state kitty asks for at open, whatever it remembered.
-- Static rule (evaluated once at open): manual Super+F fullscreen still works.
hl.window_rule({
    name             = "kitty-no-restore-fullscreen",
    match            = { class = "kitty" },
    fullscreen_state = "0 0",
})

-- NOTE: static effects are evaluated once when the window is opened and
-- match on initialTitle/initialClass. A login page that changes its <title>
-- after load will keep whatever rule matched at creation. For genuine
-- title-change handling use an event listener instead, e.g.:
--
-- hl.on("window.title", function(w)
--     if w ~= nil and w.title:match("(?i)sign.?in") then
--         hl.dispatch(hl.dsp.window.float({ action = "set" }))
--     end
-- end)
