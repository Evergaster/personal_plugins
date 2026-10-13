--!nonstrict
-- widget.luau — bar widget. A left click, or the "open" IPC event, launches the
-- screen magnifier. All launch logic lives in lib/launch.luau.

local launch = require("./lib/launch.luau")

local GLYPH = "zoom-in"

local function render()
  barWidget.setGlyph(GLYPH)
  barWidget.setTooltip(noctalia.tr("widget.tooltip"))
end

render()

function update()
  -- The content is static; this interval only exists so render() also runs on a
  -- tick, independent of top-level presentation calls.
  noctalia.setUpdateInterval(60000)
  render()
end

function onClick()
  launch.open()
end

function onIpc(event, _payload)
  if event == "open" then
    launch.open()
  end
end
