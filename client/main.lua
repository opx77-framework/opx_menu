-- opx_menu service: owns "who holds the screen" across resources, serves the document bundle
-- (RML + RCSS + locale + settings) to the library running in each caller VM, and owns the menu
-- navigation keys: one set of rebindable key mappings for every resource, forwarded to the owner.

local RESOURCE = GetCurrentResourceName()
local RELEASE_EXPORT = 'opx_menu_release'
local INPUT_EXPORT = 'opx_menu_input'

local owner = nil          -- resource whose menu or dialog is on screen
local ownerGeneration = nil -- its VM generation at Claim: a hot reload starts the new VM before the old one's stop notice
local inputWanted = false  -- the owner wants the navigation keys (false while a text dialog types)
local documentSource = nil -- themed RML with the RCSS inlined, built once
local locales = {}         -- language -> merged locale table

local function log(message)
    print(('[%s] %s'):format(RESOURCE, message))
end

---@param path string
---@return table|nil
local function readJson(path)
    local text = Open77.resource.readFile(path)
    if not text then return nil end
    local ok, value = pcall(Open77.json.decode, text)
    return ok and type(value) == 'table' and value or nil
end

local function replacePlain(text, from, to)
    local out, pos = {}, 1
    while true do
        local first, last = text:find(from, pos, true)
        if not first then break end
        out[#out + 1] = text:sub(pos, first - 1)
        out[#out + 1] = to
        pos = last + 1
    end
    out[#out + 1] = text:sub(pos)
    return table.concat(out)
end

-- Swap the `@token name #rrggbb` defaults of the sheet for Config.theme in one pass, so a colour
-- set to another token's default is not swapped twice. Alpha variants (#rrggbbaa) follow.
local function applyTheme(rcss)
    local swap = {}
    for name, value in rcss:gmatch('@token%s+(%S+)%s+(#%x%x%x%x%x%x)') do
        local wanted = type(Config.theme) == 'table' and Config.theme[name]
        if type(wanted) == 'string' and wanted:match('^#%x%x%x%x%x%x$') then swap[value:lower()] = wanted end
    end
    return (rcss:gsub('#%x%x%x%x%x%x', function(hex) return swap[hex:lower()] end))
end

local function buildSource()
    if documentSource then return documentSource end
    local rml = Open77.resource.readFile('ui/menu.rml')
    local rcss = Open77.resource.readFile('ui/menu.rcss')
    if not rml or not rcss then
        log('cannot read ui/menu.rml or ui/menu.rcss')
        return nil
    end
    -- The document is created from a string in the caller's VM, where a relative
    -- stylesheet would resolve against the caller: inline the sheet instead.
    local link = '<link type="text/rcss" href="menu.rcss"/>'
    if not rml:find(link, 1, true) then
        log('ui/menu.rml has no ' .. link)
        return nil
    end
    documentSource = replacePlain(rml, link, '<style>\n' .. applyTheme(rcss) .. '\n</style>')
    return documentSource
end

local function number(value, default, min, max)
    value = tonumber(value) or default
    if value < min then return min end
    if value > max then return max end
    return value
end

local function tiltSettings()
    local t = type(Config.tilt) == 'table' and Config.tilt or {}
    local spring = type(t.spring) == 'table' and t.spring or {}
    return {
        enabled = t.enabled ~= false,
        degrees = number(t.degrees, 10, -45, 45),
        pitch = number(t.pitch, 2, -30, 30),
        centerPitch = number(t.centerPitch, 4, -30, 30),
        perspective = number(t.perspective, 1250, 300, 5000),
        spring = { duration = number(spring.duration, 0.5, 0.05, 3), bounce = number(spring.bounce, 0.12, -1, 0.9) },
        exitMs = math.floor(number(t.exitMs, 160, 0, 1000)),
    }
end

local function wheelSettings()
    local w = type(Config.wheel) == 'table' and Config.wheel or {}
    local spring = type(w.spring) == 'table' and w.spring or {}
    return {
        rows = math.floor(number(w.rows, 3, 1, 6)),
        spacing = number(w.spacing, 32, 16, 80),
        bend = number(w.bend, 56, 0, 200),
        scale = number(w.scale, 0.72, 0.3, 1),
        shrink = number(w.shrink, 0.12, 0, 0.5),
        spring = { duration = number(spring.duration, 0.32, 0.05, 2), bounce = number(spring.bounce, 0.1, -1, 0.9) },
    }
end

local function language()
    local wanted = Config.locale or 'auto'
    if wanted ~= 'auto' then return wanted end
    local ok, info = pcall(Open77.session.locale)
    if ok and type(info) == 'table' and type(info.code) == 'string' then
        return info.code:sub(1, 2):lower()
    end
    return 'en'
end

local function locale(lang)
    if locales[lang] then return locales[lang] end
    local merged = readJson('locales/en.json') or {}
    if lang ~= 'en' then
        for key, text in pairs(readJson(('locales/%s.json'):format(lang)) or {}) do
            merged[key] = text
        end
    end
    locales[lang] = merged
    return merged
end

local function settings()
    local sounds = Config.sounds or {}
    return {
        position = Config.position == 'left' and 'left' or 'right',
        wheel = wheelSettings(),
        maxSwatches = math.max(3, math.floor(tonumber(Config.maxSwatches) or 7)),
        zIndex = math.floor(tonumber(Config.zIndex) or 0),
        tilt = tiltSettings(),
        sounds = sounds.enabled ~= false,
        debug = Config.debug == true,
    }
end

-- Navigation keys -------------------------------------------------------------------------
-- Key mappings live here, not in each caller VM: one entry per action in KEY BINDINGS (a rebind
-- applies to every resource's menus), callers need no input permission, and only the screen
-- owner ever receives a key. Registered observing (consume = false) so they stay listed and
-- rebindable; re-registered with consume = true while a menu wants them, so the game does not
-- also act on those keys. Without a focus lease the player keeps walking and the mouse camera.

local ACTIONS = { 'up', 'down', 'left', 'right', 'select', 'back' }
local REPEATS = { up = true, down = true, left = true, right = true }
local DEFAULT_KEYS = { up = 'UP', down = 'DOWN', left = 'LEFT', right = 'RIGHT', select = 'ENTER', back = 'BACKSPACE' }

local mapped = {}         -- action -> true when its key mapping is registered
local consuming = nil     -- consume flag the mappings were last registered with
local consumeOk = true    -- false once the client answered input_consumption_unavailable
local registering = false -- inside our own registerKeyMapping calls
local held = nil          -- { action, at } the direction repeating while held
local repeating, polling = false, false

local function L(key)
    local text = locale(language())[key]
    return type(text) == 'string' and text or key
end

local function keyOf(action)
    local keys = type(Config.keys) == 'table' and Config.keys or {}
    local key = keys[action]
    return type(key) == 'string' and key ~= '' and key or DEFAULT_KEYS[action]
end

local function active()
    return owner ~= nil and inputWanted
end

local function forward(action)
    if not owner then return end
    local ok, err = pcall(Open77.exports.callSync, owner, INPUT_EXPORT, action)
    if not ok and Config.debug then log(('input to %s failed: %s'):format(tostring(owner), tostring(err))) end
end

-- Physical state of an action's key, nil when the client cannot tell (unknown name...).
local function physicallyDown(action)
    local key = mapped[action] and Open77.input.keyFor('opx_menu.' .. action) or keyOf(action)
    local ok, down, reason = pcall(Open77.input.isDown, key or '')
    if not ok or reason then return nil end
    return down == true
end

-- One thread while an arrow is held: first repeat after keyRepeatDelayMs, then every keyRepeatMs.
local function startRepeat()
    if repeating then return end
    repeating = true
    CreateThread(function()
        while held and active() do
            local now = GetGameTimer()
            if now >= held.at then
                if physicallyDown(held.action) == false then
                    held = nil -- a release we never heard about (focus change, rebind)
                else
                    forward(held.action)
                    held.at = now + math.max(30, tonumber(Config.keyRepeatMs) or 80)
                end
            end
            Wait(0)
        end
        held, repeating = nil, false
    end)
end

local function press(action)
    if not active() then return end
    forward(action)
    if REPEATS[action] then
        held = { action = action, at = GetGameTimer() + math.max(0, tonumber(Config.keyRepeatDelayMs) or 320) }
        startRepeat()
    end
end

local function release(action)
    if held and held.action == action then held = nil end
end

-- Fallback for an action whose mapping was refused: edge-detect its default key while active.
local function startPolling()
    if polling then return end
    polling = true
    CreateThread(function()
        local down = {}
        while active() do
            local missing = false
            for _, action in ipairs(ACTIONS) do
                if not mapped[action] then
                    missing = true
                    local now = physicallyDown(action) == true
                    if now and not down[action] then press(action)
                    elseif not now and down[action] then release(action) end
                    down[action] = now
                end
            end
            if not missing then break end
            Wait(0)
        end
        polling = false
    end)
end

local function register(action, consume)
    local spec = {
        id = 'opx_menu.' .. action,
        name = L('key_' .. action),
        key = keyOf(action),
        hold = true,
        consume = consume or nil,
        onPressed = function() press(action) end,
        onReleased = function() release(action) end,
    }
    registering = true
    local ok, done, reason = pcall(Open77.input.registerKeyMapping, spec)
    if ok and done ~= true and consume and (reason == 'input_consumption_unavailable' or reason == 'gamepad_consumption_unavailable') then
        consumeOk = false
        spec.consume = nil
        ok, done, reason = pcall(Open77.input.registerKeyMapping, spec)
    end
    registering = false
    mapped[action] = ok and done == true
    if not mapped[action] then
        log(('key %s (%s) not mapped: %s'):format(action, tostring(spec.key), tostring(ok and reason or done)))
    end
end

-- Mappings consume their keys only while a menu wants them.
local function syncInput()
    local consume = active() and consumeOk
    if consume ~= consuming then
        consuming = consume
        for _, action in ipairs(ACTIONS) do register(action, consume) end
    end
    if not active() then held = nil return end
    for _, action in ipairs(ACTIONS) do
        if not mapped[action] then startPolling() break end
    end
end

local function setOwner(name, generation)
    if owner ~= name or ownerGeneration ~= generation then inputWanted = false end
    owner, ownerGeneration = name, name and generation or nil
    syncInput()
end

-- The export caller is the VM that holds the screen (same name AND same generation).
local function isOwner()
    return owner ~= nil and owner == GetInvokingResource() and ownerGeneration == GetInvokingResourceGeneration()
end

-- Rebinding and focus changes release consumption without telling us: while we consume, re-register
-- any of our mappings the registry lists as observing (records without a consume field are left alone).
AddEventHandler('open77:keybinds:changed', function()
    if registering or consuming ~= true then return end
    local ok, list = pcall(Open77.input.mappings)
    if not ok or type(list) ~= 'table' then return end
    for _, mapping in ipairs(list) do
        if type(mapping) == 'table' and mapping.resource == RESOURCE and mapping.consume == false
            and type(mapping.id) == 'string' and mapping.id:sub(1, 9) == 'opx_menu.' then
            local action = mapping.id:sub(10)
            if mapped[action] then register(action, true) end
        end
    end
end)

-- Escape is swallowed by the client and raised as open77:pauseKey: it closes or cancels.
AddEventHandler('open77:pauseKey', function()
    if owner then forward('pause') end
end)

-- Exports ---------------------------------------------------------------------------------

-- Everything the library needs to draw: called once per caller VM.
exports('GetBundle', function()
    local rml = buildSource()
    if not rml then return nil, 'ui_files_unreadable' end
    return { source = rml, locale = locale(language()), settings = settings() }
end)

-- Take the screen. The current owner is asked to let go; it refuses while a menu
-- has canClose = false or a dialog cannot be cancelled.
exports('Claim', function()
    local checked, formOpen = pcall(Open77.exports.callSync, 'opx_dialog', 'IsOpen')
    if checked and formOpen then return false, 'dialog_busy' end
    local caller, generation = GetInvokingResource(), GetInvokingResourceGeneration()
    if not caller then return false, 'no_caller' end
    -- same name, other generation: the reloaded VM replaces its predecessor (which can no longer answer)
    if owner == nil or owner == caller then
        setOwner(caller, generation)
        return true
    end
    local ok, released = pcall(Open77.exports.callSync, owner, RELEASE_EXPORT, false)
    if ok and released == false then return false, 'menu_busy' end
    setOwner(caller, generation) -- released, or the previous owner is gone
    return true
end)

exports('Release', function()
    if isOwner() then setOwner(nil) end
    return true
end)

-- The owner says whether it wants the navigation keys (false while a text dialog has the keyboard).
exports('SetInput', function(wanted)
    if not isOwner() then return false end
    inputWanted = wanted == true
    -- consumption may have been released meanwhile (focus change): register again on every request
    if inputWanted then consuming = nil end
    syncInput()
    return true
end)

exports('IsAnyOpen', function()
    local checked, formOpen = pcall(Open77.exports.callSync, 'opx_dialog', 'IsOpen')
    return owner ~= nil or (checked and formOpen == true)
end)

exports('GetOwner', function()
    return owner
end)

-- Closes whatever opx menu is on screen, even one with canClose = false (logout, death...).
exports('CloseAll', function()
    if not owner then return true end
    local ok = pcall(Open77.exports.callSync, owner, RELEASE_EXPORT, true)
    if not ok then setOwner(nil) end
    return true
end)

exports('PlaySound', function(kind)
    local sounds = Config.sounds
    if not sounds or sounds.enabled == false then return false end
    local event = sounds[kind]
    if type(event) ~= 'string' then return false end
    local ok, played = pcall(Open77.sfx.play2d, event)
    return ok and played == true
end)

-- The owner's VM is gone unless the resource still runs the generation that claimed (hot reload:
-- the new VM may already have claimed before this stop notice of the old one arrives).
local function ownerAlive()
    return GetResourceState(owner) == 'running' and Open77.resource.generation(owner) == ownerGeneration
end

AddEventHandler('onClientResourceStop', function(name)
    if name ~= owner then return end
    if not ownerAlive() then setOwner(nil) return end
    -- still listed as running with the claiming generation: check again once the stop has settled
    local generation = ownerGeneration
    SetTimeout(1000, function()
        if owner == name and ownerGeneration == generation and not ownerAlive() then setOwner(nil) end
    end)
end)

-- Listed (and rebindable) from the start, observing until a menu opens.
syncInput()

if type(Open77.ui) ~= 'table' or type(Open77.ui.create) ~= 'function' then
    log('NativeUI (Open77.ui) is not available on this client: menus will not open')
end
