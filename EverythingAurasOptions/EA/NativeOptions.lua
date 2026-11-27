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
  for _, entry in ipairs(trigger.auranames) do
    -- The trigger reads a spell ID here as that spell's name, and a buff often has another ID than its cast or rank.
    local spellId = EverythingAuras.SafeToNumber(entry)
    local name = spellId and C_Spell.GetSpellName(spellId) or entry
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

  local SWITCHES = {
    icon = {
      label = L["Blizzard Draws This Icon"],
      text = L["Blizzard draws this aura's icon, swipe and timer, in combat too. Everything Auras' other texts, borders and glows still follow the trigger and hide while it is unsure in combat."],
      fallback = L["On Target or Focus, Blizzard draws a named buff only on friendly units and a named debuff only on enemies. Otherwise Everything Auras draws the icon as usual."],
    },
    aurabar = {
      label = L["Blizzard Draws This Bar"],
      text = L["Blizzard draws this aura's bar and icon, and a text that shows only %n or %p, in combat too. Everything Auras' other texts, borders and glows still follow the trigger and hide while it is unsure in combat."],
      fallback = L["On Target or Focus, Blizzard draws a named buff only on friendly units and a named debuff only on enemies. Otherwise Everything Auras draws the bar as usual."],
    },
    texture = {
      label = L["Blizzard Draws This Texture"],
      text = L["Blizzard draws this texture while the aura is there, in combat too, with its color, rotation and mirror. Everything Auras' other texts, borders and glows still follow the trigger and hide while it is unsure in combat."],
      fallback = L["On Target or Focus, Blizzard draws a named buff only on friendly units and a named debuff only on enemies. Otherwise Everything Auras draws the texture as usual."],
    },
    text = {
      label = L["Blizzard Draws This Text"],
      text = L["Blizzard draws this text while the aura is there, in combat too, when it shows one %p, %s or %n with fixed words around it: %p as a timer in its own time format, %s as the stack count and %n as the spell's name."],
      fallback = L["On Target or Focus, Blizzard draws a named buff only on friendly units and a named debuff only on enemies. Otherwise Everything Auras draws the text as usual."],
    },
    progresstexture = {
      label = L["Blizzard Draws This Progress Texture"],
      text = L["Blizzard fills this texture, in combat too, straight or round, with its crop, mirror and background. Everything Auras' other texts, borders and glows still follow the trigger and hide while it is unsure in combat."],
      fallback = L["On Target or Focus, Blizzard draws a named buff only on friendly units and a named debuff only on enemies. Otherwise Everything Auras draws the texture as usual."],
    },
  }

  local function Listed(trigger)
    local count = 0
    for _, list in ipairs({ trigger.useName and trigger.auranames or false, trigger.useExactSpellId and trigger.auraspellids or false }) do
      count = count + (type(list) == "table" and #list or 0)
    end
    return count
  end

  for regionType, switch in pairs(SWITCHES) do
    local regionOptions = Private.regionOptions[regionType] or {}
    local create = regionOptions.create or function() return {} end
    regionOptions.create = function(id, data)
      local result = create(id, data)
      local group = result[regionType]
      if group and not data.controlledChildren then
        -- Never disabled: a disabled checkbox gets no mouse-over on this engine, so its tooltip with the reason would not show.
        group.eaNative = {
          type = "toggle",
          width = EverythingAuras.doubleWidth,
          name = function()
            if Private.EANativeQualifies(data) then
              return switch.label
            end
            return "|cff808080" .. switch.label .. " " .. L["(not available)"] .. "|r"
          end,
          desc = function()
            local text = switch.text .. "\n\n" .. L["On Show and On Hide sound files play through Blizzard, so they play in combat too, except on an aura that names no spell or shows always. Blizzard stops a sound after 5 seconds, and with Own Only set the aura keeps its own sounds."]
            -- A Text region has no sub-texts, glows or borders (SubText.lua, Border.lua and Glow.lua supports).
            if regionType ~= "text" then
              text = text .. "\n\n" .. L["A text that shows only %s becomes Blizzard's stack count."]
                .. "\n\n" .. L["A text that shows only %p becomes Blizzard's timer in the text's own time format, and Remaining Time conditions that color or hide it carry over. A glow that is always on and a Square Full White border, plain or colored by Debuff Type, are drawn by Blizzard too."]
            end
            text = text .. "\n\n" .. switch.fallback .. "\n\n" .. L["It is on by default wherever it works."]
            local trigger = type(data.triggers) == "table" and data.triggers[1] and data.triggers[1].trigger
            if type(trigger) == "table" and not trigger.showClones and Listed(trigger) ~= 1 then
              text = text .. "\n\n" .. L["Blizzard shows the aura that ends soonest, and an aura that never ends last."]
            end
            if type(trigger) == "table" and trigger.matchesShowOn == "showAlways" and regionType == "icon" then
              text = text .. "\n\n" .. L["With Show On Always, Everything Auras shows the icon's missing look, and Blizzard draws the icon over it while the aura is there, in combat too."]
            end
            if type(trigger) == "table" and trigger.useTotal then
              text = text .. "\n\n" .. L["With a Total Time limit, Blizzard never shows an aura that lasts until canceled."]
            end
            local ok, reason = Private.EANativeQualifies(data)
            if not ok then
              text = text .. "\n\n|cffff5555" .. L["Not available:"] .. "|r " .. reason
            end
            return text
          end,
          -- On by default even where it cannot work yet, so it shows ticked only where Blizzard really draws.
          get = function()
            return data.eaNative and Private.EANativeQualifies(data) and true or false
          end,
          order = 0.5,
        }
      end
      return result
    end
  end

  -- Auras switched on by default never had their ranks stored, so they get them once the spell list is complete.
  local tries = 0
  local function StoreMissingRanks()
    local odb = OptionsPrivate.savedVars and OptionsPrivate.savedVars.odb
    if not odb or odb.needsRebuild or odb.rebuilding then
      tries = tries + 1
      if tries < 120 then
        C_Timer.After(5, StoreMissingRanks)
      end
      return
    end
    local stored = false
    for _, data in pairs(Private.db and Private.db.displays or {}) do
      if type(data) == "table" and data.eaNative and SWITCHES[data.regionType] and not data.eaNativeIds then
        local ids = RankIds(data)
        if ids then
          data.eaNativeIds = ids
          stored = true
        end
      end
    end
    if stored and Private.EANativeRefresh then
      Private.EANativeRefresh()
    end
  end
  StoreMissingRanks()

  Private.callbacks:RegisterCallback("Add", function(_, _, _, data)
    if data.eaNative and SWITCHES[data.regionType] then
      -- A rebuilding cache holds only the ranks scanned so far, so a stored list waits for the full one.
      local odb = OptionsPrivate.savedVars and OptionsPrivate.savedVars.odb
      if data.eaNativeIds and odb and (odb.needsRebuild or odb.rebuilding) then
        return
      end
      local ids = RankIds(data)
      if ids and not SameList(ids, data.eaNativeIds) then
        data.eaNativeIds = ids
      end
    end
  end)
end)
