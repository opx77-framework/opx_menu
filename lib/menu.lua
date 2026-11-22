-- Menus: the stack, the selection wheel of the top menu, keyboard navigation (no mouse).
-- Keys arrive as actions from the service's key mappings: up, down, left, right, select, back, pause.

local Bridge = require('@opx_menu/lib.bridge')
local View = require('@opx_menu/lib.view')
local State = require('@opx_menu/lib.state')
local Wheel = require('@opx_menu/lib.wheel')
local Icons = require('@opx_menu/lib.icons')

local Menus = {}
local METHODS = {}

local L = Bridge.locale

-- Runs a caller callback in its own task so it may yield (Menu.dialog, AwaitCallback...).
local function fire(fn, ...)
    if type(fn) ~= 'function' then return end
    local args = table.pack(...)
    CreateThread(function()
        local ok, err = pcall(fn, table.unpack(args, 1, args.n))
        if not ok then print(('[opx_menu] callback error: %s'):format(tostring(err))) end
    end)
end
Menus.fire = fire

local function clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

-- Upper case that keeps accents (RCSS text-transform breaks them): ASCII, Latin-1, œ, ÿ.
---@param text any
---@return string
function Menus.upper(text)
    text = tostring(text or '')
    if not utf8 then return text:upper() end
    local ok, out = pcall(function()
        local parts = {}
        for _, code in utf8.codes(text) do
            local c = code
            if (c >= 0x61 and c <= 0x7A) or (c >= 0xE0 and c <= 0xFE and c ~= 0xF7) then c = c - 0x20
            elseif c == 0xFF then c = 0x178
            elseif c == 0x153 then c = 0x152 end
            parts[#parts + 1] = utf8.char(c)
        end
        return table.concat(parts)
    end)
    return ok and out or text:upper()
end

local function isSeparator(el)
    return el.type == 'separator'
end

local function top()
    return State.stack[#State.stack]
end

local function indexOf(menu)
    for i, m in ipairs(State.stack) do
        if m == menu then return i end
    end
end

---@param option any
---@return string
function Menus.optionLabel(option)
    if type(option) == 'table' then return tostring(option.label or option.value or '') end
    return tostring(option)
end

local function colorHex(color)
    if type(color) == 'string' then return color end
    if type(color) ~= 'table' then return '#000000' end
    local function byte(v) return clamp(math.floor(tonumber(v) or 0), 0, 255) end
    return ('#%02x%02x%02x'):format(byte(color.r), byte(color.g), byte(color.b))
end

local function decimals(step)
    local digits = tostring(step):match('%.(%d+)$')
    return digits and #digits or 0
end

-- Clamp a slider value to [min, max] on its step grid.
local function snap(el, value)
    local min, max = el.min, el.max
    local step = el.step
    value = clamp(value, min, max)
    value = min + math.floor((value - min) / step + 0.5) * step
    local digits = decimals(step)
    if digits == 0 then
        value = math.floor(value + 0.5)
    else
        value = tonumber(('%.' .. digits .. 'f'):format(value))
    end
    return clamp(value, min, max)
end

local function formatSlider(el)
    if type(el.format) == 'string' then
        local ok, text = pcall(string.format, el.format, el.current)
        if ok then return text end
    end
    return tostring(el.current)
end

-- Every element must be a table (checked before anything is shown or claimed).
local function validElements(elements)
    if elements == nil then return true end
    if type(elements) ~= 'table' then return false end
    for _, el in ipairs(elements) do
        if type(el) ~= 'table' then return false end
    end
    return true
end

-- Fills defaults in place, so the caller reads element.index / current / checked directly.
local function normalize(elements)
    for _, el in ipairs(elements) do
        el.type = el.type or 'button'
        if el.type == 'list' or el.type == 'color' then
            local list = el.type == 'list' and el.options or el.colors
            el.index = clamp(math.floor(tonumber(el.index) or 1), 1, math.max(1, list and #list or 1))
        elseif el.type == 'slider' then
            el.min = tonumber(el.min) or 0
            el.max = math.max(el.min, tonumber(el.max) or 100)
            el.step = tonumber(el.step) or 1
            if el.step <= 0 then el.step = 1 end
            el.current = snap(el, tonumber(el.current) or el.min)
        elseif el.type == 'checkbox' then
            el.checked = el.checked == true
        end
    end
end

-- Footer line "· GARAGE / PEINTURE · SUBTITLE · 3/6 ·": the titles down to this menu (three levels),
-- the subtitle, the position among the selectable rows.
local function footerLine(menu)
    local titles, m = {}, menu
    while m and #titles < 3 do
        local title = tostring(m.title or '')
        if title ~= '' then table.insert(titles, 1, Menus.upper(title)) end
        m = m.parent
    end
    local position, total = 0, 0
    for i, el in ipairs(menu.elements) do
        if not isSeparator(el) then
            total = total + 1
            if i <= menu.selected then position = position + 1 end
        end
    end
    local parts = {}
    if #titles > 0 then parts[#parts + 1] = table.concat(titles, ' / ') end
    local subtitle = tostring(menu.subtitle or '')
    if subtitle ~= '' then parts[#parts + 1] = Menus.upper(subtitle) end
    if total > 0 then parts[#parts + 1] = ('%d/%d'):format(position, total) end
    if #parts == 0 then return '' end
    return '· ' .. table.concat(parts, ' · ') .. ' ·'
end

local unknownIcons = {} -- icon names already reported (debug)

-- Icon drawing of an element, or nil. An unknown name draws nothing (reported once with Config.debug).
local function iconOf(el)
    if el.icon == nil or el.type == 'separator' then return nil end
    local d, box = Icons.get(el.icon)
    if not d and Bridge.settings().debug and not unknownIcons[tostring(el.icon)] then
        unknownIcons[tostring(el.icon)] = true
        print(('[opx_menu] unknown icon %q (Menu.icons() lists the names)'):format(tostring(el.icon)))
    end
    return d, box
end

-- True when a row of the menu draws an icon: the others keep an empty icon box so labels line up.
local function hasIcons(menu)
    for _, el in ipairs(menu.elements) do
        if el.icon ~= nil and el.type ~= 'separator' and Icons.get(el.icon) then return true end
    end
    return false
end

-- Data of one wheel row; `cap` (upper-cased label) is drawn when it is selected or a section label.
local function buildRow(el, selected, iconSlot)
    local row = {
        kind = el.type, label = tostring(el.label or ''), cap = '',
        right = el.rightLabel ~= nil and tostring(el.rightLabel) or '',
        off = el.disabled == true,
        text = '', pct = 0, checked = false, colors = {},
        iconSlot = iconSlot,
    }
    row.icon, row.iconBox = iconOf(el)
    if selected or el.type == 'separator' then row.cap = Menus.upper(row.label) end
    if el.type == 'list' then
        local options = el.options or {}
        row.text = #options > 0 and Menus.optionLabel(options[el.index]) or '-'
    elseif el.type == 'slider' then
        row.text = formatSlider(el)
        local span = el.max - el.min
        row.pct = span > 0 and math.floor((el.current - el.min) / span * 100 + 0.5) or 100
    elseif el.type == 'color' then
        local colors = el.colors or {}
        local shown = Bridge.settings().maxSwatches or 7
        local first = clamp(el.index - math.floor(shown / 2), 1, math.max(1, #colors - shown + 1))
        for n = first, math.min(#colors, first + shown - 1) do
            row.colors[#row.colors + 1] = { hex = colorHex(colors[n]), on = n == el.index }
        end
        row.text = #colors > 0 and ('%02d/%02d'):format(el.index, #colors) or '-'
    elseif el.type == 'checkbox' then
        row.checked = el.checked
    elseif el.type ~= 'separator' then
        row.kind = 'button'
    end
    return row
end

local VALUE_TYPES = { list = true, slider = true, color = true, checkbox = true }

-- The wheel wraps like the navigation: up to `side` rows on each side of the selection, each
-- element at most once (a short menu shows all its rows).
function Menus.render()
    if State.form then View.merge({ menuShown = false }); return end
    local menu = top()
    if not menu then
        View.merge({ menuShown = false })
        return
    end
    local n = #menu.elements
    local above, below = 0, 0
    if n > 0 then
        above = math.min(menu.side, math.floor((n - 1) / 2))
        below = math.min(menu.side, n - 1 - above)
    end
    local list = {}
    local iconSlot = hasIcons(menu)
    for d = -above, n > 0 and below or -1 do
        local i = (menu.selected - 1 + d) % n + 1
        list[#list + 1] = { index = i, d = d, row = buildRow(menu.elements[i], d == 0, iconSlot) }
    end
    local selected = menu.elements[menu.selected]
    local desc = selected and selected.description and tostring(selected.description) or ''
    local descLines = Wheel.describe(desc) -- two lines at most, cut with "…"
    if #descLines == 0 then desc = '' end
    local canBack = menu.canClose ~= false
    View.batch(function(ui)
        View.merge({
            menuShown = State.dialog == nil, -- a dialog over a menu takes its place
            pos = menu.position,
            crumb = footerLine(menu),
            desc = desc,
            desc1 = descLines[1] or '',
            desc2 = descLines[2] or '',
            hasValue = selected ~= nil and VALUE_TYPES[selected.type] == true and not selected.disabled,
            hTurn = L('hint_turn'),
            hChange = L('hint_change'),
            hSelect = L(selected and selected.type == 'checkbox' and 'hint_toggle' or 'hint_select'),
            hBack = canBack and L((#State.stack > 1 or menu.parent) and 'hint_back' or 'hint_close') or '',
        })
        Wheel.draw(ui, menu, list, { side = menu.side, below = below, desc = desc, descLines = #descLines, edge = menu.position == 'left' and -1 or 1 })
    end)
    View.sync()
end

local function renderIfTop(menu)
    if top() == menu then Menus.render() end
end

local function firstSelectable(menu, wanted)
    local elements = menu.elements
    if type(wanted) == 'number' and elements[wanted] and not isSeparator(elements[wanted]) then return wanted end
    if wanted ~= nil then
        for i, el in ipairs(elements) do
            if el.value == wanted and not isSeparator(el) then return i end
        end
    end
    for i, el in ipairs(elements) do
        if not isSeparator(el) then return i end
    end
    return 1
end

local function choose(menu, index)
    if index == menu.selected then return end
    menu.selected = index
    Menus.render()
    Bridge.sound('move')
    fire(menu.onHover, menu.elements[index], menu)
end

local function move(menu, dir)
    local n = #menu.elements
    if n == 0 then return end
    local i, steps = menu.selected, 0
    for _ = 1, n do
        i, steps = i + dir, steps + 1
        if i < 1 then i = n elseif i > n then i = 1 end
        if not isSeparator(menu.elements[i]) then break end
    end
    if i ~= menu.selected then menu.turn = steps * dir end -- the wheel turns this way, even across the wrap
    choose(menu, i)
end

local function changed(menu, el, value, sound)
    Bridge.sound(sound)
    Menus.render()
    if View.ui then Wheel.pulse(View.ui, menu) end
    fire(menu.onChange, el, value, menu)
end

-- Left/Right on a list, slider, colour or checkbox row.
local function step(menu, el, dir)
    if not el or el.disabled then return end
    if el.type == 'list' or el.type == 'color' then
        local list = el.type == 'list' and el.options or el.colors
        local n = list and #list or 0
        if n < 2 then return end
        el.index = (el.index - 1 + dir) % n + 1
        changed(menu, el, el.index, dir > 0 and 'up' or 'down')
    elseif el.type == 'slider' then
        local value = snap(el, el.current + dir * el.step)
        if value == el.current then return end
        el.current = value
        changed(menu, el, value, dir > 0 and 'up' or 'down')
    elseif el.type == 'checkbox' then
        el.checked = not el.checked
        changed(menu, el, el.checked, 'select')
    end
end

-- Enter: a checkbox toggles (onChange), everything else fires onSelect.
local function activate(menu, el)
    if not el or isSeparator(el) then return end
    if el.disabled then
        Bridge.sound('error')
        return
    end
    if el.type == 'checkbox' then
        step(menu, el, 1)
        return
    end
    Bridge.sound('select')
    fire(menu.onSelect, el, menu)
end

-- Tell the service whether this VM wants the navigation keys: yes while a menu or a confirm is on
-- screen, no while a text dialog types (it holds the keyboard itself) or nothing is shown.
function Menus.syncInput()
    if not State.claimed then
        State.input = false
        return
    end
    local wanted = (#State.stack > 0 or State.dialog ~= nil) and State.form == nil
    if wanted ~= State.input then
        State.input = wanted
        Bridge.input(wanted)
    end
end

-- Hide the document and give the screen back when nothing is left.
function Menus.shutdownIfIdle()
    if #State.stack > 0 or State.dialog or State.form then return end
    View.hide()
    if State.claimed then
        Menus.syncInput()
        State.claimed, State.input = false, false
        Bridge.release()
    end
end

-- Remove `menu` and every menu above it, firing onClose top-down.
local function closeFrom(at, reason)
    for i = #State.stack, at, -1 do
        local m = table.remove(State.stack, i)
        m.opened = false
        fire(m.onClose, m, reason)
    end
end

---@param menu table
---@param reason string
function Menus.close(menu, reason)
    local at = indexOf(menu)
    if not at then return end
    if State.form and State.finishInput then State.finishInput() end
    closeFrom(at, reason)
    -- Back from a child whose parent was closed meanwhile: bring the parent back.
    local parent = menu.parent
    if reason == 'back' and parent and not indexOf(parent) and #State.stack == 0 then
        parent.opened = true
        State.stack[1] = parent
    end
    if #State.stack == 0 then
        if reason ~= 'replaced' then Bridge.sound('close') end
        Menus.shutdownIfIdle()
        return
    end
    Menus.render() -- the wheel sees a new page and slides it in
    local now = top()
    fire(now.onHover, now.elements[now.selected], now)
end

---@param reason string
function Menus.closeAll(reason)
    if State.form and State.finishInput then State.finishInput() end
    if #State.stack > 0 then closeFrom(1, reason) end
    if State.dialog and State.finishDialog then State.finishDialog(State.dialog, nil, 'closed') end
    Menus.shutdownIfIdle()
end

-- True when nothing on screen refuses to close (canClose = false, a dialog that cannot be cancelled).
function Menus.releasable()
    if State.form and not State.form.canCancel then return false end
    if State.dialog and not State.dialog.canCancel then return false end
    for _, m in ipairs(State.stack) do
        if m.canClose == false then return false end
    end
    return true
end

local function back(menu)
    if menu.canClose == false then
        Bridge.sound('error')
        return
    end
    if #State.stack > 1 or menu.parent then Bridge.sound('back') end -- the last one plays 'close'
    Menus.close(menu, 'back')
end

---A navigation action from the service while a menu (and no dialog) is on screen.
---@param action 'up'|'down'|'left'|'right'|'select'|'back'|'pause'
function Menus.input(action)
    if State.form then return end
    local menu = top()
    if not menu then return end
    local el = menu.elements[menu.selected]
    if action == 'up' then move(menu, -1)
    elseif action == 'down' then move(menu, 1)
    elseif action == 'left' then step(menu, el, -1)
    elseif action == 'right' then step(menu, el, 1)
    elseif action == 'select' then activate(menu, el)
    elseif action == 'back' then back(menu)
    elseif action == 'pause' then
        -- Escape opens the game's pause menu: close every menu that may close.
        if not Menus.releasable() then return end
        closeFrom(1, 'paused')
        Bridge.sound('close')
        Menus.shutdownIfIdle()
    end
end

-- Handle methods (no metatables in the client sandbox: copied onto each handle).

function METHODS.setElements(self, elements, keepSelection)
    if not validElements(elements) then return false, 'invalid_elements' end
    self.elements = type(elements) == 'table' and elements or {}
    normalize(self.elements)
    local selected = self.elements[self.selected]
    if not keepSelection or not selected or isSeparator(selected) then
        self.selected = firstSelectable(self, keepSelection and self.selected or nil)
        self.wheelReset = true -- other rows: the wheel is drawn afresh
    end
    renderIfTop(self)
    return true
end

function METHODS.updateElement(self, value, patch)
    if type(patch) ~= 'table' then return false end
    for _, el in ipairs(self.elements) do
        if el.value == value then
            for k, v in pairs(patch) do el[k] = v end
            normalize({ el })
            renderIfTop(self)
            return true
        end
    end
    return false
end

function METHODS.getElement(self, value)
    for _, el in ipairs(self.elements) do
        if el.value == value then return el end
    end
end

function METHODS.getSelected(self)
    return self.elements[self.selected]
end

function METHODS.setSelected(self, target)
    local index
    if type(target) == 'number' and self.elements[target] then
        index = target
    else
        for i, el in ipairs(self.elements) do
            if el.value == target then index = i break end
        end
    end
    if not index or isSeparator(self.elements[index]) then return false end
    if index == self.selected then return true end
    self.selected = index
    if self.opened and top() == self then
        Menus.render()
        fire(self.onHover, self.elements[index], self)
    end
    return true
end

function METHODS.setTitle(self, title, subtitle)
    self.title = title
    if subtitle ~= nil then self.subtitle = subtitle end
    renderIfTop(self)
end

function METHODS.refresh(self)
    normalize(self.elements)
    renderIfTop(self)
end

function METHODS.isOpen(self)
    return self.opened == true
end

function METHODS.close(self)
    Menus.close(self, 'closed')
end

---@param opts table
---@return table|nil menu, string|nil reason
function Menus.open(opts)
    if type(opts) ~= 'table' then return nil, 'invalid_options' end
    if not validElements(opts.elements) then return nil, 'invalid_elements' end
    local ok, reason = View.ensure()
    if not ok then return nil, reason end

    if not State.claimed then
        local claimed, why = Bridge.claim()
        if not claimed then return nil, why end
        State.claimed = true
    end

    -- A child keeps its parent below it; a new root replaces this VM's stack.
    local parentAt = opts.parent and indexOf(opts.parent)
    if parentAt then
        if parentAt < #State.stack then closeFrom(parentAt + 1, 'replaced') end
    elseif #State.stack > 0 then
        closeFrom(1, 'replaced')
    end

    local settings = Bridge.settings()
    local menu = {
        id = opts.id,
        title = opts.title or '',
        subtitle = opts.subtitle or '',
        position = (opts.position == 'left' or opts.position == 'right') and opts.position or settings.position or 'right',
        -- rows drawn on each side of the selection; maxVisible (rows drawn at once) can only lower it
        side = math.max(1, math.min(Wheel.rows(), math.floor(((tonumber(opts.maxVisible) or math.huge) - 1) / 2))),
        canClose = opts.canClose ~= false,
        style = Menus.styleOf(opts.style) or (type(opts.parent) == 'table' and opts.parent.style) or nil,
        parent = opts.parent,
        onSelect = opts.onSelect, onChange = opts.onChange, onHover = opts.onHover, onClose = opts.onClose,
        elements = type(opts.elements) == 'table' and opts.elements or {},
        selected = 1, opened = true,
    }
    for name, fn in pairs(METHODS) do menu[name] = fn end
    normalize(menu.elements)
    menu.selected = firstSelectable(menu, opts.selected)

    State.stack[#State.stack + 1] = menu
    View.show()
    Menus.render() -- a new page for the wheel: it slides in (from the edge, or over its parent)
    Menus.syncInput()
    Bridge.sound('open')
    fire(menu.onHover, menu.elements[menu.selected], menu)
    return menu
end

-- Styles are kept for compatibility: 'clean', 'flat' and 'holo' all draw the same wheel.
---@param style any
---@return string|nil
function Menus.styleOf(style)
    if style == 'clean' or style == 'flat' or style == 'holo' then return style end
    return nil
end

function Menus.current()
    return top()
end

return Menus
