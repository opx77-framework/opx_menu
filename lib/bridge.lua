-- Calls from the caller's VM to the opx_menu service (exports run inline, values are copied).

local SERVICE = 'opx_menu'

local Bridge = {}
local bundle = nil
local generation = nil -- service generation the bundle came from

local function call(name, ...)
    local ok, a, b = pcall(Open77.exports.callSync, SERVICE, name, ...)
    if not ok then return nil, tostring(a) end
    return a, b
end

---@return table|nil bundle, string|nil reason
function Bridge.bundle()
    if bundle then return bundle end
    local value, reason = call('GetBundle')
    if type(value) ~= 'table' or type(value.source) ~= 'string' then
        return nil, reason or 'opx_menu_unavailable'
    end
    bundle = value
    generation = Open77.resource.generation(SERVICE)
    return bundle
end

function Bridge.reset()
    bundle, generation = nil, nil
end

-- True while the service VM our bundle came from still runs: on a hot reload the new service starts
-- before the old one's stop notice reaches us, and that notice is then not about our bundle.
---@return boolean
function Bridge.current()
    return bundle ~= nil and generation ~= nil and GetResourceState(SERVICE) == 'running'
        and Open77.resource.generation(SERVICE) == generation
end

---@return table
function Bridge.settings()
    return bundle and bundle.settings or {}
end

---@param key string
---@return string
function Bridge.locale(key, ...)
    local text = bundle and bundle.locale and bundle.locale[key] or key
    if select('#', ...) == 0 then return text end
    local ok, formatted = pcall(string.format, text, ...)
    return ok and formatted or text
end

---@return boolean ok, string|nil reason
function Bridge.claim()
    local ok, reason = call('Claim')
    if ok == true then return true end
    return false, reason or 'menu_busy'
end

function Bridge.release()
    call('Release')
end

-- Ask the service for the navigation keys (it forwards them to the opx_menu_input export).
---@param wanted boolean
function Bridge.input(wanted)
    call('SetInput', wanted == true)
end

function Bridge.isAnyOpen()
    return call('IsAnyOpen') == true
end

---@param kind 'open'|'close'|'move'|'select'|'back'|'up'|'down'|'error'
function Bridge.sound(kind)
    if bundle and bundle.settings and bundle.settings.sounds then call('PlaySound', kind) end
end

return Bridge
