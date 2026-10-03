-- Hyprland config for the builder-linux* boxes.
-- Lua config (hyprland.lua) replaces hyprland.conf; hyprlang is deprecated
-- since Hyprland 0.55 and will be removed. Reference:
-- https://wiki.hypr.land/Configuring/Start/

------------------
---- MONITORS ----
------------------
-- Auto-detect resolution and refresh rate.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

-------------------
---- AUTOSTART ----
-------------------
hl.on("hyprland.start", function()
    -- For cleaner logouts
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    -- Status bar and wallpaper daemon (awww is the packaged swww fork)
    hl.exec_cmd("waybar")
    hl.exec_cmd("awww-daemon")
end)

---------------
---- INPUT ----
---------------
hl.config({
    input = {
        kb_layout    = "us",
        follow_mouse = 1,
        touchpad = {
            natural_scroll = false,
        },
    },
})

-----------------------
---- LOOK AND FEEL ----
-----------------------
hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 10,
        border_size = 2,
        col = {
            active_border   = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },
        layout = "dwindle",
    },

    decoration = {
        rounding = 10,
        blur = {
            enabled = true,
            size    = 3,
            passes  = 1,
        },
    },
})

----------------------
---- WINDOW RULES ----
----------------------
-- Float the system-monitor/network popups launched from waybar clicks
hl.window_rule({
    name   = "floating-monitor",
    match  = { class = "floating-monitor" },
    float  = true,
    center = true,
    size   = { 1000, 650 },
})

---------------------
---- KEYBINDINGS ----
---------------------
-- Every bind carries a description; ~/.config/hypr/scripts/keybinds.sh reads
-- them back via `hyprctl binds -j` to build the cheatsheet.
local mainMod = "SUPER" -- "Windows" key as the main modifier

local function desc(text)
    return { description = text }
end

hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("~/.config/wofi/powermenu.sh"),        desc("Power menu"))
hl.bind(mainMod .. " + slash",  hl.dsp.exec_cmd("~/.config/hypr/scripts/keybinds.sh"), desc("Show keybind cheatsheet"))
hl.bind(mainMod .. " + B",      hl.dsp.exec_cmd("google-chrome-stable"),               desc("Open browser"))
hl.bind(mainMod .. " + Q",      hl.dsp.exec_cmd("kitty"),                              desc("Open terminal"))
hl.bind(mainMod .. " + C",      hl.dsp.window.close(),                                 desc("Close window"))
hl.bind(mainMod .. " + M",      hl.dsp.exec_cmd("~/.config/hypr/scripts/logout.sh"),   desc("Exit Hyprland (back to login)"))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd("thunar"),                             desc("Open file manager"))
hl.bind(mainMod .. " + V",      hl.dsp.window.float({ action = "toggle" }),            desc("Toggle floating"))
hl.bind(mainMod .. " + R",      hl.dsp.exec_cmd("wofi --show drun"),                   desc("App launcher"))
hl.bind("Print",                hl.dsp.exec_cmd("bash ~/.config/hypr/scripts/screenshot.sh full"),   desc("Screenshot full screen (saved and copied)"))
hl.bind("SHIFT + Print",        hl.dsp.exec_cmd("bash ~/.config/hypr/scripts/screenshot.sh region"), desc("Screenshot region (saved and copied)"))
hl.bind(mainMod .. " + P",      hl.dsp.window.pseudo(),                                desc("Toggle pseudotile (dwindle)"))
hl.bind(mainMod .. " + J",      hl.dsp.layout("togglesplit"),                          desc("Toggle split direction (dwindle)"))
hl.bind(mainMod .. " + F",      hl.dsp.window.fullscreen({ action = "toggle" }),       desc("Toggle fullscreen"))

-- Resize the active tiled window
hl.bind(mainMod .. " + CTRL + left",  hl.dsp.window.resize({ x = -50, y = 0,  relative = true }), desc("Shrink window horizontally"))
hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.resize({ x = 50,  y = 0,  relative = true }), desc("Grow window horizontally"))
hl.bind(mainMod .. " + CTRL + up",    hl.dsp.window.resize({ x = 0,   y = -50, relative = true }), desc("Shrink window vertically"))
hl.bind(mainMod .. " + CTRL + down",  hl.dsp.window.resize({ x = 0,   y = 50,  relative = true }), desc("Grow window vertically"))

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }),  desc("Focus window left"))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }), desc("Focus window right"))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }),    desc("Focus window up"))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }),  desc("Focus window down"))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }),       desc("Switch to workspace " .. i))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), desc("Move window to workspace " .. i))
end
