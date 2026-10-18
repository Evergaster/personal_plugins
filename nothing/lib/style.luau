--!nonstrict
-- style.luau — la tarjeta y la escala que comparten los cuatro bloques.
-- `noctalia` y `ui` solo se tocan dentro de las funciones: el modulo se puede
-- cargar (y probar) sin Noctalia.

local M = {}

M.MONO = "monospace"
M.ACCENT = "#D71921"

-- Escala del bloque, en por ciento: 100 = tamano nominal.
function M.scale()
  local percent = tonumber(noctalia.getConfig("scale")) or 100
  return math.max(0.5, math.min(3, percent / 100))
end

-- Pixeles fisicos: redondeados y nunca por debajo de 1.
function M.px(base, factor)
  return math.max(1, math.floor(base * factor + 0.5))
end

function M.accent()
  return noctalia.getConfig("accent") or M.ACCENT
end

-- La tarjeta: identica en los cuatro bloques, para que se lean como familia.
function M.card(factor, children, opts)
  opts = opts or {}
  return ui.column({
    width = "fill",
    align = "center",
    gap = opts.gap or M.px(12, factor),
    padding = opts.padding or M.px(18, factor),
    fill = "surface/0.85",
    radius = M.px(24, factor),
    border = "surface_variant",
    borderWidth = 1,
  }, children)
end

-- Fila apagada para los estados vacios (sin dispositivo, sin clima todavia).
function M.muted(factor, glyph, text, onClick)
  return ui.row({ gap = M.px(8, factor), align = "center", width = "fill", onClick = onClick }, {
    ui.glyph({ name = glyph, size = M.px(20, factor), color = "on_surface_variant" }),
    ui.label({
      text = text,
      flexGrow = 1,
      fontSize = M.px(12, factor),
      fontFamily = M.MONO,
      color = "on_surface_variant",
    }),
  })
end

return M
