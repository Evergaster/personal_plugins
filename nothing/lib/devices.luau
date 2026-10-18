--!nonstrict
-- devices.luau — bateria de perifericos, sin dependencias extra:
--   * BlueZ (busctl, una sola llamada) para dispositivos Bluetooth.
--   * upower para lo que no pasa por BlueZ (mouse/teclado por dongle, etc.).
-- Los dos se cruzan por MAC para no mostrar el mismo dispositivo dos veces.

local M = {}

local BUSCTL_ARGS = {
  "busctl", "--system", "--json=short", "call", "org.bluez", "/",
  "org.freedesktop.DBus.ObjectManager", "GetManagedObjects",
}

-- Icono de BlueZ (audio-headset, input-mouse, ...) a glyph Tabler.
local BT_GLYPHS = {
  ["audio-headset"] = "headphones",
  ["audio-card"] = "headphones",
  ["input-mouse"] = "mouse",
  ["input-keyboard"] = "keyboard",
  ["input-gaming"] = "device-gamepad",
}

local function glyphForPath(path)
  local name = (path:match("/([^/]+)$") or ""):lower()
  if name:find("mouse") then return "mouse" end
  if name:find("key") then return "keyboard" end
  if name:find("head") or name:find("audio") then return "headphones" end
  if name:find("gamepad") or name:find("joystick") then return "device-gamepad" end
  return "battery"
end

-- upower mezcla la bateria de la maquina con los perifericos: solo interesan
-- los perifericos.
local function isPeripheral(path)
  local name = path:match("/([^/]+)$") or ""
  if name == "DisplayDevice" then return false end
  return name:match("^battery_") == nil and name:match("^line_power") == nil
end

local function prop(props, key)
  local found = props and props[key]
  return found and found.data or nil
end

-- `busctl --json=short` emite a{oa{sa{sv}}} como lista: segun la version, un
-- mapa path -> interfaces o pares path, mapa.
local function managedObjects(decoded)
  local out = {}
  local data = decoded and decoded.data
  if type(data) ~= "table" then
    return out
  end
  local i = 1
  while i <= #data do
    local item = data[i]
    if type(item) == "string" and type(data[i + 1]) == "table" then
      out[item] = data[i + 1]
      i = i + 2
    else
      if type(item) == "table" then
        for path, ifaces in pairs(item) do
          out[path] = ifaces
        end
      end
      i = i + 1
    end
  end
  return out
end

-- upower nombra sus dispositivos con la MAC dentro del path (mouse_dev_AA_BB_..).
local function macFromPath(path)
  local tail = path:match("dev_([0-9A-Fa-f_]+)$")
  if tail == nil or #tail ~= 17 then
    return nil
  end
  return (tail:gsub("_", ":")):upper()
end

local function parseBt(stdout)
  local objects = managedObjects(noctalia.json.decode(stdout))
  local list = {}
  for path, ifaces in pairs(objects) do
    local device = ifaces["org.bluez.Device1"]
    if type(device) == "table" then
      local address = prop(device, "Address")
      local percent = prop(ifaces["org.bluez.Battery1"] or {}, "Percentage")
      table.insert(list, {
        id = address or path,
        name = tostring(prop(device, "Alias") or prop(device, "Name") or address or "?"),
        glyph = BT_GLYPHS[tostring(prop(device, "Icon") or "")] or "bluetooth",
        percent = type(percent) == "number" and math.floor(percent + 0.5) or nil,
        connected = prop(device, "Connected") == true,
      })
    end
  end
  return list
end

local function addUpower(path, stdout, list)
  local percent = tonumber(stdout:match("percentage:%s*(%d+)%%"))
  if percent == nil then
    return
  end
  local mac = macFromPath(path)
  if mac ~= nil then
    for _, device in ipairs(list) do
      -- Ya esta en la lista de BlueZ: solo faltaba la lectura de upower.
      if device.id == mac then
        device.percent = percent
        return
      end
    end
  end
  local model = stdout:match("model:%s*([^\r\n]+)")
  table.insert(list, {
    id = path,
    name = (model or path:match("/([^/]+)$") or "?"):gsub("^%s+", ""):gsub("%s+$", ""),
    glyph = glyphForPath(path),
    percent = percent,
    connected = true,
  })
end

-- cb(lista) con cada periferico conocido; `percent` puede ser nil.
function M.list(cb)
  noctalia.runAsync(BUSCTL_ARGS, function(result)
    local list = {}
    if result.exitCode == 0 then
      local ok, parsed = pcall(parseBt, result.stdout or "")
      if ok then
        list = parsed
      end
    end
    noctalia.runAsync({ "upower", "-e" }, function(devices)
      local paths = {}
      for line in (devices.stdout or ""):gmatch("[^\r\n]+") do
        if isPeripheral(line) then
          table.insert(paths, line)
        end
      end
      local index = 0
      local function nextDevice()
        index = index + 1
        local path = paths[index]
        if path == nil then
          cb(list)
          return
        end
        noctalia.runAsync({ "upower", "-i", path }, function(info)
          if info.exitCode == 0 then
            pcall(addUpower, path, info.stdout or "", list)
          end
          nextDevice()
        end)
      end
      nextDevice()
    end)
  end)
end

return M
