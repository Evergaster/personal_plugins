--!nonstrict
-- weather.luau — Open-Meteo (sin API key).
-- Coordenadas: ajustes del plugin > [location] de Noctalia > geocodificacion
-- del nombre de ciudad.

local M = {}

-- Codigos WMO agrupados por su maximo. Los textos viven en translations/.
local WMO = {
  { max = 0,  key = "wmo.clear",        glyph = "sun" },
  { max = 1,  key = "wmo.mainly_clear", glyph = "sun" },
  { max = 2,  key = "wmo.partly",       glyph = "cloud" },
  { max = 3,  key = "wmo.overcast",     glyph = "cloud" },
  { max = 48, key = "wmo.fog",          glyph = "cloud-fog" },
  { max = 57, key = "wmo.drizzle",      glyph = "cloud-rain" },
  { max = 67, key = "wmo.rain",         glyph = "cloud-rain" },
  { max = 77, key = "wmo.snow",         glyph = "cloud-snow" },
  { max = 82, key = "wmo.showers",      glyph = "cloud-rain" },
  { max = 86, key = "wmo.snow",         glyph = "cloud-snow" },
  { max = 99, key = "wmo.thunder",      glyph = "cloud-storm" },
}

function M.describe(code)
  local value = tonumber(code) or 0
  for _, entry in ipairs(WMO) do
    if value <= entry.max then
      return entry
    end
  end
  return WMO[#WMO]
end

local function geocode(query, cb)
  local url = "https://geocoding-api.open-meteo.com/v1/search?count=1&format=json&name="
    .. noctalia.string.urlEncode(query)
  noctalia.http({ url = url }, function(response)
    local data = response.ok and noctalia.json.decode(response.body)
    local first = data and data.results and data.results[1]
    if first == nil then
      cb(nil)
      return
    end
    cb({ latitude = first.latitude, longitude = first.longitude, city = first.name })
  end)
end

local function coordinates(cfg, cb)
  if cfg.latitude ~= nil and cfg.longitude ~= nil then
    cb({ latitude = cfg.latitude, longitude = cfg.longitude, city = cfg.city })
    return
  end
  local location = noctalia.getSetting("location")
  local city = cfg.city
  if type(location) == "table" then
    local latitude = tonumber(location.latitude)
    local longitude = tonumber(location.longitude)
    if latitude ~= nil and longitude ~= nil then
      cb({ latitude = latitude, longitude = longitude, city = city or location.address })
      return
    end
    if city == nil or city == "" then
      city = location.address
    end
  end
  if city ~= nil and city ~= "" then
    geocode(city, cb)
    return
  end
  cb(nil)
end

-- cfg = { latitude, longitude, city, unit }. cb(resultado):
--   { ok = true, temp, code, days = { { date, code, max, min } … } }
--   { ok = false, error = "location" | "http" | "parse" }
function M.fetch(cfg, cb)
  coordinates(cfg, function(place)
    if place == nil then
      cb({ ok = false, error = "location" })
      return
    end
    local unit = cfg.unit == "imperial" and "fahrenheit" or "celsius"
    local url = string.format(
      "https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f"
        .. "&current=temperature_2m,weather_code"
        .. "&daily=weather_code,temperature_2m_max,temperature_2m_min"
        .. "&forecast_days=4&timezone=auto&temperature_unit=%s",
      place.latitude, place.longitude, unit)
    noctalia.http({ url = url }, function(response)
      local data = response.ok and noctalia.json.decode(response.body)
      local current = data and data.current
      if type(current) ~= "table" then
        cb({ ok = false, error = response.ok and "parse" or "http" })
        return
      end
      local days = {}
      local daily = data.daily
      if type(daily) == "table" and type(daily.time) == "table" then
        for i = 2, 4 do
          if daily.time[i] ~= nil then
            table.insert(days, {
              date = daily.time[i],
              code = daily.weather_code[i],
              max = daily.temperature_2m_max[i],
              min = daily.temperature_2m_min[i],
            })
          end
        end
      end
      cb({
        ok = true,
        city = place.city,
        temp = math.floor((current.temperature_2m or 0) + 0.5),
        code = current.weather_code,
        days = days,
      })
    end)
  end)
end

return M
