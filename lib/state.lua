-- Shared state of the library inside one caller VM. Hooks are filled by lib/menu.lua and lib/dialog.lua.
return {
    stack = {},       -- open menus, bottom to top; the top one is drawn
    dialog = nil,     -- the active dialog or confirm
    claimed = false,  -- this VM holds the opx_menu screen (see the service Claim export)
    input = false,    -- the service forwards the navigation keys to this VM (SetInput)
    style = nil,      -- Menu.setStyle value, kept for compatibility (every style draws the same wheel)
}
