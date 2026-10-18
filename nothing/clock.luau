--!nonstrict
-- clock.luau — bloque de reloj: matriz de puntos NDot y la fecha corta debajo.
-- El tamano lo lleva el ajuste `scale` de esta entrada.

local dates = require("./lib/dates.luau")
local dotmatrix = require("./lib/dotmatrix.luau")
local style = require("./lib/style.luau")

local WEEKDAY_KEYS = {
  "date.sun", "date.mon", "date.tue", "date.wed", "date.thu", "date.fri", "date.sat",
}
local MONTH_KEYS = {
  "date.jan", "date.feb", "date.mar", "date.apr", "date.may", "date.jun",
  "date.jul", "date.aug", "date.sep", "date.oct", "date.nov", "date.dec",
}

local factor = style.scale()
local accent = style.accent()
local hourFormat = noctalia.getConfig("hour_format") or "24"
local showSeconds = noctalia.getConfig("show_seconds") == true

local last = ""

local function clockText()
  local pattern = hourFormat == "12" and "%I:%M" or "%H:%M"
  if showSeconds then
    pattern = pattern .. ":%S"
  end
  return os.date(pattern)
end

local function render()
  local now = os.date("*t")
  last = clockText()
  local dot = style.px(4, factor)
  -- La separacion sigue al punto: el reloj crece sin perder la reticula.
  local gap = math.max(1, math.floor(dot / 2 + 0.5))
  local weekday = noctalia.tr(WEEKDAY_KEYS[dates.weekday(now.year, now.month, now.day) + 1])
  local month = noctalia.tr(MONTH_KEYS[now.month]):sub(1, 3)

  desktopWidget.render(style.card(factor, {
    dotmatrix.text(last, { dot = dot, gap = gap, color = "on_surface" }),
    ui.row({ gap = style.px(6, factor), align = "center" }, {
      ui.box({
        width = style.px(6, factor),
        height = style.px(6, factor),
        radius = style.px(3, factor),
        fill = accent,
      }),
      ui.label({
        text = weekday .. " " .. tostring(now.day) .. " " .. month,
        fontSize = style.px(11, factor),
        fontFamily = style.MONO,
        color = "on_surface_variant",
      }),
    }),
  }, { gap = style.px(14, factor) }))
end

function update()
  if clockText() ~= last then
    render()
  end
end

desktopWidget.setWantsSecondTicks(true)
render()
