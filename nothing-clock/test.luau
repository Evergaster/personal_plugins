--!nonstrict
-- Autocomprobacion del bloque (sin noctalia ni ui de verdad):
--   lua5.4 nothing-clock/test.luau   (desde la raiz del repo)

local DIR = "nothing-clock"

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

local dates = load(DIR .. "/lib/dates.luau")
local dotmatrix = load(DIR .. "/lib/dotmatrix.luau")
local style = load(DIR .. "/lib/style.luau")

-- ── Fecha ───────────────────────────────────────────────────────────────────

eq(dates.daysInMonth(2024, 2), 29, "febrero 2024")
eq(dates.daysInMonth(1900, 2), 28, "febrero 1900")
eq(dates.weekday(2026, 10, 17), 6, "17 oct 2026 = sabado")
eq(dates.weekday(2000, 1, 1), 6, "1 ene 2000 = sabado")

-- ── Reticula de puntos ──────────────────────────────────────────────────────

for character, pattern in pairs(dotmatrix.GLYPHS) do
  eq(#pattern, 7, "alto de " .. character)
  for _, line in ipairs(pattern) do
    eq(#line, 5, "ancho de " .. character)
  end
end

local tree = dotmatrix.text("1", { dot = 4, gap = 2 })
local glyph = tree.children[1]
eq(#glyph.children, 7, "siete filas por digito")
local lit, points = 0, 0
for _, row in ipairs(glyph.children) do
  eq(#row.children, 5, "cinco puntos por fila")
  for _, cell in ipairs(row.children) do
    points = points + 1
    if cell.fill ~= nil then
      lit = lit + 1
    end
  end
end
eq(points, 35, "35 puntos por digito")
eq(lit, 7, "un uno enciende siete puntos")

-- ── Escala ──────────────────────────────────────────────────────────────────

local config = {}
_G.noctalia = { getConfig = function(key) return config[key] end }

eq(style.px(4, 1), 4, "px sin escala")
eq(style.px(11, 1.5), 17, "px redondea al alza")
eq(style.px(0.4, 1), 1, "px nunca baja de 1")
config.scale = nil
eq(style.scale(), 1, "escala por defecto")
config.scale = 10
eq(style.scale(), 0.5, "escala acotada por abajo")
config.scale = 900
eq(style.scale(), 3, "escala acotada por arriba")


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

local SOURCES = { DIR .. "/plugin.toml", DIR .. "/clock.luau", DIR .. "/lib/dates.luau", DIR .. "/lib/dotmatrix.luau", DIR .. "/lib/style.luau" }
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
