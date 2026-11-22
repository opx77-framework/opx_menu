Config = {}

-- Enables the demo command below and console reports for developers (unknown element icons, NativeUI
-- errors of the menu document). Leave it off on a live server.
Config.debug = false

-- Command that opens the demo menu (every element type, the icons, a dialog, a confirm) when debug is on.
Config.demoCommand = 'opxmenu'

-- Language of the menu texts: 'auto' follows the game language, or a file in locales/ ('en', 'fr').
Config.locale = 'auto'

-- Side a menu sits on when the caller does not choose one: 'left' or 'right'.
Config.position = 'right'

-- The selection wheel: the selected row big in the middle, its neighbours above and below smaller,
-- dimmer and pushed toward the screen edge along an arc. The wheel wraps like the navigation does.
Config.wheel = {
    rows = 3,          -- rows drawn above and below the selection (1-6; fewer when the menu is short)
    spacing = 32,      -- dp between the centres of two neighbouring rows (it shrinks with their scale)
    bend = 56,         -- dp the farthest drawn row is pushed toward the screen edge: the arc
    scale = 0.72,      -- size of the rows next to the selection (1 = as big as the selected row)
    shrink = 0.12,     -- each further step is this much smaller again (0.12 = 12 %)
    spring = { duration = 0.32, bounce = 0.1 }, -- rows sliding into their new place when the wheel turns
}

-- Colour swatches drawn at once on a colour row (centred on the current one).
Config.maxSwatches = 7

-- Default keys of the menu navigation. They are key mappings: each player can rebind them in
-- Pause > Settings > KEY BINDINGS ("opx_menu"). Names: UP, DOWN, LEFT, RIGHT, ENTER, BACKSPACE, letters...
-- While a menu is open these keys are kept from the game; WASD/ZQSD and the mouse stay with the player.
Config.keys = {
    up = 'UP',
    down = 'DOWN',
    left = 'LEFT',
    right = 'RIGHT',
    select = 'ENTER',
    back = 'BACKSPACE',
}

-- Holding an arrow repeats it: first repeat after keyRepeatDelayMs, then one step every keyRepeatMs.
Config.keyRepeatDelayMs = 320
Config.keyRepeatMs = 80

-- Text forms are configured in opx_dialog/config.lua.

-- Order of the menu document inside the NativeUI 'menu' layer.
Config.zIndex = 100

-- Frontend sounds, Wwise events played with Open77.sfx.play2d. `false` mutes one, enabled = false mutes all.
Config.sounds = {
    enabled = true,
    open = 'ui_menu_open',
    close = 'ui_menu_close',
    move = 'ui_menu_hover',
    select = 'ui_menu_onpress',
    back = 'ui_menu_exit',
    up = 'ui_menu_value_up',
    down = 'ui_menu_value_down',
    error = 'ui_menu_attributes_fail',
}

-- Colours. Each value replaces the token of the same name declared at the top of ui/menu.rcss,
-- alpha variants included (#ff3b4733 follows `accent`). Hex #rrggbb only.
Config.theme = {
    accent = '#ff3b47',     -- selection bar, active field, value chevrons of the selected row
    holo = '#4fe3ff',       -- accents: section labels, footer line, key icons
    text = '#e9fbff',       -- rows and titles
    textDim = '#86a9b5',    -- descriptions, hints, right labels, disabled rows
    alarm = '#ffa8ae',      -- field errors
    shade = '#05090b',      -- the backing gradient behind the selected row and under text inputs
}

-- The whole document leans toward the screen centre (NativeUI projection) and springs in on open.
-- nui.reducedmotion lands the springs and fades at once.
Config.tilt = {
    enabled = true,
    degrees = 10,              -- a side menu turns toward the centre about its screen edge (rotateY)
    pitch = 2,                 -- it leans back slightly (rotateX)
    centerPitch = 4,           -- a dialog shown alone (centred) leans back
    perspective = 1250,        -- dp from the eye to the screen; smaller is stronger
    spring = { duration = 0.5, bounce = 0.12 }, -- the tilt-in on open
    exitMs = 160,              -- untilt + fade on close (0: hide at once)
}

-- Update check at start: compares this version with the one published on GitHub and prints a line in the
-- server console when an update is out. Needs outbound HTTP in server.jsonc ("http": "enabled": true, with
-- "raw.githubusercontent.com" in "allowedHosts"). false = no request.
Config.versionCheck = true
