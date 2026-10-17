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

function Private.EAUpdateWarnings(data)
  local uid = data.uid
  if not uid or type(data.triggers) ~= "table" then
    return
  end

  local converted, cooldownManager, combatLog
  local unknownEvents = {}
  for _, triggerData in ipairs(data.triggers) do
    local trigger = type(triggerData) == "table" and triggerData.trigger
    if type(trigger) == "table" then
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

  SetWarning(uid, "EAConvertedSecretAura", "info", converted
    and (Private.EANativeWanted and Private.EANativeWanted(data)
      and L["Imported from ForeverAuras' Aura (Modern) and converted to a standard Aura trigger. Blizzard draws its icon, so the icon stays accurate in combat. You can turn this off under Display, Blizzard Draws This Icon."]
      or L["Imported from ForeverAuras' Aura (Modern) and converted to a standard Aura trigger. In combat it can only show what Blizzard lets addons read."]))
  SetWarning(uid, "EACooldownManagerTrigger", "warning", cooldownManager
    and L["Uses ForeverAuras' Cooldown Manager trigger, which Everything Auras does not support yet. That trigger never activates."])
  SetWarning(uid, "EACombatLog", "warning", combatLog
    and L["Uses the combat log, which WoW Forever closes to addons. That part never fires."])
  SetWarning(uid, "EAUnknownEvent", "warning", #unknownEvents > 0
    and L["Uses a trigger Everything Auras does not have on WoW Forever, so that trigger stays off: %s"]:format(table.concat(unknownEvents, ", ")))
  SetWarning(uid, "EAMissingFunctions", "warning", #missing > 0
    and L["Custom code calls functions WoW Forever does not have, so that code will cause errors: %s"]:format(table.concat(missing, ", ")))
  SetWarning(uid, "EASecretHealth", "warning", readsHealth
    and L["Custom code reads UnitHealth. Health is a secret value on WoW Forever, so math or comparisons on it cause errors."])
  SetWarning(uid, "EAForeverSpec", "warning", type(data.load) == "table" and data.load.use_forever_spec ~= nil
    and L["Uses ForeverAuras' talent spec load option, which Everything Auras does not have. The aura loads regardless of talent spec."])
  SetWarning(uid, "EAAuraReads", "info", auraReads
    and L["Custom code reads auras with UnitAura, UnitBuff or UnitDebuff. On WoW Forever these return nothing while Blizzard keeps auras secret, for example in combat."])
end
