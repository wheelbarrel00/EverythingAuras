if not EverythingAuras.IsLibsOK() then return end

local OptionsPrivate = select(2, ...)
local L = EverythingAuras.L

-- Every rank of each name the trigger matches, from the options' spell cache. Blizzard's slot needs spell IDs.
local function RankIds(data)
  local trigger = type(data.triggers) == "table" and data.triggers[1] and data.triggers[1].trigger
  if type(trigger) ~= "table" or not trigger.useName or type(trigger.auranames) ~= "table" then
    return nil
  end
  local ids, seen = {}, {}
  for _, name in ipairs(trigger.auranames) do
    if type(name) == "string" and name ~= "" and not tonumber(name) then
      for id in pairs(EverythingAuras.spellCache.GetSpellsMatching(name) or {}) do
        if not seen[id] then
          seen[id] = true
          ids[#ids + 1] = id
        end
      end
    end
  end
  if #ids == 0 then
    return nil
  end
  table.sort(ids)
  return ids
end

local function SameList(a, b)
  if type(b) ~= "table" or #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

OptionsPrivate.registerRegions = OptionsPrivate.registerRegions or {}
tinsert(OptionsPrivate.registerRegions, function()
  local Private = OptionsPrivate.Private

  local iconOptions = Private.regionOptions.icon
  local create = iconOptions.create
  iconOptions.create = function(id, data)
    local result = create(id, data)
    if result.icon and not data.controlledChildren then
      -- Never disabled: a disabled checkbox gets no mouse-over on this engine, so its tooltip with the reason would not show.
      result.icon.eaNative = {
        type = "toggle",
        width = EverythingAuras.doubleWidth,
        name = function()
          if Private.EANativeQualifies(data) then
            return L["Blizzard Draws This Icon"]
          end
          return "|cff808080" .. L["Blizzard Draws This Icon"] .. " " .. L["(not available)"] .. "|r"
        end,
        desc = function()
          local text = L["Blizzard draws this aura's icon, swipe, timer and stack count, in combat too. Everything Auras' own texts, borders and glows still follow the trigger and hide while it is unsure in combat. On Show and On Hide sound files play through Blizzard, so they play in combat too."]
          local ok, reason = Private.EANativeQualifies(data)
          if not ok then
            text = text .. "\n\n|cffff5555" .. L["Not available:"] .. "|r " .. reason
          end
          return text
        end,
        order = 0.5,
      }
    end
    return result
  end

  Private.callbacks:RegisterCallback("Add", function(_, _, _, data)
    if data.eaNative and data.regionType == "icon" then
      local ids = RankIds(data)
      if ids and not SameList(ids, data.eaNativeIds) then
        data.eaNativeIds = ids
      end
    end
  end)
end)
