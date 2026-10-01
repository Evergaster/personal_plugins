--!nonstrict
-- Blobatar panel - the [[panel]] entry, and the only keyboard-capable surface.
--
-- Desktop widgets cannot take focus, so typed input (the name field) lives
-- here. The panel drives the service exclusively through noctalia.state and
-- renders whatever the service reports; it holds no independent state beyond
-- the text the user is currently editing.
--
-- Note on the name field: plugin settings are edited in Noctalia's settings UI
-- and a plugin cannot write them, so typing a name here sends SET_NAME to the
-- service, which stores the override in its own data dir and uses it in place
-- of the `name` setting until it is cleared.

local EXPRESSIONS = {
  "idle", "happy", "sad", "mad", "surprised", "wink", "sleepy", "smug",
  "unsure", "scared", "love", "shy", "sick", "thinking",
}

local focusState = "IDLE"
local focusRemaining = 0
local focusFormatted = "0"
local expression = "idle"
local reasonKey = "reason.idle"
local override = ""
local petName = "evergaster"
local errorMessage = ""
local avatar = ""

local battery = -1
local charging = false
local cpu = -1
local ram = -1
local dnd = false

-- The text currently in the name input. The input is uncontrolled, so this is
-- the only way to read it back; `nameKey` is bumped when the name changes from
-- outside (initial load, or a service-side change) so the field re-seeds.
local nameDraft = ""
local nameKey = 0

-------------------------------------------------------------------- helpers

local function batteryLabel()
  if battery < 0 then
    return noctalia.tr("ui.unknown")
  end
  if charging then
    return noctalia.tr("ui.battery_charging", { value = battery })
  end
  return noctalia.tr("ui.battery_level", { value = battery })
end

local function expressionIndex(value)
  for i, e in ipairs(EXPRESSIONS) do
    if e == value then
      return i - 1
    end
  end
  return 0
end

------------------------------------------------------------------- sections

local function renderPreview()
  if avatar == "" then
    return ui.box({
      width = 96,
      height = 96,
      radius = 12,
      fill = "surface_variant/0.4",
      justify = "center",
    }, {})
  end
  return ui.image({
    key = `preview:{avatar}`,
    path = avatar,
    width = 96,
    height = 96,
    fit = "contain",
  })
end

local function renderIdentity()
  return ui.column({ gap = 8, padding = 12, fill = "surface_variant/0.4", radius = 10 }, {
    ui.row({ gap = 12 }, {
      renderPreview(),
      ui.column({ gap = 4, flexGrow = 1 }, {
        ui.label({ text = petName, fontSize = 16, fontWeight = "bold" }),
        ui.label({
          text = noctalia.tr(reasonKey),
          fontSize = 12,
          color = "outline",
          maxLines = 2,
        }),
        ui.label({
          text = expression,
          fontSize = 11,
          color = "outline",
        }),
      }),
    }),
    ui.input({
      key = `name:{nameKey}`,
      value = nameDraft,
      placeholder = noctalia.tr("ui.name_placeholder"),
      onChange = function(value)
        nameDraft = value
      end,
      onSubmit = function(value)
        nameDraft = value
        applyName()
      end,
    }),
    ui.row({ gap = 8 }, {
      ui.button({
        text = noctalia.tr("ui.apply"),
        variant = "primary",
        controlSize = "sm",
        onClick = "onApplyName",
      }),
      ui.button({
        text = noctalia.tr("ui.use_setting"),
        variant = "ghost",
        controlSize = "sm",
        onClick = "onResetName",
      }),
    }),
  })
end

local function renderFocus()
  local running = focusState == "RUNNING"
  local busy = running or focusState == "PAUSED"
  local label = running
    and noctalia.tr("ui.pause")
    or (focusState == "PAUSED" and noctalia.tr("ui.resume") or noctalia.tr("ui.start"))

  return ui.column({ gap = 8, padding = 12, fill = "surface_variant/0.4", radius = 10 }, {
    ui.row({ justify = "space_between" }, {
      ui.label({ text = noctalia.tr("ui.focus"), fontSize = 13, fontWeight = "bold" }),
      ui.label({
        text = busy and focusFormatted or noctalia.tr("ui.idle_label"),
        fontSize = 20,
        fontWeight = "bold",
        color = busy and "primary" or "outline",
      }),
    }),
    ui.progress({
      progress = (focusState == "DONE") and 0 or
        (focusRemaining > 0 and (noctalia.state.get("pet.focus.duration") or 0) > 0
          and focusRemaining / noctalia.state.get("pet.focus.duration")
          or 0),
      height = 4,
      radius = 2,
    }),
    ui.row({ gap = 8 }, {
      ui.button({
        text = label,
        variant = running and "secondary" or "primary",
        controlSize = "sm",
        onClick = "onToggleFocus",
      }),
      ui.button({
        text = noctalia.tr("ui.reset"),
        variant = "destructive",
        controlSize = "sm",
        onClick = "onResetFocus",
      }),
    }),
  })
end

local function renderMood()
  local options = { noctalia.tr("ui.expression_auto") }
  for _, e in ipairs(EXPRESSIONS) do
    table.insert(options, noctalia.tr(`expression.{e}`))
  end

  -- A select is value-driven, so it needs the index of the live override, with
  -- 0 reserved for "auto".
  local selected = 0
  if override ~= "" then
    selected = expressionIndex(override) + 1
  end

  return ui.column({ gap = 8, padding = 12, fill = "surface_variant/0.4", radius = 10 }, {
    ui.label({ text = noctalia.tr("ui.mood"), fontSize = 13, fontWeight = "bold" }),
    ui.select({
      options = options,
      selectedIndex = selected,
      onChange = "onExpressionChange",
    }),
  })
end

local function renderStats()
  return ui.column({ gap = 4, padding = 12, fill = "surface_variant/0.4", radius = 10 }, {
    ui.label({ text = noctalia.tr("ui.machine"), fontSize = 13, fontWeight = "bold" }),
    ui.label({
      text = noctalia.tr("ui.cpu_value", { value = cpu < 0 and "?" or cpu }),
      fontSize = 12,
      color = "outline",
    }),
    ui.label({
      text = noctalia.tr("ui.ram_value", { value = ram < 0 and "?" or ram }),
      fontSize = 12,
      color = "outline",
    }),
    ui.label({
      text = batteryLabel(),
      fontSize = 12,
      color = "outline",
    }),
    dnd and ui.label({
      text = noctalia.tr("ui.dnd_on"),
      fontSize = 12,
      color = "error",
    }) or ui.label({
      text = noctalia.tr("ui.dnd_off"),
      fontSize = 12,
      color = "outline",
    }),
    errorMessage ~= "" and ui.label({
      text = noctalia.tr("ui.offline_warning"),
      fontSize = 12,
      color = "error",
    }) or nil,
  })
end

----------------------------------------------------------------------- render

local function render()
  local rows = {}
  for _, child in ipairs({
    renderIdentity(),
    renderFocus(),
    renderMood(),
    renderStats(),
  }) do
    table.insert(rows, child)
  end
  panel.render(ui.column({ gap = 10, padding = 16 }, rows))
end

-------------------------------------------------------------------- actions

local function applyName()
  local value = noctalia.string.trim(nameDraft)
  if value == "" then
    return
  end
  noctalia.state.set("pet.name_value", value)
  noctalia.state.set("pet.cmd", "SET_NAME")
end

function onApplyName()
  applyName()
end

function onResetName()
  noctalia.state.set("pet.cmd", "CLEAR_NAME")
end

function onToggleFocus()
  if focusState == "RUNNING" then
    noctalia.state.set("pet.cmd", "PAUSE")
  else
    noctalia.state.set("pet.cmd", "START")
  end
end

function onResetFocus()
  noctalia.state.set("pet.cmd", "RESET")
end

function onExpressionChange(index, text)
  local i = tonumber(index) or 0
  if i <= 0 then
    noctalia.state.set("pet.cmd", "CLEAR_OVERRIDE")
    return
  end
  local value = EXPRESSIONS[i]
  if value == nil then
    return
  end
  noctalia.state.set("pet.override_value", value)
  noctalia.state.set("pet.cmd", "SET_OVERRIDE")
end

--------------------------------------------------------------- state wiring

noctalia.state.watch("pet.name", function(value)
  local next = value or "evergaster"
  if next == petName then
    return
  end
  petName = next
  nameDraft = next
  nameKey += 1
  render()
end)

noctalia.state.watch("pet.avatar", function(value)
  avatar = value or ""
  render()
end)

noctalia.state.watch("pet.expression", function(value)
  expression = value or "idle"
  render()
end)

noctalia.state.watch("pet.reason", function(value)
  reasonKey = value or "reason.idle"
  render()
end)

noctalia.state.watch("pet.override", function(value)
  override = value or ""
  render()
end)

noctalia.state.watch("pet.error", function(value)
  errorMessage = value or ""
  render()
end)

noctalia.state.watch("pet.focus.state", function(value)
  focusState = value or "IDLE"
  render()
end)

noctalia.state.watch("pet.focus.remaining", function(value)
  focusRemaining = tonumber(value) or 0
  render()
end)

noctalia.state.watch("pet.focus.formatted", function(value)
  focusFormatted = value or "0"
  render()
end)

noctalia.state.watch("pet.dnd", function(value)
  dnd = value == true
  render()
end)

noctalia.state.watch("pet.battery", function(value)
  battery = tonumber(value) or -1
  render()
end)

noctalia.state.watch("pet.charging", function(value)
  charging = value == true
  render()
end)

noctalia.state.watch("pet.cpu", function(value)
  cpu = tonumber(value) or -1
  render()
end)

noctalia.state.watch("pet.ram", function(value)
  ram = tonumber(value) or -1
  render()
end)

------------------------------------------------------------------- lifecycle

function onOpen()
  -- The panel is only open briefly, but a timer left running should not keep
  -- re-rendering it for nothing.
  panel.setWantsSecondTicks(true)
  render()
end

function onClose()
  panel.setWantsSecondTicks(false)
end

function update()
  render()
end

------------------------------------------------------------------- bootstrap

petName = noctalia.state.get("pet.name") or "evergaster"
nameDraft = petName
avatar = noctalia.state.get("pet.avatar") or ""
expression = noctalia.state.get("pet.expression") or "idle"
reasonKey = noctalia.state.get("pet.reason") or "reason.idle"
override = noctalia.state.get("pet.override") or ""
errorMessage = noctalia.state.get("pet.error") or ""
focusState = noctalia.state.get("pet.focus.state") or "IDLE"
focusRemaining = tonumber(noctalia.state.get("pet.focus.remaining")) or 0
focusFormatted = noctalia.state.get("pet.focus.formatted") or "0"
dnd = noctalia.state.get("pet.dnd") == true
battery = tonumber(noctalia.state.get("pet.battery")) or -1
charging = noctalia.state.get("pet.charging") == true
cpu = tonumber(noctalia.state.get("pet.cpu")) or -1
ram = tonumber(noctalia.state.get("pet.ram")) or -1

render()
