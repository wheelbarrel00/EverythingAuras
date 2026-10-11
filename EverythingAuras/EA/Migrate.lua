if not EverythingAuras.IsLibsOK() then return end

local Private = select(2, ...)

-- Everything Auras' own migration counter, kept apart from the internalVersion shared with WeakAuras.
local EA_VERSION = 2

local FA_INTERNAL_VERSION = 91
local OLD_ADDON_FOLDERS = { "WeakAuras", "M33kAuras", "ForeverAuras" }
local FA_CLASSIFICATION = { Buff = "HELPFUL", Debuff = "HARMFUL", Dispel = "HARMFUL" }

-- Forever has one class tree per class, so each of its spec IDs names a class (GetSpecializationInfoByID).
local FOREVER_SPEC_CLASS = {
  [1482] = "MAGE", [1484] = "DRUID", [1485] = "HUNTER", [1486] = "PALADIN", [1487] = "PRIEST",
  [1488] = "ROGUE", [1489] = "SHAMAN", [1490] = "WARLOCK", [1491] = "WARRIOR",
}

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

-- M33kAuras loads Forever auras by Player Class, so a spec-only restriction from ForeverAuras becomes a class one.
local function ConvertSpecLoad(load)
  if type(load) ~= "table" or load.use_class ~= nil or load.use_class_and_spec == nil
    or type(load.class_and_spec) ~= "table" then
    return
  end
  local specs = {}
  if load.use_class_and_spec then
    specs[1] = load.class_and_spec.single
  elseif type(load.class_and_spec.multi) == "table" then
    for specID, enabled in pairs(load.class_and_spec.multi) do
      if enabled then
        specs[#specs + 1] = specID
      end
    end
  end
  local classes, count, last = {}, 0, nil
  for _, specID in ipairs(specs) do
    local class = FOREVER_SPEC_CLASS[tonumber(specID)]
    if not class then
      return
    end
    if not classes[class] then
      classes[class] = true
      count = count + 1
      last = class
    end
  end
  if count > 0 then
    load.use_class = load.use_class_and_spec
    load.class = { single = count == 1 and last or nil, multi = classes }
  end
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
  if version < 2 then
    ConvertSpecLoad(data.load)
  end
  data.eaVersion = math.max(version, EA_VERSION)
  Private.EAUpdateWarnings(data)
end
