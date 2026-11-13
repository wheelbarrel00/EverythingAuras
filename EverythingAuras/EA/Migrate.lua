if not EverythingAuras.IsLibsOK() then return end

local Private = select(2, ...)

-- Everything Auras' own migration counter, kept apart from the internalVersion shared with WeakAuras.
local EA_VERSION = 7

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

local FLOW_FRAMES = { UNITFRAME = true, NAMEPLATE = true }
local DIRECTIONS = { R = { 1, 0 }, L = { -1, 0 }, U = { 0, 1 }, D = { 0, -1 } }
local GRID_STEPS = {}
for _, code in ipairs({ "RD", "RU", "LD", "LU", "DR", "DL", "UR", "UL" }) do
  GRID_STEPS[code] = { DIRECTIONS[code:sub(1, 1)], DIRECTIONS[code:sub(2, 2)] }
end

local function MemberSize(member)
  local width = tonumber(member.width) or tonumber(member.fixedWidth) or 32
  local height = tonumber(member.height) or 32
  return width, height
end

local POINT_SIGNS = { CENTER = { 0, 0 }, LEFT = { 1, 0 }, RIGHT = { -1, 0 }, TOP = { 0, -1 }, BOTTOM = { 0, 1 },
  TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 } }

local function Offsets(member)
  return tonumber(member.xOffset) or 0, tonumber(member.yOffset) or 0
end

local function CenterOffset(member, width, height)
  local sign = POINT_SIGNS[member.selfPoint or "CENTER"] or POINT_SIGNS.CENTER
  local x, y = Offsets(member)
  return x + sign[1] * width / 2, y + sign[2] * height / 2
end

-- A plain group cannot close gaps, so each member gets the place it has when every member shows.
local function LayoutModernRow(group, members)
  if group.regionType ~= "group" or group.blizzardFlow ~= true or group.eaFlowLaidOut
    or FLOW_FRAMES[group.blizzardFlowFrames or ""] or #members == 0 then
    return
  end
  local growth = group.blizzardFlowGrowth or "RIGHT"
  local spacing = tonumber(group.blizzardFlowSpacing) or 2
  local newOrigin = group.blizzardFlowOrigin == "group"
  local sizes, total = {}, 0
  local horizontal = growth ~= "UP" and growth ~= "DOWN" and growth ~= "CENTER_VERTICAL"
  for index, member in ipairs(members) do
    local width, height = MemberSize(member)
    sizes[index] = { width, height }
    total = total + (horizontal and width or height) + (index > 1 and spacing or 0)
  end
  local gridType = group.blizzardFlowGrid and GRID_STEPS[group.blizzardFlowGridType or ""] and group.blizzardFlowGridType
    or "RD"
  local anchorX, anchorY
  if not newOrigin then
    anchorX, anchorY = CenterOffset(members[1], sizes[1][1], sizes[1][2])
  else
    -- A group's region is a 2 px point, and the row starts at its corner on that point, not its center.
    local corner = group.blizzardFlowGrid and gridType or growth
    local halfWidth, halfHeight = sizes[1][1] / 2, sizes[1][2] / 2
    local first = corner:sub(1, 1)
    anchorX = (corner == "CENTER_HORIZONTAL" and 0) or ((first == "L" or corner == "DL" or corner == "UL") and -halfWidth)
      or halfWidth
    anchorY = (corner == "CENTER_VERTICAL" and 0) or ((first == "U" or corner == "RU" or corner == "LU") and halfHeight)
      or -halfHeight
  end
  local positions = {}
  if group.blizzardFlowGrid then
    local perRow = math.max(1, tonumber(group.blizzardFlowPerRow) or 6)
    local columnSpace = tonumber(group.blizzardFlowColumnSpace) or spacing
    local rowSpace = tonumber(group.blizzardFlowRowSpace) or spacing
    local width, height = sizes[1][1], sizes[1][2]
    local along, across = GRID_STEPS[gridType][1], GRID_STEPS[gridType][2]
    local stepX, stepY = width + columnSpace, height + rowSpace
    for index = 1, #members do
      local step, line = (index - 1) % perRow, math.floor((index - 1) / perRow)
      positions[index] = { anchorX + (along[1] * step + across[1] * line) * stepX,
        anchorY + (along[2] * step + across[2] * line) * stepY }
    end
  else
    local firstWidth, firstHeight = sizes[1][1], sizes[1][2]
    local cursor
    if growth == "CENTER_HORIZONTAL" then
      cursor = anchorX - total / 2
    elseif growth == "CENTER_VERTICAL" then
      cursor = anchorY + total / 2
    elseif growth == "LEFT" then
      cursor = anchorX + firstWidth / 2
    elseif growth == "DOWN" then
      cursor = anchorY + firstHeight / 2
    elseif growth == "UP" then
      cursor = anchorY - firstHeight / 2
    else
      cursor = anchorX - firstWidth / 2
    end
    for index = 1, #members do
      local width, height = sizes[index][1], sizes[index][2]
      if growth == "LEFT" then
        positions[index] = { cursor - width / 2, anchorY + firstHeight / 2 - height / 2 }
        cursor = cursor - width - spacing
      elseif growth == "UP" then
        positions[index] = { anchorX - firstWidth / 2 + width / 2, cursor + height / 2 }
        cursor = cursor + height + spacing
      elseif growth == "DOWN" or growth == "CENTER_VERTICAL" then
        positions[index] = { anchorX - firstWidth / 2 + width / 2, cursor - height / 2 }
        cursor = cursor - height - spacing
      else
        positions[index] = { cursor + width / 2, anchorY + firstHeight / 2 - height / 2 }
        cursor = cursor + width + spacing
      end
    end
  end
  for index, member in ipairs(members) do
    local nudgeX, nudgeY = 0, 0
    if newOrigin then
      nudgeX, nudgeY = Offsets(member)
    end
    member.selfPoint, member.anchorPoint = "CENTER", "CENTER"
    member.xOffset, member.yOffset = positions[index][1] + nudgeX, positions[index][2] + nudgeY
  end
  group.eaFlowLaidOut = true
end

-- Members that no longer share one place were arranged by hand after an earlier import, so they stay.
local function Untouched(members)
  local first = members[1]
  for index = 2, #members do
    local member = members[index]
    if (member.selfPoint or "CENTER") ~= (first.selfPoint or "CENTER")
      or (member.anchorPoint or "CENTER") ~= (first.anchorPoint or "CENTER")
      or (tonumber(member.xOffset) or 0) ~= (tonumber(first.xOffset) or 0)
      or (tonumber(member.yOffset) or 0) ~= (tonumber(first.yOffset) or 0) then
      return false
    end
  end
  return true
end

local function ChildrenOf(group, byId)
  local members = {}
  for _, id in ipairs(type(group.controlledChildren) == "table" and group.controlledChildren or {}) do
    local member = byId and byId[id] or not byId and EverythingAuras.GetData(id)
    if type(member) == "table" then
      members[#members + 1] = member
    end
  end
  return members
end

-- The import runs PreAdd, which stamps eaVersion, before its window opens, so the origin is noted here first.
Private.EAForeignImports = setmetatable({}, { __mode = "k" })

-- ForeverAuras stamps 91 without any data migration behind it, so its exports are internalVersion 90 data.
function Private.EANormalizeImport(data, children)
  if type(data) ~= "table" or not IsForeverBuild(data.tocversion) then
    return
  end
  if data.eaVersion == nil then
    Private.EAForeignImports[data] = true
  end
  if data.internalVersion == FA_INTERNAL_VERSION then
    data.internalVersion = 90
  end
  if type(children) == "table" then
    local byId = {}
    for _, child in ipairs(children) do
      if type(child) == "table" then
        if child.internalVersion == FA_INTERNAL_VERSION then
          child.internalVersion = 90
        end
        if child.id then
          byId[child.id] = child
        end
      end
    end
    if EverythingAuras.IsForever() then
      LayoutModernRow(data, ChildrenOf(data, byId))
      for _, child in ipairs(children) do
        if type(child) == "table" and child.regionType == "group" then
          LayoutModernRow(child, ChildrenOf(child, byId))
        end
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

-- The options reset a dropdown value that is not one of its choices, so imported values are made valid first.
local function CompleteItemTrigger(trigger)
  if trigger.event == "Bag Space" and trigger.bagType == nil then
    trigger.bagType = trigger.use_includeSpecialty and "all" or "general"
  elseif trigger.event == "Equipment Durability" then
    trigger.durabilitySlot = tonumber(trigger.durabilitySlot) or trigger.durabilitySlot
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

local CDM_SHOW = { cooldown = "showOnCooldown", ready = "showOnReady" }
local CDM_BUFF_SHOW = { active = "showOnActive", missing = "showOnMissing", always = "showAlways" }
local CDM_COMBINE = { showLowest = "showLowest", showHighest = "showHighest" }
local CDM_TRACK = { auto = true, cooldown = true, charges = true }
local CDM_OPERATORS = { ["<"] = true, ["<="] = true, [">"] = true, [">="] = true, ["=="] = true, ["~="] = true }

local function Filled(values)
  local list = {}
  for _, value in ipairs(type(values) == "table" and values or {}) do
    if value ~= nil and value ~= "" then
      list[#list + 1] = value
    end
  end
  return list
end

local function CdmEntries(trigger)
  local entries = {}
  local names = trigger.cdmUseNames and Filled(trigger.cdmNames) or {}
  local ids = trigger.cdmUseExactIDs and Filled(trigger.cdmExactIDs) or {}
  for _, name in ipairs(names) do
    entries[#entries + 1] = { value = name }
  end
  for _, id in ipairs(ids) do
    local number = EverythingAuras.SafeToNumber(id)
    if number then
      entries[#entries + 1] = { value = number, exact = true }
    end
  end
  if #names == 0 and #ids == 0 and trigger.cdmSpell ~= nil and trigger.cdmSpell ~= "" then
    local number = trigger.cdmExact and EverythingAuras.SafeToNumber(trigger.cdmSpell)
    entries[1] = number and { value = number, exact = true } or { value = trigger.cdmSpell }
  end
  return entries
end

-- Cooldown IDs are Blizzard's Cooldown Manager entries, read on this client because their spells are client data.
local function PickedSpells(trigger, buff)
  local ids, seen = {}, {}
  local picks = type(trigger.cdmSpells) == "table" and trigger.cdmSpells.multi
  local viewer = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
  if type(picks) ~= "table" or not viewer then
    return ids
  end
  local function Add(id)
    if type(id) == "number" and not issecretvalue(id) and id > 0 and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  local keys = {}
  for key, picked in pairs(picks) do
    if picked then
      keys[#keys + 1] = EverythingAuras.SafeToNumber(key)
    end
  end
  table.sort(keys)
  for _, cooldownID in ipairs(keys) do
    local ok, info = pcall(viewer, cooldownID)
    if ok and type(info) == "table" then
      if buff then
        for _, id in ipairs(type(info.linkedSpellIDs) == "table" and info.linkedSpellIDs or {}) do
          Add(id)
        end
        Add(info.spellID)
      else
        Add(info.linkedSpellID or info.overrideTooltipSpellID or info.overrideSpellID or info.spellID)
      end
    end
  end
  return ids
end

local function CopyFilter(trigger, use, operator, value, toUse, toOperator, toValue, default, fallback)
  if trigger[use] then
    trigger[toUse] = true
    trigger[toOperator] = CDM_OPERATORS[trigger[operator]] and trigger[operator] or default
    trigger[toValue] = tostring(trigger[value] or fallback)
  end
end

local function EntryText(entry)
  local number = type(entry.value) == "number" and entry.value or EverythingAuras.SafeToNumber(entry.value)
  return number and C_Spell.GetSpellName(number) or tostring(entry.value)
end

local function IsHarmful(spell)
  local id = EverythingAuras.SafeToNumber(spell)
  if not id then
    local info = C_Spell.GetSpellInfo(spell)
    id = info and info.spellID
  end
  return id and C_Spell.IsSpellHarmful and C_Spell.IsSpellHarmful(id) == true or false
end

local function ToSpellCooldown(trigger, entries)
  local first = entries[1]
  local number = EverythingAuras.SafeToNumber(first.value)
  trigger.type, trigger.event = "spell", "Cooldown Progress (Spell)"
  trigger.use_spellName, trigger.spellName = true, number or first.value
  trigger.use_exact_spellName = first.exact and true or false
  trigger.use_track, trigger.track = true, CDM_TRACK[trigger.cdmTrack or ""] and trigger.cdmTrack or "auto"
  trigger.use_showgcd = trigger.use_cdmShowGCD == true or nil
  CopyFilter(trigger, "cdmUseRemaining", "cdmRemainingOperator", "cdmRemainingTime", "use_remaining",
    "remaining_operator", "remaining", "<", 10)
  CopyFilter(trigger, "cdmUseCharges", "cdmChargeOperator", "cdmChargeCount", "use_charges", "charges_operator",
    "charges", ">=", 1)
  CopyFilter(trigger, "cdmUseSpellCount", "cdmSpellCountOperator", "cdmSpellCount", "use_spellCount",
    "spellCount_operator", "spellCount", ">=", 1)
  trigger.use_genericShowOn, trigger.genericShowOn = true, CDM_SHOW[trigger.cdmShow or ""] or "showAlways"
  local others = {}
  for index = 2, #entries do
    others[#others + 1] = EntryText(entries[index])
  end
  trigger.eaCdmOthers = #others > 0 and others or nil
end

local function ToAura(trigger, entries, picked)
  local names, ids, harmful = {}, {}, false
  for _, entry in ipairs(entries) do
    if entry.exact then
      ids[#ids + 1] = tostring(entry.value)
    else
      names[#names + 1] = EntryText(entry)
    end
    harmful = harmful or IsHarmful(entry.value)
  end
  for _, id in ipairs(picked) do
    ids[#ids + 1] = tostring(id)
    harmful = harmful or IsHarmful(id)
  end
  trigger.type = "aura2"
  trigger.useName, trigger.auranames = #names > 0, names
  trigger.useExactSpellId, trigger.auraspellids = #ids > 0, ids
  if harmful then
    trigger.unit, trigger.debuffType, trigger.ownOnly = "target", "HARMFUL", true
  else
    trigger.unit, trigger.debuffType, trigger.ownOnly = "player", "HELPFUL", nil
  end
  trigger.matchesShowOn = CDM_BUFF_SHOW[trigger.cdmBuffShow or ""] or "showOnActive"
  trigger.unitExists = not trigger.cdmRequireTarget
  trigger.showClones = #names + #ids > 1 and trigger.cdmAutoClone ~= false and trigger.matchesShowOn ~= "showOnMissing"
  trigger.combineMode = CDM_COMBINE[trigger.cdmCombineMode or ""]
  CopyFilter(trigger, "cdmUseRemaining", "cdmRemainingOperator", "cdmRemainingTime", "useRem", "remOperator", "rem", "<", 10)
  CopyFilter(trigger, "cdmUseStacks", "cdmStackOperator", "cdmStackCount", "useStacks", "stacksOperator", "stacks", ">=", 1)
end

local function ToItemCooldown(trigger, entries)
  local items = trigger.cdmUseItemIDs and Filled(trigger.cdmItemIDs) or {}
  local item = EverythingAuras.SafeToNumber(items[1])
  local first = entries[1]
  if not item and not (first and not first.exact) then
    return false
  end
  trigger.type, trigger.event = "item", "Cooldown Progress (Item)"
  trigger.use_itemName, trigger.itemName = true, item or first.value
  trigger.use_exact_itemName = item and true or false
  trigger.use_genericShowOn, trigger.genericShowOn = true, "showAlways"
  return true
end

-- A trigger this client cannot resolve is left as it was, so its warning still names it.
local function ConvertCooldownManager(trigger)
  local event = trigger.event
  local kind = (event == "Blizzard CDM Buff" or trigger.cdmSource == "buff") and "buff"
    or event == "Blizzard CDM Item" and "item" or "cooldown"
  local entries = CdmEntries(trigger)
  local picked = #entries == 0 and PickedSpells(trigger, kind == "buff") or {}
  if kind == "buff" then
    if #entries == 0 and #picked == 0 then
      return
    end
    ToAura(trigger, entries, picked)
  elseif kind == "item" then
    if not ToItemCooldown(trigger, entries) then
      return
    end
  else
    for _, id in ipairs(picked) do
      entries[#entries + 1] = { value = id, exact = true }
    end
    if #entries == 0 then
      return
    end
    ToSpellCooldown(trigger, entries)
  end
  trigger.eaConvertedFrom = "cdm"
  return kind
end

local CDM_CONDITIONS = {
  cooldown = { stacks = "charges", isUsable = "spellUsable", inRange = "spellInRange", spellId = "effectiveSpellId",
    onCooldown = "onCooldown", isReady = "isReady", spellCount = "spellCount", insufficientResources = "insufficientResources",
    name = "name", expirationTime = "expirationTime", duration = "duration" },
  buff = { stacks = "stacks", name = "name", spellId = "spellId", expirationTime = "expirationTime", duration = "duration" },
  item = { onCooldown = "onCooldown", name = "name", expirationTime = "expirationTime", duration = "duration" },
}
-- show and activationTime are on every trigger (Private.GetTriggerConditions), so they always carry over.
local SHARED_CONDITIONS = { show = "show", activationTime = "activationTime" }

-- The aura trigger has Aura(s) Found only with Show On Always. On Found it is the trigger's own state, on Missing its inverse.
local AURA_ACTIVE = { showAlways = "buffed", showOnActive = "show", showOnMissing = "!show" }

local function ConditionNames(kind, trigger)
  local names = {}
  for from, to in pairs(CDM_CONDITIONS[kind]) do
    names[from] = to
  end
  for from, to in pairs(SHARED_CONDITIONS) do
    names[from] = to
  end
  if kind == "buff" then
    names.auraActive = AURA_ACTIVE[trigger.matchesShowOn or ""]
  end
  return names
end

local function RenameConditions(checks, triggernum, names, lost, seen)
  for _, check in ipairs(checks) do
    if type(check) == "table" then
      if check.trigger == triggernum and type(check.variable) == "string" then
        local mapped = names[check.variable]
        if mapped and mapped:sub(1, 1) == "!" then
          check.variable = mapped:sub(2)
          check.value = tonumber(check.value) == 1 and 0 or 1
        elseif mapped then
          check.variable = mapped
        elseif not seen[check.variable] then
          seen[check.variable] = true
          lost[#lost + 1] = check.variable
        end
      end
      if type(check.checks) == "table" then
        RenameConditions(check.checks, triggernum, names, lost, seen)
      end
    end
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
  if version < 6 and type(data.triggers) == "table" then
    for _, triggerData in ipairs(data.triggers) do
      local trigger = type(triggerData) == "table" and triggerData.trigger
      if type(trigger) == "table" and trigger.type == "item" then
        CompleteItemTrigger(trigger)
      end
    end
  end
  if version < 7 and EverythingAuras.IsForever() then
    for triggernum, triggerData in ipairs(type(data.triggers) == "table" and data.triggers or {}) do
      local trigger = type(triggerData) == "table" and triggerData.trigger
      local kind = type(trigger) == "table" and (trigger.type == "cdm"
        or trigger.type == "spell" and trigger.event == "Blizzard Cooldown Manager") and ConvertCooldownManager(trigger)
      if kind and type(data.conditions) == "table" then
        local checks, lost = {}, {}
        for _, condition in ipairs(data.conditions) do
          checks[#checks + 1] = type(condition) == "table" and condition.check or nil
        end
        RenameConditions(checks, triggernum, ConditionNames(kind, trigger), lost, {})
        trigger.eaCdmLostConditions = #lost > 0 and lost or nil
      end
    end
    -- An import or a chat link runs PreAdd on data not saved yet, whose children's IDs may name the player's own auras.
    if data.regionType == "group" and data.blizzardFlow == true and EverythingAuras.GetData(data.id) == data then
      local members = ChildrenOf(data)
      if #members > 0 and Untouched(members) then
        LayoutModernRow(data, members)
      end
    end
  end
  data.eaVersion = math.max(version, EA_VERSION)
  Private.EAUpdateWarnings(data)
end
