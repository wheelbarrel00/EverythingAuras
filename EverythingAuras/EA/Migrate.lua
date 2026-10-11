if not EverythingAuras.IsLibsOK() then return end

local Private = select(2, ...)
local L = EverythingAuras.L

-- Everything Auras' own migration counter, kept apart from the internalVersion shared with WeakAuras.
local EA_VERSION = 1

local FA_INTERNAL_VERSION = 91
local OLD_ADDON_FOLDERS = { "WeakAuras", "M33kAuras", "ForeverAuras" }
local FA_CLASSIFICATION = { Buff = "HELPFUL", Debuff = "HARMFUL", Dispel = "HARMFUL" }

local function IsForeverBuild(tocversion)
  return type(tocversion) == "number" and tocversion >= 16000 and tocversion < 20000
end

-- ForeverAuras stamps 91 without any data migration behind it, so its exports are internalVersion 90 data.
function Private.EANormalizeImport(data, children)
  if type(data) ~= "table" or not IsForeverBuild(data.tocversion) then
    return
  end
  if data.internalVersion == FA_INTERNAL_VERSION then
    data.internalVersion = 90
  end
  if type(children) == "table" then
    for _, child in ipairs(children) do
      if type(child) == "table" and child.internalVersion == FA_INTERNAL_VERSION then
        child.internalVersion = 90
      end
    end
  end
end

local function RemapMediaPath(value)
  for _, folder in ipairs(OLD_ADDON_FOLDERS) do
    local rest = value:match("^[Ii]nterface[\\/][Aa]dd[Oo]ns[\\/]" .. folder .. "[\\/](.+)$")
    if rest then
      return "Interface\\AddOns\\EverythingAuras\\" .. rest
    end
  end
end

local function RemapMedia(tbl, depth)
  for key, value in pairs(tbl) do
    if type(value) == "string" then
      local remapped = RemapMediaPath(value)
      if remapped then
        tbl[key] = remapped
      end
    elseif type(value) == "table" and depth < 20 then
      RemapMedia(value, depth + 1)
    end
  end
end

local function HasEntries(list)
  return type(list) == "table" and next(list) ~= nil
end

-- FA's "Aura (Modern)" keeps the standard aura fields and mirrors a few under secret* names, so this maps them
-- back and leaves every FA field in place.
local function ConvertSecretAura(trigger)
  trigger.type = "aura2"
  trigger.eaConvertedFrom = "secretAura"

  local readable = trigger.auraReadableSettings
  if type(readable) == "table" then
    if readable.onlyMaw ~= nil then
      trigger.onlyMaw = readable.onlyMaw
    end
    if readable.debuffType == "BOTH" then
      trigger.debuffType = "BOTH"
    end
  end
  trigger.debuffType = FA_CLASSIFICATION[trigger.debuffType] or trigger.debuffType

  if trigger.secretShowOn then
    trigger.matchesShowOn = trigger.secretShowOn
  end
  if trigger.secretUseRem ~= nil then
    trigger.useRem, trigger.remOperator, trigger.rem = trigger.secretUseRem, trigger.secretRemOperator, trigger.secretRem
  end
  if trigger.secretUseStacks ~= nil then
    trigger.useStacks, trigger.stacksOperator, trigger.stacks = trigger.secretUseStacks, trigger.secretStacksOperator, trigger.secretStacks
  end
  if trigger.secretUseTotal ~= nil then
    trigger.useTotal, trigger.totalOperator, trigger.total = trigger.secretUseTotal, trigger.secretTotalOperator, trigger.secretTotal
  end

  trigger.useExactSpellId = trigger.secretUseSpellIDs ~= false and HasEntries(trigger.auraspellids)

  -- Every Vanilla rank shares its spell's name, so a rank seed matches all ranks by name on this client.
  if trigger.secretUseRankSpellIDs == true and HasEntries(trigger.auraRankSpellIDs) then
    local names, seen = {}, {}
    for _, id in ipairs(trigger.auraRankSpellIDs) do
      local name = C_Spell.GetSpellName(tonumber(id) or 0)
      if name and not seen[name] then
        seen[name] = true
        names[#names + 1] = name
      end
    end
    if #names > 0 then
      trigger.useName = true
      trigger.auranames = names
    elseif not trigger.useExactSpellId then
      trigger.useExactSpellId = true
      trigger.auraspellids = CopyTable(trigger.auraRankSpellIDs)
    end
  end
end

local function UpdateImportWarnings(data)
  local converted, cooldownManager
  if type(data.triggers) == "table" then
    for _, triggerData in ipairs(data.triggers) do
      local trigger = type(triggerData) == "table" and triggerData.trigger
      if type(trigger) == "table" then
        converted = converted or trigger.eaConvertedFrom == "secretAura"
        cooldownManager = cooldownManager or trigger.type == "cdm"
      end
    end
  end
  Private.AuraWarnings.UpdateWarning(data.uid, "EAConvertedSecretAura", converted and "info" or nil,
    converted and L["Imported from ForeverAuras' Aura (Modern) and converted to a standard Aura trigger. In combat it can only show what Blizzard lets addons read."] or nil)
  Private.AuraWarnings.UpdateWarning(data.uid, "EACooldownManagerTrigger", cooldownManager and "warning" or nil,
    cooldownManager and L["Uses ForeverAuras' Cooldown Manager trigger, which Everything Auras does not support yet. That trigger never activates."] or nil)
end

function Private.EAModernize(data)
  local version = data.eaVersion or 0
  if version < 1 then
    if type(data.triggers) == "table" then
      for _, triggerData in ipairs(data.triggers) do
        local trigger = type(triggerData) == "table" and triggerData.trigger
        if type(trigger) == "table" and trigger.type == "secretAura" then
          ConvertSecretAura(trigger)
        end
      end
    end
    RemapMedia(data, 0)
  end
  data.eaVersion = math.max(version, EA_VERSION)
  if data.uid then
    UpdateImportWarnings(data)
  end
end
