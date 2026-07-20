--!nonstrict
-- panel.luau — Panel desplegable del bar widget.
-- Dos secciones:
--   Mirror — selector de outputs conectados + botón para iniciar/stopear
--   Window — selección de ventana vía xdg-desktop-portal

local running = false
local outputs = {}
local selectedOutput = 1

local function getExtraArgs()
  local extra = noctalia.getConfig("extra_args") or ""
  if noctalia.string.trim(extra) ~= "" then
    return " " .. extra
  end
  return ""
end

local function startMirror(target)
  if not noctalia.commandExists("wl-mirror") then
    noctalia.notifyError("WL Mirror", "wl-mirror no esta instalado")
    return
  end
  noctalia.runAsync("wl-mirror " .. target .. getExtraArgs())
  noctalia.notify("WL Mirror", "Espejando " .. target)
end

local function stopMirror()
  noctalia.runAsync("pkill -x wl-mirror")
  noctalia.notify("WL Mirror", "Deteniendo espejo")
end

local function getOutputNames()
  local names = {}
  for _, out in outputs do
    local label = out.name
    if out.description and out.description ~= "" then
      label = out.description .. " (" .. out.name .. ")"
    end
    table.insert(names, label)
  end
  return names
end

local function render()
  local outputNames = getOutputNames()

  local mirrorSection
  if #outputNames == 0 then
    mirrorSection = ui.column({ gap = 8 }, {
      ui.label({ text = "Mirror", fontWeight = "medium", color = "on_surface_variant" }),
      ui.label({ text = "No outputs detected", color = "on_surface_variant" }),
    })
  else
    mirrorSection = ui.column({ gap = 8 }, {
      ui.label({ text = "Mirror", fontWeight = "medium", color = "on_surface_variant" }),
      ui.select({
        options = outputNames,
        selectedIndex = selectedOutput - 1,
        onChange = "onOutputSelect",
      }),
      ui.button({
        text = running and "Stop Mirror" or "Start Mirror",
        glyph = running and "player-stop" or "player-play",
        variant = running and "destructive" or "primary",
        onClick = "onMirrorToggle",
      }),
    })
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

    mirrorSection,

    ui.separator({}),

    ui.column({ gap = 8 }, {
      ui.label({ text = "Window", fontWeight = "medium", color = "on_surface_variant" }),
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
  selectedOutput = 1
  render()
end

function onCloseClicked()
  panel.close()
end

function onOutputSelect(index)
  selectedOutput = (tonumber(index) or 0) + 1
end

function onMirrorToggle()
  if running then
    stopMirror()
    return
  end
  local out = outputs[selectedOutput]
  if out then
    startMirror(out.name)
  end
end

function onWindowClick()
  if running then
    stopMirror()
    return
  end
  if not noctalia.commandExists("wl-mirror") then
    noctalia.notifyError("WL Mirror", "wl-mirror no esta instalado")
    return
  end
  noctalia.runAsync("wl-mirror portal:window" .. getExtraArgs())
  noctalia.notify("WL Mirror", "Selecciona una ventana...")
end

noctalia.state.watch("running", function(value)
  running = value == true
  render()
end)
