if not EverythingAuras.IsLibsOK() then return end
if not EverythingAuras.IsForever() then return end

local Private = select(2, ...)
local L = EverythingAuras.L

local BAG_ICON, DURABILITY_ICON, AMMO_ICON = 133633, 132530, 132382
local MAX_ITEM_ID = 2147483647

Private.ea_bag_types = {
  general = L["General Bags"],
  specialty = L["Specialty Bags"],
  all = L["All Bags"],
}

Private.ea_durability_slots = { [0] = L["All Equipped Items"] }
for slot = 1, 19 do
  if slot ~= 4 and Private.item_slot_types[slot] then
    Private.ea_durability_slots[slot] = Private.item_slot_types[slot]
  end
end

Private.ea_durability_progress = {
  overall = L["Overall Durability (%)"],
  lowest = L["Lowest Item Durability (%)"],
}

Private.ea_ammo_modes = {
  equipped = L["Equipped Ammo"],
  all = L["All Carried Ammo"],
}

local function LastBag()
  return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

-- A reading that turns secret falls back to the last plain one, so a hidden value never shows or hides an aura.
local lastBags
function Private.ExecEnv.EABagSpace(kind)
  local free, total = { general = 0, specialty = 0 }, { general = 0, specialty = 0 }
  for bag = 0, LastBag() do
    local slots = C_Container.GetContainerNumSlots(bag)
    local numFree, family = C_Container.GetContainerNumFreeSlots(bag)
    if hasanysecretvalues(slots, numFree, family) then
      free = nil
      break
    end
    if slots and slots > 0 and numFree then
      local group = (family or 0) == 0 and "general" or "specialty"
      free[group] = free[group] + numFree
      total[group] = total[group] + slots
    end
  end
  if free then
    lastBags = { free = free, total = total }
  elseif lastBags then
    free, total = lastBags.free, lastBags.total
  else
    return nil
  end
  local kindFree, kindTotal
  if kind == "all" then
    kindFree, kindTotal = free.general + free.specialty, total.general + total.specialty
  else
    kindFree, kindTotal = free[kind], total[kind]
  end
  if not kindTotal or kindTotal == 0 then
    return nil
  end
  return kindFree, kindTotal, free.general, free.specialty
end

local lastDurability = {}
function Private.ExecEnv.EADurability(slot)
  local first, last = slot, slot
  if slot == 0 then
    first, last = 1, 19
  end
  local current, maximum, broken, count, lowest, worst = 0, 0, 0, 0, nil, nil
  for index = first, last do
    local now, top = GetInventoryItemDurability(index)
    if hasanysecretvalues(now, top) then
      local previous = lastDurability[slot]
      if previous then
        return unpack(previous, 1, 6)
      end
      return nil
    end
    if now and top and top > 0 then
      count = count + 1
      current, maximum = current + now, maximum + top
      if now == 0 then
        broken = broken + 1
      end
      local percent = now / top * 100
      if not lowest or percent < lowest then
        lowest, worst = percent, index
      end
    end
  end
  if count == 0 then
    lastDurability[slot] = nil
    return nil
  end
  local name, icon = L["Equipment Durability"], DURABILITY_ICON
  if lowest < 100 then
    local itemID = GetInventoryItemID("player", worst)
    name = itemID and C_Item.GetItemNameByID(itemID) or name
    icon = GetInventoryItemTexture("player", worst) or icon
  end
  local result = { lowest, current / maximum * 100, broken, count, name, icon }
  lastDurability[slot] = result
  return unpack(result, 1, 6)
end

-- nil for an empty field, false for one that is not a list of whole item IDs.
local function ParseAmmoIDs(text)
  if type(text) == "number" then
    text = tostring(text)
  end
  if type(text) ~= "string" or not text:find("%S") then
    return nil
  end
  local ids, seen = {}, {}
  for entry in (text .. ","):gmatch("([^,]*),") do
    local id = tonumber(entry:match("^%s*(%d+)%s*$"))
    if not id or id < 1 or id >= MAX_ITEM_ID then
      return false
    end
    if not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  return ids
end

local ammoBags, ammoWatcher
local waitingItems, lastAmmo = {}, {}

-- An item whose class data has not loaded yet is skipped and counted once GET_ITEM_INFO_RECEIVED brings it.
local function ScanAmmoBags()
  local totals = {}
  for bag = 0, LastBag() do
    local slots = C_Container.GetContainerNumSlots(bag)
    if issecretvalue(slots) then
      return nil
    end
    for slot = 1, slots or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info then
        local itemID, stack = info.itemID, info.stackCount
        if hasanysecretvalues(itemID, stack) then
          return nil
        end
        local classID = select(6, C_Item.GetItemInfoInstant(itemID))
        if classID == nil then
          if not waitingItems[itemID] then
            waitingItems[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
          end
        elseif classID == Enum.ItemClass.Projectile then
          totals[itemID] = (totals[itemID] or 0) + (stack or 0)
        end
      end
    end
  end
  return totals
end

function Private.ExecEnv.EAAmmo(text, mode)
  local ids = ParseAmmoIDs(text)
  if ids == false then
    return nil
  end
  if not (ammoWatcher and ammoBags) then
    ammoBags = ScanAmmoBags()
  end
  local ammoSlot = INVSLOT_AMMO or 0
  local equipped = GetInventoryItemID("player", ammoSlot)
  local slotCount = GetInventoryItemCount("player", ammoSlot)
  local key = tostring(text) .. "|" .. mode
  if not ammoBags or hasanysecretvalues(equipped, slotCount) then
    local previous = lastAmmo[key]
    if previous then
      return unpack(previous, 1, 3)
    end
    return nil
  end
  -- An empty ammo slot reads as item 0 with a count of 1 on WoW Forever (measured 2026-11-11).
  if not equipped or equipped <= 0 then
    equipped, slotCount = nil, 0
  end
  slotCount = slotCount or 0

  local count, single = 0, nil
  if ids then
    local listsEquipped = false
    for _, id in ipairs(ids) do
      count = count + (ammoBags[id] or 0)
      listsEquipped = listsEquipped or id == equipped
    end
    if listsEquipped and not ammoBags[equipped] then
      count = count + slotCount
    end
    single = #ids == 1 and ids[1] or nil
  elseif mode == "equipped" and equipped then
    -- The ammo slot can report the carried total itself, so the larger of the two is the count, never the sum.
    count = math.max(ammoBags[equipped] or 0, slotCount)
    single = equipped
  else
    local kinds = 0
    for id, total in pairs(ammoBags) do
      count, kinds, single = count + total, kinds + 1, id
    end
    if equipped and not ammoBags[equipped] and slotCount > 0 then
      count, kinds, single = count + slotCount, kinds + 1, equipped
    end
    if kinds ~= 1 then
      single = nil
    end
  end

  local name, icon = L["Ammo"], AMMO_ICON
  if single then
    name = C_Item.GetItemNameByID(single) or name
    icon = C_Item.GetItemIconByID(single) or icon
  end
  lastAmmo[key] = { count, name, icon }
  return count, name, icon
end

local function WatchAmmo()
  if ammoWatcher then
    return
  end
  ammoWatcher = CreateFrame("Frame")
  ammoWatcher:RegisterEvent("BAG_UPDATE_DELAYED")
  ammoWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
  ammoWatcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  ammoWatcher:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
  ammoWatcher:SetScript("OnEvent", function(_, event, itemID)
    if event == "GET_ITEM_INFO_RECEIVED" then
      if not waitingItems[itemID] then
        return
      end
      waitingItems[itemID] = nil
    end
    ammoBags = nil
    Private.ScanEvents("FA_AMMO_UPDATE")
  end)
end

local function AmmoMode(trigger)
  return trigger.ammoMode == "all" and "all" or "equipped"
end

local function DurabilitySlot(trigger)
  local slot = tonumber(trigger.durabilitySlot) or 0
  if slot < 0 or slot > 19 or slot % 1 ~= 0 then
    return nil
  end
  return slot
end

local function StateArgs(args)
  args[#args + 1] = { name = "progressType", init = "'static'", hidden = true, store = true, test = "true" }
  args[#args + 1] = { name = "name", hidden = true, store = true, test = "true" }
  args[#args + 1] = { name = "icon", hidden = true, store = true, test = "true" }
  return args
end

Private.event_prototypes["Bag Space"] = {
  type = "item",
  events = { ["events"] = { "BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE", "PLAYER_ENTERING_WORLD" } },
  force_events = "BAG_UPDATE_DELAYED",
  name = EverythingAuras.newFeatureString .. L["Bag Space"],
  init = function(trigger)
    local kind = Private.ea_bag_types[trigger.bagType or ""] and trigger.bagType or "general"
    return ([[
local free, totalSlots, freeGeneral, freeSpecialty = Private.ExecEnv.EABagSpace(%q)
if not free then return false end
local used, freePercent = totalSlots - free, free / totalSlots * 100
local name, icon = %q, %d
]]):format(kind, L["Bag Space"], BAG_ICON)
  end,
  args = StateArgs({
    {
      name = "bagType",
      display = L["Bags"],
      type = "select",
      values = "ea_bag_types",
      default = "general",
      required = true,
      test = "true",
      desc = L["General bags hold any item. Specialty bags, such as quivers, ammo pouches, soul bags and herb bags, hold only certain items. The keyring and the bank never count."],
    },
    { name = "free", display = L["Free Slots"], type = "number", store = true, conditionType = "number" },
    { name = "used", display = L["Used Slots"], type = "number", store = true, conditionType = "number" },
    { name = "totalSlots", display = L["Total Slots"], type = "number", store = true, conditionType = "number" },
    { name = "freePercent", display = L["Free Space (%)"], type = "number", store = true, conditionType = "number" },
    { name = "freeGeneral", display = L["Free Slots in General Bags"], hidden = true, store = true, test = "true",
      conditionType = "number" },
    { name = "freeSpecialty", display = L["Free Slots in Specialty Bags"], hidden = true, store = true, test = "true",
      conditionType = "number" },
    { name = "value", init = "free", display = L["Progress Value"], hidden = true, store = true, test = "true",
      conditionType = "number" },
    { name = "total", init = "totalSlots", display = L["Progress Total"], hidden = true, store = true, test = "true",
      conditionType = "number" },
  }),
  GetNameAndIcon = function()
    return L["Bag Space"], BAG_ICON
  end,
  statesParameter = "one",
  automaticrequired = true,
  progressType = "static",
}

Private.event_prototypes["Equipment Durability"] = {
  type = "item",
  events = { ["events"] = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" } },
  force_events = "UPDATE_INVENTORY_DURABILITY",
  name = EverythingAuras.newFeatureString .. L["Equipment Durability"],
  init = function(trigger)
    local slot = DurabilitySlot(trigger)
    if not slot then
      return "do return false end\n"
    end
    return ([[
local lowest, overall, broken, itemCount, name, icon = Private.ExecEnv.EADurability(%d)
if not lowest then return false end
local value = %s
]]):format(slot, trigger.durabilityProgress == "lowest" and "lowest" or "overall")
  end,
  args = StateArgs({
    {
      name = "durabilitySlot",
      display = L["Equipment Slot"],
      type = "select",
      values = "ea_durability_slots",
      default = 0,
      required = true,
      test = "true",
      desc = L["Only equipped items count. Empty slots and items without durability are skipped."],
    },
    {
      name = "durabilityProgress",
      display = L["Progress Value"],
      type = "select",
      values = "ea_durability_progress",
      default = "overall",
      required = true,
      test = "true",
      desc = L["What a progress bar and its text show. Overall adds up the durability of every item, so a worn chest counts for more than worn gloves."],
    },
    { name = "lowest", display = L["Lowest Item Durability (%)"], type = "number", store = true, conditionType = "number",
      desc = L["The durability of your most worn item, from 0 to 100."] },
    { name = "overall", display = L["Overall Durability (%)"], type = "number", store = true, conditionType = "number",
      desc = L["The durability of all your items together, from 0 to 100."] },
    { name = "broken", display = L["Broken Items"], type = "number", store = true, conditionType = "number" },
    { name = "itemCount", display = L["Items with Durability"], hidden = true, store = true, test = "true",
      conditionType = "number" },
    { name = "value", display = L["Progress Value"], hidden = true, store = true, test = "true", conditionType = "number" },
    { name = "total", init = "100", display = L["Progress Total"], hidden = true, store = true, test = "true",
      conditionType = "number" },
  }),
  GetNameAndIcon = function(trigger)
    local slot = DurabilitySlot(trigger)
    local name, icon
    if slot then
      name, icon = select(5, Private.ExecEnv.EADurability(slot))
    end
    return name or L["Equipment Durability"], icon or DURABILITY_ICON
  end,
  statesParameter = "one",
  automaticrequired = true,
  progressType = "static",
}

Private.event_prototypes["Ammo"] = {
  type = "item",
  events = {},
  internal_events = { "FA_AMMO_UPDATE" },
  force_events = "FA_AMMO_UPDATE",
  name = EverythingAuras.newFeatureString .. L["Ammo"],
  loadFunc = WatchAmmo,
  init = function(trigger)
    return ([[
local count, name, icon = Private.ExecEnv.EAAmmo(%q, %q)
if not count then return false end
]]):format(tostring(trigger.ammoItemIDs or ""), AmmoMode(trigger))
  end,
  args = StateArgs({
    {
      name = "ammoItemIDs",
      display = L["Item IDs"],
      type = "string",
      required = true,
      test = "true",
      reloadOptions = true,
      validate = function(_, value)
        return ParseAmmoIDs(value) ~= false or L["Enter whole item IDs separated by commas, or leave this empty."]
      end,
      desc = L["Leave this empty to count the ammo the Count setting picks. Enter item IDs separated by commas to count only those items. The bank never counts."],
    },
    {
      name = "ammoMode",
      display = L["Count"],
      type = "select",
      values = "ea_ammo_modes",
      default = "equipped",
      required = true,
      test = "true",
      hidden = function(trigger)
        return ParseAmmoIDs(trigger.ammoItemIDs) ~= nil
      end,
      desc = L["Equipped Ammo counts the arrows or bullets in your ammo slot, or all you carry when the slot is empty. All Carried Ammo counts every arrow and bullet in your bags."],
    },
    { name = "count", display = L["Ammo Count"], type = "number", store = true, conditionType = "number",
      multiEntry = { operator = "and", limit = 2 } },
    { name = "stacks", init = "count", display = L["Stacks"], hidden = true, store = true, test = "true",
      conditionType = "number" },
    { name = "value", init = "count", display = L["Progress Value"], hidden = true, store = true, test = "true",
      conditionType = "number" },
    { name = "total", init = "0", display = L["Progress Total"], hidden = true, store = true, test = "true",
      conditionType = "number" },
  }),
  GetNameAndIcon = function(trigger)
    local _, name, icon = Private.ExecEnv.EAAmmo(trigger.ammoItemIDs, AmmoMode(trigger))
    return name or L["Ammo"], icon or AMMO_ICON
  end,
  statesParameter = "one",
  automaticrequired = true,
  progressType = "static",
}

Private.category_event_prototype.item = Private.category_event_prototype.item or {}
for _, event in ipairs({ "Bag Space", "Equipment Durability", "Ammo" }) do
  Private.category_event_prototype.item[event] = Private.event_prototypes[event].name
end

local money = Private.event_prototypes["Money"]
if money then
  for _, arg in ipairs(money.args) do
    if arg.name == "money" or arg.name == "silver" or arg.name == "copper" then
      arg.hidden, arg.test, arg.conditionType = nil, nil, "number"
    end
    if arg.name == "money" then
      arg.display, arg.formatter = L["Money (total in copper)"], "BigNumber"
      arg.desc = L["All your money in copper. 1 gold is 10000 copper."]
    elseif arg.name == "silver" then
      arg.desc = L["Only the silver part of your money, from 0 to 99."]
    elseif arg.name == "copper" then
      arg.desc = L["Only the copper part of your money, from 0 to 99."]
    end
  end
end

-- The range library compares the client's answers without a secret check, so an error or a hidden value is unknown.
local RawGetRange, RawSpellInRange = EverythingAuras.GetRange, EverythingAuras.IsSpellInRange

function EverythingAuras.GetRange(unit, checkVisible)
  local ok, minRange, maxRange = pcall(RawGetRange, unit, checkVisible)
  if not ok or hasanysecretvalues(minRange, maxRange) then
    return nil
  end
  return minRange, maxRange
end

function EverythingAuras.CheckRange(unit, range, operator)
  local minRange, maxRange = EverythingAuras.GetRange(unit, true)
  range = tonumber(range)
  if not range then
    return
  end
  if operator == "<=" then
    return (maxRange or 999) <= range
  end
  return (minRange or 0) >= range
end

function EverythingAuras.IsSpellInRange(spellId, unit)
  local ok, result = pcall(RawSpellInRange, spellId, unit)
  if not ok or issecretvalue(result) then
    return nil
  end
  return result
end

local RANGE_TICK, SPELL_RANGE = "EA_RANGE_UPDATE", "EA_SPELL_RANGE_UPDATE"

Private.ea_range_states = {
  inRange = L["In Range"],
  outOfRange = L["Out of Range"],
  noTarget = L["No Target"],
}

local rangeTicker
local function StartRangeTicker()
  if not rangeTicker then
    rangeTicker = C_Timer.NewTicker(0.1, function()
      Private.ScanEvents(RANGE_TICK)
    end)
  end
end

-- SPELL_RANGE_CHECK_UPDATE fires for every spell any addon enabled, so only the ones watched here start a scan.
local watchedSpells, spellRangeWatcher = {}, nil
local function WatchSpellRange(spellID)
  if not spellRangeWatcher then
    spellRangeWatcher = CreateFrame("Frame")
    spellRangeWatcher:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")
    spellRangeWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
    spellRangeWatcher:SetScript("OnEvent", function(_, event, spell)
      if event == "SPELL_RANGE_CHECK_UPDATE" and not issecretvalue(spell) and not watchedSpells[spell] then
        return
      end
      Private.ScanEvents(SPELL_RANGE)
    end)
  end
  if type(spellID) == "number" and spellID > 0 and not watchedSpells[spellID] then
    watchedSpells[spellID] = true
    C_Spell.EnableSpellRangeCheck(spellID, true)
  end
end

-- With Exact Spell Match the client is asked about that ID, otherwise about the name, which covers every rank.
local function ResolveSpell(trigger)
  local value = trigger.spellName
  local id = tonumber(value)
  if trigger.use_exact_spellName then
    id = id or 0
    return id, id
  end
  local spell = id and (C_Spell.GetSpellName(id) or id) or value
  if spell == nil or spell == "" then
    return nil
  end
  local info = C_Spell.GetSpellInfo(spell)
  return spell, info and info.spellID or id
end

local function SpellNameAndIcon(trigger, spell)
  local info = spell and C_Spell.GetSpellInfo(spell)
  return info and info.name or tostring(trigger.spellName or ""), info and info.iconID
end

local function Literal(value)
  if type(value) == "string" then
    return ("%q"):format(value)
  end
  return tostring(value)
end

local function RangeUnit(trigger)
  return type(trigger.unit) == "string" and trigger.unit ~= "" and trigger.unit or "target"
end

function Private.ExecEnv.EASpellInRange(spell, unit)
  if spell == nil or not UnitExists(unit) then
    return nil
  end
  local result = C_Spell.IsSpellInRange(spell, unit)
  if issecretvalue(result) then
    return nil
  end
  return result
end

function Private.ExecEnv.EASpellKnown(spell)
  return spell ~= nil and EverythingAuras.IsSpellKnownIncludingPet(spell)
end

function Private.ExecEnv.EAActionSlot(spellID)
  local slots = spellID and C_ActionBar.FindSpellActionButtons(spellID)
  return slots and slots[1]
end

function Private.ExecEnv.EAGetRange(unit)
  return EverythingAuras.GetRange(unit, true)
end

function Private.ExecEnv.EAUnitExists(unit)
  return UnitExists(unit)
end

local function RangeNote()
  local lib = LibStub("LibRangeCheck-3.0")
  local function List(iterator)
    local ranges = {}
    for range in iterator(lib) do
      ranges[#ranges + 1] = range
    end
    table.sort(ranges)
    return table.concat(ranges, ", ")
  end
  return L["Note: This trigger type estimates the range to the hitbox of a unit. The actual range of friendly players is usually 3 yards more than the estimate. Range checking capabilities depend on your current class and known abilities as well as the type of unit being checked. Some of the ranges may also not work with certain NPCs.|n|n|cFFAAFFAAFriendly Units:|r %s|n|cFFFFAAAAHarmful Units:|r %s|n|cFFAAAAFFMiscellanous Units:|r %s"]
    :format(List(lib.GetFriendCheckers), List(lib.GetHarmCheckers), List(lib.GetMiscCheckers))
end

Private.event_prototypes["Range Check"] = {
  type = "unit",
  events = {},
  internal_events = { RANGE_TICK },
  force_events = RANGE_TICK,
  loadFunc = StartRangeTicker,
  name = L["Range Check"],
  init = function(trigger)
    local test = "true"
    if trigger.use_range then
      local range = tonumber(trigger.range) or 8
      test = trigger.range_operator == "<=" and ("maxRange <= " .. range) or ("minRange >= " .. range)
    end
    return ([[
local unit = %q
local minRange, maxRange = Private.ExecEnv.EAGetRange(unit)
minRange, maxRange = minRange or 0, maxRange or 999
if not (%s) then return false end
]]):format(RangeUnit(trigger), test)
  end,
  args = {
    { name = "note", type = "description", display = "", text = RangeNote },
    { name = "unit", display = L["Unit"], type = "unit", values = "unit_types_range_check", default = "target",
      required = true, test = "true", store = true },
    { name = "minRange", display = L["Minimum Estimate"], type = "number", hidden = true, store = true, test = "true",
      conditionType = "number", operator_types = "without_equal" },
    { name = "maxRange", display = L["Maximum Estimate"], type = "number", hidden = true, store = true, test = "true",
      conditionType = "number", operator_types = "without_equal" },
    {
      name = "range",
      display = L["Distance"],
      type = "number",
      operator_types = "without_equal",
      test = "true",
      conditionType = "number",
      conditionTest = function(state, needle, needle2)
        return state and EverythingAuras.CheckRange(state.unit, needle, needle2)
      end,
      noProgressSource = true,
    },
    { hidden = true, test = "Private.ExecEnv.EAUnitExists(unit)" },
  },
  statesParameter = "one",
  automaticrequired = true,
  progressType = "none",
}

local function SpellRangeEvents(trigger)
  return { RangeUnit(trigger) == "target" and SPELL_RANGE or RANGE_TICK }
end

Private.event_prototypes["Spell in Range"] = {
  type = "spell",
  events = {},
  internal_events = SpellRangeEvents,
  force_events = SPELL_RANGE,
  loadFunc = function(trigger)
    WatchSpellRange(select(2, ResolveSpell(trigger)))
    if RangeUnit(trigger) ~= "target" then
      StartRangeTicker()
    end
  end,
  name = L["Spell in Range"],
  init = function(trigger)
    local spell = ResolveSpell(trigger)
    local name, icon = SpellNameAndIcon(trigger, spell)
    return ([[
local unit = %q
local inRange = Private.ExecEnv.EASpellInRange(%s, unit)
if inRange == nil or inRange == %s then return false end
local name, icon = %q, %s
]]):format(RangeUnit(trigger), Literal(spell), trigger.use_inverse and "true" or "false", name, Literal(icon))
  end,
  args = {
    { name = "spellName", display = L["Spell"], type = "spell", required = true, showExactOption = true, test = "true" },
    { name = "unit", display = L["Unit"], type = "unit", values = "unit_types_range_check", default = "target",
      required = true, test = "true", store = true },
    { name = "inverse", display = L["Inverse"], type = "toggle", test = "true",
      desc = L["Show while the unit is out of the spell's range instead. With no unit, or a unit the spell cannot be cast on, the aura stays hidden either way."] },
    { name = "name", hidden = true, store = true, test = "true" },
    { name = "icon", hidden = true, store = true, test = "true" },
  },
  GetNameAndIcon = function(trigger)
    return SpellNameAndIcon(trigger, (ResolveSpell(trigger)))
  end,
  statesParameter = "one",
  automaticrequired = true,
  progressType = "none",
}

Private.event_prototypes["Spell in Range (Action Bar)"] = {
  type = "spell",
  events = {},
  internal_events = { SPELL_RANGE },
  force_events = SPELL_RANGE,
  loadFunc = function(trigger)
    WatchSpellRange(select(2, ResolveSpell(trigger)))
  end,
  name = L["Spell in Range (Action Bar)"],
  init = function(trigger)
    local spell, spellID = ResolveSpell(trigger)
    local name, icon = SpellNameAndIcon(trigger, spell)
    return ([[
if not Private.ExecEnv.EASpellKnown(%s) then return false end
local inRange = Private.ExecEnv.EASpellInRange(%s, "target")
local rangeState = inRange == nil and "noTarget" or inRange and "inRange" or "outOfRange"
inRange = inRange == true
local slot = Private.ExecEnv.EAActionSlot(%s)
local name, icon = %q, %s
]]):format(Literal(spell), Literal(spell), Literal(spellID), name, Literal(icon))
  end,
  args = {
    { name = "spellName", display = L["Spell"], type = "spell", required = true, showExactOption = true, test = "true",
      desc = L["Checked against your current target. The spell does not need to be on an action bar."] },
    { name = "rangeState", display = L["Show On"], type = "select", values = "ea_range_states", store = true,
      conditionType = "select" },
    { name = "inRange", display = L["In Range"], hidden = true, store = true, test = "true", conditionType = "bool" },
    { name = "slot", display = L["Action Slot"], hidden = true, store = true, test = "true", conditionType = "number" },
    { name = "name", hidden = true, store = true, test = "true" },
    { name = "icon", hidden = true, store = true, test = "true" },
  },
  GetNameAndIcon = function(trigger)
    return SpellNameAndIcon(trigger, (ResolveSpell(trigger)))
  end,
  statesParameter = "one",
  automaticrequired = true,
  progressType = "none",
}

Private.category_event_prototype.unit["Range Check"] = Private.event_prototypes["Range Check"].name
Private.category_event_prototype.spell = Private.category_event_prototype.spell or {}
for _, event in ipairs({ "Spell in Range", "Spell in Range (Action Bar)" }) do
  Private.category_event_prototype.spell[event] = Private.event_prototypes[event].name
end
