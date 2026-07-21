--!nonstrict
-- panel.luau — Panel desplegable del bar widget.
-- Selector de source (que monitor clonar) y destination (donde mostrar la ventana).

local running = false
local outputs = {}
local sourceIndex = 1
local destIndex = 1
local fullscreen = false
local dataDir = nil

local function getDataDir()
  if dataDir == nil then
    dataDir = noctalia.pluginDataDir()
  end
  return dataDir
end

local function loadState()
  local dir = getDataDir()
  if dir == nil then return end
  local ok, raw = pcall(noctalia.readFile, dir .. "/panel.json")
  if ok and raw then
    local decodeOk, data = pcall(noctalia.json.decode, raw)
    if decodeOk and data then
      if data.fullscreen ~= nil then
        fullscreen = data.fullscreen == true or data.fullscreen == "true"
      end
      if data.sourceIndex ~= nil then
        sourceIndex = tonumber(data.sourceIndex) or 1
      end
      if data.destIndex ~= nil then
        destIndex = tonumber(data.destIndex) or 1
      end
    end
  end
end

local function saveState()
  local dir = getDataDir()
  if dir == nil then return end
  noctalia.mkdirAll(dir)
  noctalia.writeFile(dir .. "/panel.json", noctalia.json.encode({
    fullscreen = fullscreen,
    sourceIndex = sourceIndex,
    destIndex = destIndex,
  }))
end

local function getExtraArgs()
  local extra = noctalia.getConfig("extra_args") or ""
  if noctalia.string.trim(extra) ~= "" then
    return " " .. extra
  end
  return ""
end

local function startMirror(source, destination)
  if not noctalia.commandExists("wl-mirror") then
    noctalia.notifyError("WL Mirror", "wl-mirror no esta instalado")
    return
  end

  local args = ""
  if fullscreen then
    args = " --fullscreen"
  end
  local extra = getExtraArgs()
  if extra ~= "" then
    args = args .. extra
  end

  if destination and noctalia.commandExists("niri") then
    noctalia.runAsync(string.format("niri msg action focus-output '%s' 2>/dev/null || true", destination))
    noctalia.runAsync(string.format("sleep 0.5 && niri msg action spawn-sh 'setsid wl-mirror%s %s' 2>/dev/null", args, source))
  elseif destination and noctalia.commandExists("hyprctl") then
    noctalia.runAsync(string.format("setsid wl-mirror%s %s >/dev/null 2>&1 &", args, source))
    noctalia.runAsync(string.format(
      "sleep 2 && hyprctl dispatch focuswindow 'wl-mirror' 2>/dev/null && hyprctl dispatch movewindow 'monitor:%s' 2>/dev/null",
      destination
    ))
  else
    noctalia.runAsync(string.format("setsid wl-mirror%s %s >/dev/null 2>&1 &", args, source))
  end

  noctalia.notify("WL Mirror", "Espejando " .. source .. " en " .. (destination or "monitor actual"))
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
      ui.label({ text = "Monitor", fontWeight = "medium", color = "on_surface_variant" }),
      ui.label({ text = "No outputs detected", color = "on_surface_variant" }),
    })
  else
    mirrorSection = ui.column({ gap = 12 }, {
      ui.column({ gap = 4 }, {
        ui.label({ text = "Clone from", fontWeight = "medium", color = "on_surface_variant" }),
        ui.select({
          options = outputNames,
          selectedIndex = sourceIndex - 1,
          onChange = "onSourceSelect",
        }),
      }),
      ui.column({ gap = 4 }, {
        ui.label({ text = "Show on", fontWeight = "medium", color = "on_surface_variant" }),
        ui.select({
          options = outputNames,
          selectedIndex = destIndex - 1,
          onChange = "onDestSelect",
        }),
      }),
      ui.row({ align = "center", gap = 8 }, {
        ui.toggle({ checked = fullscreen, onChange = "onFullscreenToggle" }),
        ui.label({ text = "Fullscreen", flexGrow = 1 }),
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
  }))
end

function onOpen(_context)
  loadState()
  outputs = noctalia.outputs() or {}
  if sourceIndex > #outputs then sourceIndex = 1 end
  if destIndex > #outputs then destIndex = 1 end
  render()
end

function onCloseClicked()
  panel.close()
end

function onSourceSelect(index)
  sourceIndex = (tonumber(index) or 0) + 1
  saveState()
  render()
end

function onDestSelect(index)
  destIndex = (tonumber(index) or 0) + 1
  saveState()
  render()
end

function onFullscreenToggle(value)
  fullscreen = value == "true"
  saveState()
  render()
end

function onMirrorToggle()
  if running then
    stopMirror()
    return
  end
  local src = outputs[sourceIndex]
  local dst = outputs[destIndex]
  if src then
    startMirror(src.name, dst and dst.name or nil)
  else
    noctalia.notifyError("WL Mirror", "No output selected")
  end
end

noctalia.state.watch("running", function(value)
  running = value == true
  render()
end)
