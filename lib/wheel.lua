-- The selection wheel: the rows of the top menu laid on an arc around the selected one.
-- Two pools of row elements are written once per document (#wa1.., #wb1..). A menu element keeps its
-- row element while it stays on the wheel, so a move only retargets each row (top, left, scale,
-- opacity) and the springs turn the wheel. A new page (submenu, back, another menu) swaps the pools:
-- the old wheel is hidden, the new one slides in. Nothing runs per frame; ui:animate lands at once
-- under nui.reducedmotion. Positions are dp lengths (top / left): the x / y channels are physical pixels.

local Bridge = require('@opx_menu/lib.bridge')

local Wheel = {}

local POOLS = { 'wa', 'wb' }
local SPARE = 4          -- rows per pool beyond the drawn ones: rows leaving can finish fading out
local HALF = 18          -- dp, half the height of a row at scale 1 (ui/menu.rcss .row)
local PAGE_SHIFT = 40    -- dp a wheel slides when the page changes
local DESC_WIDTH = 396   -- dp of text per description line (ui/menu.rcss #wdesc is 400dp)
local DESC_LINE = 21     -- dp per description line (ui/menu.rcss #wdesc, two lines at most)
local DESC_SIZE = 17     -- dp, Rajdhani (ui/menu.rcss .desc)
local ROW_INNER = 410    -- dp inside a row: 440 - border 4 - padding 14 + 12 (ui/menu.rcss .row)
local ICON_W = 28        -- dp of the icon box and its margin (.ic)
local PVAL_MIN, PVAL_MAX = 96, 168 -- dp of a list value between its chevrons (.pval)
local RIGHT_MAX = 150    -- dp of the right label at most (.right, Roboto Mono 14dp)
local ELLIPSIS = '…'
local FOOT_GAP = 14      -- dp between the last row and the footer line

local DEFAULTS = { rows = 3, spacing = 32, bend = 56, scale = 0.72, shrink = 0.12, spring = { duration = 0.32, bounce = 0.1 } }

local CHEV_LEFT = '<path class="chev" view-box="0 0 6 10" d="M5.5 0.5 L0.5 5 L5.5 9.5 Z"/>'
local CHEV_RIGHT = '<path class="chev" view-box="0 0 6 10" d="M0.5 0.5 L5.5 5 L0.5 9.5 Z"/>'

local st

-- Forget every pool (a new document is built, or none is left).
function Wheel.reset()
    st = {
        pools = {},      -- { id, slots = { sel, index, d, shown, gone, markup, cls, target } }
        active = 1,      -- pool drawing the current page
        menu = nil,      -- menu the active pool shows
        selected = nil,  -- its selection at the last draw
        desc = nil, foot = nil, tick = 0,
    }
end
Wheel.reset()

local function cfg()
    local w = Bridge.settings().wheel
    return type(w) == 'table' and w or DEFAULTS
end

---Rows drawn above and below the selection at most.
function Wheel.rows()
    return cfg().rows
end

-- Braces too: row markup sits inside the data model, where a text `{{...}}` would become a binding.
local function escape(text)
    return (tostring(text or ''):gsub('[&<>"\'{}]', {
        ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;', ['"'] = '&quot;', ["'"] = '&#39;',
        ['{'] = '&#123;', ['}'] = '&#125;',
    }))
end

local function dp(value)
    return ('%.1fdp'):format(value)
end

local function round(value)
    return math.floor(value * 1000 + 0.5) / 1000
end

-- Text fitting ------------------------------------------------------------------------------
-- RCSS has no text-overflow here: long texts are cut in Lua with "…", on a width computed from the
-- advance widths of the loaded fonts (overflow: hidden stays as a backstop). Roboto Mono is 0.6em for
-- every glyph. Characters are whole UTF-8 sequences: a cut never splits one.

local CHARS = utf8 and utf8.charpattern or '[%z\1-\127\194-\244][\128-\191]*'

-- Advance of each ASCII character 32..126 in hundredths of an em (rounded up, two digits each);
-- `other` is used for every other character (accented letters, symbols).
local function advances(digits, other)
    local em = {}
    for i = 0, 94 do em[32 + i] = tonumber(digits:sub(i * 2 + 1, i * 2 + 2)) / 100 end
    return { em = em, other = other }
end
local FONTS = {
    rajdhani = advances( -- Rajdhani regular
        '27243368517260192929415320322040523248505249503852502020525454487654555556494654'
        .. '57235053467058565356545742565080515049294029473827515140515031515121214421775150'
        .. '515132443551426942464130213053', 0.56),
    chakra = advances( -- Chakra Petch bold (labels are upper-cased)
        '28284672648867263535355724442453663958615861635364632424625762578465676669615868'
        .. '70285866578170706570686459706588666460355435664924586056615940616028295727876060'
        .. '616041544260517353605038273859', 0.7),
}

---@return number dp
local function charWidth(c, font)
    if font.mono then return 0.6 * font.size + (font.spacing or 0) end
    local m = font.metrics
    local w = #c == 1 and m.em[c:byte()] or m.other
    return w * font.size + (font.spacing or 0)
end

local function chars(text, font)
    local list, widths = {}, {}
    for c in text:gmatch(CHARS) do
        list[#list + 1] = c
        widths[#widths + 1] = charWidth(c, font)
    end
    return list, widths
end

-- `list[from..]` within `width` dp, ending with "…" when cut (trailing spaces dropped first).
local function cut(list, widths, from, width, font)
    local total = 0
    for i = from, #list do total = total + widths[i] end
    if total <= width then return table.concat(list, '', from, #list) end
    local room, stop = width - charWidth(ELLIPSIS, font), from - 1
    local used = 0
    while stop < #list and used + widths[stop + 1] <= room do
        stop = stop + 1
        used = used + widths[stop]
    end
    while stop >= from and list[stop] == ' ' do stop = stop - 1 end
    return (stop >= from and table.concat(list, '', from, stop) or '') .. ELLIPSIS
end

---`text` cut with "…" to fit `width` dp in `font`, and the dp it then takes.
local function fit(text, width, font)
    local list, widths = chars(tostring(text or ''), font)
    local out = cut(list, widths, 1, math.max(0, width), font)
    local used = 0
    for c in out:gmatch(CHARS) do used = used + charWidth(c, font) end
    return out, used
end

local DESC_FONT = { metrics = FONTS.rajdhani, size = DESC_SIZE }
local LABEL_FONT = { metrics = FONTS.chakra, size = 25, spacing = 1 }   -- .row.sel .label
local ROW_FONT = { metrics = FONTS.rajdhani, size = 26 }                -- .row (neighbours)
local SEP_FONT = { mono = true, size = 15, spacing = 3 }           -- .row.sep .label
local RIGHT_FONT = { mono = true, size = 14 }                      -- .right
local VALUE_FONT = { mono = true, size = 16 }                      -- .pval

---The description as drawn: wrapped on words into two lines at most, the second ending with "…"
---when the text is longer, inside « ».
---@param desc string
---@return string[] lines 0, 1 or 2 lines
function Wheel.describe(desc)
    desc = tostring(desc or ''):gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
    if desc == '' then return {} end
    local font = DESC_FONT
    local width = DESC_WIDTH - charWidth('«', font) - charWidth(' ', font) -- room of the quotes
    local list, widths = chars(desc, font)
    local lines, from = {}, 1
    while from <= #list do
        if #lines == 1 then
            lines[2] = cut(list, widths, from, width, font)
            break
        end
        local used, i, space = 0, from, nil
        while i <= #list and used + widths[i] <= width do
            if list[i] == ' ' then space = i end
            used, i = used + widths[i], i + 1
        end
        if i > #list then
            lines[#lines + 1] = table.concat(list, '', from, #list)
            break
        end
        local stop, nextFrom = i - 1, i            -- a word longer than the line breaks anywhere
        if list[i] == ' ' then stop, nextFrom = i - 1, i + 1
        elseif space and space > from then stop, nextFrom = space - 1, space + 1 end
        if stop < from then stop, nextFrom = from, from + 1 end
        lines[#lines + 1] = table.concat(list, '', from, stop)
        from = nextFrom
        while list[from] == ' ' do from = from + 1 end
    end
    lines[1] = '« ' .. lines[1]
    lines[#lines] = lines[#lines] .. ' »'
    return lines
end

---Writes both pools of empty rows into the document (once, right after it is created).
---@param ui table
function Wheel.build(ui)
    Wheel.reset()
    local size = 2 * cfg().rows + 1 + SPARE
    for p, id in ipairs(POOLS) do
        local markup, slots = {}, {}
        for s = 1, size do
            markup[s] = ('<div class="row idle" id="%s%d"></div>'):format(id, s)
            slots[s] = { sel = ('#%s%d'):format(id, s), cls = 'row idle' }
        end
        ui:rml('#' .. id, table.concat(markup))
        ui:setClasses('#' .. id, 'wheel idle')
        st.pools[p] = { id = id, slots = slots }
    end
end

-- Row content -------------------------------------------------------------------------------

-- The value widget and the dp it takes in the row (margins included, ui/menu.rcss .val and children).
-- A list value sits between its chevrons in a box of 96 to 168dp, cut with "…" past that.
local function valueMarkup(r)
    if r.kind == 'list' then
        local text, used = fit(r.text, PVAL_MAX, VALUE_FONT)
        local box = math.max(PVAL_MIN, math.min(PVAL_MAX, math.ceil(used)))
        return ('<div class="val">%s<span class="pval" style="width: %ddp;">%s</span>%s</div>')
            :format(CHEV_LEFT, box, escape(text), CHEV_RIGHT), 12 + 8 + 6 + box + 6 + 8
    elseif r.kind == 'slider' then
        local text = fit(r.text, PVAL_MIN, VALUE_FONT)
        return ('<div class="val">%s<div class="slide"><span class="pval">%s</span><div class="track"><div class="fill" style="width: %d%%;"></div></div></div>%s</div>')
            :format(CHEV_LEFT, escape(text), r.pct, CHEV_RIGHT), 12 + 8 + 6 + PVAL_MIN + 6 + 8
    elseif r.kind == 'color' then
        local swatches, used = {}, 12 + 8 + 8 + 8 + #tostring(r.text) * 0.6 * 13
        for i, c in ipairs(r.colors) do
            swatches[i] = ('<div class="sw%s" style="background-color: %s;"></div>'):format(c.on and ' on' or '', escape(c.hex))
            used = used + (c.on and 24 or 17)
        end
        return ('<div class="val">%s%s%s<span class="swn">%s</span></div>')
            :format(CHEV_LEFT, table.concat(swatches), CHEV_RIGHT, escape(r.text)), used
    elseif r.kind == 'checkbox' then
        return ('<div class="val"><div class="check%s"><div class="tick"></div></div></div>'):format(r.checked and ' on' or ''), 12 + 17
    end
    return '', 0
end

-- Icon drawn before the label: a dark halo stroke under the coloured one (lib/icons.lua). A row
-- without one keeps an empty box when other rows of the menu have one, so the labels line up.
local function iconMarkup(r)
    if r.icon then
        local box, d = escape(r.iconBox), escape(r.icon)
        return ('<div class="ic"><path class="ib" view-box="%s" d="%s"/><path class="if" view-box="%s" d="%s"/></div>')
            :format(box, d, box, d)
    end
    return r.iconSlot and '<div class="ic"></div>' or ''
end

-- Neighbours show their icon and label only; the selected row its caps label, right label and value widget.
-- Labels are cut with "…" before the right label and the value widget.
local function rowMarkup(r, selected)
    if r.kind == 'separator' then
        return ('<div class="sep-line"></div><span class="label">%s</span>'):format(escape(fit(r.cap, ROW_INNER - 26, SEP_FONT)))
    end
    local room = ROW_INNER - ((r.icon or r.iconSlot) and ICON_W or 0) - 2
    if not selected then
        return ('%s<span class="label">%s</span>'):format(iconMarkup(r), escape(fit(r.label, room, ROW_FONT)))
    end
    local right = ''
    if r.right ~= '' then
        local text, used = fit(r.right, RIGHT_MAX, RIGHT_FONT)
        right = ('<span class="right">%s</span>'):format(escape(text))
        room = room - 12 - used
    end
    local value, used = valueMarkup(r)
    room = room - used
    return ('%s<span class="label">%s</span>%s%s'):format(iconMarkup(r), escape(fit(r.cap, room, LABEL_FONT)), right, value)
end

local function classesOf(r, selected)
    local cls = 'row'
    if selected then cls = cls .. ' sel' end
    if r.off then cls = cls .. ' off' end
    if r.kind == 'separator' then cls = cls .. ' sep' end
    return cls
end

-- Layout ------------------------------------------------------------------------------------

local function scaleAt(w, a)
    if a == 0 then return 1 end
    return w.scale * (1 - w.shrink) ^ (a - 1)
end

-- dp from the selected row's centre to the centre of the row `a` steps away (rows shrink, so do gaps).
local function reach(w, a)
    local y = 0
    for j = 1, a do
        y = y + (j == 1 and (HALF + w.spacing * 0.5 + 2) or w.spacing * scaleAt(w, j) / w.scale)
    end
    return y
end

-- Resting place of the row `d` steps from the selection. Rows below make room for the description;
-- the arc pushes rows toward the screen edge (edge 1: right, -1: left); past `side` they are faded out.
local function pose(w, d, o)
    local a = math.abs(d)
    local top = reach(w, a)
    if d < 0 then top = -top elseif d > 0 then top = top + o.room end
    local opacity = 1
    if a > o.side then opacity = 0 elseif a > 0 then opacity = 1 - (a / (o.side + 1)) ^ 1.3 end
    return {
        top = dp(top),
        left = dp(o.edge * w.bend * (a / o.side) ^ 1.5),
        scale = round(scaleAt(w, a)),
        opacity = round(opacity),
    }
end

local function keyOf(t)
    return ('%s|%s|%s|%s'):format(tostring(t.top), tostring(t.left), tostring(t.scale), tostring(t.opacity))
end

-- Retargets a row; `from` makes it start elsewhere (entering), `instant` places it (new page).
local function place(ui, slot, to, w, from, instant)
    local key = keyOf(to)
    if key == slot.target and not from and not instant then return end
    slot.target = key
    local spec = { to = to }
    if instant then spec.instant = true else spec.from, spec.spring = from, w.spring end
    ui:animate(slot.sel, spec)
end

local function setClasses(ui, slot, cls)
    if slot.cls == cls then return end
    slot.cls = cls
    ui:setClasses(slot.sel, cls)
end

-- True when `b` is `a` or one of its parents.
local function descends(a, b)
    local m, guard = a, 0
    while m and guard < 16 do
        if m == b then return true end
        m, guard = m.parent, guard + 1
    end
    return false
end

-- Signed steps the selection travelled, the short way round the wrapping list.
local function shiftOf(from, to, n)
    if not from or n == 0 then return 0 end
    local delta = (to - from) % n
    if delta > n / 2 then delta = delta - n end
    return delta
end

-- Only the current pool may draw. Opacity animation alone does not retire a page; explicitly hide
-- it and reset every reused row, including the spare rows a shorter page will not overwrite.
-- The new page still slides in (back: from the centre; deeper: from the edge).
local function turnPage(ui, menu, w, edge)
    local dir = 0
    if st.menu then
        if descends(menu, st.menu) then dir = 1 elseif descends(st.menu, menu) then dir = -1 end
        ui:setClasses('#' .. st.pools[st.active].id, 'wheel idle')
        st.active = 3 - st.active
    end
    local pool = st.pools[st.active]
    for _, slot in ipairs(pool.slots) do
        slot.index, slot.shown, slot.d, slot.gone = nil, false, nil, 0
        slot.target = nil
        setClasses(ui, slot, 'row idle')
    end
    ui:setClasses('#' .. pool.id, 'wheel')
    local from = dir < 0 and -edge * PAGE_SHIFT or edge * PAGE_SHIFT
    ui:animate('#' .. pool.id, { from = { left = dp(from), opacity = 0 }, to = { left = '0dp', opacity = 1 }, spring = w.spring })
    ui:animate('#wfoot .crumb', { from = { opacity = 0 }, to = { opacity = 1 }, tween = { duration = 0.2, easing = 'ease-out' } })
end

-- The pool row of an element: the one it already has, else a free one (never used, or left longest
-- ago) that does not belong to another element coming back in this draw.
local function slotFor(pool, index, wanted)
    local best
    for _, slot in ipairs(pool.slots) do
        if slot.index == index then return slot end
        if not slot.shown and not (slot.index and wanted[slot.index])
            and (not best or (slot.gone or 0) < (best.gone or 0)) then best = slot end
    end
    return best
end

---Draws the wheel of the top menu.
---@param ui table
---@param menu table
---@param list table[] { index, d, row }: the elements to draw, d = signed steps from the selection
---@param o table { side, below, desc, descLines?, edge }: rows per side, rows drawn below, description (and its line count, Wheel.describe), 1 right / -1 left
function Wheel.draw(ui, menu, list, o)
    if #st.pools == 0 then return end
    local w = cfg()
    local page = st.menu ~= menu or menu.wheelReset == true
    if page then turnPage(ui, menu, w, o.edge) end
    local shift = 0
    if not page then shift = menu.turn or shiftOf(st.selected, menu.selected, #menu.elements) end
    menu.turn, menu.wheelReset = nil, nil
    st.menu, st.selected, st.tick = menu, menu.selected, st.tick + 1

    local lines = o.descLines or (o.desc == '' and 0 or #Wheel.describe(o.desc))
    o.room = lines > 0 and lines * DESC_LINE + 6 or 0
    local pool = st.pools[st.active]
    local step = math.max(-2, math.min(2, shift)) -- rows enter / leave at most two slots away (big jumps)

    local wanted = {}
    for _, item in ipairs(list) do wanted[item.index] = true end
    -- Rows leaving the wheel go one more step the way it turns and fade out.
    for _, slot in ipairs(pool.slots) do
        if slot.shown and not wanted[slot.index] then
            slot.shown, slot.gone = false, st.tick
            if shift ~= 0 then
                local to = pose(w, slot.d - step, o)
                to.opacity = 0
                slot.d = slot.d - shift
                place(ui, slot, to, w)
            else
                place(ui, slot, { opacity = 0 }, w)
            end
        end
    end

    for _, item in ipairs(list) do
        local slot = slotFor(pool, item.index, wanted)
        local selected = item.d == 0
        local markup = rowMarkup(item.row, selected)
        if slot.markup ~= markup then
            slot.markup = markup
            ui:rml(slot.sel, markup)
        end
        setClasses(ui, slot, classesOf(item.row, selected))
        local to = pose(w, item.d, o)
        if page then
            place(ui, slot, to, w, nil, true)
        elseif slot.index == item.index and slot.d and (shift == 0 or slot.d - shift == item.d) then
            place(ui, slot, to, w) -- slides from where it is
        else
            -- enters from the side the wheel turns from (or fades in where it rests)
            local from = pose(w, item.d + step, o)
            from.opacity = 0
            place(ui, slot, to, w, from)
        end
        slot.index, slot.d, slot.shown = item.index, item.d, true
    end
    if page then
        for _, slot in ipairs(pool.slots) do
            if not slot.shown then setClasses(ui, slot, 'row idle') end
        end
    end

    -- The footer follows the last row; the description fades in when it changes.
    local last = o.below > 0 and reach(w, o.below) + o.room + HALF * scaleAt(w, o.below) or HALF + o.room
    local foot = dp(last + FOOT_GAP)
    if foot ~= st.foot then
        st.foot = foot
        ui:animate('#wfoot', { to = { top = foot }, spring = w.spring })
    end
    if o.desc ~= st.desc then
        st.desc = o.desc
        if o.desc ~= '' then
            ui:animate('#wdesc', { from = { opacity = 0 }, to = { opacity = 1 }, tween = { duration = 0.18, easing = 'ease-out' } })
        end
    end
end

---A value of the selected row changed: its widget flashes in.
---@param ui table
---@param menu table
function Wheel.pulse(ui, menu)
    if st.menu ~= menu or #st.pools == 0 then return end
    for _, slot in ipairs(st.pools[st.active].slots) do
        if slot.shown and slot.d == 0 then
            ui:animate(slot.sel .. ' .val', { from = { opacity = 0.35 }, to = { opacity = 1 }, tween = { duration = 0.14, easing = 'ease-out' } })
            return
        end
    end
end

return Wheel
