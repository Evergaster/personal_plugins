--!nonstrict
-- Autocomprobacion del bloque (sin noctalia ni ui de verdad):
--   lua5.4 nothing-calendar/test.luau   (desde la raiz del repo)

local DIR = "nothing-calendar"

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

-- ── Mes ─────────────────────────────────────────────────────────────────────

local function checkGrid(year, month, weekStart, expectedWeeks, firstCell, firstDay)
  local weeks = dates.monthGrid(year, month, weekStart)
  eq(#weeks, expectedWeeks, string.format("semanas de %04d-%02d", year, month))
  local days = 0
  for index, week in ipairs(weeks) do
    eq(#week, 7, "celdas por semana")
    for _, day in ipairs(week) do
      if day ~= false then
        days = days + 1
      end
    end
    if index == 1 then
      eq(week[firstCell], firstDay, "primer dia del mes")
    end
  end
  eq(days, dates.daysInMonth(year, month), "todos los dias aparecen una vez")
end

eq(dates.daysInMonth(2023, 2), 28, "febrero 2023")
eq(dates.daysInMonth(2000, 2), 29, "febrero 2000")
-- Octubre 2026: el dia 1 cae en jueves.
checkGrid(2026, 10, 1, 5, 4, 1)
checkGrid(2026, 10, 0, 5, 5, 1)
-- Agosto 2026 empieza sabado y necesita seis semanas.
checkGrid(2026, 8, 1, 6, 6, 1)

-- ── Escala ──────────────────────────────────────────────────────────────────

local config = {}
_G.noctalia = { getConfig = function(key) return config[key] end }

eq(style.px(24, 1.5), 36, "celda a 150%")
eq(style.px(11, 1.5), 17, "numero a 150%")
config.scale = 50
eq(style.scale(), 0.5, "escala al 50%")


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

local SOURCES = { DIR .. "/plugin.toml", DIR .. "/calendar.luau", DIR .. "/lib/dates.luau", DIR .. "/lib/style.luau" }
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
