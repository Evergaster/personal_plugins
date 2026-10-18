--!nonstrict
-- weather.luau — bloque de clima: estado actual y los tres dias siguientes,
-- via Open-Meteo (sin API key). El tamano lo lleva el ajuste `scale`.

local dates = require("./lib/dates.luau")
local style = require("./lib/style.luau")
local weatherApi = require("./lib/weather.luau")

local WEEKDAY_KEYS = {
  "date.sun", "date.mon", "date.tue", "date.wed", "date.thu", "date.fri", "date.sat",
}

local factor = style.scale()
local accent = style.accent()
local unit = noctalia.getConfig("temperature_unit") or "metric"
local refreshSeconds = math.max(60, (tonumber(noctalia.getConfig("weather_refresh_minutes")) or 30) * 60)

local render
local weather = nil
local nextRefresh = 0

local function weekdayLabel(year, month, day)
  return noctalia.tr(WEEKDAY_KEYS[dates.weekday(year, month, day) + 1]):sub(1, 3)
end

local function forecast(day)
  local year, month, number = tostring(day.date):match("^(%d+)-(%d+)-(%d+)$")
  local label = year ~= nil and weekdayLabel(tonumber(year), tonumber(month), tonumber(number)) or ""
  return ui.column({ key = "f" .. tostring(day.date), gap = 0, align = "center" }, {
    ui.label({ text = label, fontSize = style.px(10, factor), fontFamily = style.MONO, color = "on_surface_variant" }),
    ui.label({ text = string.format("%d°", math.floor(day.max + 0.5)), fontSize = style.px(12, factor), fontWeight = "bold" }),
    ui.label({
      text = string.format("%d°", math.floor(day.min + 0.5)),
      fontSize = style.px(10, factor),
      color = "on_surface_variant",
    }),
  })
end

local function current()
  local description = weatherApi.describe(weather.code)
  local lines = {
    ui.label({
      text = string.format("%d°", weather.temp),
      fontSize = style.px(30, factor),
      fontWeight = "bold",
    }),
    ui.label({
      text = noctalia.tr(description.key),
      fontSize = style.px(10, factor),
      fontFamily = style.MONO,
      color = "on_surface_variant",
      maxLines = 1,
    }),
  }
  if weather.city ~= nil and weather.city ~= "" then
    table.insert(lines, ui.label({
      text = tostring(weather.city):upper(),
      fontSize = style.px(9, factor),
      fontFamily = style.MONO,
      color = "on_surface_variant",
      maxLines = 1,
    }))
  end
  return ui.row({ gap = style.px(12, factor), align = "center", width = "fill" }, {
    ui.glyph({ name = description.glyph, size = style.px(34, factor), color = accent }),
    ui.column({ gap = style.px(2, factor), flexGrow = 1 }, lines),
  })
end

local function days()
  local cells = {}
  for _, day in ipairs(weather.days) do
    table.insert(cells, forecast(day))
  end
  return ui.row({ gap = style.px(16, factor), align = "center" }, cells)
end

render = function()
  if weather == nil then
    desktopWidget.render(style.card(factor, { style.muted(factor, "cloud-off", noctalia.tr("weather.loading")) }))
    return
  end
  if not weather.ok then
    local key = weather.error == "location" and "weather.no_location" or "weather.unavailable"
    desktopWidget.render(style.card(factor, { style.muted(factor, "cloud-off", noctalia.tr(key)) }))
    return
  end
  local children = { current() }
  if #weather.days > 0 then
    table.insert(children, ui.separator({ thickness = 1, color = "surface_variant" }))
    table.insert(children, days())
  end
  desktopWidget.render(style.card(factor, children))
end

local function load()
  nextRefresh = os.time() + refreshSeconds
  weatherApi.fetch({
    latitude = tonumber(noctalia.getConfig("latitude")),
    longitude = tonumber(noctalia.getConfig("longitude")),
    city = noctalia.getConfig("city") or "",
    unit = unit,
  }, function(result)
    weather = result
    render()
  end)
end

function update()
  if os.time() >= nextRefresh then
    load()
  end
end

desktopWidget.setWantsSecondTicks(true)
render()
load()
