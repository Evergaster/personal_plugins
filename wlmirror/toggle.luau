--!nonstrict
-- toggle.luau — Bar widget que abre el panel de WL Mirror.
-- Solo muestra el glyph "cast" y abre el panel al hacer click.

local running = false

local function render()
  barWidget.setGlyph(running and "cast-connected" or "cast")
end

noctalia.state.watch("running", function(value)
  running = value == true
  render()
end)

function update()
  render()
end

function onClick()
  noctalia.togglePanel("evergaster/wlmirror:panel")
end
