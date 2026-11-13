if not EverythingAuras.IsLibsOK() then return end
if not EverythingAuras.IsForever() then return end
---@class OptionsPrivate
local OptionsPrivate = select(2, ...)

local L = EverythingAuras.L

local MAX_NAMES = 10
local FLOW_FRAMES = { UNITFRAME = true, NAMEPLATE = true }

local function Count(lines, count, singular, plural)
  if count > 0 then
    lines[#lines + 1] = "- " .. (count == 1 and singular or plural:format(count))
  end
end

function OptionsPrivate.EAImportSummary(root)
  local Private = OptionsPrivate.Private
  local modern, cdm, swing, groups = 0, 0, 0, 0
  local flagged = {}
  for data in Private.TraverseAll(root) do
    if data.regionType == "group" and data.blizzardFlow == true and data.eaFlowLaidOut
      and not FLOW_FRAMES[data.blizzardFlowFrames or ""] then
      groups = groups + 1
    end
    for _, triggerData in ipairs(type(data.triggers) == "table" and data.triggers or {}) do
      local trigger = type(triggerData) == "table" and triggerData.trigger
      if type(trigger) == "table" then
        modern = modern + (trigger.eaConvertedFrom == "secretAura" and 1 or 0)
        cdm = cdm + (trigger.eaConvertedFrom == "cdm" and 1 or 0)
        swing = swing + (trigger.event == "Swing Timer" and trigger.swingType ~= nil and 1 or 0)
      end
    end
    if data.uid and Private.EAHasWarning(data.uid) then
      flagged[#flagged + 1] = data.id
    end
  end

  local converted = {}
  Count(converted, modern, L["1 Aura (Modern) trigger, now a standard Aura trigger"],
    L["%d Aura (Modern) triggers, now standard Aura triggers"])
  Count(converted, cdm, L["1 Cooldown Manager trigger, now a standard trigger"],
    L["%d Cooldown Manager triggers, now standard triggers"])
  Count(converted, groups, L["1 Modern Aura Group, now a fixed row"], L["%d Modern Aura Groups, now fixed rows"])
  Count(converted, swing, L["1 Swing Timer trigger, now on its hand setting"],
    L["%d Swing Timer triggers, now on their hand setting"])
  if #converted == 0 and #flagged == 0 then
    return nil
  end

  local parts = {}
  if #converted > 0 then
    parts[#parts + 1] = L["Converted on import:"] .. "\n" .. table.concat(converted, "\n")
  end
  if #flagged > 0 then
    table.sort(flagged)
    local names = {}
    for index = 1, math.min(#flagged, MAX_NAMES) do
      names[index] = flagged[index]
    end
    local list = table.concat(names, ", ")
    if #flagged > MAX_NAMES then
      list = list .. " " .. L["and %d more"]:format(#flagged - MAX_NAMES)
    end
    parts[#parts + 1] = L["These auras have a warning. Hover the warning icon beside each one in the aura list to see what does not work yet:"]
      .. "\n" .. list
  end
  return table.concat(parts, "\n\n")
end

local OpenUpdate = OptionsPrivate.OpenUpdate
function OptionsPrivate.OpenUpdate(data, children, target, linkedAuras, sender, callbackFunc)
  local summarize = OptionsPrivate.Private.EAForeignImports[data]
  return OpenUpdate(data, children, target, linkedAuras, sender, function(success, id, ...)
    if callbackFunc then
      callbackFunc(success, id, ...)
    end
    local root = success and summarize and EverythingAuras.GetData(id)
    local text = root and OptionsPrivate.EAImportSummary(root)
    if text then
      -- After the import has picked the new aura in the list.
      C_Timer.After(0, function()
        OptionsPrivate.Private.EAShowDialog({ title = L["Import Summary"], text = text, button1 = L["Got it"] })
      end)
    end
  end)
end
