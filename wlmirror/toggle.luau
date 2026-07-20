--!nonstrict
-- toggle.luau — Bar widget que abre el panel de WL Mirror.

local running = false

local function render()
  barWidget.setGlyph(running and "cast-connected" or "cast")
end

noctalia.state.watch("running", function(value)
  running = value == true
  render()
end)

function update()
  noctalia.setUpdateInterval(1000)
  render()
end

function onClick()
  noctalia.togglePanel("evergaster/wlmirror:panel")
end
