if not EverythingAuras.IsLibsOK() then return end

local Private = select(2, ...)
local L = EverythingAuras.L

-- Classic functions WoW Forever lacks that have no stand-in, from the wago.io import corpus.
local MISSING_FUNCTIONS = {
  "GetTalentInfo", "GetNumTalentTabs", "GetTalentTabInfo", "GetNumTalents", "GetActiveTalentGroup",
  "GetGlyphSocketInfo", "GetNumGlyphSockets", "GetGlyphLink", "UnitPVPRank", "GetPVPRankInfo",
  "GetPVPRankProgress", "GetPVPThisWeekStats", "SetLootMethod", "UnitDefense",
  "GetNumSkillLines", "GetSkillLineInfo", "UnitMana", "UnitManaMax", "ChannelInfo", "CastingInfo",
  "GetQuestLogSelection", "SelectQuestLogEntry", "SetAbandonQuest", "AbandonQuest", "EquipSet",
}

local AURA_READS = { "UnitAura", "UnitBuff", "UnitDebuff" }

-- Saved filters these triggers never read. Tristate and multiselect ones are on whenever set, the rest when true.
local UNREAD_FILTERS = {
  ["Stance/Form/Aura"] = { { "use_formID", L["Form ID filter"], "set" } },
  ["Swing Timer"] = { { "use_inRange", L["Target In Range filter"], "set" } },
  ["Cast"] = { { "use_important", L["Important filter"], "set" } },
  ["Health"] = { { "use_showIncomingHeal", L["Incoming Heal display"] }, { "use_healprediction", L["Incoming Heal filter"] } },
  ["Cooldown Progress (Spell)"] = { { "use_showgcdtext", L["Global Cooldown Text"] } },
  ["Money"] = { { "use_money", L["Money filter"] }, { "use_silver", L["Silver filter"] }, { "use_copper", L["Copper filter"] } },
  ["Character Stats"] = {
    { "use_rangedattackpower", L["Ranged Attack Power filter"] }, { "use_meleecritpercent", L["Melee Critical filter"] },
    { "use_rangedcritpercent", L["Ranged Critical filter"] }, { "use_spellcritpercent", L["Spell Critical filter"] },
    { "use_rangedhastepercent", L["Ranged Haste filter"] }, { "use_spellhastepercent", L["Spell Haste filter"] },
    { "use_manaregen", L["Mana Regen filter"] }, { "use_manaregenidle", L["Mana Regen filter"] },
    { "use_bonushealing", L["Bonus Healing filter"] }, { "use_expertisepercent", L["Expertise filter"] },
  },
}

-- Health is always secret, so the Health trigger hides these filters and lets them pass (Prototypes.lua Health).
local SECRET_HEALTH_FILTERS = {
  { "use_health", L["Health"] }, { "use_percenthealth", L["Health (%)"] }, { "use_deficit", L["Health Deficit"] },
  { "use_maxhealth", L["Max Health"] }, { "use_absorb", L["Absorb"] }, { "use_healabsorb", L["Heal Absorb"] },
}

local ADDON_TABLES = { "EverythingAuras", "WeakAuras", "M33kAuras", "ForeverAuras" }
local GROUP_UNITS = { group = true, party = true, raid = true }
-- Aura flags that only mean something on buffs, or only on debuffs, so an export applies them to that kind only.
local BUFF_ONLY_FLAGS = { CANCELABLE = true, EXTERNAL_DEFENSIVE = true, BIG_DEFENSIVE = true, IMPORTANT = true }
local DEBUFF_ONLY_FLAGS = { CROWD_CONTROL = true }

local function AddCode(list, code, enabled)
  if enabled ~= false and type(code) == "string" and code ~= "" then
    list[#list + 1] = code
  end
end

local function AddAnimationCode(list, animation)
  if type(animation) == "table" and animation.type == "custom" then
    AddCode(list, animation.alphaFunc, animation.alphaType == "custom" and animation.use_alpha)
    AddCode(list, animation.translateFunc, animation.translateType == "custom" and animation.use_translate)
    AddCode(list, animation.scaleFunc, animation.scaleType == "custom" and animation.use_scale)
    AddCode(list, animation.rotateFunc, animation.rotateType == "custom" and animation.use_rotate)
    AddCode(list, animation.colorFunc, animation.colorType == "custom" and animation.use_color)
  end
end

local function AddConditionChecks(list, check)
  if type(check) ~= "table" then
    return
  end
  if check.trigger == -1 and check.variable == "customcheck" then
    AddCode(list, check.value)
  end
  if type(check.checks) == "table" then
    for _, subCheck in pairs(check.checks) do
      AddConditionChecks(list, subCheck)
    end
  end
end

-- The same code fields the options' custom code list shows, enabled ones only.
local function CollectCode(data)
  local list = {}
  for _, triggerData in ipairs(data.triggers) do
    local trigger = type(triggerData) == "table" and triggerData.trigger
    local untrigger = type(triggerData) == "table" and triggerData.untrigger
    if type(trigger) == "table" and trigger.type == "custom" then
      AddCode(list, trigger.custom)
      if trigger.custom_type == "stateupdate" then
        AddCode(list, trigger.customVariables)
      else
        AddCode(list, type(untrigger) == "table" and untrigger.custom)
        AddCode(list, trigger.customDuration)
        AddCode(list, trigger.customName)
        AddCode(list, trigger.customIcon)
        AddCode(list, trigger.customTexture)
        AddCode(list, trigger.customStacks)
        for i = 1, 7 do
          AddCode(list, trigger["customOverlay" .. i])
        end
      end
    end
  end
  AddCode(list, data.triggers.customTriggerLogic, data.triggers.disjunctive == "custom")
  AddCode(list, data.customText)
  AddCode(list, data.customAnchor, data.anchorFrameType == "CUSTOM")
  local actions = type(data.actions) == "table" and data.actions or {}
  if type(actions.init) == "table" then
    AddCode(list, actions.init.custom, actions.init.do_custom)
    AddCode(list, actions.init.customOnLoad, actions.init.do_custom_load)
    AddCode(list, actions.init.customOnUnload, actions.init.do_custom_unload)
  end
  for _, key in ipairs({ "start", "finish" }) do
    if type(actions[key]) == "table" then
      AddCode(list, actions[key].custom, actions[key].do_custom)
      AddCode(list, actions[key].message_custom, actions[key].do_message)
    end
  end
  if type(data.animation) == "table" then
    AddAnimationCode(list, data.animation.start)
    AddAnimationCode(list, data.animation.main)
    AddAnimationCode(list, data.animation.finish)
  end
  if data.regionType == "dynamicgroup" then
    AddCode(list, data.customGrow, data.grow == "CUSTOM")
    AddCode(list, data.customSort, data.sort == "custom")
    AddCode(list, data.customAnchorPerUnit, data.grow ~= "CUSTOM" and data.useAnchorPerUnit and data.anchorPerUnit == "CUSTOM")
  end
  if type(data.conditions) == "table" then
    for _, condition in ipairs(data.conditions) do
      if type(condition.changes) == "table" then
        for _, change in ipairs(condition.changes) do
          if type(change.value) == "table" and (change.property == "chat" or change.property == "customcode") then
            AddCode(list, change.value.custom)
          end
        end
      end
      AddConditionChecks(list, condition.check)
    end
  end
  return list
end

-- A global call, not a field, method or the code's own definition of that name.
local function CallsGlobal(code, name)
  return code:find("[^%w_%.:]" .. name .. "%s*%(") ~= nil
    and not code:find("function%s+" .. name .. "%s*%(")
    and not code:find("[^%w_%.:]" .. name .. "%s*=[^=]")
end

-- Code that tests for the function first, as in "if GetQuestLogSelection then", does not error without it.
local function ChecksGlobal(code, name)
  local pattern = "[^%w_%.:]" .. name
  return code:find(pattern .. "%s+then") ~= nil or code:find(pattern .. "%s+and[^%w_]") ~= nil
    or code:find("not%s+" .. name .. "[^%w_%(]") ~= nil
end

local function SetWarning(uid, key, severity, message)
  Private.AuraWarnings.UpdateWarning(uid, key, message and severity or nil, message)
end

local function Add(list, seen, label)
  if not seen[label] then
    seen[label] = true
    list[#list + 1] = label
  end
end

local function FilterOn(trigger, key, mode)
  if mode == "set" then
    return trigger[key] ~= nil
  end
  return trigger[key] == true
end

local function CountNames(trigger)
  local names = {}
  if trigger.useName and type(trigger.auranames) == "table" then
    for _, name in ipairs(trigger.auranames) do
      names[name] = true
    end
  end
  if trigger.useExactSpellId and type(trigger.auraspellids) == "table" then
    for _, id in ipairs(trigger.auraspellids) do
      local name = tonumber(id) and C_Spell.GetSpellName(tonumber(id))
      names[name or id] = true
    end
  end
  local count = 0
  for _ in pairs(names) do
    count = count + 1
  end
  return count
end

-- Settings a converted trigger saved that the standard aura trigger cannot apply.
local function AddConvertedLosses(data, trigger, list, seen)
  if type(trigger.secretSpellList) == "string" and trigger.secretSpellList ~= "" then
    Add(list, seen, L["Spell List"])
  end
  if (tonumber(trigger.secretGainedSeconds) or 0) > 0 then
    Add(list, seen, L["Show On Gained"])
  end
  if trigger.secretApproximate == true then
    Add(list, seen, L["Approximate Match"])
  end
  local kind = trigger.debuffType or "HELPFUL"
  for key, value in pairs(type(trigger.nativeFilters) == "table" and trigger.nativeFilters or {}) do
    local applies = not (BUFF_ONLY_FLAGS[key] and kind ~= "HELPFUL") and not (DEBUFF_ONLY_FLAGS[key] and kind ~= "HARMFUL")
    if key ~= "PLAYER" and key ~= "HELPFUL" and key ~= "HARMFUL" and value ~= nil and applies then
      Add(list, seen, L["aura type filters such as Raid or Dispellable"])
    end
  end
  local unit = trigger.unit or "player"
  if not GROUP_UNITS[unit] and (trigger.useUnitClass or trigger.useUnitRoles or trigger.useUnitNames
    or trigger.useIncludePets or (trigger.useHostility and unit ~= "nameplate")) then
    Add(list, seen, L["unit filters on this unit"])
  end
  local display = type(data.blizzardAuraDisplay) == "table" and data.blizzardAuraDisplay or {}
  local limit = tonumber(display.maxIcons) or 10
  if limit > 1 and (trigger.matchesShowOn or "showOnActive") == "showOnActive" and not trigger.showClones
    and (GROUP_UNITS[unit] or CountNames(trigger) > 1) then
    Add(list, seen, L["more than one icon"])
  end
end

-- The sandbox hands custom code this addon's table under each fork's name (AuraEnvironment.lua:628-631).
local function MissingAddonFunctions(code)
  local missing, seen = {}, {}
  for _, tableName in ipairs(ADDON_TABLES) do
    for name in code:gmatch("[^%w_]" .. tableName .. "%s*[%.:]%s*([%a_][%w_]*)%s*%(") do
      local full = tableName .. "." .. name
      local qualified = tableName .. "%." .. name
      local guarded = code:find(qualified .. "%s+then") or code:find(qualified .. "%s+and[^%w_]")
        or code:find("not%s+" .. qualified .. "[^%w_%(]")
      if EverythingAuras[name] == nil and not guarded and not seen[full] then
        seen[full] = true
        missing[#missing + 1] = full
      end
    end
  end
  table.sort(missing)
  return missing
end

function Private.EAUpdateWarnings(data)
  local uid = data.uid
  if not uid or type(data.triggers) ~= "table" then
    return
  end

  local converted, cooldownManager, combatLog
  local unknownEvents = {}
  local notHere, notHereSeen = {}, {}
  local secretHealth, secretHealthSeen = {}, {}
  if data.blizzardFlow == true then
    Add(notHere, notHereSeen, L["Modern Aura Group layout"])
  end
  if type(data.load) == "table" and data.load.use_loadFlag == true then
    Add(notHere, notHereSeen, L["Load Flag"])
  end
  for _, triggerData in ipairs(data.triggers) do
    local trigger = type(triggerData) == "table" and triggerData.trigger
    if type(trigger) == "table" then
      if trigger.eaConvertedFrom == "secretAura" then
        AddConvertedLosses(data, trigger, notHere, notHereSeen)
      end
      if Private.event_prototypes[trigger.event] and Private.category_event_prototype[trigger.type] then
        for _, filter in ipairs(UNREAD_FILTERS[trigger.event] or {}) do
          if FilterOn(trigger, filter[1], filter[3]) then
            Add(notHere, notHereSeen, filter[2])
          end
        end
        if trigger.event == "Weapon Enchant" and trigger.use_enchantKind == true
          and trigger.enchantKind ~= nil and trigger.enchantKind ~= "any" then
          Add(notHere, notHereSeen, L["Enchant Type filter"])
        end
        if trigger.event == "Health" then
          for _, filter in ipairs(SECRET_HEALTH_FILTERS) do
            if trigger[filter[1]] == true then
              Add(secretHealth, secretHealthSeen, filter[2])
            end
          end
        end
      end
      converted = converted or trigger.eaConvertedFrom == "secretAura"
      cooldownManager = cooldownManager or trigger.type == "cdm"
      if trigger.type == "combatlog" then
        combatLog = true
      elseif trigger.type == "custom" and type(trigger.events) == "string" then
        local events = trigger.events:upper()
        combatLog = combatLog or events:find("COMBAT_LOG_EVENT_UNFILTERED", 1, true) ~= nil
          or events:find("%f[%w_]CLEU%f[^%w_]") ~= nil
      end
      if Private.category_event_prototype[trigger.type] and type(trigger.event) == "string"
        and not Private.event_prototypes[trigger.event] then
        unknownEvents[#unknownEvents + 1] = trigger.event
      end
    end
  end

  local code = " " .. table.concat(CollectCode(data), "\n"):gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
  combatLog = combatLog or code:find("CombatLogGetCurrentEventInfo", 1, true) ~= nil
  local readsHealth = CallsGlobal(code, "UnitHealth") and not code:find("issecretvalue", 1, true)
  local auraReads = false
  for _, name in ipairs(AURA_READS) do
    auraReads = auraReads or (Private.EAStandIns[name] and CallsGlobal(code, name))
  end
  local missing = {}
  for _, name in ipairs(MISSING_FUNCTIONS) do
    if _G[name] == nil and not Private.EAStandIns[name] and CallsGlobal(code, name) and not ChecksGlobal(code, name) then
      missing[#missing + 1] = name
    end
  end
  if _G.C_Engraving == nil and code:find("C_Engraving.", 1, true) then
    missing[#missing + 1] = "C_Engraving"
  end
  local missingAddon = MissingAddonFunctions(code)

  SetWarning(uid, "EAConvertedSecretAura", "info", converted
    and (Private.EANativeWanted and Private.EANativeWanted(data)
      and L["Imported from ForeverAuras' Aura (Modern) and converted to a standard Aura trigger. Blizzard draws its icon where it can, so the icon stays accurate in combat. You can turn this off under Display, Blizzard Draws This Icon."]
      or L["Imported from ForeverAuras' Aura (Modern) and converted to a standard Aura trigger. In combat it can only show what Blizzard lets addons read."]))
  SetWarning(uid, "EACooldownManagerTrigger", "warning", cooldownManager
    and L["Uses ForeverAuras' Cooldown Manager trigger, which Everything Auras does not support yet. That trigger never activates."])
  SetWarning(uid, "EACombatLog", "warning", combatLog
    and L["Uses the combat log, which WoW Forever closes to addons. That part never fires."])
  SetWarning(uid, "EAUnknownEvent", "warning", #unknownEvents > 0
    and L["Uses a trigger Everything Auras does not have on WoW Forever, so that trigger stays off: %s"]:format(table.concat(unknownEvents, ", ")))
  SetWarning(uid, "EAMissingFunctions", "warning", #missing > 0
    and L["Custom code calls functions WoW Forever does not have, so that code will cause errors: %s"]:format(table.concat(missing, ", ")))
  SetWarning(uid, "EAMissingAddonFunctions", "warning", #missingAddon > 0
    and L["Custom code calls functions Everything Auras does not have yet, so that code will cause errors: %s"]:format(table.concat(missingAddon, ", ")))
  SetWarning(uid, "EANotHereYet", "warning", #notHere > 0
    and L["Uses ForeverAuras settings Everything Auras does not have yet, so this aura ignores them: %s"]:format(table.concat(notHere, ", ")))
  SetWarning(uid, "EASecretHealthFilters", "warning", #secretHealth > 0
    and L["Health is always secret, so the Health trigger ignores these filters and acts as if they pass: %s"]:format(table.concat(secretHealth, ", ")))
  SetWarning(uid, "EASecretHealth", "warning", readsHealth
    and L["Custom code reads UnitHealth. Health is a secret value on WoW Forever, so math or comparisons on it cause errors."])
  SetWarning(uid, "EAForeverSpec", "warning", type(data.load) == "table" and data.load.use_forever_spec ~= nil
    and L["Uses ForeverAuras' talent spec load option, which Everything Auras does not have. The aura loads regardless of talent spec."])
  SetWarning(uid, "EAAuraReads", "info", auraReads
    and L["Custom code reads auras with UnitAura, UnitBuff or UnitDebuff. On WoW Forever these return nothing while Blizzard keeps auras secret, for example in combat."])
end
