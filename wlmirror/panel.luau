--!nonstrict
-- panel.luau — Panel desplegable del bar widget.
-- Mirror — selector de outputs + checkbox fullscreen persistente.

local running = false
local outputs = {}
local selectedOutput = 1
local fullscreen = false
local dataDir = nil

local function getDataDir()
  if dataDir == nil then
    dataDir = noctalia.pluginDataDir()
  end
  return dataDir
end

local function loadFullscreen()
  local dir = getDataDir()
  if dir == nil then return end
  local ok, raw = pcall(noctalia.readFile, dir .. "/panel.json")
  if ok and raw then
    local decodeOk, data = pcall(noctalia.json.decode, raw)
    if decodeOk and data and data.fullscreen ~= nil then
      fullscreen = data.fullscreen == true or data.fullscreen == "true"
    end
  end
end

local function saveFullscreen()
  local dir = getDataDir()
  if dir == nil then return end
  noctalia.mkdirAll(dir)
  noctalia.writeFile(dir .. "/panel.json", noctalia.json.encode({ fullscreen = fullscreen }))
end

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
  local cmd = "wl-mirror"
  if fullscreen then
    cmd = cmd .. " --fullscreen"
  end
  cmd = cmd .. " " .. target
  local extra = getExtraArgs()
  if extra ~= "" then
    cmd = cmd .. extra
  end
  noctalia.log("Running: " .. cmd)
  noctalia.runAsync(cmd, function(result)
    if result.exitCode ~= 0 then
      noctalia.log("wl-mirror exit " .. tostring(result.exitCode) .. ": " .. (result.stderr or ""))
    end
  end)
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
  loadFullscreen()
  outputs = noctalia.outputs() or {}
  selectedOutput = 1
  noctalia.log("Panel opened, outputs: " .. tostring(#outputs))
  render()
end

function onCloseClicked()
  panel.close()
end

function onOutputSelect(index)
  selectedOutput = (tonumber(index) or 0) + 1
  render()
end

function onFullscreenToggle(value)
  fullscreen = value == "true"
  saveFullscreen()
  render()
end

function onMirrorToggle()
  if running then
    stopMirror()
    return
  end
  local out = outputs[selectedOutput]
  if out then
    noctalia.log("Selected output: " .. out.name)
    startMirror(out.name)
  else
    noctalia.notifyError("WL Mirror", "No output selected")
  end
end

noctalia.state.watch("running", function(value)
  running = value == true
  render()
end)
