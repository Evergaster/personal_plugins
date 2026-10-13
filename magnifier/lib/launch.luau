--!nonstrict
-- lib/launch.luau
--
-- Shared launch logic for the Magnifier plugin. Every entry (bar widget,
-- control-center tile, IPC) calls M.open(), so one module decides how to build a
-- backend command, check that the binary exists, wait for popups to close, and
-- refuse a second concurrent instance.
--
-- A module sees the same sandboxed globals as an entry script (noctalia.*,
-- ui.*), so noctalia.* is used directly here.

local M = {}

-- Per-backend metadata. `binary` is looked up on PATH; `name` and `url` are
-- shown when the tool is missing so the user knows where to install it.
local BACKENDS = {
  maggie = {
    binary = "maggie",
    name = "Maggie",
    url = "https://github.com/hced/maggie",
  },
  hyprmag = {
    binary = "hyprmag",
    name = "hyprmag",
    url = "https://github.com/SIMULATAN/hyprmag",
  },
  wooz = {
    binary = "wooz",
    name = "wooz",
    url = "https://github.com/negrel/wooz",
  },
}

local DEFAULT_BACKEND = "maggie"
local DEFAULT_ZOOM = 3
local DEFAULT_DELAY_MS = 150
local ZOOM_MIN = 1
local ZOOM_MAX = 9
local DELAY_MAX_MS = 10000

local function clampInt(value, fallback, minimum, maximum)
  local number = tonumber(value)
  if number == nil then
    return fallback
  end
  return math.clamp(math.floor(number), minimum, maximum)
end

local function basename(path)
  return string.match(path, "([^/]+)$") or path
end

local function readSettings()
  local backend = noctalia.getConfig("backend") or DEFAULT_BACKEND
  if backend ~= "custom" and BACKENDS[backend] == nil then
    backend = DEFAULT_BACKEND
  end

  return {
    backend = backend,
    zoom = clampInt(noctalia.getConfig("zoom"), DEFAULT_ZOOM, ZOOM_MIN, ZOOM_MAX),
    binaryPath = noctalia.getConfig("binary_path") or "",
    customCommand = noctalia.getConfig("custom_command") or "",
    delayMs = clampInt(noctalia.getConfig("delay_ms"), DEFAULT_DELAY_MS, 0, DELAY_MAX_MS),
  }
end

-- The executable to run: an explicit path when the user set one, otherwise the
-- backend's binary name for a PATH lookup.
local function resolveProgram(settings)
  if settings.binaryPath ~= "" then
    return settings.binaryPath
  end
  return BACKENDS[settings.backend].binary
end

local function isInstalled(settings)
  if settings.binaryPath ~= "" then
    return noctalia.fileExists(settings.binaryPath)
  end
  return noctalia.commandExists(BACKENDS[settings.backend].binary)
end

-- Argument arrays run the program directly, with no shell parsing, so paths and
-- numbers are passed verbatim. Only documented flags are used:
--   maggie  none                  (maggie exposes no zoom flag: only
--                                  -l/--log-filter, --help, --version)
--   hyprmag -s/--scale <factor>
--   wooz    --zoom-in <PERCENT>   (no 1-9 level maps onto a percentage, so zoom
--                                 is not applied to wooz)
local function buildArguments(settings, program)
  if settings.backend == "hyprmag" then
    return { program, "-s", string.format("%d", settings.zoom) }
  end
  return { program }
end

-- The process name to look for when guarding against a second instance. A custom
-- command's process name is unknown, so it has no guard.
local function runningProcess(settings)
  if settings.backend == "custom" then
    return nil
  end
  return basename(resolveProgram(settings))
end

local function startBackend(settings)
  if settings.backend == "custom" then
    -- Trusted, user-authored command: it is deliberately handed to the shell.
    noctalia.runAsync(settings.customCommand)
    return
  end
  noctalia.runAsync(buildArguments(settings, resolveProgram(settings)))
end

-- Wait before capturing the screen, so an open panel or popup is gone first.
-- sleep takes an argument array too, so the validated number never touches a
-- shell. Whole milliseconds are formatted as integers, avoiding locale quirks.
local function afterDelay(milliseconds, action)
  if milliseconds <= 0 then
    action()
    return
  end
  local seconds = string.format("%d.%03d", math.floor(milliseconds / 1000), milliseconds % 1000)
  noctalia.runAsync({ "sleep", seconds }, action)
end

local function launchMissingBackendError(backend)
  noctalia.notifyError(
    noctalia.tr("notify.missing.title"),
    noctalia.tr("notify.missing.body", { program = backend.name, url = backend.url })
  )
end

local function launchCustomOrBackend(settings)
  afterDelay(settings.delayMs, function()
    startBackend(settings)
  end)
end

-- Launch the configured magnifier, or explain why it cannot be launched.
function M.open()
  local settings = readSettings()

  if settings.backend == "custom" then
    if noctalia.string.trim(settings.customCommand) == "" then
      noctalia.notifyError(
        noctalia.tr("notify.custom_missing.title"),
        noctalia.tr("notify.custom_missing.body")
      )
      return
    end
  elseif not isInstalled(settings) then
    launchMissingBackendError(BACKENDS[settings.backend])
    return
  end

  local process = runningProcess(settings)
  if process == nil then
    launchCustomOrBackend(settings)
    return
  end

  local requested = noctalia.processMatches(function(matched)
    if matched then
      noctalia.notify(
        noctalia.tr("notify.running.title"),
        noctalia.tr("notify.running.body", { program = process })
      )
    else
      launchCustomOrBackend(settings)
    end
  end, process)

  -- If the guard could not be requested, launch rather than silently do nothing.
  if not requested then
    launchCustomOrBackend(settings)
  end
end

return M
