-- Pose of the document: tilted toward the screen centre with a NativeUI projection, a short fade
-- in and out. Springs and fades go through the motion system, so nui.reducedmotion lands them.
-- Nothing runs per frame: a projection is sent only when the pose changes.

local Bridge = require('@opx_menu/lib.bridge')
local State = require('@opx_menu/lib.state')

local Pose = {}

local cur = {}

function Pose.reset()
    cur = {
        ui = nil,          -- the document these values belong to
        pose = nil,        -- 'left' | 'right' | 'center' while tilted
        animated = false,  -- #root opacity was animated once (it has a history to start from)
        faded = false,     -- #root was faded out by a close
    }
end
Pose.reset()

local function tilt()
    return Bridge.settings().tilt or {}
end

local function project(ui, p)
    local ok, err = pcall(ui.projection, ui, p)
    if not ok and Bridge.settings().debug then print('[opx_menu] projection: ' .. tostring(err)) end
end

-- A dialog alone sits in the centre; over a menu it takes the menu's side.
function Pose.side()
    local top = State.stack[#State.stack]
    if not top then return 'center' end
    return top.position == 'left' and 'left' or 'right'
end

---Projection of a side: a side menu turns toward the centre about its screen edge.
---@param side 'left'|'right'|'center'
---@return table
function Pose.target(side)
    local t = tilt()
    local degrees, pitch = tonumber(t.degrees) or 10, tonumber(t.pitch) or 2
    local p = { perspective = tonumber(t.perspective) or 1250 }
    if side == 'left' then
        p.origin, p.rotateX, p.rotateY = { 0.0, 0.5 }, pitch, degrees
    elseif side == 'right' then
        p.origin, p.rotateX, p.rotateY = { 1.0, 0.5 }, pitch, -degrees
    else
        p.origin, p.rotateX, p.rotateY = { 0.5, 0.5 }, tonumber(t.centerPitch) or 4, 0
    end
    return p
end

local function fadeIn(ui, fromZero)
    local spec = { to = { opacity = 1 }, tween = { duration = 0.16, easing = 'ease-out' } }
    if fromZero or not cur.animated then spec.from = { opacity = 0 } end
    ui:animate('#root', spec)
    cur.animated, cur.faded = true, false
end

---Brings the document to the pose of what is on screen.
---@param ui table
---@param opening? 'show'|'resume' it was hidden / a close was fading out
function Pose.sync(ui, opening)
    if cur.ui ~= ui then
        Pose.reset()
        cur.ui = ui
    end
    if opening == 'show' then fadeIn(ui, true)
    elseif opening == 'resume' or cur.faded then fadeIn(ui, false) end

    local t = tilt()
    if t.enabled == false then
        if cur.pose then project(ui, false) end
        cur.pose = nil
        return
    end
    local side = Pose.side()
    if side == cur.pose and not opening then return end
    local p = Pose.target(side)
    -- From hidden the projection is off: turned on with a spring, the page tilts in from flat.
    if opening == 'show' then p.reset = true end
    p.spring = t.spring or { duration = 0.5, bounce = 0.12 }
    project(ui, p)
    cur.pose = side
end

---Untilts and fades the page, then calls `done` (which hides it). False: hide now.
---@param ui table
---@param done function
---@return boolean
function Pose.close(ui, done)
    local ms = tonumber(tilt().exitMs) or 160
    if cur.ui ~= ui or ms <= 0 then return false end
    local tween = { duration = ms / 1000, easing = 'ease-in' }
    if cur.pose then project(ui, { rotateX = 0, rotateY = 0, tween = tween }) end
    local spec = { to = { opacity = 0 }, tween = tween }
    if not cur.animated then spec.from = { opacity = 1 } end
    ui:animate('#root', spec)
    cur.animated, cur.faded = true, true
    SetTimeout(ms, done)
    return true
end

---The document is hidden: the next show tilts in from flat again.
---@param ui table
function Pose.hidden(ui)
    if cur.ui ~= ui or not cur.pose then return end
    project(ui, false)
    cur.pose = nil
end

return Pose
