--!nonstrict
-- panel.luau — Panel de control de los audifonos: bateria, ANC, graves,
-- baja latencia, audio espacial y EQ. Todo pasa por el servicio via el canal
-- "opennothing.command" para no hablar dos veces con el dispositivo a la vez.

local SNAPSHOT = "opennothing.status"
local COMMAND  = "opennothing.command"

local snap = noctalia.state.get(SNAPSHOT) or {
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

local ANC_NORMALIZE = {
  alto = "alto",
  medio = "medio",
  bajo = "bajo",
  adaptativo = "adaptativo",
  desactivado = "off",
  transparencia = "transparencia",
  high = "alto",
  mid = "medio",
  low = "bajo",
  adaptive = "adaptativo",
  off = "off",
  transparency = "transparencia",
}

local ANC_OPTIONS = {
  { value = "alto", key = "anc.high" },
  { value = "medio", key = "anc.mid" },
  { value = "bajo", key = "anc.low" },
  { value = "adaptativo", key = "anc.adaptive" },
  { value = "off", key = "anc.off" },
  { value = "transparencia", key = "anc.transparency" },
}

local EQ_NORMALIZE = {
  balanceado = "balanced",
  ["mas bajos"] = "more_bass",
  ["mas agudos"] = "more_treble",
  voz = "voice",
  personalizado = "custom",
  balanced = "balanced",
  more_bass = "more_bass",
  more_treble = "more_treble",
  voice = "voice",
  custom = "custom",
}

local EQ_OPTIONS = {
  { value = "balanced", key = "eq.balanced" },
  { value = "more_bass", key = "eq.more_bass" },
  { value = "more_treble", key = "eq.more_treble" },
  { value = "voice", key = "eq.voice" },
  { value = "custom", key = "eq.custom" },
}

local function ancIndex(current)
  local canon = ANC_NORMALIZE[(current or ""):lower()]
  for i, o in ipairs(ANC_OPTIONS) do
    if o.value == canon then
      return i - 1
    end
  end
  return -1
end

local function eqIndex(current)
  local canon = EQ_NORMALIZE[(current or ""):lower()]
  for i, o in ipairs(EQ_OPTIONS) do
    if o.value == canon then
      return i - 1
    end
  end
  return -1
end

local function labelTexts(list)
  local out = {}
  for _, o in ipairs(list) do
    table.insert(out, noctalia.tr(o.key))
  end
  return out
end

local function send(msg)
  msg.nonce = string.format("%d%03d", os.time(), math.random(0, 999))
  noctalia.state.set(COMMAND, msg)
end

local function lowColor(side)
  local t = tonumber(noctalia.getConfig("low_battery_threshold")) or 20
  local v = snap.battery[side]
  if v ~= nil and v <= t then
    return "#e67e80"
  end
  return "primary"
end

local function batteryCell(title, side)
  local v = snap.battery[side]
  local pct = v == nil and 0 or v
  local text = v == nil and "—" or (string.format("%d%%", v))
  return ui.column({ gap = 4, flexGrow = 1, align = "center" }, {
    ui.label({ text = title, fontSize = 11, color = "on_surface_variant" }),
    ui.progress({ progress = pct / 100, width = 92, height = 8, radius = 4, fill = lowColor(side) }),
    ui.label({ text = text, fontSize = 12, fontWeight = "bold" }),
  })
end

local function sectionTitle(text)
  return ui.label({ text = text, fontSize = 11, fontWeight = "bold", color = "on_surface_variant" })
end

local function statusText()
  if not snap.available then
    if snap.lastError ~= "" then
      return noctalia.tr("ui.disconnected") .. ": " .. snap.lastError
    end
    return noctalia.tr("ui.disconnected")
  end
  local parts = {}
  if snap.model and snap.model ~= "" then
    table.insert(parts, snap.model)
  end
  if snap.firmware and snap.firmware ~= "" then
    table.insert(parts, "fw " .. snap.firmware)
  end
  if snap.anc and snap.anc ~= "" then
    table.insert(parts, "ANC " .. snap.anc)
  end
  local base = table.concat(parts, " · ")
  if snap.busy then
    base = base .. " · " .. noctalia.tr("ui.updating")
  end
  return base
end

local function render()
  local busy = snap.busy == true
  local bassOn = snap.bassBoost == true
  local spatialOn = snap.spatial == true

  panel.render(ui.column({ flexGrow = 1, gap = 10 }, {
    ui.row({ align = "center", justify = "space_between", gap = 8 }, {
      ui.row({ align = "center", gap = 6 }, {
        ui.glyph({ name = "ear", color = "primary", size = 18 }),
        ui.label({ text = noctalia.tr("ui.title"), fontSize = 15, fontWeight = "bold", color = "on_surface" }),
      }),
      ui.row({ gap = 6 }, {
        ui.button({ glyph = "refresh", enabled = not busy, onClick = "onRefresh" }),
        ui.button({ glyph = "close", onClick = "onCloseClicked" }),
      }),
    }),

    ui.scroll({ flexGrow = 1, gap = 14 }, {

      ui.column({ gap = 6 }, {
        sectionTitle(noctalia.tr("battery.header")),
        ui.row({ gap = 8 }, {
          batteryCell(noctalia.tr("battery.left"), "left"),
          batteryCell(noctalia.tr("battery.right"), "right"),
          batteryCell(noctalia.tr("battery.case"), "case"),
        }),
      }),

      ui.separator({ thickness = 1, color = "surface_variant" }),

      ui.column({ gap = 6 }, {
        sectionTitle(noctalia.tr("anc.header")),
        ui.select({
          options = labelTexts(ANC_OPTIONS),
          selectedIndex = ancIndex(snap.anc),
          placeholder = noctalia.tr("anc.header"),
          enabled = not busy,
          onChange = "onAncSelect",
        }),
      }),

      ui.separator({ thickness = 1, color = "surface_variant" }),

      ui.column({ gap = 6 }, {
        sectionTitle(noctalia.tr("bass.header")),
        ui.row({ align = "center", gap = 8 }, {
          ui.toggle({ checked = bassOn, enabled = not busy, onChange = "onBassToggle" }),
          ui.label({ text = noctalia.tr("bass.toggle"), flexGrow = 1 }),
        }),
        ui.row({ align = "center", gap = 8 }, {
          ui.label({ text = noctalia.tr("bass.level"), width = 56, color = "on_surface_variant", fontSize = 12 }),
          ui.slider({
            min = 0,
            max = 10,
            step = 1,
            value = snap.bassLevel or 0,
            enabled = not busy and bassOn,
            onChange = "onBassLevel",
          }),
          ui.label({
            text = tostring(snap.bassLevel or 0),
            width = 24,
            color = "on_surface_variant",
            fontSize = 12,
            textAlign = "end",
          }),
        }),
      }),

      ui.separator({ thickness = 1, color = "surface_variant" }),

      ui.column({ gap = 6 }, {
        sectionTitle(noctalia.tr("latency.header")),
        ui.row({ align = "center", gap = 8 }, {
          ui.toggle({ checked = snap.lowLatency == true, enabled = not busy, onChange = "onLowLatencyToggle" }),
          ui.label({ text = noctalia.tr("latency.toggle"), flexGrow = 1 }),
        }),
      }),

      ui.separator({ thickness = 1, color = "surface_variant" }),

      ui.column({ gap = 6 }, {
        sectionTitle(noctalia.tr("spatial.header")),
        ui.row({ align = "center", gap = 8 }, {
          ui.toggle({ checked = spatialOn, enabled = not busy, onChange = "onSpatialToggle" }),
          ui.label({ text = noctalia.tr("spatial.toggle"), flexGrow = 1 }),
        }),
        ui.row({ align = "center", gap = 8 }, {
          ui.toggle({ checked = snap.tracking == true, enabled = not busy and spatialOn, onChange = "onTrackingToggle" }),
          ui.label({ text = noctalia.tr("spatial.tracking"), flexGrow = 1 }),
        }),
      }),

      ui.separator({ thickness = 1, color = "surface_variant" }),

      ui.column({ gap = 6 }, {
        sectionTitle(noctalia.tr("eq.header")),
        ui.select({
          options = labelTexts(EQ_OPTIONS),
          selectedIndex = eqIndex(snap.eq),
          placeholder = noctalia.tr("eq.header"),
          enabled = not busy,
          onChange = "onEqSelect",
        }),
      }),

    }),

    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({
        name = "ear",
        size = 14,
        color = snap.available and "primary" or "#e67e80",
      }),
      ui.label({ text = statusText(), fontSize = 11, color = "on_surface_variant", flexGrow = 1 }),
    }),
  }))
end

function onOpen(_context)
  snap = noctalia.state.get(SNAPSHOT) or snap
  pcall(noctalia.log, string.format(
    "[opennothing:panel] onOpen available=%s battery=L:%s R:%s C:%s anc=%s",
    tostring(snap.available),
    tostring(snap.battery and snap.battery.left),
    tostring(snap.battery and snap.battery.right),
    tostring(snap.battery and snap.battery.case),
    tostring(snap.anc)
  ))
  render()
  send({ action = "read_all" })
end

function onCloseClicked()
  panel.close()
end

function onRefresh()
  send({ action = "read_all" })
end

function onAncSelect(index)
  local i = tonumber(index)
  local opt = ANC_OPTIONS[i and (i + 1) or 1]
  if opt then
    send({ action = "set_anc", mode = opt.value })
  end
end

function onBassToggle(value)
  send({ action = "set_bass", value = value == "true" })
end

function onBassLevel(value)
  local level = math.floor(tonumber(value) or 0)
  level = math.clamp(level, 0, 10)
  send({ action = "set_bass", value = true, level = level })
end

function onLowLatencyToggle(value)
  send({ action = "set_low_latency", value = value == "true" })
end

function onSpatialToggle(value)
  send({ action = "set_spatial", value = value == "true" })
end

function onTrackingToggle(value)
  send({ action = "set_spatial", value = snap.spatial == true, tracking = value == "true" })
end

function onEqSelect(index)
  local i = tonumber(index)
  local opt = EQ_OPTIONS[i and (i + 1) or 1]
  if opt then
    send({ action = "set_eq", preset = opt.value })
  end
end

noctalia.state.watch(SNAPSHOT, function(val)
  if type(val) == "table" then
    snap = val
    render()
  end
end)

function update()
  render()
end

render()