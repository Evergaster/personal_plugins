--!nonstrict
-- calendar.luau — bloque de calendario: el mes en curso, con hoy marcado.
-- El tamano lo lleva el ajuste `scale` de esta entrada.

local dates = require("./lib/dates.luau")
local style = require("./lib/style.luau")

local MONTH_KEYS = {
  "date.jan", "date.feb", "date.mar", "date.apr", "date.may", "date.jun",
  "date.jul", "date.aug", "date.sep", "date.oct", "date.nov", "date.dec",
}
local WEEKDAY_KEYS = {
  "date.sun", "date.mon", "date.tue", "date.wed", "date.thu", "date.fri", "date.sat",
}

local factor = style.scale()
local accent = style.accent()
local weekStart = noctalia.getConfig("week_start") == "sunday" and 0 or 1

local cell = style.px(24, factor)
local numeral = style.px(11, factor)
local monthGap = style.px(2, factor)
local lastMonth = nil

-- Todas las celdas miden lo mismo: el mes no baila segun el dia de la semana.
local function dayCell(day, today, key)
  -- El borde se declara siempre, con ancho 0 cuando no toca: si se omite, la
  -- celda que fue "hoy" conserva el aro al cambiar de mes (Noctalia no borra
  -- los props que no vienen).
  local badge = {
    width = cell,
    height = cell,
    align = "center",
    justify = "center",
    radius = math.floor(cell / 2),
    border = accent,
    borderWidth = today and 1 or 0,
  }
  return ui.column(badge, {
    ui.label({
      key = key,
      text = tostring(day),
      fontSize = numeral,
      fontWeight = today and "bold" or nil,
      fontFamily = style.MONO,
      color = today and accent or "on_surface",
    }),
  })
end

local function render()
  local now = os.date("*t")
  lastMonth = string.format("%04d-%02d", now.year, now.month)

  local rows = {
    ui.row({ gap = style.px(6, factor), align = "center" }, {
      ui.box({
        width = style.px(6, factor),
        height = style.px(6, factor),
        radius = style.px(3, factor),
        fill = accent,
      }),
      ui.label({
        text = noctalia.tr(MONTH_KEYS[now.month]) .. " " .. tostring(now.year),
        fontSize = style.px(12, factor),
        fontWeight = "bold",
        fontFamily = style.MONO,
      }),
    }),
  }

  local header = {}
  for column = 1, 7 do
    local index = ((weekStart + column - 1) % 7) + 1
    -- Las iniciales van dentro de un hueco del ancho de una celda: asi caen
    -- justo encima de su columna de dias.
    table.insert(header, ui.column({ key = "wd" .. index, width = cell, align = "center" }, {
      ui.label({
        text = noctalia.tr(WEEKDAY_KEYS[index]):sub(1, 2),
        fontSize = style.px(10, factor),
        fontFamily = style.MONO,
        color = "on_surface_variant",
      }),
    }))
  end
  table.insert(rows, ui.row({ gap = monthGap }, header))

  for weekIndex, week in ipairs(dates.monthGrid(now.year, now.month, weekStart)) do
    local cells = {}
    for dayIndex, day in ipairs(week) do
      local key = "c" .. weekIndex .. "-" .. dayIndex
      if day == false then
        -- Hueco vacio: reserva su sitio sin pintar nada.
        table.insert(cells, ui.box({ key = key, width = cell, height = cell, opacity = 0 }))
      else
        table.insert(cells, dayCell(day, day == now.day, key))
      end
    end
    table.insert(rows, ui.row({ gap = monthGap }, cells))
  end

  desktopWidget.render(style.card(factor, rows, { gap = style.px(4, factor) }))
end

function update()
  local now = os.date("*t")
  if string.format("%04d-%02d", now.year, now.month) ~= lastMonth then
    render()
  end
end

desktopWidget.setWantsSecondTicks(true)
render()
