--!nonstrict
-- Blobatar service - the headless [[service]] entry.
--
-- This entry owns everything that has to survive without a UI attached:
--
--   1. The mood engine. Samples battery / CPU / RAM / do-not-disturb plus the
--      shared focus timer and decides which Blobatar *expression* the pet
--      should hold. Expressions have a priority order (see decideExpression),
--      so a rare event like a 3% battery outranks a permanent one like "RAM
--      is 70% used".
--   2. The avatar cache. Blobatar renders SVG over HTTPS; ui.image only
--      accepts *local* files, so the service downloads each distinct
--      (name, expression, size, background, gen, hue, tone) tuple into
--      pluginDataDir/avatars/ and publishes the resulting local path. The
--      filename is a hash of the request parameters, so a mood switch only
--      costs one small GET the first time it is seen, and nothing afterwards.
--   3. The focus (pomodoro) timer, which the panel and the desktop widget
--      both drive through commands and read back as state.
--
-- It publishes to other entries via noctalia.state and listens for commands:
--
--   pet.expression   current expression (a Blobatar expression id)
--   pet.reason       translation key explaining the current expression
--   pet.avatar       absolute local path of the cached SVG ("" when absent)
--   pet.ready        true once an avatar has been resolved at least once
--   pet.error        last download error message ("" when healthy)
--   pet.battery      battery percent, or -1 when unknown
--   pet.charging     true while the battery is charging
--   pet.cpu          cpu usage percent, or -1 when unknown
--   pet.ram          ram usage percent, or -1 when unknown
--   pet.dnd          true while do-not-disturb is on
--   pet.focus.state  IDLE | RUNNING | PAUSED | DONE
--   pet.focus.remaining  seconds left
--   pet.focus.duration   the countdown total captured at start
--   pet.focus.formatted  "MM:SS" for the remaining time
--   pet.override     forced expression from the panel ("" = automatic)
--   pet.cmd          command channel: START | PAUSE | RESET | SET_OVERRIDE |
--                    CLEAR_OVERRIDE | POKE
--
-- pet.poke_id increments on every POKE so a client can react to the tap even
-- when the resulting expression matches the one already on screen.

local TICK_MS = 1000
-- How often the slower, more expensive probes run, in ticks. DND needs a
-- subprocess; battery needs a couple of sysfs reads. Neither needs 1Hz.
local DND_EVERY = 30
local BATTERY_EVERY = 10

local EXPRESSIONS = {
  "idle", "happy", "sad", "mad", "surprised", "wink", "sleepy", "smug",
  "unsure", "scared", "love", "shy", "sick", "thinking",
}

local FOCUS_STATE_IDLE = "IDLE"
local FOCUS_STATE_RUNNING = "RUNNING"
local FOCUS_STATE_PAUSED = "PAUSED"
local FOCUS_STATE_DONE = "DONE"

noctalia.setUpdateInterval(TICK_MS)

---------------------------------------------------------------------- helpers

local function trim(s)
  if s == nil then
    return ""
  end
  return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The avatar path is a single path segment, so a name containing "/" has to be
-- percent-encoded: blobatar returns 400 for "a/b" but 200 for "a%2Fb". We do
-- the encoding by hand rather than trusting noctalia.string.urlEncode, which is
-- specified for query values, not path segments.
local function encodeName(name)
  return (tostring(name):gsub("[^%w%-%.%_%~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- djb2, mod a prime. Used only to turn a request tuple into a stable cache
-- filename, so collision resistance is not a security property here. Written
-- with plain arithmetic rather than FNV's bitwise mix: the Luau runtime
-- noctalia ships rejects `~` at parse time.
local function hashKey(s)
  local h = 5381
  for i = 1, #s do
    h = (h * 33 + string.byte(s, i)) % 1000000007
  end
  return string.format("%08x", h)
end

local function isExpression(value)
  for _, e in ipairs(EXPRESSIONS) do
    if e == value then
      return true
    end
  end
  return false
end

local function formatTime(seconds)
  local m = seconds // 60
  local s = seconds % 60
  if m >= 60 then
    return `{m // 60}:{string.format("%02d", m % 60)}:{string.format("%02d", s)}`
  end
  return `{m}:{string.format("%02d", s)}`
end

----------------------------------------------------------------- local state

local name = "evergaster"
-- A panel-level override of the `name` setting. Plugin settings live in the
-- Noctalia settings UI and a plugin cannot write them, so typing a new name in
-- the panel goes here instead and is persisted next to the avatar cache.
local nameOverride = ""
local size = 256
local background = "none"
local gen = "2"
local hue = 0
local tone = 0.5
local lockHue = false
local lockTone = false
local reactions = true
local pomodoroMinutes = 25
local notifyEnabled = true

local focusState = FOCUS_STATE_IDLE
local focusRemaining = 0
local focusDuration = 0

local override = ""
local expression = "idle"
local expressionChangedAtMs = 0
local reason = "reason.idle"
-- Wall-clock deadline for a one-off POKE reaction. Kept out of the override
-- channel so a tap never sticks.
local pokeUntilMs = 0
local pokeId = 0

local battery = -1
local charging = false
local cpu = -1
local ram = -1
local dnd = false

-- The cache key whose download is currently in flight, and the key we last
-- published. A single in-flight slot is deliberate: while a mood switch is
-- being fetched we keep showing the previous avatar rather than flashing
-- nothing, and we coalesce further switches onto the newest key.
local pendingKey = ""
local currentKey = ""
local currentAvatar = ""

local tick = 0
local batteryPath = ""

-- Resolved once by ensureDirs() at startup. Declared up here rather than next
-- to ensureDirs because saveProfile/loadProfile above need to reach them; a
-- local declared further down is not in scope up here and would silently
-- resolve to a nil global, turning the path into the literal "nil/profile.json".
local dataDir = ""
local avatarDir = ""

------------------------------------------------------------------- config

-- The name actually sent to Blobatar: the panel override when one is set,
-- otherwise the plugin setting.
local function effectiveName()
  if nameOverride ~= "" then
    return nameOverride
  end
  return name
end

local function saveProfile()
  if dataDir == "" then
    return
  end
  local encoded = noctalia.json.encode({ name = nameOverride })
  if encoded == nil then
    return
  end
  noctalia.writeFile(`{dataDir}/profile.json`, encoded)
end

local function loadProfile()
  if dataDir == "" then
    return
  end
  local contents = noctalia.readFile(`{dataDir}/profile.json`)
  if contents == nil then
    return
  end
  local decoded = noctalia.json.decode(contents)
  if type(decoded) == "table" and type(decoded.name) == "string" then
    nameOverride = trim(decoded.name)
  end
end

local function readConfig()
  name = trim(noctalia.getConfig("name"))
  if name == "" then
    name = "evergaster"
  end

  size = tonumber(noctalia.getConfig("size")) or 256
  background = tostring(noctalia.getConfig("background") or "none")
  gen = tostring(noctalia.getConfig("gen") or "2")
  hue = tonumber(noctalia.getConfig("hue")) or 0
  tone = (tonumber(noctalia.getConfig("tone")) or 50) / 100
  lockHue = noctalia.getConfig("lock_hue") == true
  lockTone = noctalia.getConfig("lock_tone") == true
  reactions = noctalia.getConfig("reactions") ~= false
  pomodoroMinutes = tonumber(noctalia.getConfig("pomodoro_minutes")) or 25
  notifyEnabled = noctalia.getConfig("notify") ~= false

  -- A changed name, size, or palette invalidates the cache key, so the next
  -- ensureAvatar() refetches. The previously published path is deliberately
  -- left in place: ui.image keeps showing the old avatar until the new file
  -- lands, which reads better than a blank box.
  currentKey = ""
  currentAvatar = ""
end

------------------------------------------------------------------ mood rules
--
-- Ordered most-specific first; the first match wins. Keeping this a flat list
-- (rather than a scoring system) makes "what does the pet look like when X?"
-- answerable by reading top to bottom.

local function decideExpression()
  -- A manual choice from the panel outranks every automatic rule.
  if override ~= "" and isExpression(override) then
    return override, "reason.manual"
  end

  -- A tap is a transient reaction: it outranks the ambient rules for a couple
  -- of seconds and then the rules take the pet back.
  if pokeUntilMs > 0 and noctalia.nowMs() < pokeUntilMs then
    return "surprised", "reason.poke"
  end

  if not reactions then
    return "idle", "reason.idle"
  end

  -- Focus states first: the pomodoro is the reason the pet exists.
  if focusState == FOCUS_STATE_RUNNING then
    return "thinking", "reason.focus"
  end
  if focusState == FOCUS_STATE_DONE then
    return "love", "reason.focus_done"
  end
  if focusState == FOCUS_STATE_PAUSED then
    return "unsure", "reason.focus_paused"
  end

  -- Do-not-disturb beats the ambient stats: the user asked for quiet, and a
  -- busy CPU is exactly what DND is meant to be hiding.
  if dnd then
    return "sleepy", "reason.dnd"
  end

  -- Battery is the one rule worth escalating, so it gets two tiers. Charging
  -- cancels the low-battery moods entirely.
  if not charging then
    if battery >= 0 and battery <= 10 then
      return "scared", "reason.battery_critical"
    end
    if battery >= 0 and battery <= 20 then
      return "sad", "reason.battery_low"
    end
  end

  if cpu >= 90 then
    return "mad", "reason.cpu_high"
  end
  if ram >= 90 then
    return "unsure", "reason.ram_high"
  end

  -- A quiet machine is happy, but only when something else did not already
  -- claim a mood. Keeps the default from being a dead stare.
  if cpu >= 0 and cpu <= 20 and ram >= 0 and ram <= 60 then
    return "smug", "reason.relaxed"
  end

  return "idle", "reason.idle"
end

------------------------------------------------------------- avatar resolve

local function ensureDirs()
  local dir = noctalia.pluginDataDir()
  if dir == nil then
    return false
  end
  dataDir = dir
  avatarDir = `{dir}/avatars`
  noctalia.mkdirAll(avatarDir)
  return true
end

-- Builds the Blobatar request for one expression. Parameters are appended in a
-- fixed order so the cache key below is stable for a given configuration.
local function avatarUrl(expr)
  local params = {
    `expression={expr}`,
    `size={size}`,
  }
  if background ~= "none" then
    table.insert(params, `background={background}`)
  end
  if gen ~= "" then
    table.insert(params, `gen={gen}`)
  end
  if lockHue then
    table.insert(params, `hue={hue}`)
  end
  if lockTone then
    -- The setting is 0-100 because that is a friendlier slider, but the endpoint
    -- takes tone as a 0-1 position in its swatch set. Sending 50 gets a 400.
    -- 1 is the top edge and renders as 0, so the maximum lands just under it.
    local normalized = tone / 100
    if normalized > 0.999 then
      normalized = 0.999
    end
    table.insert(params, `tone={normalized}`)
  end
  return `https://blobatar.dev/avatar/{encodeName(effectiveName())}?{table.concat(params, "&")}`
end

-- Publishes the expression only when it actually changed. update() runs at 1Hz
-- and the expression is usually stable, so the equality check keeps the widget
-- from re-rendering once a second for no reason.
local function publishExpression()
  local nextExpression, nextReason = decideExpression()
  if nextExpression == expression and nextReason == reason then
    return
  end
  local previousExpression = expression
  expression = nextExpression
  reason = nextReason
  -- Stamp the change so ensureAvatar() can wait for the mood to settle before
  -- spending a request on it. A reason-only change keeps the old stamp: the
  -- picture did not change, so it should not restart the settle window.
  if nextExpression ~= previousExpression then
    expressionChangedAtMs = noctalia.nowMs()
  end
  noctalia.state.set("pet.expression", expression)
  noctalia.state.set("pet.reason", reason)
end

-- NOTE: the body/eye layer split and the pre-composed blink and look poses that
-- stood here are gone. ui.image renders one flat file and there is no compositor,
-- so the only way to move the eyes was to swap the image source between
-- pre-rendered poses. Every swap reloads the texture and blanks the node for a
-- frame, which made the pet vanish and reappear several times a minute. Keeping
-- the pet permanently visible wins over eye motion.

-- A new expression is only fetched once it has held still for this long.
-- Expression changes are one request each, so a value oscillating around a
-- threshold (e.g. CPU hovering at 90) would otherwise re-download forever. The
-- widget keeps the previous avatar meanwhile, which is the behaviour we want
-- anyway: the old expression is a better picture than no picture.
local EXPRESSION_SETTLE_MS = 700

-- Upper bound on cached avatars. The key space is (name x expression x size x
-- background x gen x hue x tone); hue is a 0-360 slider, so a user dragging it
-- can generate keys without limit. Pruned oldest-mtime-first.
local MAX_CACHED_AVATARS = 40

-- Drops the least recently used avatars down to the cap. Never removes the one
-- currently published to pet.avatar. Cache limits are counted in avatars, not
-- files, and a key's files are always removed as a group so a half-deleted
-- avatar can never be left behind.
--
-- ABANDONED: an earlier version split each avatar into body/eye files and then
-- into whole-avatar pose files (base, blink, look_*). Both were removed: the
-- layer split is unused and the poses made the pet flicker when swapped. Their
-- suffixes are still listed here purely so that entryKey groups those leftover
-- files with their avatar, letting the sweep below reclaim them instead of
-- leaving them counted as separate avatars in the cache forever.
local ABANDONED_SUFFIXES = {
  base = true,
  blink = true,
  look_left = true,
  look_right = true,
  look_up = true,
  look_down = true,
  body = true,
  eye1 = true,
  eye2 = true,
}

-- Lua patterns have no alternation, so the two suffix shapes are tried apart.
local ABANDONED_RES = {
  "^.+_(eye%d+)%.svg$",
  "^.+_(body)%.svg$",
}

local function isAbandoned(entry)
  for _, pattern in ipairs(ABANDONED_RES) do
    if string.match(entry, pattern) ~= nil then
      return true
    end
  end
  local _, suffix = string.match(entry, "^(.+)_(%a[%w_]*)%.svg$")
  return suffix ~= nil and ABANDONED_SUFFIXES[suffix] == true
end

local function entryKey(name)
  local key, suffix = string.match(name, "^(.+)_(%a[%w_]*)%.svg$")
  if key ~= nil and ABANDONED_SUFFIXES[suffix] == true then
    return key
  end
  return string.match(name, "^(.+)%.svg$")
end

local function pruneAvatarCache()
  if avatarDir == "" then
    return
  end
  local entries = noctalia.listDir(avatarDir)
  if entries == nil then
    return
  end

  local groups = {}
  for _, entry in ipairs(entries) do
    local path = `{avatarDir}/{entry}`

    -- Files from the abandoned layer split and pose set. Nothing references
    -- them any more, and leaving them would make the cache grow unbounded.
    if isAbandoned(entry) then
      noctalia.removeFile(path)
    else
      local key = entryKey(entry)
      if key ~= nil then
        local info = noctalia.fileInfo(path)
        if info ~= nil and info.isDir ~= true then
          local group = groups[key]
          if group == nil then
            group = { mtime = 0, paths = {} }
            groups[key] = group
          end
          local mtime = info.mtime or 0
          if mtime > group.mtime then
            group.mtime = mtime
          end
          table.insert(group.paths, path)
        end
      end
    end
  end

  local keys = {}
  for key in pairs(groups) do
    table.insert(keys, key)
  end
  if #keys <= MAX_CACHED_AVATARS then
    return
  end

  table.sort(keys, function(a, b)
    return groups[a].mtime < groups[b].mtime
  end)

  local excess = #keys - MAX_CACHED_AVATARS
  for i = 1, math.min(excess, #keys) do
    local key = keys[i]
    -- Never evict the avatar currently on screen, even if it is somehow the
    -- oldest; that would leave the widget showing a broken picture.
    if `{avatarDir}/{key}.svg` ~= currentAvatar then
      for _, path in ipairs(groups[key].paths) do
        noctalia.removeFile(path)
      end
    end
  end
end

-- Makes sure `pet.avatar` points at a local file for the current expression,
-- downloading it if this exact request has never been seen. Returns without
-- touching state when a download for a different key is already in flight, so
-- rapid mood changes collapse into one request instead of a pile-up.
local function ensureAvatar()
  if avatarDir == "" and not ensureDirs() then
    return
  end

  local url = avatarUrl(expression)
  local key = hashKey(url)

  if key == currentKey then
    -- Republish on every pass so a running service always shows the file on disk
    -- even if it was cached before this session started. This also makes the
    -- first paint after a reload independent of whether the avatar is still in
    -- the cache.
    local path = `{avatarDir}/{key}.svg`
    if noctalia.fileExists(path) then
      currentAvatar = path
      noctalia.state.set("pet.avatar", path)
    end
    return
  end
  if pendingKey ~= "" then
    return
  end

  local path = `{avatarDir}/{key}.svg`
  if noctalia.fileExists(path) then
    currentKey = key
    currentAvatar = path
    noctalia.state.set("pet.avatar", path)
    noctalia.state.set("pet.error", "")
    noctalia.state.set("pet.ready", true)
    return
  end

  -- Already cached expressions are free, so they are served immediately. Only
  -- an expression we have to go to the network for waits to settle first.
  if noctalia.nowMs() - expressionChangedAtMs < EXPRESSION_SETTLE_MS then
    return
  end

  pendingKey = key
  noctalia.download(url, path, function(ok)
    pendingKey = ""
    if ok ~= true then
      -- Leave currentKey alone so a mood change during the failed request is
      -- still detected, and let the next tick retry.
      noctalia.state.set("pet.error", "download_failed")
      return
    end
    currentKey = key
    currentAvatar = path
    noctalia.state.set("pet.avatar", path)
    noctalia.state.set("pet.error", "")
    noctalia.state.set("pet.ready", true)
    pruneAvatarCache()
  end)
end

---------------------------------------------------------------- battery probe

local POWER_SUPPLY = "/sys/class/power_supply"

-- Finds the first BAT* device. Reuses the resolved directory across ticks since
-- the kernel does not hot-swap battery names in practice.
local function findBatteryPath()
  if batteryPath ~= "" then
    return batteryPath
  end
  local entries = noctalia.listDir(POWER_SUPPLY)
  if entries == nil then
    return ""
  end
  for _, entry in ipairs(entries) do
    if string.sub(entry, 1, 3) == "BAT" then
      batteryPath = `{POWER_SUPPLY}/{entry}/capacity`
      return batteryPath
    end
  end
  return ""
end

local function readBattery()
  local path = findBatteryPath()
  if path == "" then
    battery = -1
    noctalia.state.set("pet.battery", battery)
    return
  end

  -- status lives next to capacity and distinguishes "Charging" from
  -- "Discharging"; without it a charging battery would still look critical.
  local statusPath = string.gsub(path, "capacity$", "status")

  noctalia.readFileAsync(path, function(contents)
    local percent = tonumber(trim(contents))
    if percent ~= nil then
      battery = math.floor(percent)
      noctalia.state.set("pet.battery", battery)
    end
  end)

  noctalia.readFileAsync(statusPath, function(contents)
    local status = trim(contents):lower()
    charging = status == "charging" or status == "full"
    noctalia.state.set("pet.charging", charging)
  end)
end

------------------------------------------------------------------- dnd probe

-- Do-not-disturb is not exposed in the config file, only over IPC, so this
-- shells out. DND_EVERY keeps that to one process every 30s.
local function readDnd()
  noctalia.runAsync({ "noctalia", "msg", "notification-dnd-status" }, function(result)
    if result.exitCode ~= 0 then
      return
    end
    local value = trim(result.stdout):lower()
    dnd = value == "on" or value == "true" or value == "1"
    noctalia.state.set("pet.dnd", dnd)
  end)
end

---------------------------------------------------------------- focus timer

local function setFocusState(next)
  focusState = next
  noctalia.state.set("pet.focus.state", focusState)
  noctalia.state.set("pet.focus.formatted", formatTime(focusRemaining))
end

local function setFocusRemaining(seconds)
  focusRemaining = math.max(0, seconds)
  noctalia.state.set("pet.focus.remaining", focusRemaining)
  noctalia.state.set("pet.focus.formatted", formatTime(focusRemaining))
end

local function finishFocus()
  setFocusRemaining(0)
  setFocusState(FOCUS_STATE_DONE)
  if notifyEnabled then
    noctalia.notify(
      noctalia.tr("ui.notify_title"),
      noctalia.tr("ui.notify_body")
    )
  end
end

local function tickFocus()
  if focusState ~= FOCUS_STATE_RUNNING then
    return
  end
  if focusRemaining > 0 then
    setFocusRemaining(focusRemaining - 1)
  else
    finishFocus()
  end
end

-------------------------------------------------------------- command channel

-- Single entry point for every command, so the state channel (panel, widget)
-- and the IPC channel (CLI, keybindings) cannot drift apart. `value` is the
-- optional argument for the two commands that take one; the state channel
-- passes nil and the value is read from the paired state key instead.
local function applyCommand(command, value)
  if command == "START" then
    if focusState == FOCUS_STATE_IDLE or focusState == FOCUS_STATE_DONE then
      -- A finished focus starts over at the configured length, so START is
      -- always meaningful even when the previous run drained to zero.
      focusDuration = pomodoroMinutes * 60
      setFocusRemaining(focusDuration)
      noctalia.state.set("pet.focus.duration", focusDuration)
    end
    setFocusState(FOCUS_STATE_RUNNING)
  elseif command == "PAUSE" then
    if focusState == FOCUS_STATE_RUNNING then
      setFocusState(FOCUS_STATE_PAUSED)
    end
  elseif command == "RESET" then
    focusDuration = 0
    setFocusRemaining(0)
    noctalia.state.set("pet.focus.duration", 0)
    setFocusState(FOCUS_STATE_IDLE)
  elseif command == "SET_OVERRIDE" then
    local next = value or noctalia.state.get("pet.override_value")
    if isExpression(next) then
      override = next
      noctalia.state.set("pet.override", override)
    end
  elseif command == "CLEAR_OVERRIDE" then
    override = ""
    noctalia.state.set("pet.override", override)
    noctalia.state.set("pet.override_value", "")
  elseif command == "SET_NAME" then
    local next = trim(value or noctalia.state.get("pet.name_value") or "")
    if next ~= "" then
      nameOverride = next
      saveProfile()
      -- Same rule as a palette change: the cache key no longer matches, so the
      -- next ensureAvatar() fetches the new identity.
      currentKey = ""
      noctalia.state.set("pet.name", effectiveName())
    end
  elseif command == "CLEAR_NAME" then
    nameOverride = ""
    saveProfile()
    currentKey = ""
    noctalia.state.set("pet.name", effectiveName())
  elseif command == "POKE" then
    -- A tap is a one-off reaction, so it goes through the poke deadline rather
    -- than the override channel (which would stick). The id bump lets the
    -- desktop widget squash immediately even when the expression is unchanged.
    pokeUntilMs = noctalia.nowMs() + 2000
    pokeId += 1
    noctalia.state.set("pet.poke_id", pokeId)
  end
end

noctalia.state.watch("pet.cmd", function(command)
  applyCommand(command)
end)

-- CLI / keybinding surface, e.g.
--   noctalia msg plugin evergaster/blobatar:pet desktop poke
--   noctalia msg plugin evergaster/blobatar:pet desktop set_name Umberto
-- Command names are lower case here; the state channel uses the upper case
-- names documented above. The payload carries the argument where one applies.
local IPC_COMMANDS = {
  start = "START",
  pause = "PAUSE",
  reset = "RESET",
  poke = "POKE",
  set_override = "SET_OVERRIDE",
  clear_override = "CLEAR_OVERRIDE",
  set_name = "SET_NAME",
  clear_name = "CLEAR_NAME",
}

function onIpc(event, payload)
  local command = IPC_COMMANDS[event]
  if command == nil then
    return
  end
  applyCommand(command, payload)
end

------------------------------------------------------------------- lifecycle

function onConfigChanged()
  readConfig()
  publishExpression()
  ensureAvatar()
end

function update()
  tick += 1

  tickFocus()

  if tick % BATTERY_EVERY == 1 then
    readBattery()
  end
  if tick % DND_EVERY == 1 then
    readDnd()
  end

  -- systemStats() is the host's own sampler, so reading it every second is
  -- cheap and gives a fresh cpu/ram pair each tick.
  local stats = noctalia.systemStats()
  if stats ~= nil then
    cpu = math.floor(stats.cpu.usagePercent)
    ram = math.floor(stats.ram.usagePercent)
    noctalia.state.set("pet.cpu", cpu)
    noctalia.state.set("pet.ram", ram)
  end

  publishExpression()
  ensureAvatar()
end

------------------------------------------------------------------- bootstrap

noctalia.state.set("pet.expression", expression)
noctalia.state.set("pet.reason", reason)
noctalia.state.set("pet.avatar", "")
noctalia.state.set("pet.ready", false)
noctalia.state.set("pet.error", "")
noctalia.state.set("pet.battery", -1)
noctalia.state.set("pet.charging", false)
noctalia.state.set("pet.cpu", -1)
noctalia.state.set("pet.ram", -1)
noctalia.state.set("pet.dnd", false)
noctalia.state.set("pet.override", "")
noctalia.state.set("pet.override_value", "")
noctalia.state.set("pet.poke_id", 0)
noctalia.state.set("pet.name_value", "")
noctalia.state.set("pet.name", "evergaster")
noctalia.state.set("pet.focus.state", focusState)
noctalia.state.set("pet.focus.remaining", focusRemaining)
noctalia.state.set("pet.focus.duration", focusDuration)
noctalia.state.set("pet.focus.formatted", formatTime(focusRemaining))

readConfig()
ensureDirs()
-- Swept once at startup, not just after a download, so a cache written by an
-- older version gets tidied without waiting for the next avatar to arrive.
pruneAvatarCache()
loadProfile()
noctalia.state.set("pet.name", effectiveName())
publishExpression()
ensureAvatar()
