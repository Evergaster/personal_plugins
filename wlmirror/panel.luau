--!nonstrict
-- panel.luau — Panel desplegable del bar widget.
-- Dos secciones:
--   Mirror — outputs conectados, click para iniciar/stopear wl-mirror
--   Window — selección de ventana vía xdg-desktop-portal

local running = false
local outputs = {}

local function getExtraArgs()
  local extra = noctalia.getConfig("extra_args") or ""
  if noctalia.string.trim(extra) ~= "" then
    return " " .. extra
  end
  return ""
end

local function startMirror(target)
  if not noctalia.commandExists("wl-mirror") then
    noctalia.notifyError("WL Mirror", "wl-mirror no está instalado")
    return
  end
  noctalia.runAsync("wl-mirror " .. target .. getExtraArgs())
  noctalia.notify("WL Mirror", "Espejando " .. target)
end

local function stopMirror()
  noctalia.runAsync("pkill -x wl-mirror")
  noctalia.notify("WL Mirror", "Deteniendo espejo")
end

local function makeOutputHandler(index)
  return function()
    if running then
      stopMirror()
      return
    end
    local out = outputs[tonumber(index)]
    if out then
      startMirror(out.name)
    end
  end
end

local function registerOutputHandlers()
  for i, _ in outputs do
    local key = "onOutputClick_" .. tostring(i)
    _G[key] = makeOutputHandler(i)
  end
end

local function buildOutputButtons()
  local buttons = {}
  for i, out in outputs do
    local isActive = running
    local label = out.name
    if out.description and out.description ~= "" then
      label = out.description .. " (" .. out.name .. ")"
    end
    table.insert(buttons, ui.button({
      text = label,
      glyph = isActive and "check" or "monitor",
      variant = isActive and "primary" or "default",
      onClick = "onOutputClick_" .. tostring(i),
    }))
  end
  return buttons
end

local function render()
  registerOutputHandlers()

  local outputButtons = buildOutputButtons()
  if #outputButtons == 0 then
    table.insert(outputButtons, ui.label({
      text = "No outputs detected",
      color = "on_surface_variant",
    }))
  end

  panel.render(ui.column({ flexGrow = 1, gap = 16 }, {
    ui.row({ align = "center", justify = "space_between" }, {
      ui.label({
        text = "WL Mirror",
        fontSize = 16,
        fontWeight = "bold",
        color = "on_surface",
        flexGrow = 1,
      }),
      ui.button({ glyph = "close", onClick = "onCloseClicked" }),
    }),

    ui.column({ gap = 8 }, {
      ui.label({
        text = "Mirror",
        fontWeight = "medium",
        color = "on_surface_variant",
      }),
      ui.column({ gap = 6 }, outputButtons),
    }),

    ui.separator({}),

    ui.column({ gap = 8 }, {
      ui.label({
        text = "Window",
        fontWeight = "medium",
        color = "on_surface_variant",
      }),
      ui.button({
        text = running and "Stop Mirror" or "Select Window",
        glyph = running and "player-stop" or "app-window",
        variant = running and "destructive" or "default",
        onClick = "onWindowClick",
      }),
    }),
  }))
end

function onOpen(_context)
  outputs = noctalia.outputs() or {}
  render()
end

function onCloseClicked()
  panel.close()
end

function onWindowClick()
  if running then
    stopMirror()
    return
  end
  if not noctalia.commandExists("wl-mirror") then
    noctalia.notifyError("WL Mirror", "wl-mirror no está instalado")
    return
  end
  noctalia.runAsync("wl-mirror portal:window" .. getExtraArgs())
  noctalia.notify("WL Mirror", "Selecciona una ventana...")
end

noctalia.state.watch("running", function(value)
  running = value == true
  render()
end)
