--!nonstrict
-- Blobatar desktop widget - a [[desktop_widget]] client of the pet service.
--
-- This entry draws and animates; it owns no mood logic. The service decides the
-- expression and publishes a *local* SVG path, which is what ui.image can
-- display (ui.image never loads a URL).
--
-- The animation is a deliberate imitation of the web client: a volume-preserving
-- breath, a vertical bob riding on it, a slow lateral sway, and a squash-and-hop
-- reaction to taps and mood changes.
--
-- Noctalia's UI has no transform, so the motion is assembled from the primitives
-- that do exist. A non-uniform width/height with fit="stretch" squashes the
-- picture; a fixed-size container with justify="start" turns paddingV into a
-- real vertical offset, and paddingH with align="center" into a lateral one.
-- Both offsets start from a centred inset so the blob never walks out of the
-- fixed widget box and gets clipped.
--
--   desktopWidget.render(tree)          declarative UI tree
--   desktopWidget.setNeedsFrameTick()   request onFrameTick(deltaMs)
--   noctalia.getConfig(key)             per-widget settings
--   noctalia.state.watch(key, fn)       react to service state
--   ui.image onClick = "name"           calls a plugin global

local widgetSize = tonumber(noctalia.getConfig("widget_size")) or 128
local animate = noctalia.getConfig("animate") ~= false
local showProgress = noctalia.getConfig("show_progress") ~= false
local showStatus = noctalia.getConfig("show_status") ~= false
local accent = noctalia.getConfig("accent") or "primary"

-- Breathing, matching the amplitudes the web client uses: the blob widens while
-- it rises and narrows as it settles, so the silhouette changes but the area
-- roughly does not.
local BREATH_PERIOD_MS = 3600
local BREATH_X = 0.022
local BREATH_Y = 0.018

-- A second, slower cycle on the lateral axis. If it shared the breath's period
-- the two would read as one loop, so the periods are deliberately coprime-ish.
local SWAY_PERIOD_MS = 7300
local SWAY_UNITS = 0.8

-- The idle loop is kept subtle and the hover loop is allowed to be a little
-- wider, which is what gives the web version its "it noticed you" feeling.
local IDLE_AMP = 1
local HOVER_AMP = 1.5

-- The blob is drawn smaller than the box so the bob, sway and hop all have room
-- to move without the fixed widget box clipping them. The leftover margin is
-- also what the motion offsets are measured from.
local BASE_FILL = 0.8
local HOP_UNITS = 7
local HOP_MS = 620

-- Geometry is rounded to a fraction of a pixel. The pet is slow art, so the
-- frame tick could re-render 100 times a second to move the blob by an amount
-- nobody can see; coarser steps land near 20 re-renders a second while the
-- motion still reads as continuous.
local QUANTUM = 0.4

-- How long a mood-change pop takes to settle.
local POP_MS = 420

local avatar = ""
local expression = "idle"
local reasonKey = "reason.idle"
local errorMessage = ""

local focusState = "IDLE"
local focusRemaining = 0
local focusDuration = 0
local focusFormatted = "0"

local battery = -1
local charging = false
local cpu = -1
local ram = -1
local dnd = false

local clock = 0
local popUntil = 0
local hopUntil = 0
local hovered = false
-- Last geometry handed to the render, so the frame tick can tell whether
-- anything visible actually moved.
local lastGeo = nil
-- Bumped whenever the avatar path changes so ui.image is forced to reload the
-- file rather than reusing the previous texture.
--
-- This is the ONLY thing that may change the image source, and it changes only
-- when the mood does. Changing it for any other reason makes the node blank for
-- a frame while the new file is decoded, which reads as the pet blinking out of
-- existence several times a minute. Blink and eye-look poses were built on top
-- of this same mechanism and were removed for that reason; see the animation
-- notes in README.md.
local avatarKey = ""



--------------------------------------------------------------- derived text

local function focusPercent()
  if focusDuration <= 0 then
    return 0
  end
  return math.max(0, math.min(1, focusRemaining / focusDuration))
end

local function statusLine()
  if errorMessage ~= "" then
    return noctalia.tr("ui.status_offline")
  end
  if focusState == "RUNNING" then
    return focusFormatted
  end
  if focusState == "PAUSED" then
    return noctalia.tr("ui.status_paused")
  end
  if focusState == "DONE" then
    return noctalia.tr("ui.status_done")
  end
  if dnd then
    return noctalia.tr("ui.status_dnd")
  end
  return noctalia.tr(reasonKey)
end

-------------------------------------------------------------------- animation

local function quantize(value)
  return math.floor(value / QUANTUM + 0.5) * QUANTUM
end

-- One tap's worth of motion, as a fraction of the widget size. Returns the
-- vertical offset in user units (negative is up) and a squash multiplier.
--
-- The shape is a launch followed by two diminishing bounces. Fading the
-- amplitude with (1-u)^2 keeps the blob from settling with a visible wobble,
-- and a short anticipation dip at the very start reads as the pet gathering
-- itself before it jumps rather than simply snapping upward.
local function hopCurve(u)
  if u >= 1 then
    return 0, 1
  end
  local bounces = math.sin(u * math.pi * 3) * (1 - u) * (1 - u)
  local offset = -HOP_UNITS * bounces

  -- Anticipation: compress downward for the first slice of the hop.
  local ANTICIPATION = 0.16
  if u < ANTICIPATION then
    local a = 1 - (u / ANTICIPATION)
    offset += HOP_UNITS * 0.28 * a * a
  end

  -- Rising stretches the blob, so counter-scale the width to keep the area even.
  local squash = 1 + 0.11 * bounces
  return offset, squash
end

-- Everything the renderer needs for one frame, in pixels. A nil return means
-- animation is switched off and the blob should be drawn at rest.
local function geometry(nowMs)
  if not animate then
    return nil
  end

  local amp = hovered and HOVER_AMP or IDLE_AMP
  local unit = widgetSize / 100

  local breath = math.sin(clock / BREATH_PERIOD_MS * 2 * math.pi)
  local sway = math.sin(clock / SWAY_PERIOD_MS * 2 * math.pi + 1.1) * SWAY_UNITS * amp

  local scaleX = 1 + BREATH_X * breath * amp
  local scaleY = 1 - BREATH_Y * breath * amp

  -- The bob rides the breath and is deliberately asymmetric: the blob rises a
  -- little further than it falls, which reads as breathing rather than bouncing.
  local bob = (-1.5 * breath - 0.4 * breath * math.abs(breath)) * unit * amp

  local offsetX = 0
  local offsetY = 0

  -- A mood change gets a short swell; a tap gets the full hop.
  if popUntil > nowMs then
    local t = 1 - (popUntil - nowMs) / POP_MS
    local hump = math.sin(t * math.pi)
    scaleX += 0.05 * hump
    scaleY -= 0.04 * hump
    bob -= 2.2 * hump * unit
  end

  if hopUntil > nowMs then
    local u = 1 - (hopUntil - nowMs) / HOP_MS
    local offset, squash = hopCurve(u)
    offsetY += offset * unit
    scaleX /= squash
    scaleY *= squash
  end

  local base = widgetSize * BASE_FILL
  local inset = (widgetSize - base) / 2

  return {
    width = quantize(base * scaleX),
    height = quantize(base * scaleY),
    padH = quantize(sway * unit + inset),
    padV = quantize(bob + offsetY + inset),
  }
end

-- True when the frame changed enough to be worth re-rendering.
local function geometryChanged(geo)
  if geo == nil or lastGeo == nil then
    return geo ~= lastGeo
  end
  return geo.width ~= lastGeo.width
    or geo.height ~= lastGeo.height
    or geo.padH ~= lastGeo.padH
    or geo.padV ~= lastGeo.padV
end

----------------------------------------------------------------------- render

local function render()
  local children = {}
  local geo = geometry(noctalia.nowMs())
  lastGeo = geo

  if avatar ~= "" and geo == nil then
    table.insert(children, ui.image({
      key = avatarKey,
      path = avatar,
      width = widgetSize,
      height = widgetSize,
      fit = "contain",
      onClick = "onPoke",
    }))
  elseif avatar ~= "" then
    -- justify="start" makes paddingV a plain vertical offset from the top of
    -- the box, and align="center" with paddingH shifts the blob sideways.
    -- stretch is what makes a non-uniform width/height squash the picture
    -- instead of letterboxing it.
    table.insert(children, ui.column({
      width = widgetSize,
      height = widgetSize,
      justify = "start",
      align = "center",
      paddingH = geo.padH,
      paddingV = geo.padV,
    }, {
      ui.image({
        key = avatarKey,
        path = avatar,
        width = geo.width,
        height = geo.height,
        fit = "stretch",
        onClick = "onPoke",
        onHover = "onHoverBlob",
      }),
    }))
  else
    -- Nothing cached yet (first launch, or offline). A visible placeholder
    -- beats an empty box so the widget does not look broken.
    table.insert(children, ui.glyph({
      name = "ghost",
      size = widgetSize,
      color = "outline",
    }))
  end

  if showProgress and focusState ~= "IDLE" and focusDuration > 0 then
    table.insert(children, ui.progress({
      progress = focusPercent(),
      fill = focusState == "DONE" and "error" or accent,
      width = widgetSize,
      height = 4,
      radius = 2,
    }))
  end

  if showStatus then
    table.insert(children, ui.label({
      text = statusLine(),
      fontSize = 11,
      color = "outline",
      textAlign = "center",
      maxLines = 1,
    }))
  end

  desktopWidget.render(ui.column({ gap = 6, align = "center", width = widgetSize }, children))
end

-- Re-renders from the current state. Called from the frame tick and from every
-- state change.
local function refresh()
  render()
end

---------------------------------------------------------------- entry callbacks

function onFrameTick(deltaMs)
  if not animate then
    return
  end
  clock = (clock + deltaMs) % 1000000

  local nowMs = noctalia.nowMs()
  if geometryChanged(geometry(nowMs)) then
    refresh()
  end
end

-- The pointer being over the pet is the signal the web client uses to raise its
-- motion amplitude, so hovering here buys a slightly wider, livelier idle.
function onHoverBlob(entered)
  local next = entered == true
  if next == hovered then
    return
  end
  hovered = next
  refresh()
end

function onPoke()
  -- Immediate reaction so the tap registers even if the new SVG is still
  -- downloading; the service also flips the pet to "surprised" briefly.
  local now = noctalia.nowMs()
  hopUntil = now + HOP_MS
  popUntil = now + POP_MS
  refresh()
  noctalia.state.set("pet.cmd", "POKE")
end

----------------------------------------------------------------- state wiring

noctalia.state.watch("pet.avatar", function(value)
  if value == avatar then
    return
  end
  avatar = value or ""
  avatarKey = `{expression}:{avatar}`
  refresh()
end)

noctalia.state.watch("pet.expression", function(value)
  local next = value or "idle"
  if next == expression then
    return
  end
  expression = next
  local now = noctalia.nowMs()
  popUntil = now + POP_MS
  -- A mood change is a bigger event than a swell, so it also gets most of a
  -- hop. Without this the expression swap reads as a flicker rather than a
  -- reaction.
  hopUntil = now + HOP_MS
  refresh()
end)

noctalia.state.watch("pet.reason", function(value)
  reasonKey = value or "reason.idle"
  render()
end)

noctalia.state.watch("pet.poke_id", function()
  -- The service echoes every poke, including the ones a panel button sends, so
  -- the hop fires wherever the interaction came from.
  local now = noctalia.nowMs()
  popUntil = now + POP_MS
  hopUntil = now + HOP_MS
  refresh()
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

noctalia.state.watch("pet.focus.duration", function(value)
  focusDuration = tonumber(value) or 0
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
end)

noctalia.state.watch("pet.charging", function(value)
  charging = value == true
end)

noctalia.state.watch("pet.cpu", function(value)
  cpu = tonumber(value) or -1
end)

noctalia.state.watch("pet.ram", function(value)
  ram = tonumber(value) or -1
end)

------------------------------------------------------------------- bootstrap

avatar = noctalia.state.get("pet.avatar") or ""
expression = noctalia.state.get("pet.expression") or "idle"
reasonKey = noctalia.state.get("pet.reason") or "reason.idle"
errorMessage = noctalia.state.get("pet.error") or ""
focusState = noctalia.state.get("pet.focus.state") or "IDLE"
focusRemaining = tonumber(noctalia.state.get("pet.focus.remaining")) or 0
focusDuration = tonumber(noctalia.state.get("pet.focus.duration")) or 0
focusFormatted = noctalia.state.get("pet.focus.formatted") or "0"
dnd = noctalia.state.get("pet.dnd") == true
battery = tonumber(noctalia.state.get("pet.battery")) or -1
charging = noctalia.state.get("pet.charging") == true
cpu = tonumber(noctalia.state.get("pet.cpu")) or -1
ram = tonumber(noctalia.state.get("pet.ram")) or -1

-- The avatar is read once, here, and then only ever changed by the pet.avatar
-- watcher below. Nothing else is allowed to swap the image source: every change
-- reloads the texture and blanks the node for a frame.
avatarKey = `{expression}:{avatar}`

if animate then
  desktopWidget.setNeedsFrameTick(true)
  -- Second ticks keep the countdown label honest without polling state.
  desktopWidget.setWantsSecondTicks(true)
end

refresh()

function update()
  -- Re-read the clock each second so a long-running widget cannot drift away
  -- from the service's own countdown label.
  local remaining = tonumber(noctalia.state.get("pet.focus.remaining")) or 0
  if remaining ~= focusRemaining then
    focusRemaining = remaining
    render()
  end
end
