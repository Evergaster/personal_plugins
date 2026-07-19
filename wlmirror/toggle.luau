-- toggle.luau
-- Tile del control center: un click lanza wl-mirror sobre el output
-- configurado (o el enfocado), otro click lo mata.

local running = false

local function render()
  shortcut.setLabel(running and "Mirroring" or "Mirror")
  shortcut.setIcon("cast")
  shortcut.setActive(running)
end

-- Se actualiza solo cuando el service detecta cambios (incluye el caso
-- de que el usuario cierre la ventana de wl-mirror a mano).
noctalia.state.watch("running", function(value)
  running = value == true
  render()
end)

render()

function onClick()
  if running then
    noctalia.runAsync("pkill -x wl-mirror")
    noctalia.notify("WL Mirror", "Deteniendo espejo")
    return
  end

  if not noctalia.commandExists("wl-mirror") then
    noctalia.notifyError("WL Mirror", "wl-mirror no está instalado")
    return
  end

  local output = noctalia.getConfig("output")
  if output == nil or noctalia.string.trim(output) == "" then
    output = noctalia.focusedOutputName()
  end

  if output == nil or output == "" then
    noctalia.notifyError("WL Mirror", "No se detectó ningún output")
    return
  end

  local extra = noctalia.getConfig("extra_args") or ""
  local cmd = "wl-mirror " .. output .. " " .. extra

  noctalia.runAsync(cmd)
  noctalia.notify("WL Mirror", "Espejando " .. output)
end

function onRightClick()
  local output = noctalia.getConfig("output")
  if output == nil or output == "" then
    output = "(output enfocado)"
  end
  noctalia.notify("WL Mirror", "Configurado: " .. output)
end
