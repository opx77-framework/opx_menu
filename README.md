# opx_menu

Keyboard menus and yes/no confirms, drawn as a selection wheel next to the screen edge. The player keeps
walking and looking around while a menu is open. One menu is on screen at a time across all resources.

## Install
- Needs: `opx_dialog` (forms). Load it after `opx_dialog` and before every resource that uses it.
- No database.
- Provider of the `menu` slot: a replacement implements the library and exports in `types.lua`.

## In game
- Up / Down: move through the rows (hold to repeat).
- Left / Right: change a list, slider, colour or checkbox.
- Enter: select. Backspace: back to the parent menu, or close. Escape: closes every menu.
- Players can rebind these keys in Pause > Settings > Key bindings.

## Config
`config.lua`: `position` (default side), `keys` (default navigation keys), `theme` (colours), `tilt`.
Everything else is commented in the file.

## For developers
- `local Menu = require('@opx_menu')` (manifest: `dependency "opx_menu"`, plus `dependency "opx_dialog"` for `Menu.dialog`).
- `Menu.open(opts)` → menu handle, or `nil, reason` (`menu_busy`...). Rows: `button`, `list`, `slider`, `color`, `checkbox`, `separator`.
- `Menu.confirm(opts)` → `true`, or `false, reason`; waits, call it from a thread.
- `Menu.dialog(opts)` → values, or `nil, reason`; waits; the form is drawn by opx_dialog.
- `menu:updateElement(value, patch)`, `menu:setElements(rows)`, `menu:close()` → change or close an open menu.
- `Open77.exports.callSync('opx_menu', 'CloseAll')` → closes any menu, even a locked one (death, logout).
- Full contract: `types.lua`.
