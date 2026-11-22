resource "opx_menu"
version "2.1.0"
open77_version ">=0.0.1"
auto_start true

dependency "opx_dialog"

-- The service: one screen owner across resources, the navigation key mappings, the document bundle,
-- sounds, the demo.
client_script "config.lua"
client_script "client/main.lua"
client_script "client/demo.lua"

-- Published to dependants: `require('@opx_menu')` loads init.lua into the caller's VM.
-- The service reads the ui and locale files and hands them to the library.
files {
    "init.lua",
    "lib/*.lua",
    "ui/menu.rml",
    "ui/menu.rcss",
    "locales/*.json",
}

permissions {
    "world.effects",   -- Open77.sfx.play2d (menu sounds)
    "session.locale",  -- Open77.session.locale (Config.locale = 'auto')
    "input.actions",   -- RegisterKeyMapping / Open77.input.isDown / keyFor (menu navigation keys)
}
