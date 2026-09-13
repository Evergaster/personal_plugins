--!nonstrict
-- widget.luau — Widget de barra: bateria de los audifonos + acceso al panel.

local SNAPSHOT = "opennothing.status"

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

local function pct(side)
  local v = snap.battery[side]
  return v == nil and 0 or v
end

local function threshold()
  return tonumber(noctalia.getConfig("low_battery_threshold")) or 20
end

local function onOff(v)
  if v == nil then return "—" end
  return v and "on" or "off"
end

local function defaultColor()
  return "#7aa2f7"
end

local function render()
  barWidget.setGlyph("ear")
  if not snap.available then
    barWidget.setGlyphColor("#6b7280")
    barWidget.setText("")
    barWidget.setTooltip({
      { key = "Nothing Buds", value = noctalia.tr("ui.disconnected") },
    })
    return
  end

  local left = pct("left")
  local right = pct("right")
  local t = threshold()
  local known = snap.battery.left ~= nil or snap.battery.right ~= nil
  local low = known and (left <= t or right <= t)

  barWidget.setGlyphColor(low and "#e67e80" or defaultColor())

  if noctalia.getConfig("show_percent") == false then
    barWidget.setText("")
  else
    barWidget.setText(string.format("%d%% %d%%", left, right))
  end

  local rows = {
    { key = noctalia.tr("battery.left"), value = string.format("%d%%", left) },
    { key = noctalia.tr("battery.right"), value = string.format("%d%%", right) },
    { key = noctalia.tr("battery.case"), value = string.format("%d%%", pct("case")) },
  }
  if snap.anc ~= "" then
    table.insert(rows, { key = "ANC", value = snap.anc })
  end
  if snap.lowLatency ~= nil then
    table.insert(rows, { key = noctalia.tr("latency.toggle"), value = onOff(snap.lowLatency) })
  end
  if snap.bassBoost ~= nil then
    local v = onOff(snap.bassBoost)
    if snap.bassBoost and snap.bassLevel ~= nil then
      v = v .. " · " .. tostring(snap.bassLevel)
    end
    table.insert(rows, { key = noctalia.tr("bass.toggle"), value = v })
  end
  if snap.spatial ~= nil then
    table.insert(rows, { key = noctalia.tr("spatial.toggle"), value = onOff(snap.spatial) })
  end
  barWidget.setTooltip(rows)
end

noctalia.state.watch(SNAPSHOT, function(val)
  if type(val) == "table" then
    snap = val
    pcall(noctalia.log, string.format(
      "[opennothing:widget] watch available=%s battery=L:%s R:%s C:%s",
      tostring(val.available),
      tostring(val.battery and val.battery.left),
      tostring(val.battery and val.battery.right),
      tostring(val.battery and val.battery.case)
    ))
render()
pcall(noctalia.log, string.format(
  "[opennothing:widget] initial available=%s battery=L:%s R:%s C:%s",
  tostring(snap.available),
  tostring(snap.battery and snap.battery.left),
  tostring(snap.battery and snap.battery.right),
  tostring(snap.battery and snap.battery.case)
))
  end
end)

function update()
  noctalia.setUpdateInterval(15000)
  render()
end

function onClick()
  noctalia.togglePanel("evergaster/opennothing:panel")
end

render()