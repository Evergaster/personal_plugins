--!nonstrict
-- toggle.luau — Bar widget que abre el panel de WL Mirror.
-- Muestra el glyph "cast" + texto y abre el panel al hacer click.

local running = false

local function render()
  barWidget.setGlyph("cast")
  barWidget.setText(running and "Mirroring" or "Mirror")
  barWidget.setTooltip(running and "Click to stop mirroring" or "Click to open mirror panel")
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
