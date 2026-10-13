if not EverythingAuras.IsLibsOK() then return end
---@class Private
local Private = select(2, ...)

local L = EverythingAuras.L

-- The transform renamed every "M33kAuras" and "WeakAuras" in the locales to the identifier. What a
-- player reads gets the space back, while code names (EverythingAuras.GetRegion), longer identifiers
-- and paths keep it.
local function ShownName(s)
  return (s:gsub("()EverythingAuras()", function(i, j)
    local before, after = s:sub(i - 1, i - 1), s:sub(j, j + 1)
    if before:find("[%w_%.\\/]") or after:find("^[%w_\\/]") or after:find("^%.[%w_]") then
      return nil
    end
    return "Everything Auras"
  end))
end
Private.EAShownName = ShownName

local function RenameAll()
  for key, value in pairs(L) do
    if type(value) == "string" then
      L[key] = ShownName(value)
    end
  end
end
RenameAll()

-- A key no locale has reads back as itself, so it is renamed the same way.
local meta = getmetatable(L)
if meta and meta.__index then
  local index = meta.__index
  meta.__index = function(self, key)
    local value = index(self, key)
    if type(value) == "string" then
      value = ShownName(value)
      rawset(self, key, value)
    end
    return value
  end
end

-- The options addon adds its own strings to the same table when it loads: a new key is renamed as it
-- is written, and a translation that overwrites one is renamed once the addon has loaded.
if meta and meta.__newindex == nil then
  meta.__newindex = function(self, key, value)
    rawset(self, key, type(value) == "string" and ShownName(value) or value)
  end
end
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, _, name)
  if name == "EverythingAurasOptions" then
    self:UnregisterEvent("ADDON_LOADED")
    RenameAll()
  end
end)
