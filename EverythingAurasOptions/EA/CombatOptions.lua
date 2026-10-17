if not EverythingAuras.IsLibsOK() then return end

local OptionsPrivate = select(2, ...)
local L = EverythingAuras.L

-- On Target or Focus Blizzard can refuse the unit's reaction (Native.lua Drawable), so only Player is always drawn.
local function Native(data)
  local Private = OptionsPrivate.Private
  if not (Private and Private.EANativeWanted and Private.EANativeWanted(data)) then
    return false, false
  end
  local trigger = type(data.triggers) == "table" and data.triggers[1] and data.triggers[1].trigger
  return true, (type(trigger) == "table" and trigger.unit or "player") == "player"
end

local PositionOptions = OptionsPrivate.commonOptions.PositionOptions
OptionsPrivate.commonOptions.PositionOptions = function(id, data, ...)
  local options = PositionOptions(id, data, ...)
  if not data.controlledChildren then
    options.eaUnsureDisplay = {
      type = "select",
      width = EverythingAuras.normalWidth,
      -- Gray, not disabled: a disabled control gets no mouse-over on this engine, so the tooltip would not show.
      name = function()
        local _, always = Native(data)
        if always then
          return "|cff808080" .. L["When Unsure in Combat"] .. " " .. L["(not used)"] .. "|r"
        end
        return L["When Unsure in Combat"]
      end,
      desc = function()
        local text = L["In combat WoW Forever hides most auras from addons, so Everything Auras shows what it last knew. Dim fades it and adds a small corner marker. Sounds, glows, chat and custom actions never fire for it, whatever you pick."]
        local native, always = Native(data)
        if always then
          text = text .. "\n\n" .. L["Blizzard draws this icon, so its other parts always hide while unsure."]
        elseif native then
          text = text .. "\n\n" .. L["Blizzard draws this icon for buffs on friendly units and debuffs on enemies, and its other parts then hide while unsure. This setting applies when Everything Auras draws it instead."]
        end
        return text
      end,
      order = 81.5,
      values = { dim = L["Dim"], hide = L["Hide"], show = L["Show Normally"] },
      get = function()
        return data.eaUnsureDisplay or "dim"
      end,
      set = function(_, value)
        data.eaUnsureDisplay = value ~= "dim" and value or nil
        EverythingAuras.Add(data)
      end,
    }
  end
  return options
end

local NEVER_SECRET = Enum.SecrecyLevel and Enum.SecrecyLevel.NeverSecret or 0

local function SpellSecrecy(spell)
  local ok, level = pcall(C_Secrets.GetSpellAuraSecrecy, spell)
  if ok and not issecretvalue(level) then
    return level
  end
end

local function TrackedSpells(trigger)
  local spells = {}
  if trigger.useExactSpellId and type(trigger.auraspellids) == "table" then
    for _, id in ipairs(trigger.auraspellids) do
      spells[#spells + 1] = tonumber(id)
    end
  end
  if trigger.useName and type(trigger.auranames) == "table" then
    for _, name in ipairs(trigger.auranames) do
      if name ~= "" then
        spells[#spells + 1] = tonumber(name) or name
      end
    end
  end
  return spells
end

-- What step 5's Aura trigger does with this trigger while auras are secret.
function OptionsPrivate.EACombatStatus(data, trigger)
  if trigger.unit == "multi" then
    return "|cffff5555" .. L["In combat: not available."] .. "|r "
      .. L["This mode reads the combat log, which WoW Forever closes to addons."]
  end
  local native, always = Native(data)
  if always then
    return "|cff55ff55" .. L["In combat: exact. Blizzard draws this icon."] .. "|r "
      .. L["Its texts, borders and glows hide while Everything Auras is unsure."]
  elseif native then
    return "|cff55ff55" .. L["In combat: exact where Blizzard draws this icon."] .. "|r "
      .. L["That is buffs on friendly units and debuffs on enemies. Otherwise it is last known, as without the option."]
  end
  local spells = TrackedSpells(trigger)
  local readable = #spells > 0
  for _, spell in ipairs(spells) do
    if SpellSecrecy(spell) ~= NEVER_SECRET then
      readable = false
      break
    end
  end
  if readable then
    local exact
    -- A name can also match a hidden aura, so only spell IDs prove one is missing (EANoMatchUnsure).
    if trigger.matchesShowOn == "showOnMissing" and trigger.useName and type(trigger.auranames) == "table" then
      exact = "|cffffd200" .. L["In combat: holds what it showed when the fight started, until the fight ends."] .. "|r "
        .. L["Blizzard never hides these auras, but only Exact Spell ID can prove one is missing."]
    else
      exact = "|cff55ff55" .. L["In combat: exact."] .. "|r " .. L["Blizzard never hides these auras."]
    end
    return exact .. " " .. L["Its On Hide actions do not fire in combat."]
  end
  local status
  if trigger.matchesShowOn == "showOnMissing" then
    status = L["In combat: holds what it showed when the fight started, until the fight ends."]
  elseif trigger.unit == "player" and trigger.debuffType == "HELPFUL" then
    status = L["In combat: last known, and estimated again when you cast it on yourself."]
  else
    status = L["In combat: last known, until its timer runs out or the unit changes."]
  end
  local look
  if data.eaUnsureDisplay == "hide" then
    look = L["While unsure it is hidden (Display tab)."]
  elseif data.eaUnsureDisplay == "show" then
    look = L["While unsure it shows normally (Display tab)."]
  else
    look = L["While unsure it is dimmed with a corner marker."]
  end
  return "|cffffd200" .. status .. "|r " .. look .. " "
    .. L["It never fires sounds, glows, chat or custom actions while unsure."]
end

-- OptionsPrivate.Private only exists once the options first open, when registerRegions runs.
OptionsPrivate.registerRegions = OptionsPrivate.registerRegions or {}
tinsert(OptionsPrivate.registerRegions, function()
  local triggerTypesOptions = OptionsPrivate.Private.triggerTypesOptions
  local AuraTriggerOptions = triggerTypesOptions.aura2
  triggerTypesOptions.aura2 = function(data, triggernum)
    local result = AuraTriggerOptions(data, triggernum)
    local options = result and result["trigger." .. triggernum .. ".aura_options"]
    local warning = options and options.restrictions12_1Warning
    if warning then
      warning.name = function()
        local trigger = data.triggers[triggernum] and data.triggers[triggernum].trigger
        return L["Auras can become secret during combat, encounters, Mythic+ runs, or PvP matches. Some auras are explicitly made \"never secret\" by Blizzard."]
          .. (trigger and ("\n\n" .. OptionsPrivate.EACombatStatus(data, trigger)) or "")
      end
    end
    if options and options.matchesShowOn then
      options.matchesShowOn.desc = "|cffffd200" .. L["Secret values"] .. "|r\n"
        .. L["In combat Everything Auras keeps what it read before the fight, so a Missing reminder holds until the fight ends instead of appearing from a guess."]
    end
    return result
  end
end)
