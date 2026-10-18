--!nonstrict
-- dotmatrix.luau — reloj de matriz de puntos al estilo Nothing (NDot).
-- Solo digitos y separadores: el resto de la tarjeta usa texto normal.

local M = {}

M.GLYPHS = {
  ["0"] = { " ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### " },
  ["1"] = { "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  " },
  ["2"] = { " ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####" },
  ["3"] = { " ### ", "#   #", "    #", "  ## ", "    #", "#   #", " ### " },
  ["4"] = { "   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # " },
  ["5"] = { "#####", "#    ", "#### ", "    #", "    #", "#   #", " ### " },
  ["6"] = { "  ## ", " #   ", "#    ", "#### ", "#   #", "#   #", " ### " },
  ["7"] = { "#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   " },
  ["8"] = { " ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### " },
  ["9"] = { " ### ", "#   #", "#   #", " ####", "    #", "   # ", " ##  " },
  [":"] = { "     ", "  #  ", "     ", "     ", "  #  ", "     ", "     " },
  ["."] = { "     ", "     ", "     ", "     ", "     ", "     ", "  #  " },
}

local BLANK = { "     ", "     ", "     ", "     ", "     ", "     ", "     " }

-- Un caracter como columna de puntos. Las celdas apagadas no se pintan pero
-- ocupan su hueco: es lo que mantiene la reticula alineada.
--
-- Noctalia solo aplica los props que ve en el arbol nuevo: si un prop no
-- viene, el control conserva el valor del render anterior. Como la celda
-- apagada declara opacity = 0, la que se enciende tiene que declarar opacity
-- otra vez o se queda invisible. Por eso cada celda manda siempre su estado
-- completo (relleno y opacidad), no solo cuando esta encendida.
function M.glyph(ch, dot, gap, color)
  local pattern = M.GLYPHS[ch] or BLANK
  local rows = {}
  for r = 1, #pattern do
    local line = pattern[r]
    local cells = {}
    for c = 1, #line do
      local on = line:sub(c, c) == "#"
      table.insert(cells, ui.box({
        width = dot,
        height = dot,
        radius = dot / 2,
        fill = color,
        opacity = on and 1 or 0,
      }))
    end
    table.insert(rows, ui.row({ gap = gap }, cells))
  end
  return ui.column({ gap = gap }, rows)
end

-- text: "13:37". Devuelve una fila lista para meter en un arbol ui.
function M.text(text, opts)
  local dot = opts.dot or 4
  local gap = opts.gap or 2
  local color = opts.color or "on_surface"
  local glyphs = {}
  for i = 1, #text do
    table.insert(glyphs, M.glyph(text:sub(i, i), dot, gap, color))
  end
  -- Entre caracteres basta un punto: la columna en blanco que cierra cada
  -- glifo ya separa, y mas aire rompe la palabra.
  return ui.row({ gap = dot, align = "center", justify = "center" }, glyphs)
end

return M
