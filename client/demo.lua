-- Developer demo: every element type, icons, a submenu, a dialog and a confirm. Config.debug only.
if not Config.debug then return end

local HAIR_COLORS = {
    { r = 20, g = 16, b = 14 }, { r = 74, g = 45, b = 30 }, { r = 140, g = 90, b = 50 },
    { r = 210, g = 170, b = 110 }, { r = 230, g = 225, b = 215 }, { r = 255, g = 59, b = 71 },
    { r = 94, g = 200, b = 255 }, { r = 61, g = 220, b = 151 }, { r = 160, g = 90, b = 220 },
    { r = 255, g = 181, b = 71 },
}

local function log(...)
    print('[opx_menu demo]', ...)
end

local function openSubmenu(Menu, parent)
    local elements = {}
    for i = 1, 18 do
        elements[i] = { label = ('Entry %02d'):format(i), value = i, rightLabel = ('%d €$'):format(i * 25),
            description = 'A long menu turns on the wheel; the footer counts the rows.' }
    end
    Menu.open({
        id = 'demo_sub', title = 'Scrolling', subtitle = 'Submenu', parent = parent, elements = elements,
        onSelect = function(element) log('picked', element.value) end,
    })
end

-- Every icon name, drawn on its own row.
local function openIcons(Menu, parent)
    local elements = {}
    for _, name in ipairs(Menu.icons()) do
        elements[#elements + 1] = { label = name, value = name, icon = name }
    end
    Menu.open({ id = 'demo_icons', title = 'Icons', subtitle = 'element.icon', parent = parent, elements = elements })
end

local function openDemo()
    local Menu = assert(require('@opx_menu'))
    Menu.open({
        id = 'demo_main', title = 'Garage', subtitle = 'Demo',
        elements = {
            { type = 'separator', label = 'Values' },
            { label = 'Hairstyle', value = 'hair', icon = 'person', type = 'list', options = { 'Buzz', 'Bob', 'Braids', 'Mohawk' }, index = 2,
                description = 'A list: Left and Right cycle, onChange fires live.' },
            { label = 'Hair colour', value = 'hair_color', icon = 'dot', type = 'color', colors = HAIR_COLORS, index = 1,
                description = 'A colour row: Left and Right walk the swatches.' },
            { label = 'Nose', value = 'nose', type = 'slider', min = 0, max = 20, step = 1, current = 10 },
            { label = 'Opacity', value = 'opacity', type = 'slider', min = 0, max = 1, step = 0.05, current = 0.5, format = '%.2f' },
            { label = 'Glasses', value = 'glasses', icon = 'eye', type = 'checkbox', checked = false },
            { type = 'separator', label = 'Actions' },
            { label = 'Submenu', value = 'sub', icon = 'list', rightLabel = '18 rows', description = 'Opens a child menu; Backspace returns here.' },
            { label = 'Icons', value = 'icons', icon = 'star', rightLabel = 'element.icon', description = 'Every name element.icon accepts.' },
            { label = 'Dialog', value = 'dialog', icon = 'edit', description = 'Text, number, date and select fields.' },
            { label = 'Confirm', value = 'confirm', icon = 'warning' },
            { label = 'Locked', value = 'locked', icon = 'lock', disabled = true, rightLabel = '€$ 9999', description = 'Disabled rows ignore Enter.' },
            { label = 'Close', value = 'close', icon = 'close' },
        },
        onChange = function(element, value) log('change', element.value, tostring(value)) end,
        onHover = function(element) log('hover', element and element.value) end,
        onClose = function(_, reason) log('closed', reason) end,
        onSelect = function(element, menu)
            if element.value == 'sub' then
                openSubmenu(Menu, menu)
            elseif element.value == 'icons' then
                openIcons(Menu, menu)
            elseif element.value == 'dialog' then
                local values, reason = Menu.dialog({
                    title = 'New identity', submitLabel = 'Create',
                    fields = {
                        { name = 'firstname', label = 'First name', type = 'text', maxLength = 24, default = 'Judy' },
                        { name = 'age', label = 'Age', type = 'number', min = 18, max = 99 },
                        { name = 'birthdate', label = 'Birthdate', type = 'date', min = '2000-01-01', max = '2059-12-31' },
                        { name = 'family', label = 'Body', type = 'select', options = { { label = 'Male', value = 'male' }, { label = 'Female', value = 'female' } }, default = 'female' },
                    },
                    validate = function(v)
                        if v.firstname:lower() == 'v' then return false, 'That name is taken.' end
                        return true
                    end,
                })
                log('dialog', values and Open77.json.encode(values) or 'cancelled', reason)
            elseif element.value == 'confirm' then
                local yes = Menu.confirm({ title = 'Delete character', message = 'This cannot be undone.', confirmLabel = 'Delete' })
                log('confirm', tostring(yes))
            elseif element.value == 'close' then
                menu:close()
            end
        end,
    })
end

-- The menu does not block the game: walk and look around while it is open.
RegisterCommand(Config.demoCommand or 'opxmenu', function() openDemo() end, false)
