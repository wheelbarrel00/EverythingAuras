if not EverythingAuras.IsLibsOK() then return end

local Private = select(2, ...)

-- Everything Auras' own migration counter, kept apart from the internalVersion shared with WeakAuras.
local EA_VERSION = 5

local FA_INTERNAL_VERSION = 91
local OLD_ADDON_FOLDERS = { "WeakAuras", "M33kAuras", "ForeverAuras" }
local FA_CLASSIFICATION = { Buff = "HELPFUL", Debuff = "HARMFUL", Dispel = "HARMFUL" }
-- A lone "=" pasted into the aura trigger's generated test would not compile.
local OPERATORS = { ["="] = "==" }
local OPERATOR_KEYS = { "remOperator", "stacksOperator", "totalOperator" }
local SWING_HANDS = { [0] = "main", [1] = "off", [2] = "ranged" }
local DISPEL_CLASSES = { "magic", "curse", "disease", "poison", "enrage", "none" }

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

local function TypedName(value)
  if type(value) == "string" and not tonumber(value) then
    local name = value:match("^%s*(.-)%s*$")
    return name ~= "" and name or nil
  end
end

local function AddName(trigger, name)
  trigger.useName = true
  trigger.auranames = type(trigger.auranames) == "table" and trigger.auranames or {}
  for _, existing in ipairs(trigger.auranames) do
    if existing == name then
      return
    end
  end
  trigger.auranames[#trigger.auranames + 1] = name
end

local function HasSpells(trigger)
  return (trigger.useName and HasEntries(trigger.auranames))
    or (trigger.useExactSpellId and HasEntries(trigger.auraspellids))
end

local function Strings(list)
  local out = {}
  for key, value in pairs(type(list) == "table" and list or {}) do
    if type(value) == "string" and value ~= "" then
      out[#out + 1] = value
    elseif type(value) == "number" then
      out[#out + 1] = tostring(value)
    elseif value == true and type(key) == "string" then
      out[#out + 1] = key
    end
  end
  table.sort(out)
  return out
end

local function DispelClasses(trigger)
  local classes = {}
  if HasEntries(trigger.includeDispelTypes) then
    for kind, on in pairs(trigger.includeDispelTypes) do
      if on and type(kind) == "string" then
        classes[kind:lower()] = true
      end
    end
  elseif HasEntries(trigger.excludeDispelTypes) then
    for _, kind in ipairs(DISPEL_CLASSES) do
      classes[kind] = true
    end
    for kind, on in pairs(trigger.excludeDispelTypes) do
      if on and type(kind) == "string" then
        classes[kind:lower()] = nil
      end
    end
  end
  return next(classes) and classes or nil
end

-- An aura saved before keeps what its owner may have changed since, a fresh import follows the export.
local function CompleteSecretAura(trigger, fresh)
  for _, key in ipairs(OPERATOR_KEYS) do
    trigger[key] = OPERATORS[trigger[key]] or trigger[key]
  end

  local native = type(trigger.nativeFilters) == "table" and trigger.nativeFilters or {}
  if trigger.ownOnly == nil and type(native.PLAYER) == "boolean" then
    trigger.ownOnly = native.PLAYER
  end

  local addNames = fresh or trigger.useName ~= false
  if trigger.secretUseRankSpellIDs == true and type(trigger.auraRankSpellIDs) == "table" then
    for _, value in ipairs(trigger.auraRankSpellIDs) do
      local name = TypedName(value)
      if name and addNames then
        AddName(trigger, name)
      end
    end
  end
  if trigger.useExactSpellId and type(trigger.auraspellids) == "table" then
    local ids, moved = {}, false
    for _, value in ipairs(trigger.auraspellids) do
      if tonumber(value) then
        ids[#ids + 1] = value
      else
        moved = true
        local name = TypedName(value)
        if name and addNames then
          AddName(trigger, name)
        end
      end
    end
    -- An empty exact-ID list matches nothing, while no list at all would match every aura.
    if moved then
      trigger.auraspellids = ids
      trigger.useExactSpellId = #ids > 0 or not (trigger.useName and HasEntries(trigger.auranames))
    end
  end

  if trigger.useIgnoreExactSpellId == nil and trigger.secretUseExcludedSpellIDs == true
    and HasEntries(trigger.excludedAuraSpellIDs) then
    trigger.useIgnoreExactSpellId = true
    trigger.ignoreAuraSpellids = Strings(trigger.excludedAuraSpellIDs)
  end

  if trigger.use_debuffClass == nil or (fresh and trigger.use_debuffClass == false) then
    local classes = DispelClasses(trigger)
    if classes then
      trigger.use_debuffClass = true
      trigger.debuffClass = classes
    end
  end

  if trigger.useClass == nil and trigger.useUnitClass == true and HasEntries(trigger.unitClass) then
    trigger.useClass, trigger.class = true, CopyTable(trigger.unitClass)
  end
  if trigger.useGroupRole == nil and trigger.useUnitRoles == true and HasEntries(trigger.unitRoles) then
    trigger.useGroupRole, trigger.group_role = true, CopyTable(trigger.unitRoles)
  end
  if trigger.useUnitName == nil and trigger.useUnitNames == true and HasEntries(trigger.unitNames) then
    trigger.useUnitName, trigger.unitName = true, table.concat(Strings(trigger.unitNames), ", ")
  end
  if trigger.use_includePets == nil and trigger.useIncludePets == true then
    trigger.use_includePets, trigger.includePets = true, "PlayersAndPets"
  end

  -- With no names or IDs the aura trigger matches every aura on the unit, so a list it cannot read matches none.
  if type(trigger.secretSpellList) == "string" and trigger.secretSpellList ~= "" and not HasSpells(trigger) then
    trigger.useName, trigger.auranames = true, {}
  end
end

-- Exports keep a stale hand beside the weapon they use, while a saved aura's hand may be the owner's own pick.
local function CompleteSwingTimer(trigger, fresh)
  local hand = SWING_HANDS[tonumber(trigger.swingType)]
  if hand and (fresh or trigger.hand == nil or trigger.hand == "main") then
    trigger.hand = hand
  end
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
      local number = EverythingAuras.SafeToNumber(id)
      local name = number and C_Spell.GetSpellName(number) or TypedName(id)
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
  -- A switch already set, even to off, is left as is (decision 19).
  if version < 3 and data.eaNative == nil and type(data.triggers) == "table" and #data.triggers == 1 then
    local trigger = type(data.triggers[1]) == "table" and data.triggers[1].trigger
    if type(trigger) == "table" and trigger.eaConvertedFrom == "secretAura" and Private.EANativeQualifies(data) then
      data.eaNative = true
    end
  end
  if version < 4 and data.eaNative == nil and (data.regionType == "icon" or data.regionType == "aurabar") then
    data.eaNative = true
  end
  if version < 5 and type(data.triggers) == "table" then
    for _, triggerData in ipairs(data.triggers) do
      local trigger = type(triggerData) == "table" and triggerData.trigger
      if type(trigger) == "table" and trigger.eaConvertedFrom == "secretAura" then
        CompleteSecretAura(trigger, version < 1)
      elseif type(trigger) == "table" and trigger.event == "Swing Timer" and trigger.swingType ~= nil then
        CompleteSwingTimer(trigger, version < 1)
      end
    end
  end
  data.eaVersion = math.max(version, EA_VERSION)
  Private.EAUpdateWarnings(data)
end
