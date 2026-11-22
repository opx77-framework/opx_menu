-- opx_menu client library: `local Menu = require('@opx_menu')` in a resource that declares
-- `dependency "opx_menu"`. It runs in the CALLER's VM, so callbacks are plain Lua functions.
-- Keyboard only and non-blocking: menus never take the focus or the cursor; the navigation keys
-- are key mappings of the opx_menu service, forwarded here (opx_menu_input) while we own the screen.

local Bridge = require('@opx_menu/lib.bridge')
local View = require('@opx_menu/lib.view')
local State = require('@opx_menu/lib.state')
local Menus = require('@opx_menu/lib.menu')
local Dialog = require('@opx_menu/lib.dialog')
local Input = require('@opx_menu/lib.input')
local Pose = require('@opx_menu/lib.pose')
local Icons = require('@opx_menu/lib.icons')

local Menu = {}

local function onScreen()
    return #State.stack > 0 or State.dialog ~= nil or State.form ~= nil
end

-- Navigation keys from the service (key mappings, open77:pauseKey): to the dialog when one is open.
exports('opx_menu_input', function(action)
    if type(action) ~= 'string' then return false end
    if State.dialog then Dialog.input(action) else Menus.input(action) end
    return true
end)

-- Called by the opx_menu service when another resource claims the screen (force: CloseAll export).
exports('opx_menu_release', function(force)
    if not onScreen() then
        -- nothing drawn: give the claim back too, so the service never keeps a stale owner
        if State.claimed then Bridge.release() end
        State.claimed, State.input = false, false
        return true
    end
    if not force and not Menus.releasable() then return false end
    Menus.closeAll('preempted')
    return true
end)

-- The service stopped: drop everything, the next open fetches a fresh bundle.
local function serviceStopped()
    -- a claim may already sit on a reloaded service: give it back (fails harmlessly on a stopping one)
    if State.claimed then Bridge.release() end
    State.claimed, State.input = false, false
    Menus.closeAll('stopped')
    View.destroy()
    Bridge.reset()
end

AddEventHandler('onClientResourceStop', function(name)
    if name ~= 'opx_menu' then return end
    if not Bridge.current() then serviceStopped() return end
    -- our service VM is still listed as running: the notice is a predecessor's (hot reload), unless
    -- the stop has not settled yet, so look again once it has
    SetTimeout(1000, function()
        if not Bridge.current() then serviceStopped() end
    end)
end)

---Opens a menu. Without `parent`, it replaces this resource's open menus.
---@param opts OpxMenuOptions
---@return OpxMenu|nil menu, string|nil reason
function Menu.open(opts)
    return Menus.open(opts)
end

---Form dialog. Yields: call it from a CreateThread or a menu callback.
---@param opts OpxDialogOptions
---@return table|nil values keyed by field name; nil + reason when it was not answered
function Menu.dialog(opts)
    return Input.run(opts)
end

---Yes/no question. Yields like Menu.dialog.
---@param opts OpxConfirmOptions
---@return boolean yes, string|nil reason why it is false without a "no" ('cancelled', 'closed', 'menu_busy'...)
function Menu.confirm(opts)
    local answer, reason = Dialog.run('confirm', opts)
    if answer == true then return true end
    return false, reason
end

---Closes this resource's menus and its pending dialog (which answers nil / false).
function Menu.closeAll()
    Menus.closeAll('closeAll')
end

---True while this resource shows a menu or a dialog.
function Menu.isOpen()
    return onScreen()
end

---The menu currently drawn by this resource, or nil.
function Menu.current()
    return Menus.current()
end

---Kept for compatibility: every style ('clean', 'flat', 'holo') draws the same selection wheel.
---@param style 'clean'|'flat'|'holo'|nil
---@return boolean ok, string|nil reason
function Menu.setStyle(style)
    if style ~= nil and not Menus.styleOf(style) then return false, 'invalid_style' end
    State.style = style
    return true
end

---The menu tilt of a side ('left', 'right', 'center') from Config.tilt, for a document of your own
---that should match the menus. Nil when opx_menu is unavailable.
---@param side 'left'|'right'|'center'
---@return table|nil projection { origin, rotateX, rotateY, perspective } for ui:projection / create
function Menu.projection(side)
    if not Bridge.bundle() then return nil end
    return Pose.target(side == 'left' and 'left' or side == 'right' and 'right' or 'center')
end

---Every icon name an element can use (built in, aliases, and the ones this resource added), sorted.
---@return string[]
function Menu.icons()
    return Icons.names()
end

---Adds (or replaces) an icon for this resource's menus: SVG path data, stroked like the built-in ones.
---@param name string letters, digits, _ and -, 32 characters at most
---@param d string SVG path data (commands and numbers only)
---@param viewBox? string default '0 0 24 24'
---@return boolean ok, string|nil reason 'invalid_name' | 'invalid_path' | 'invalid_view_box'
function Menu.addIcon(name, d, viewBox)
    local ok, reason = Icons.add(name, d, viewBox)
    if ok and #State.stack > 0 then Menus.render() end
    return ok, reason
end

---True while ANY resource shows an opx menu or dialog.
function Menu.isAnyOpen()
    return onScreen() or Bridge.isAnyOpen()
end

return Menu
