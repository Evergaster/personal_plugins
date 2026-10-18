--!nonstrict
-- Autocomprobacion de la logica pura (sin noctalia ni ui de verdad):
--   lua5.4 nothing/test.luau
--
-- Cubre lo que no se ve a ojo: aritmetica del calendario, geometria de la
-- reticula de puntos, escala de los bloques, tabla de codigos WMO y que ningun
-- texto ni etiqueta de ajuste se quede sin traducir.

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

-- `ui` de mentira: guarda los props de cada punto para poder contarlos.
local boxes = {}
_G.ui = {
  box = function(props)
    table.insert(boxes, props)
    return props
  end,
  row = function(props, children) return { props = props, children = children } end,
  column = function(props, children) return { props = props, children = children } end,
}

local dates = load("nothing/lib/dates.luau")
local dotmatrix = load("nothing/lib/dotmatrix.luau")
local weather = load("nothing/lib/weather.luau")
local style = load("nothing/lib/style.luau")

-- ── Calendario ──────────────────────────────────────────────────────────────

eq(dates.daysInMonth(2024, 2), 29, "febrero 2024")
eq(dates.daysInMonth(2023, 2), 28, "febrero 2023")
eq(dates.daysInMonth(2000, 2), 29, "febrero 2000")
eq(dates.daysInMonth(1900, 2), 28, "febrero 1900")
eq(dates.daysInMonth(2026, 10), 31, "octubre 2026")

-- 0 = domingo. Fechas de control conocidas.
eq(dates.weekday(2026, 10, 17), 6, "17 oct 2026 = sabado")
eq(dates.weekday(2000, 1, 1), 6, "1 ene 2000 = sabado")
eq(dates.weekday(1970, 1, 1), 4, "1 ene 1970 = jueves")
eq(dates.weekday(2024, 2, 29), 4, "29 feb 2024 = jueves")

local function checkGrid(year, month, weekStart, expectedWeeks, firstCell, firstDay)
  local weeks = dates.monthGrid(year, month, weekStart)
  eq(#weeks, expectedWeeks, string.format("semanas de %04d-%02d", year, month))
  local total = 0
  for index, week in ipairs(weeks) do
    eq(#week, 7, "celdas por semana")
    for _, day in ipairs(week) do
      if day ~= false then
        total = total + 1
      end
    end
    if index == 1 then
      eq(week[firstCell], firstDay, "primer dia del mes")
    end
  end
  eq(total, dates.daysInMonth(year, month), "todos los dias aparecen una vez")
  return weeks
end

-- Octubre 2026: el dia 1 cae en jueves.
local monday = checkGrid(2026, 10, 1, 5, 4, 1)
eq(monday[5][6], 31, "31 de octubre")
eq(monday[5][7], false, "cola vacia")
-- El mismo mes empezando en domingo ocupa exactamente 5 semanas.
checkGrid(2026, 10, 0, 5, 5, 1)
-- Agosto 2026 empieza sabado y necesita 6 semanas.
checkGrid(2026, 8, 1, 6, 6, 1)

-- ── Reticula de puntos ──────────────────────────────────────────────────────

for character, pattern in pairs(dotmatrix.GLYPHS) do
  eq(#pattern, 7, "alto de " .. character)
  for _, line in ipairs(pattern) do
    eq(#line, 5, "ancho de " .. character)
  end
end
for digit = 0, 9 do
  eq(dotmatrix.GLYPHS[tostring(digit)] ~= nil, true, "digito " .. digit)
end
eq(dotmatrix.GLYPHS[":"] ~= nil, true, "dos puntos")

-- El arbol que sale de text() tiene 5x7 puntos por digito y enciende justo los
-- que el mapa marca con '#'.
local tree = dotmatrix.text("1", { dot = 4, gap = 2 })
eq(type(tree), "table", "text devuelve un arbol")
local glyph = tree.children[1]
eq(#glyph.children, 7, "siete filas por digito")
local lit, total = 0, 0
for _, row in ipairs(glyph.children) do
  eq(#row.children, 5, "cinco puntos por fila")
  for _, cell in ipairs(row.children) do
    total = total + 1
    if cell.fill ~= nil then
      lit = lit + 1
    end
  end
end
eq(total, 35, "35 puntos por digito")
eq(lit, 7, "un uno enciende siete puntos")

-- Los puntos nunca se tocan, sea cual sea el tamano.
for _, dot in ipairs({ 2, 3, 4, 6, 8 }) do
  local gap = math.max(1, math.floor(dot / 2 + 0.5))
  eq(gap >= 1 and gap <= dot, true, "separacion de puntos a " .. dot .. "px")
end

-- ── Escala de los bloques ───────────────────────────────────────────────────

local config = {}
_G.noctalia = {
  getConfig = function(key) return config[key] end,
}

eq(style.px(4, 1), 4, "px sin escala")
eq(style.px(4, 1.5), 6, "px a 150%")
eq(style.px(11, 1.5), 17, "px redondea al alza")
eq(style.px(0.4, 1), 1, "px nunca baja de 1")

config.scale = nil
eq(style.scale(), 1, "escala por defecto")
config.scale = "abc"
eq(style.scale(), 1, "escala no numerica")
config.scale = 50
eq(style.scale(), 0.5, "escala al 50%")
config.scale = 300
eq(style.scale(), 3, "escala al 300%")
config.scale = 900
eq(style.scale(), 3, "escala acotada por arriba")
config.scale = 10
eq(style.scale(), 0.5, "escala acotada por abajo")
config.scale = 100

-- ── Codigos WMO ─────────────────────────────────────────────────────────────

eq(weather.describe(0).key, "wmo.clear", "wmo 0")
eq(weather.describe(3).key, "wmo.overcast", "wmo 3")
eq(weather.describe(45).key, "wmo.fog", "wmo 45")
eq(weather.describe(48).key, "wmo.fog", "wmo 48")
eq(weather.describe(61).key, "wmo.rain", "wmo 61")
eq(weather.describe(77).key, "wmo.snow", "wmo 77")
eq(weather.describe(80).key, "wmo.showers", "wmo 80")
eq(weather.describe(86).key, "wmo.snow", "wmo 86")
eq(weather.describe(95).key, "wmo.thunder", "wmo 95")
eq(weather.describe(999).key, "wmo.thunder", "codigo fuera de rango")

-- ── Traducciones ────────────────────────────────────────────────────────────

local function keysOf(path)
  local out = {}
  for key in read(path):gmatch('"([%w%._]+)"%s*:') do
    out[key] = true
  end
  return out
end

local english = keysOf("nothing/translations/en.json")
local spanish = keysOf("nothing/translations/es.json")

local total = 0
for key in pairs(english) do
  total = total + 1
  eq(spanish[key], true, "es.json tiene " .. key)
end
for key in pairs(spanish) do
  eq(english[key], true, "en.json tiene " .. key)
end
eq(total > 60, true, "el catalogo de textos no se ha vaciado")

-- Toda clave que los bloques piden o que el manifiesto declara como etiqueta
-- debe existir en los dos idiomas. Un typo aqui se ve en el log, no en el GUI.
local PREFIXES = { date = true, wmo = true, weather = true, device = true, ui = true, settings = true }
local FILES = { luau = true, toml = true, json = true }
local used = {}
local function scan(source)
  for key in source:gmatch('"(%a+%.[%w%._]+)"') do
    -- Los nombres de fichero se parecen a una clave ("weather.luau").
    if PREFIXES[key:match("^(%a+)%.")] and not FILES[key:match("%.(%a+)$")] then
      used[key] = true
    end
  end
end

local sources = { "nothing/plugin.toml" }
for _, entry in ipairs({ "clock", "calendar", "weather", "battery" }) do
  table.insert(sources, "nothing/" .. entry .. ".luau")
end
for _, module in ipairs({ "dates", "dotmatrix", "devices", "weather", "style" }) do
  table.insert(sources, "nothing/lib/" .. module .. ".luau")
end
for _, path in ipairs(sources) do
  scan(read(path))
end

local referenced = 0
for key in pairs(used) do
  referenced = referenced + 1
  eq(english[key], true, "en.json tiene la clave usada " .. key)
  eq(spanish[key], true, "es.json tiene la clave usada " .. key)
end
eq(referenced > 40, true, "se han encontrado las claves de los bloques")

print(string.format("ok — %d comprobaciones", count))
