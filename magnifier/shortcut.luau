--!nonstrict
-- shortcut.luau — control-center tile. Shortcuts have no update() callback, so
-- the tile is rendered once at load. All launch logic lives in lib/launch.luau.

local launch = require("./lib/launch.luau")

shortcut.setLabel(noctalia.tr("shortcut.label"))
shortcut.setIcon("zoom-in")
shortcut.setActive(false)

function onClick()
  launch.open()
end

function onIpc(event, _payload)
  if event == "open" then
    launch.open()
  end
end
