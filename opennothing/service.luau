--!nonstrict
-- service.luau — Audifonos Nothing/CMF controlados via el CLI openNothing.
--
-- Es el unico entry que habla con el dispositivo Bluetooth. Hace poll del
-- estado (bateria, ANC, firmware) y ejecuta en serie las escrituras que el
-- widget/panel publican en el canal "opennothing.command". Publica el
-- snapshot en "opennothing.status".

local SNAPSHOT = "opennothing.status"
local COMMAND  = "opennothing.command"

local snapshot = {
  available = false,
  busy = false,
  model = "",
  firmware = "",
  anc = "",
  lowLatency = nil,
  bassBoost = nil,
  bassLevel = nil,
  spatial = nil,
  tracking = nil,
  eq = "",
  battery = { left = nil, right = nil, case = nil },
  lastError = "",
}

local queue = {}
local busy = false

-- Declaraciones previas: hay referencias circulares (run -> process ->
-- runCommand -> read/set -> run), asi que todos los helpers se reasignan
-- abajo con `local function`.
local process
local run
local runCommand
local finishBusy
local readStatus
local readAnc
local readLowLatency
local readBass
local readSpatial
local readEq
local setAnc
local setLowLatency
local setBass
local setSpatial
local setEq

local function trim(s)
  return ((s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function dbg(msg)
  pcall(noctalia.log, "[opennothing] " .. tostring(msg))
end

local function publish()
  noctalia.state.set(SNAPSHOT, snapshot)
  dbg(string.format(
    "publish available=%s battery=L:%s R:%s C:%s anc=%s model=%s busying=%s err=%s",
    tostring(snapshot.available),
    tostring(snapshot.battery.left),
    tostring(snapshot.battery.right),
    tostring(snapshot.battery.case),
    tostring(snapshot.anc),
    tostring(snapshot.model),
    tostring(snapshot.busy),
    tostring(snapshot.lastError)
  ))
end

local function baseArgs()
  local args = {
    noctalia.getConfig("command") or "opennothing",
    "--mac", noctalia.getConfig("mac") or "2C:BE:EE:70:76:30",
    "--channel", tostring(tonumber(noctalia.getConfig("channel")) or 15),
    "--model", noctalia.getConfig("model") or "B172",
    "--timeout", tostring(tonumber(noctalia.getConfig("timeout")) or 5.0),
  }
  if noctalia.getConfig("scripted") == true then
    table.insert(args, "--scripted")
  end
  return args
end

local function enqueue(item)
  table.insert(queue, item)
  process()
end

-- Solo un comando a la vez (el canal RFCOMM no soporta concurrencia).
-- "read_all" se expande en la cadena ordenada de lecturas, en la cola.
process = function()
  if busy then
    return
  end
  local item = table.remove(queue, 1)
  if item == nil then
    if snapshot.busy then
      snapshot.busy = false
      publish()
    end
    return
  end
  if type(item) == "table" and item.action == "read_all" then
    local order = {
      "read_status",
      "read_low_latency",
      "read_bass",
      "read_spatial",
      "read_eq",
    }
    for i = #order, 1, -1 do
      table.insert(queue, 1, { action = order[i] })
    end
    process()
    return
  end
  snapshot.busy = true
  busy = true
  publish()
  runCommand(item)
end

run = function(args, onDone)
  local ok = noctalia.runAsync(args, function(result)
    busy = false
    if result.exitCode ~= 0 then
      local err = trim(result.stderr)
      snapshot.lastError = err ~= "" and err or ("salida " .. tostring(result.exitCode))
      snapshot.available = false
    end
    onDone(result)
    process()
  end)
  if not ok then
    busy = false
    snapshot.lastError = "no se pudo ejecutar " .. tostring(args[1])
    snapshot.available = false
    publish()
    process()
  end
end

local function parseStatus(stdout)
  local o = { battery = {} }
  for line in (stdout or ""):gmatch("[^\r\n]+") do
    local m = line:match("^modelo:%s*(.*)$")
    if m then o.model = trim(m) end
    m = line:match("^firmware:%s*(.*)$")
    if m then o.firmware = trim(m) end
    m = line:match("^ANC:%s*(%S+)")
    if m then o.anc = trim(m) end
    local side, pct = line:match("^bateria%s+(left|right|case):%s*(%d+)%%")
    if side then o.battery[side] = tonumber(pct) end
  end
  return o
end

readStatus = function()
  local args = baseArgs()
  table.insert(args, "status")
  run(args, function(result)
    local raw = tostring(result.stdout or "")
    local errText = tostring(result.stderr or "")
    if #errText > 0 then
      raw = raw .. " [stderr=" .. errText .. "]"
    end
    dbg("status exit=" .. tostring(result.exitCode) .. " out=" .. raw)
    if result.exitCode == 0 then
      local o = parseStatus(result.stdout or "")
      snapshot.model = o.model or snapshot.model
      snapshot.firmware = o.firmware or snapshot.firmware
      if o.anc then snapshot.anc = o.anc end
      if o.battery.left ~= nil then snapshot.battery.left = o.battery.left end
      if o.battery.right ~= nil then snapshot.battery.right = o.battery.right end
      if o.battery.case ~= nil then snapshot.battery.case = o.battery.case end
      if o.anc or o.model or o.firmware then
        snapshot.available = true
        snapshot.lastError = ""
      end
      dbg(string.format(
        "status parsed modelo=%s anc=%s batL=%s batR=%s batC=%s",
        tostring(snapshot.model),
        tostring(snapshot.anc),
        tostring(snapshot.battery.left),
        tostring(snapshot.battery.right),
        tostring(snapshot.battery.case)
      ))
    end
    publish()
  end)
end

readAnc = function()
  local args = baseArgs()
  table.insert(args, "anc")
  run(args, function(result)
    if result.exitCode == 0 then
      local name = (result.stdout or ""):match("^ANC:%s*(%S+)")
      if name then
        snapshot.anc = name
        snapshot.available = true
        snapshot.lastError = ""
      end
    end
    publish()
  end)
end

readLowLatency = function()
  local args = baseArgs()
  table.insert(args, "low-latency")
  run(args, function(result)
    if result.exitCode == 0 then
      local v = (result.stdout or ""):match("^low%-latency:%s*(on|off)")
      if v then
        snapshot.lowLatency = v == "on"
        snapshot.available = true
        snapshot.lastError = ""
      end
    end
    publish()
  end)
end

readBass = function()
  local args = baseArgs()
  table.insert(args, "bass-boost")
  run(args, function(result)
    if result.exitCode == 0 then
      local v, lvl = (result.stdout or ""):match("^bass%-boost:%s*(on|off)%s+nivel=(%d+)")
      if v then
        snapshot.bassBoost = v == "on"
        snapshot.bassLevel = tonumber(lvl) or snapshot.bassLevel
        snapshot.available = true
        snapshot.lastError = ""
      end
    end
    publish()
  end)
end

readSpatial = function()
  local args = baseArgs()
  table.insert(args, "spatial-audio")
  run(args, function(result)
    if result.exitCode == 0 then
      local v, tr = (result.stdout or ""):match("^spatial:%s*(on|off)%s+tracking=(%S+)")
      if v then
        snapshot.spatial = v == "on"
        snapshot.tracking = tr == "on"
        snapshot.available = true
        snapshot.lastError = ""
      end
    end
    publish()
  end)
end

readEq = function()
  local args = baseArgs()
  table.insert(args, "eq")
  run(args, function(result)
    if result.exitCode == 0 then
      local name = (result.stdout or ""):match("^EQ:%s*(.+)$")
      if name then
        snapshot.eq = trim(name)
        snapshot.available = true
        snapshot.lastError = ""
      end
    end
    publish()
  end)
end

setAnc = function(mode)
  local args = baseArgs()
  table.insert(args, "anc")
  table.insert(args, tostring(mode))
  run(args, function(result)
    if result.exitCode == 0 then
      local name = (result.stdout or ""):match("ANC ahora:%s*(%S+)")
      if name then
        snapshot.anc = name
        snapshot.available = true
        snapshot.lastError = ""
        publish()
      end
    end
  end)
end

setLowLatency = function(value)
  local args = baseArgs()
  table.insert(args, "low-latency")
  table.insert(args, value and "on" or "off")
  run(args, function(result)
    if result.exitCode == 0 then
      snapshot.lowLatency = value
      snapshot.available = true
      snapshot.lastError = ""
    end
    publish()
  end)
end

setBass = function(value, level)
  local args = baseArgs()
  table.insert(args, "bass-boost")
  table.insert(args, value and "on" or "off")
  if value and level ~= nil then
    table.insert(args, "--level")
    table.insert(args, tostring(level))
  end
  run(args, function(result)
    if result.exitCode == 0 then
      snapshot.bassBoost = value
      if level ~= nil then
        snapshot.bassLevel = level
      end
      snapshot.available = true
      snapshot.lastError = ""
    end
    publish()
  end)
end

setSpatial = function(value, tracking)
  local args = baseArgs()
  table.insert(args, "spatial-audio")
  table.insert(args, value and "on" or "off")
  if tracking ~= nil then
    table.insert(args, "--tracking")
    table.insert(args, tracking and "on" or "off")
  end
  run(args, function(result)
    if result.exitCode == 0 then
      snapshot.spatial = value
      if tracking ~= nil then
        snapshot.tracking = tracking
      end
      snapshot.available = true
      snapshot.lastError = ""
    end
    publish()
  end)
end

setEq = function(preset)
  local args = baseArgs()
  table.insert(args, "eq")
  table.insert(args, tostring(preset))
  run(args, function(result)
    if result.exitCode == 0 then
      local name = (result.stdout or ""):match("^EQ:%s*(.+)$")
      if name then
        snapshot.eq = trim(name)
      end
      snapshot.available = true
      snapshot.lastError = ""
    end
    publish()
  end)
end

finishBusy = function()
  busy = false
  process()
end

runCommand = function(item)
  local action = tostring(item.action or "")
  if action == "read_status" then
    readStatus()
  elseif action == "read_anc" then
    readAnc()
  elseif action == "read_low_latency" then
    readLowLatency()
  elseif action == "read_bass" then
    readBass()
  elseif action == "read_spatial" then
    readSpatial()
  elseif action == "read_eq" then
    readEq()
  elseif action == "set_anc" then
    setAnc(item.mode)
  elseif action == "set_low_latency" then
    setLowLatency(item.value == true)
  elseif action == "set_bass" then
    setBass(item.value == true, item.level)
  elseif action == "set_spatial" then
    setSpatial(item.value == true, item.tracking)
  elseif action == "set_eq" then
    setEq(item.preset)
  else
    finishBusy()
  end
end

-- Entradas que llegan desde widget/panel.
noctalia.state.watch(COMMAND, function(msg)
  if type(msg) == "table" and msg.nonce ~= nil then
    enqueue(msg)
  end
end)

local function poll()
  enqueue({ action = "read_status" })
end

local pollMs = tonumber(noctalia.getConfig("poll_interval_ms")) or 60000
noctalia.setUpdateInterval(pollMs)

function update()
  poll()
end

function onConfigChanged()
  local newPoll = tonumber(noctalia.getConfig("poll_interval_ms")) or 60000
  if newPoll ~= pollMs then
    pollMs = newPoll
    noctalia.setUpdateInterval(pollMs)
  end
  if noctalia.commandExists(noctalia.getConfig("command") or "opennothing") then
    poll()
  end
end

publish()
if noctalia.commandExists(noctalia.getConfig("command") or "opennothing") then
  poll()
else
  snapshot.lastError = "opennothing no encontrado en PATH"
  publish()
end