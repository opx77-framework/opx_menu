-- The one NativeUI document of this caller VM: created on first use, then shown and hidden.
-- Menus/confirmations never take focus; navigation comes from the service. opx_dialog owns form input.

local Bridge = require('@opx_menu/lib.bridge')
local State = require('@opx_menu/lib.state')
local Pose = require('@opx_menu/lib.pose')
local Wheel = require('@opx_menu/lib.wheel')

local MODEL = 'opxmenu'

local View = {
    ui = nil,
    shown = false,  -- tracked here: ui:state() is a snapshot published after a frame
    closing = nil,  -- token of a close still fading out
}

local function initialModel()
    return {
        menuShown = false, pos = 'right', crumb = '', desc = '', desc1 = '', desc2 = '',
        hasValue = false, hTurn = '', hChoose = '', hChange = '', hSelect = '', hBack = '',
        dlgShown = false, dlgPos = 'center', dlgConfirm = false, dlgTitle = '', dlgMeta = '', dlgMsg = '',
        dlgStatus = '', dlgSubmit = '', dlgCancel = '', dlgSubmitCap = '', dlgCancelCap = '',
        dlgCanCancel = true, dlgHot = 0,
    }
end

-- Menus do not receive document input; retain NativeUI diagnostics only.
local function listen(ui)
    ui:onEvent('error', function(name, detail)
        if Bridge.settings().debug then
            print(('[opx_menu] ui %s: %s'):format(tostring(name), tostring(detail and detail.message)))
        end
    end)
end

---@return boolean ok, string|nil reason
function View.ensure()
    if View.ui then return true end
    if type(Open77.ui) ~= 'table' or type(Open77.ui.create) ~= 'function' then
        return false, 'nativeui_unavailable'
    end
    local bundle, reason = Bridge.bundle()
    if not bundle then return false, reason end
    local ui, err = Open77.ui.create({
        source = bundle.source,
        layer = 'menu',
        zIndex = bundle.settings.zIndex or 0,
        visible = false,
        models = { [MODEL] = initialModel() },
    })
    if not ui then return false, err or 'ui_create_failed' end
    View.ui = ui
    listen(ui)
    Wheel.build(ui) -- the row elements of the wheel, written once
    return true
end

function View.destroy()
    if View.ui then pcall(View.ui.destroy, View.ui) end
    View.ui = nil
    View.shown, View.closing = false, nil
    Pose.reset()
    Wheel.reset()
end

---@param fields table
function View.merge(fields)
    if View.ui then View.ui:merge(MODEL, fields) end
end

-- Runs fn(ui) with every document call it makes submitted together (one frame sees all of them).
---@param fn fun(ui: table)
function View.batch(fn)
    local ui = View.ui
    if not ui then return end
    if type(ui.batch) == 'function' then ui:batch(function() fn(ui) end) else fn(ui) end
end

-- Pose of what is on screen (side, tilt); cheap when nothing changed.
function View.sync()
    if View.ui and View.shown and not View.closing then Pose.sync(View.ui) end
end

-- Something opened (a menu or a dialog): show the document. It never takes the input here.
function View.show()
    local ui = View.ui
    if not ui then return end
    local opening = nil
    if View.closing then
        -- a close was fading out: keep the page, drop what it still showed
        View.closing = nil
        opening = 'resume'
        View.merge({ menuShown = #State.stack > 0 and State.dialog == nil, dlgShown = State.dialog ~= nil })
    elseif not View.shown then
        opening = 'show'
    end
    View.shown = true
    ui:show()
    Pose.sync(ui, opening)
end

-- Gives the keyboard back at once (if a dialog had it); the page untilts and fades out, then hides.
function View.hide()
    local ui = View.ui
    if not ui then return end
    ui:blur()
    if View.closing or not View.shown then return end
    local token = {}
    View.closing = token
    local function finish()
        if View.ui ~= ui or View.closing ~= token then return end
        View.closing = nil
        View.shown = false
        ui:hide()
        View.merge({ menuShown = false, dlgShown = false, dlgStatus = '' })
        Pose.hidden(ui)
    end
    if not Pose.close(ui, finish) then finish() end
end

return View
