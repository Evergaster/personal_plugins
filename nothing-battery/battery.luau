--!nonstrict
-- battery.luau — bloque de bateria del periferico elegido (audifonos, mouse,
-- teclado). Los datos salen de BlueZ y upower; el selector de dispositivos se
-- guarda en el directorio de datos del plugin.

local peripherals = require("./lib/devices.luau")
local style = require("./lib/style.luau")

local factor = style.scale()
local accent = style.accent()
local lowThreshold = tonumber(noctalia.getConfig("low_battery_threshold")) or 20
local pollSeconds = math.max(30, tonumber(noctalia.getConfig("device_poll_seconds")) or 120)

local devices = {}
local picking = false
local nextPoll = 0
-- El ajuste `device` manda al arrancar; el selector lo sustituye en caliente.
local pinned = noctalia.getConfig("device") or ""

local render

local function deviceFile()
  local dir = noctalia.pluginDataDir()
  return dir and (dir .. "/device.json") or nil
end

local function loadPinned()
  local path = deviceFile()
  if path == nil then
    return ""
  end
  local raw = noctalia.readFile(path)
  local decoded = raw and noctalia.json.decode(raw)
  return type(decoded) == "table" and tostring(decoded.id or "") or ""
end

local function savePinned(id)
  local path = deviceFile()
  if path ~= nil then
    noctalia.writeFile(path, noctalia.json.encode({ id = id }))
  end
end

-- Dispositivo a mostrar: el fijado si sigue presente; si no, uno conectado.
local function current()
  local fallback = nil
  for _, device in ipairs(devices) do
    if device.percent ~= nil then
      if pinned ~= "" then
        local name = device.name:lower()
        local needle = pinned:lower()
        if device.id == pinned or name == needle or name:find(needle, 1, true) ~= nil then
          return device
        end
      end
      if fallback == nil or (device.connected and not fallback.connected) then
        fallback = device
      end
    end
  end
  return fallback
end

local function batteryDots(device, tint)
  local lit = math.floor(device.percent / 10 + 0.5)
  local dots = {}
  for level = 1, 10 do
    table.insert(dots, ui.box({
      key = "b" .. level,
      width = style.px(7, factor),
      height = style.px(14, factor),
      radius = style.px(2, factor),
      fill = level <= lit and tint or "on_surface/0.15",
    }))
  end
  return ui.row({ gap = style.px(3, factor) }, dots)
end

local function block()
  local device = current()
  if device == nil then
    return style.muted(factor, "bluetooth", noctalia.tr("device.none"), "onTogglePicker")
  end

  local low = device.percent <= lowThreshold
  local tint = low and accent or "on_surface"
  return ui.row({ gap = style.px(10, factor), align = "center", width = "fill", onClick = "onTogglePicker" }, {
    ui.glyph({ name = device.glyph, size = style.px(20, factor), color = low and accent or "on_surface_variant" }),
    ui.column({ gap = style.px(6, factor), flexGrow = 1 }, {
      ui.label({
        text = device.name,
        fontSize = style.px(11, factor),
        fontWeight = "bold",
        fontFamily = style.MONO,
        maxLines = 1,
      }),
      batteryDots(device, tint),
    }),
    ui.label({ text = string.format("%d%%", device.percent), fontSize = style.px(18, factor), fontWeight = "bold", color = tint }),
  })
end

local function chooseDevice(id)
  pinned = id
  savePinned(id)
  picking = false
  render()
end

local function picker()
  local rows = {}
  table.insert(rows, ui.row({
    key = "auto",
    gap = style.px(8, factor),
    align = "center",
    padding = style.px(6, factor),
    radius = style.px(10, factor),
    fill = pinned == "" and "on_surface/0.08" or "on_surface/0",
    onClick = function() chooseDevice("") end,
  }, {
    ui.glyph({ name = "sparkles", size = style.px(16, factor), color = "on_surface_variant" }),
    ui.label({ text = noctalia.tr("device.auto"), flexGrow = 1, fontSize = style.px(11, factor), fontFamily = style.MONO }),
  }))

  for _, device in ipairs(devices) do
    local percent = device.percent ~= nil and string.format("%d%%", device.percent) or "—"
    table.insert(rows, ui.row({
      key = device.id,
      gap = style.px(8, factor),
      align = "center",
      padding = style.px(6, factor),
      radius = style.px(10, factor),
      -- El relleno va en cada render, aunque sea transparente: si se omite,
      -- la fila que fue la elegida conserva el resaltado.
      fill = device.id == pinned and "on_surface/0.08" or "on_surface/0",
      onClick = function() chooseDevice(device.id) end,
    }, {
      ui.glyph({ name = device.glyph, size = style.px(16, factor), color = "on_surface_variant" }),
      ui.label({ text = device.name, flexGrow = 1, fontSize = style.px(11, factor), fontFamily = style.MONO, maxLines = 1 }),
      ui.label({ text = percent, fontSize = style.px(11, factor), color = "on_surface_variant" }),
    }))
  end

  if #devices == 0 then
    table.insert(rows, ui.label({
      text = noctalia.tr("device.empty"),
      fontSize = style.px(11, factor),
      fontFamily = style.MONO,
      color = "on_surface_variant",
    }))
  end
  table.insert(rows, ui.button({ text = noctalia.tr("ui.close"), variant = "ghost", onClick = "onTogglePicker" }))
  return rows
end

local function refreshDevices()
  if not noctalia.commandExists("busctl") then
    devices = {}
    render()
    return
  end
  peripherals.list(function(found)
    devices = found
    render()
  end)
end

render = function()
  local children = { block() }
  if picking then
    table.insert(children, ui.separator({ thickness = 1, color = "surface_variant" }))
    for _, row in ipairs(picker()) do
      table.insert(children, row)
    end
  end
  desktopWidget.render(style.card(factor, children))
end

function onTogglePicker()
  picking = not picking
  if picking then
    refreshDevices()
  end
  render()
end

function update()
  if os.time() >= nextPoll then
    nextPoll = os.time() + pollSeconds
    refreshDevices()
  end
end

pinned = pinned ~= "" and pinned or loadPinned()
desktopWidget.setWantsSecondTicks(true)
render()
refreshDevices()
