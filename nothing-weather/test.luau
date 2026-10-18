--!nonstrict
-- Autocomprobacion del bloque (sin noctalia ni ui de verdad):
--   lua5.4 nothing-weather/test.luau   (desde la raiz del repo)

local DIR = "nothing-weather"

local count = 0

local function eq(actual, expected, message)
  count = count + 1
  if actual ~= expected then
    error(string.format("%s: %s ~= %s", message, tostring(actual), tostring(expected)), 2)
  end
end

local function load(path)
  return assert(loadfile(path))()
end

local function read(path)
  local file = assert(io.open(path, "r"))
  local raw = file:read("*a")
  file:close()
  return raw
end

local function exists(path)
  local file = io.open(path, "r")
  if file == nil then
    return false
  end
  file:close()
  return true
end

local dates = load(DIR .. "/lib/dates.luau")
local style = load(DIR .. "/lib/style.luau")
local wmo = load(DIR .. "/lib/weather.luau")

-- ── Etiquetas del pronostico ────────────────────────────────────────────────

eq(dates.weekday(2026, 10, 17), 6, "17 oct 2026 = sabado")
eq(dates.weekday(1970, 1, 1), 4, "1 ene 1970 = jueves")

-- ── Codigos WMO ─────────────────────────────────────────────────────────────

eq(wmo.describe(0).key, "wmo.clear", "wmo 0")
eq(wmo.describe(3).key, "wmo.overcast", "wmo 3")
eq(wmo.describe(45).key, "wmo.fog", "wmo 45")
eq(wmo.describe(61).key, "wmo.rain", "wmo 61")
eq(wmo.describe(80).key, "wmo.showers", "wmo 80")
eq(wmo.describe(86).key, "wmo.snow", "wmo 86")
eq(wmo.describe(95).key, "wmo.thunder", "wmo 95")
eq(wmo.describe(999).key, "wmo.thunder", "codigo fuera de rango")

-- ── Escala ──────────────────────────────────────────────────────────────────

local config = {}
_G.noctalia = { getConfig = function(key) return config[key] end }

eq(style.px(34, 1.3), 44, "glifo a 130%")
config.scale = 300
eq(style.scale(), 3, "escala al 300%")


-- ── Traducciones ────────────────────────────────────────────────────────────
-- Mismo juego de claves en los dos idiomas, y ninguna clave que el bloque use o
-- que su manifiesto declare sin texto: un typo se ve en el log, no en el GUI.

local PREFIXES = { date = true, wmo = true, weather = true, device = true, ui = true, settings = true }
local FILES = { luau = true, toml = true, json = true }

local function keysOf(path)
  local out = {}
  for key in read(path):gmatch('"([%w%._]+)"%s*:') do
    out[key] = true
  end
  return out
end

local english = keysOf(DIR .. "/translations/en.json")
local spanish = keysOf(DIR .. "/translations/es.json")

local total = 0
for key in pairs(english) do
  total = total + 1
  eq(spanish[key], true, "es.json tiene " .. key)
end
for key in pairs(spanish) do
  eq(english[key], true, "en.json tiene " .. key)
end
eq(total > 5, true, "el catalogo de textos no se ha vaciado")

local SOURCES = { DIR .. "/plugin.toml", DIR .. "/weather.luau", DIR .. "/lib/dates.luau", DIR .. "/lib/style.luau", DIR .. "/lib/weather.luau" }
local used = {}
for _, path in ipairs(SOURCES) do
  for key in read(path):gmatch('"(%a+%.[%w%._]+)"') do
    if PREFIXES[key:match("^(%a+)%.")] and not FILES[key:match("%.(%a+)$")] then
      used[key] = true
    end
  end
end

local referenced = 0
for key in pairs(used) do
  referenced = referenced + 1
  eq(english[key], true, "en.json tiene la clave usada " .. key)
  eq(spanish[key], true, "es.json tiene la clave usada " .. key)
end
eq(referenced > 3, true, "se han encontrado las claves del bloque")

-- ── Copias hermanas ─────────────────────────────────────────────────────────
-- Los modulos compartidos estan copiados en los cuatro plugins Nothing: si una
-- copia se queda atras, esto lo canta.

local SIBLINGS = { "nothing-clock", "nothing-calendar", "nothing-weather", "nothing-battery" }
for _, name in ipairs({ "dates", "style" }) do
  local mine = read(DIR .. "/lib/" .. name .. ".luau")
  for _, sibling in ipairs(SIBLINGS) do
    if sibling ~= DIR and exists(sibling .. "/lib/" .. name .. ".luau") then
      eq(read(sibling .. "/lib/" .. name .. ".luau"), mine, name .. " identico en " .. sibling)
    end
  end
end

print(string.format("ok — %d comprobaciones", count))
