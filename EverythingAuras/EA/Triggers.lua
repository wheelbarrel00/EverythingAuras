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
  -- An item that never loads stays marked until the bags change, so it is asked for once per change.
  ammoWatcher:SetScript("OnEvent", function(_, event, itemID, success)
    if event == "GET_ITEM_INFO_RECEIVED" then
      if not waitingItems[itemID] or success == false then
        return
      end
    else
      waitingItems = {}
    end
    ammoBags = nil
    Private.ScanEvents("FA_AMMO_UPDATE")
  end)
  ammoBags = nil
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
      enable = function(trigger)
        return ParseAmmoIDs(trigger.ammoItemIDs) == nil
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
  local id = EverythingAuras.SafeToNumber(value)
  if trigger.use_exact_spellName then
    id = id or 0
    return id, id
  end
  if id == nil and tonumber(value) then
    return nil
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

local function ClassLabel(classFile, text)
  local className = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]
    or classFile:sub(1, 1) .. classFile:sub(2):lower()
  local label = ("%s: %s"):format(className, text)
  local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  return color and color.WrapTextInColorCode and color:WrapTextInColorCode(label) or label
end

local ANY_TRACKING_SPELL = "anySpell"
local TRACKING_ICON = "Interface\\Icons\\Ability_Tracking"

Private.ea_tracking_show = {
  active = L["Active"],
  inactive = L["Inactive"],
  always = L["Always"],
}

local function TrackingEntries()
  local entries = {}
  for index = 1, C_Minimap.GetNumTrackingTypes() do
    local info = C_Minimap.GetTrackingInfo(index)
    if info then
      entries[#entries + 1] = info
    end
  end
  return entries
end

-- Town and quest filters have no spell ID, so they are saved by name.
local function TrackingKey(info)
  return info.spellID and tostring(info.spellID) or info.name
end

local function TrackingValues(trigger)
  local values = { [ANY_TRACKING_SPELL] = L["Any Tracking Spell"] }
  for _, info in ipairs(TrackingEntries()) do
    values[TrackingKey(info)] = info.name
  end
  local saved = trigger and trigger.trackingType
  if type(saved) == "string" and not values[saved] then
    values[saved] = saved .. " " .. L["(unavailable)"]
  end
  return values
end

local lastTracking = {}
function Private.ExecEnv.EATracking(key)
  if key == nil then
    return nil
  end
  local entries = TrackingEntries()
  -- An empty list means it has not loaded yet, so it never reads as no tracking on.
  local unreadable = #entries == 0
  for _, info in ipairs(entries) do
    unreadable = unreadable or hasanysecretvalues(info.active, info.spellID, info.name)
  end
  if unreadable then
    local previous = lastTracking[key]
    if previous then
      return unpack(previous, 1, 3)
    end
    return nil
  end
  local found, active, name, icon = key == ANY_TRACKING_SPELL, false, nil, nil
  for _, info in ipairs(entries) do
    if key == ANY_TRACKING_SPELL then
      if info.spellID and info.active and not active then
        active, name, icon = true, info.name, info.texture
      end
    elseif TrackingKey(info) == key and (not found or info.active and not active) then
      found, active, name, icon = true, info.active == true, info.name, info.texture
    end
  end
  if not found then
    lastTracking[key] = nil
    return nil
  end
  if not name then
    name, icon = L["Any Tracking Spell"], TRACKING_ICON
  end
  lastTracking[key] = { active, name, icon }
  return active, name, icon
end

Private.event_prototypes["Tracking"] = {
  type = "unit",
  events = { ["events"] = { "MINIMAP_UPDATE_TRACKING", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" } },
  force_events = "PLAYER_ENTERING_WORLD",
  name = EverythingAuras.newFeatureString .. L["Tracking"],
  init = function(trigger)
    local show = Private.ea_tracking_show[trigger.trackingShow or ""] and trigger.trackingShow or "active"
    local hide = show == "active" and " or not active" or show == "inactive" and " or active" or ""
    return ([[
local active, name, icon = Private.ExecEnv.EATracking(%s)
if active == nil%s then return false end
]]):format(Literal(trigger.trackingType), hide)
  end,
  args = {
    { name = "trackingType", display = L["Tracking Type"], type = "select", values = TrackingValues, required = true,
      test = "true",
      desc = L["Any Tracking Spell counts only tracking spells such as Find Herbs or Sense Undead, not the town and quest map filters."] },
    { name = "trackingShow", display = L["Show On"], type = "select", values = "ea_tracking_show", default = "active",
      required = true, test = "true" },
    { name = "active", display = L["Tracking Active"], hidden = true, store = true, test = "true", conditionType = "bool" },
    { name = "name", hidden = true, store = true, test = "true" },
    { name = "icon", hidden = true, store = true, test = "true" },
  },
  GetNameAndIcon = function(trigger)
    local _, name, icon = Private.ExecEnv.EATracking(trigger.trackingType)
    return name or L["Tracking"], icon or TRACKING_ICON
  end,
  statesParameter = "one",
  automaticrequired = true,
  progressType = "none",
}

Private.ea_role_types = {
  TANK = L["Tank"],
  HEALER = L["Healer"],
  DAMAGER = L["Damager"],
}

function Private.ExecEnv.EARole()
  local role = UnitGroupRolesAssigned("player")
  if issecretvalue(role) or role == nil or role == "NONE" then
    return nil
  end
  return role
end

Private.event_prototypes["Role"] = {
  type = "unit",
  events = { ["events"] = { "PLAYER_ROLES_ASSIGNED", "ROLE_CHANGED_INFORM", "GROUP_ROSTER_UPDATE",
    "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED" } },
  force_events = "PLAYER_ENTERING_WORLD",
  name = EverythingAuras.newFeatureString .. L["Role"],
  init = function()
    return "local role = Private.ExecEnv.EARole()\nif not role then return false end\nlocal name = role\n"
  end,
  args = {
    { name = "role", display = L["Role"], type = "select", values = "ea_role_types", default = "DAMAGER", required = true,
      store = true, conditionType = "select",
      desc = L["Your own assigned group role. The aura stays hidden while the game reports no role."] },
    { name = "name", hidden = true, store = true, test = "true" },
  },
  GetNameAndIcon = function(trigger)
    return Private.ea_role_types[trigger.role or ""] or L["Role"], nil
  end,
  statesParameter = "one",
  automaticrequired = true,
  progressType = "none",
}

Private.category_event_prototype.unit["Tracking"] = Private.event_prototypes["Tracking"].name
Private.category_event_prototype.unit["Role"] = Private.event_prototypes["Role"].name

-- Blizzard's form IDs with the spell that names each form, in the order the list shows them.
local FORMS = {
  { 0 },
  { 5, "DRUID", 5487, "Bear Form" }, { 4, "DRUID", 1066, "Aquatic Form" }, { 1, "DRUID", 768, "Cat Form" },
  { 3, "DRUID", 783, "Travel Form" }, { 31, "DRUID", 24858, "Moonkin Form" }, { 2, "DRUID", 33891, "Tree of Life" },
  { 17, "WARRIOR", 2457, "Battle Stance" }, { 18, "WARRIOR", 71, "Defensive Stance" },
  { 19, "WARRIOR", 2458, "Berserker Stance" }, { 30, "ROGUE", 1784, "Stealth" }, { 28, "PRIEST", 15473, "Shadowform" },
  { 16, "SHAMAN", 2645, "Ghost Wolf" },
}

local formValues, formOrder
local function FormValues()
  if not formValues then
    formValues, formOrder = {}, {}
    for _, form in ipairs(FORMS) do
      local id, classFile, spellID, english = form[1], form[2], form[3], form[4]
      formValues[id] = classFile and ClassLabel(classFile, C_Spell.GetSpellName(spellID) or english) or L["Humanoid"]
      formOrder[#formOrder + 1] = id
    end
  end
  return formValues
end

-- Moonkin's ID differs by race (31-35) and Dire Bear (8) is Bear Form.
local function NormalizeFormID(id)
  id = tonumber(id) or 0
  if id >= 31 and id <= 35 then
    return 31
  elseif id == 8 then
    return 5
  end
  return id
end

function Private.ExecEnv.EAFormID()
  local id = GetShapeshiftFormID()
  if issecretvalue(id) then
    return nil
  end
  return NormalizeFormID(id)
end

function Private.ExecEnv.EAFormPosition()
  return GetShapeshiftForm()
end

local function IndexOfArg(args, name)
  for index, arg in ipairs(args) do
    if arg.name == name then
      return index, arg
    end
  end
end

local stance = Private.event_prototypes["Stance/Form/Aura"]
if stance then
  local StockStanceInit = stance.init
  stance.init = function(trigger)
    if trigger.use_formID == nil or type(trigger.formID) ~= "table" then
      return StockStanceInit(trigger)
    end
    local checks = {}
    if trigger.use_formID then
      if trigger.formID.single ~= nil then
        checks[1] = "current == " .. NormalizeFormID(trigger.formID.single)
      end
    elseif type(trigger.formID.multi) == "table" then
      for id, selected in pairs(trigger.formID.multi) do
        if selected then
          checks[#checks + 1] = "current == " .. NormalizeFormID(id)
        end
      end
    end
    return ([[
local form = Private.ExecEnv.EAFormPosition()
local current = Private.ExecEnv.EAFormID()
local active = current ~= nil and (%s)
%s
]]):format(#checks > 0 and table.concat(checks, " or ") or "false", trigger.use_inverse and "active = not active" or "")
  end

  local formIndex, formArg = IndexOfArg(stance.args, "form")
  if formArg then
    formArg.display = L["Form (Bar Position)"]
    formArg.desc = L["The form's slot on this character's stance bar. Paladin auras sit here too. Prefer Form for shapeshift forms and stances. Not used while Form is set."]
    formArg.values = function()
      local values = {}
      for position, label in pairs(Private.form_types) do
        values[position] = label
      end
      for position = 1, 10 do
        values[position] = values[position] or (position .. " - " .. L["Not known on this character"])
      end
      return values
    end
    table.insert(stance.args, formIndex, {
      name = "formID",
      display = L["Form"],
      type = "multiselect",
      values = FormValues,
      sorted = true,
      sortOrder = function()
        FormValues()
        return formOrder
      end,
      init = "Private.ExecEnv.EAFormID()",
      test = "active",
      store = true,
      conditionType = "select",
      desc = L["Blizzard's own form ID, the same on every character whether the form is learned or not. Paladin auras have none, so use Form (Bar Position) for them."],
    })
  end
  local _, inverseArg = IndexOfArg(stance.args, "inverse")
  if inverseArg then
    inverseArg.enable = function(trigger)
      return type(trigger.use_form) == "boolean" or type(trigger.use_formID) == "boolean"
    end
  end
end

Private.ea_enchant_kinds = {
  any = L["Any"],
  imbue = L["Imbue"],
  temporary = L["Oil, Stone or Poison"],
}

local ENCHANT_TYPES = { [2] = "temporary", [3] = "imbue" }
local OPERATORS = { ["<"] = "<", ["<="] = "<=", [">"] = ">", [">="] = ">=", ["=="] = "==", ["~="] = "~=", ["="] = "==" }
local fullDurations, enchantNames, guessedNames, lastEnchants = {}, {}, {}, {}

local function ReadWeapon(slot)
  local found = {}
  for _, entry in ipairs(C_Item.GetWeaponEnchantInfo(slot) or {}) do
    if hasanysecretvalues(entry.enchantType, entry.timeLeft, entry.charges, entry.enchantID, entry.enchantIconID) then
      return nil
    end
    local kind = ENCHANT_TYPES[entry.enchantType]
    if kind and entry.timeLeft and entry.timeLeft > 0 then
      found[kind] = entry
    end
  end
  return found
end

-- The weapon tooltip names each enchant as "Name (29 min)", and two enchants are told apart by their time left.
local function TooltipEnchants(invSlot)
  local lines = {}
  local data = C_TooltipInfo.GetInventoryItem("player", invSlot)
  for _, line in ipairs(data and data.lines or {}) do
    local text = line.leftText
    if type(text) == "string" and not issecretvalue(text) then
      local _, _, name, short = text:find("^((.-) ?+?[VI%d]*) ?%(%d+%D.+%)$")
      if not name then
        _, _, name, short = text:find("^((.-) ?+?[VI%d]*)%（%d+%D.+%）$")
      end
      if name then
        name, short = (name:gsub("%s+$", "")), short and (short:gsub("%s+$", ""))
      end
      if name and name ~= "" then
        local amount, unit = text:match("%((%d+)%s*(%a*)")
        local first = (unit or ""):sub(1, 1):lower()
        local unitSeconds = first == "h" and 3600 or first == "m" and 60 or 1
        local seconds = tonumber(amount) and tonumber(amount) * unitSeconds
        lines[#lines + 1] = { name = name, short = short, seconds = seconds, tolerance = unitSeconds + 5 }
      end
    end
  end
  return lines
end

local function NameEnchants(found, invSlot)
  local lines
  for _, entry in pairs(found) do
    if not enchantNames[entry.enchantID] then
      lines = lines or TooltipEnchants(invSlot)
      local best, bestGap
      for _, line in ipairs(lines) do
        local gap = line.seconds and math.abs(line.seconds - entry.timeLeft / 1000) or math.huge
        if not best or gap < bestGap then
          best, bestGap = line, gap
        end
      end
      -- Set bonus lines like "(0/8)" fit the pattern too, so only a line whose time fits is kept for the session.
      if best and bestGap <= best.tolerance then
        enchantNames[entry.enchantID] = { best.name, best.short }
      elseif best then
        guessedNames[entry.enchantID] = { best.name, best.short }
      end
    end
  end
end

local function NameMatches(entry, wanted)
  local names = enchantNames[entry.enchantID] or guessedNames[entry.enchantID]
  return names and (wanted == names[1] or wanted == names[2]) or tonumber(wanted) == entry.enchantID
end

function Private.ExecEnv.EAWeaponEnchant(hand, kind, wanted)
  if hand ~= "main" and hand ~= "off" then
    return nil
  end
  local invSlot = hand == "off" and INVSLOT_OFFHAND or INVSLOT_MAINHAND
  local key = hand .. "|" .. kind .. "|" .. tostring(wanted)
  local found = ReadWeapon(hand == "off" and 1 or 0)
  if not found then
    local previous = lastEnchants[key]
    if previous then
      return unpack(previous, 1, 7)
    end
    return nil
  end
  NameEnchants(found, invSlot)
  local entry
  if kind == "any" then
    if wanted ~= "" then
      entry = found.imbue and NameMatches(found.imbue, wanted) and found.imbue
        or found.temporary and NameMatches(found.temporary, wanted) and found.temporary
    end
    entry = entry or found.imbue or found.temporary
  else
    entry = found[kind]
  end
  local result
  if entry then
    local remaining = entry.timeLeft / 1000
    -- Blizzard gives only the time left, so the longest seen this session stands in for the full duration.
    local full = math.max(fullDurations[entry.enchantID] or 0, remaining)
    fullDurations[entry.enchantID] = full
    local names = enchantNames[entry.enchantID] or guessedNames[entry.enchantID] or {}
    local icon = entry.enchantIconID and entry.enchantIconID > 0 and entry.enchantIconID
      or GetInventoryItemTexture("player", invSlot)
    result = { GetTime() + remaining, full, names[1] or L["Unknown"], names[2] or names[1] or L["Unknown"], icon,
      entry.charges, entry.enchantID }
  else
    result = { nil, nil, L["None"], L["None"], GetInventoryItemTexture("player", invSlot) }
  end
  lastEnchants[key] = result
  return unpack(result, 1, 7)
end

local enchant = Private.event_prototypes["Weapon Enchant"]
if enchant then
  enchant.init = function(trigger)
    EverythingAuras.TenchInit()
    local showOnActive = trigger.showOn == "showOnActive" or not trigger.showOn
    local kind = Private.ea_enchant_kinds[trigger.enchantKind or ""] and trigger.enchantKind or "any"
    return ([[
local triggerName = %q
local triggerStack = %s
local triggerRemaining = %s
local triggerShowOn = %q
local expirationTime, duration, name, shortenedName, icon, stacks, enchantID = Private.ExecEnv.EAWeaponEnchant(%q, %q, triggerName)
local remaining = expirationTime and expirationTime - GetTime()
local nameCheck = triggerName == "" or name and triggerName == name or shortenedName and triggerName == shortenedName
  or tonumber(triggerName) and enchantID and tonumber(triggerName) == enchantID
local stackCheck = not triggerStack or stacks and stacks %s triggerStack
local remainingCheck = not triggerRemaining or remaining and remaining %s triggerRemaining
local found = expirationTime and nameCheck and stackCheck and remainingCheck
if triggerRemaining and remaining and remaining >= triggerRemaining and remaining > 0 then
  Private.ExecEnv.ScheduleScan(expirationTime - triggerRemaining, "TENCH_UPDATE")
end
if not found then
  expirationTime, duration, remaining = nil, nil, nil
end
local charges = stacks
]]):format(trigger.use_enchant and tostring(trigger.enchant or "") or "",
      showOnActive and trigger.use_stacks and tonumber(trigger.stacks or 0) or "nil",
      showOnActive and trigger.use_remaining and tonumber(trigger.remaining or 0) or "nil",
      trigger.showOn or "showOnActive", trigger.weapon == "off" and "off" or trigger.weapon == "ranged" and "ranged" or "main", kind,
      OPERATORS[trigger.stacks_operator or "<"] or "<", OPERATORS[trigger.remaining_operator or "<"] or "<")
  end
  local weaponIndex = IndexOfArg(enchant.args, "weapon")
  table.insert(enchant.args, (weaponIndex or 0) + 1, {
    name = "enchantKind",
    display = L["Enchant Type"],
    type = "select",
    values = "ea_enchant_kinds",
    default = "any",
    required = true,
    test = "true",
    desc = L["Which kind of weapon enchant counts. Any counts either, the imbue first."],
  })
  local _, stacksArg = IndexOfArg(enchant.args, "stacks")
  if stacksArg then
    stacksArg.display = L["Charges"]
    stacksArg.desc = L["Charges left, such as poison charges. Texts show them with %s or %charges."]
  end
  table.insert(enchant.args, { name = "charges", hidden = true, store = true, test = "true" })
end

local SPEC_TREES = {
  WARRIOR = { "WARRIOR_ARMS", "WARRIOR_FURY", "WARRIOR_PROTECTION" },
  PALADIN = { "PALADIN_HOLY", "PALADIN_PROTECTION", "PALADIN_RETRIBUTION" },
  HUNTER = { "HUNTER_BEAST_MASTERY", "HUNTER_MARKSMANSHIP", "HUNTER_SURVIVAL" },
  ROGUE = { "ROGUE_ASSASSINATION", "ROGUE_COMBAT", "ROGUE_SUBTLETY" },
  PRIEST = { "PRIEST_DISCIPLINE", "PRIEST_HOLY", "PRIEST_SHADOW" },
  SHAMAN = { "SHAMAN_ELEMENTAL", "SHAMAN_ENHANCEMENT", "SHAMAN_RESTORATION" },
  MAGE = { "MAGE_ARCANE", "MAGE_FIRE", "MAGE_FROST" },
  WARLOCK = { "WARLOCK_AFFLICTION", "WARLOCK_DEMONOLOGY", "WARLOCK_DESTRUCTION" },
  DRUID = { "DRUID_BALANCE", "DRUID_FERAL_COMBAT", "DRUID_RESTORATION" },
}
local SPEC_CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local TREE_NAMES = {
  WARRIOR_ARMS = "Arms", WARRIOR_FURY = "Fury", WARRIOR_PROTECTION = "Protection",
  PALADIN_HOLY = "Holy", PALADIN_PROTECTION = "Protection", PALADIN_RETRIBUTION = "Retribution",
  HUNTER_BEAST_MASTERY = "Beast Mastery", HUNTER_MARKSMANSHIP = "Marksmanship", HUNTER_SURVIVAL = "Survival",
  ROGUE_ASSASSINATION = "Assassination", ROGUE_COMBAT = "Combat", ROGUE_SUBTLETY = "Subtlety",
  PRIEST_DISCIPLINE = "Discipline", PRIEST_HOLY = "Holy", PRIEST_SHADOW = "Shadow",
  SHAMAN_ELEMENTAL = "Elemental", SHAMAN_ENHANCEMENT = "Enhancement", SHAMAN_RESTORATION = "Restoration",
  MAGE_ARCANE = "Arcane", MAGE_FIRE = "Fire", MAGE_FROST = "Frost",
  WARLOCK_AFFLICTION = "Affliction", WARLOCK_DEMONOLOGY = "Demonology", WARLOCK_DESTRUCTION = "Destruction",
  DRUID_BALANCE = "Balance", DRUID_FERAL_COMBAT = "Feral Combat", DRUID_RESTORATION = "Restoration",
}

local specValues, specOrder
local function SpecValues()
  if not specValues then
    specValues, specOrder = {}, {}
    for _, classFile in ipairs(SPEC_CLASS_ORDER) do
      for _, key in ipairs(SPEC_TREES[classFile]) do
        specValues[key] = ClassLabel(classFile, L[TREE_NAMES[key]])
        specOrder[#specOrder + 1] = key
      end
    end
  end
  return specValues
end

-- One talent tree per class, its node columns in three groups 600 apart inside and over 2200 between (measured).
local COLUMN_GAP = 1200

local function ComputeSpec()
  local trees = SPEC_TREES[select(2, UnitClass("player")) or ""]
  local configID = trees and C_ClassTalents.GetActiveConfigID()
  local config = configID and C_Traits.GetConfigInfo(configID)
  local treeID = config and config.treeIDs and config.treeIDs[1]
  if not treeID then
    return nil
  end
  local columns = {}
  for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID)) do
    local node = C_Traits.GetNodeInfo(configID, nodeID)
    if node then
      if hasanysecretvalues(node.posX, node.ranksPurchased) then
        return nil
      end
      columns[node.posX] = (columns[node.posX] or 0) + (node.ranksPurchased or 0)
    end
  end
  local positions = {}
  for x in pairs(columns) do
    positions[#positions + 1] = x
  end
  table.sort(positions)
  local points, group, last = {}, 0, nil
  for _, x in ipairs(positions) do
    if not last or x - last > COLUMN_GAP then
      group = group + 1
      points[group] = 0
    end
    points[group] = points[group] + columns[x]
    last = x
  end
  if group ~= 3 then
    return nil
  end
  local best
  for index = 1, 3 do
    if points[index] >= 21 and (not best or points[index] > points[best]) then
      best = index
    end
  end
  return best and trees[best]
end

local specTime, specKey
function EverythingAuras.EAForeverSpec()
  local now = GetTime()
  if specTime ~= now then
    specTime = now
    local ok, key = pcall(ComputeSpec)
    specKey = ok and key or nil
  end
  return specKey
end

function EverythingAuras.EAForeverSpecIs(key)
  return key ~= nil and EverythingAuras.EAForeverSpec() == key
end

local specSets = {}
local function SpecSet(list)
  if type(list) == "table" then
    return list
  end
  local set = specSets[list]
  if not set then
    set = {}
    for key in tostring(list or ""):gmatch("[^,]+") do
      set[key] = true
    end
    specSets[list] = set
  end
  return set
end

-- Only never-load trees means every other tree loads, with no spec yet included.
function EverythingAuras.EAForeverSpecIn(load, never)
  load, never = SpecSet(load), SpecSet(never)
  local spec = EverythingAuras.EAForeverSpec()
  if next(load) then
    return spec ~= nil and load[spec] == true
  elseif next(never) then
    return spec == nil or not never[spec]
  end
  return false
end

local function KeyList(keys)
  return ("%q"):format(table.concat(keys, ","))
end

local StockLoadInit = Private.load_prototype.init
Private.load_prototype.init = function(load)
  local code = StockLoadInit and StockLoadInit(load) or ""
  local spec = type(load.forever_spec) == "table" and load.forever_spec or {}
  if load.use_forever_spec == true then
    code = code .. ("local eaForeverSpec = EverythingAuras.EAForeverSpecIs(%s)\n"):format(Literal(spec.single))
  elseif load.use_forever_spec == false then
    local loadKeys, neverKeys = {}, {}
    for key, value in pairs(type(spec.multi) == "table" and spec.multi or {}) do
      if type(key) == "string" then
        if value == true then
          loadKeys[#loadKeys + 1] = key
        elseif value == false then
          neverKeys[#neverKeys + 1] = key
        end
      end
    end
    table.sort(loadKeys)
    table.sort(neverKeys)
    code = code .. ("local eaForeverSpec = EverythingAuras.EAForeverSpecIn(%s, %s)\n"):format(KeyList(loadKeys),
      KeyList(neverKeys))
  end
  return code
end

local classIndex = IndexOfArg(Private.load_prototype.args, "class")
table.insert(Private.load_prototype.args, (classIndex or #Private.load_prototype.args) + 1, {
  name = "forever_spec",
  display = L["Specialization"],
  type = "multiselect",
  values = SpecValues,
  sorted = true,
  sortOrder = function()
    SpecValues()
    return specOrder
  end,
  multiTristate = true,
  test = "eaForeverSpec",
  events = { "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "SPELLS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED" },
  desc = L["Your specialization is the talent tree with 21 or more points, the one with the most if several, and the tree further left on a tie. Click a tree once to load for it, twice to never load for it. With only never-load trees, every other tree loads, no specialization yet included."],
})

-- Talent config changes come through these events, which the load frame does not register.
local specWatcher = CreateFrame("Frame")
for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED" }) do
  pcall(specWatcher.RegisterEvent, specWatcher, event)
end
specWatcher:SetScript("OnEvent", function()
  specTime = nil
  Private.ScanForLoads(nil, "PLAYER_TALENT_UPDATE")
end)
