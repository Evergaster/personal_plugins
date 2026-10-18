--!nonstrict
-- dates.luau — calendario puro: sin noctalia, sin ui. Testeable con lua5.4.

local M = {}

local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function isLeapYear(year)
  return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

function M.daysInMonth(year, month)
  if month == 2 and isLeapYear(year) then
    return 29
  end
  return DAYS_IN_MONTH[month]
end

-- 0 = domingo … 6 = sabado (congruencia de Zeller, calendario gregoriano).
function M.weekday(year, month, day)
  local m, y = month, year
  if m < 3 then
    m = m + 12
    y = y - 1
  end
  local k = y % 100
  local j = math.floor(y / 100)
  local h = (day + math.floor(13 * (m + 1) / 5) + k + math.floor(k / 4) + math.floor(j / 4) + 5 * j) % 7
  return (h + 6) % 7
end

-- Semanas del mes: cada semana tiene siempre 7 celdas, con el numero de dia o
-- `false` si esta vacia. weekStart: 0 = domingo, 1 = lunes.
function M.monthGrid(year, month, weekStart)
  local lead = (M.weekday(year, month, 1) - weekStart) % 7
  local weeks = {}
  local week = {}
  for _ = 1, lead do
    table.insert(week, false)
  end
  for day = 1, M.daysInMonth(year, month) do
    table.insert(week, day)
    if #week == 7 then
      table.insert(weeks, week)
      week = {}
    end
  end
  if #week > 0 then
    for _ = #week + 1, 7 do
      table.insert(week, false)
    end
    table.insert(weeks, week)
  end
  return weeks
end

return M
