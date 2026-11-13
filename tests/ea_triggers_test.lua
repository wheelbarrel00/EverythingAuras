-- Everything Auras 0.6.0: the new item triggers and Money filters, through GenericTrigger.lua's real code builder.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local function read(path)
  local file = assert(io.open(T.repoRoot .. "/" .. path))
  local text = file:read("*a"):gsub("\r\n", "\n")
  file:close()
  return text
end

local secret = newproxy(true)
local function forbidden() error("comparison or arithmetic on a secret value") end
for _, key in ipairs({ "__add", "__sub", "__mul", "__div", "__lt", "__le", "__eq", "__concat" }) do
  getmetatable(secret)[key] = forbidden
end
local function issecret(value) return rawequal(value, secret) end
local function hassecret(...)
  for i = 1, select("#", ...) do if issecret(select(i, ...)) then return true end end
  return false
end

local source = read("EverythingAuras/GenericTrigger.lua")
local first = assert(source:find("function TestForTriState", 1, true))
local last = assert(source:find("function Private.EndEvent", first, true))
local builderEnv = setmetatable({ tinsert = table.insert, tconcat = table.concat,
  Private = { QuotedString = function(s) return ("%q"):format(s) end } }, { __index = _G })
setfenv(assert(loadstring(source:sub(first, last - 1))), builderEnv)()
local ConstructFunction = builderEnv.ConstructFunction

local MONEY_ARGS = {
  { name = "money", init = "money", type = "number", store = true, hidden = true, test = "true" },
  { name = "gold", init = "gold", type = "number", store = true, conditionType = "number", formatter = "BigNumber" },
  { name = "silver", init = "silver", type = "number", store = true, hidden = true, test = "true" },
  { name = "copper", init = "copper", type = "number", store = true, hidden = true, test = "true" },
  { name = "icon", init = "C_CurrencyInfo.GetCoinIcon(money)", store = true, hidden = true, test = "true" },
}

local loadSource = read("EverythingAuras/EverythingAuras.lua")
local loadFirst = assert(loadSource:find("local function EvalBooleanArg", 1, true))
local loadLast = assert(loadSource:find("function EverythingAuras.GetActiveConditions", loadFirst, true))
local loadEnv = setmetatable({ tinsert = table.insert,
  Private = { QuotedString = function(s) return ("%q"):format(s) end } }, { __index = _G })
local LoadConstruct = setfenv(assert(loadstring(loadSource:sub(loadFirst, loadLast - 1) .. "\nreturn ConstructFunction")),
  loadEnv)()

-- Stands in for the stock Stance/Form/Aura code: always active, bar position 1.
local function StanceStub()
  return { type = "unit", statesParameter = "one", init = function() return "local form = 1\nlocal active = true\n" end, args = {
    { name = "note", type = "description" },
    { name = "form", display = "Form", type = "multiselect", values = "form_types", test = "active", store = true,
      conditionType = "select" },
    { name = "inverse", display = "Inverse", type = "toggle", test = "true",
      enable = function(trigger) return type(trigger.use_form) == "boolean" end },
  } }
end

-- The stock Weapon Enchant arguments, from Prototypes.lua.
local function EnchantStub()
  return { type = "item", statesParameter = "one", init = function() return "" end, args = {
    { name = "weapon", type = "select", values = "weapon_types", test = "true", default = "main", required = true },
    { name = "enchant", type = "string", test = "true" },
    { name = "enchantID", hidden = true, test = "true", store = true, conditionType = "number" },
    { name = "stacks", display = "Stack Count", type = "number", conditionType = "number", test = "true", store = true },
    { name = "duration", hidden = true, init = "duration", test = "true", store = true },
    { name = "expirationTime", init = "expirationTime", hidden = true, test = "true", store = true },
    { name = "progressType", hidden = true, init = "duration and 'timed'", test = "true", store = true },
    { name = "name", hidden = true, init = "name", test = "true", store = true },
    { name = "icon", hidden = true, init = "icon", test = "true", store = true },
    { name = "enchanted", hidden = true, init = "found == true", test = "true", store = true, conditionType = "bool" },
    { name = "remaining", type = "number", test = "true" },
    { name = "showOn", type = "select", values = "weapon_enchant_types", test = "true", default = "showOnActive",
      required = true },
    { hidden = true, test = "(triggerShowOn == 'showOnActive' and found) or (triggerShowOn == 'showOnMissing' and not found) "
      .. "or (triggerShowOn == 'showAlways')" },
  } }
end

local ITEMS = {
  [2512] = { name = "Rough Arrow", icon = 1001, class = 6 },
  [2516] = { name = "Light Shot", icon = 1002, class = 6 },
  [6948] = { name = "Hearthstone", icon = 1003, class = 15 },
  [9999] = { name = "Slow Arrow", icon = 1004, class = 6, unloaded = true },
}

local function fixture(forever)
  local f = { bags = {}, items = {}, durability = {}, equipped = {}, events = {}, requests = {}, frames = {},
    tickers = {}, units = { target = true }, range = { 25, 30 }, inRange = {}, asked = {}, enabled = {}, slots = {},
    known = {}, tracking = {}, role = "NONE", enchants = { [0] = {}, [1] = {} }, tooltip = {}, nodes = {}, config = 7,
    now = 100, loadScans = {} }
  local addon = { IsLibsOK = function() return true end, IsForever = function() return forever end,
    newFeatureString = "*", L = setmetatable({}, { __index = function(_, key) return key end }),
    GetRange = function()
      if f.range == "error" then error("range library error") end
      return f.range[1], f.range[2]
    end,
    IsSpellInRange = function()
      if f.spellRange == "error" then error("spell range error") end
      return f.spellRange
    end,
    IsSpellKnownIncludingPet = function(spell) return f.known[spell] == true end,
    TenchInit = function() f.tenchInit = true end }
  f.rawGetRange, f.rawSpellInRange = addon.GetRange, addon.IsSpellInRange
  local private = { ExecEnv = {}, category_event_prototype = { item = {}, unit = {}, spell = {} },
    event_prototypes = { Money = { args = {} }, ["Stance/Form/Aura"] = StanceStub(), ["Weapon Enchant"] = EnchantStub() },
    load_prototype = { args = { { name = "never" }, { name = "class" }, { name = "talent" } } },
    form_types = { [0] = "0 - Humanoid", [1] = "1 - Devotion Aura" },
    ScanForLoads = function(_, event) f.loadScans[#f.loadScans + 1] = event end,
    item_slot_types = { [0] = "Ammo", [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist",
      [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger", [12] = "Finger", [13] = "Trinket",
      [14] = "Trinket", [15] = "Back", [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged", [19] = "Tabard" },
    ScanEvents = function(event, ...) f.events[#f.events + 1] = { event = event, n = select("#", ...) } end }
  for i, arg in ipairs(MONEY_ARGS) do
    local copy = {}
    for k, v in pairs(arg) do copy[k] = v end
    private.event_prototypes.Money.args[i] = copy
  end
  local function frame()
    local fr = { events = {}, unitEvents = {} }
    function fr:RegisterEvent(event) self.events[event] = true end
    function fr:RegisterUnitEvent(event, unit) self.unitEvents[event] = unit end
    function fr:SetScript(name, fn) self[name] = fn end
    f.frames[#f.frames + 1] = fr
    return fr
  end
  local env = setmetatable({
    EverythingAuras = addon, CreateFrame = frame, NUM_BAG_SLOTS = 4, NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5,
    INVSLOT_AMMO = 0, Enum = { ItemClass = { Projectile = 6 } },
    issecretvalue = issecret, hasanysecretvalues = hassecret,
    C_Container = {
      GetContainerNumSlots = function(bag) return f.bags[bag] and f.bags[bag].slots or 0 end,
      GetContainerNumFreeSlots = function(bag)
        local b = f.bags[bag]
        if not b then return 0, 0 end
        return b.free, b.family
      end,
      GetContainerItemInfo = function(bag, slot)
        local entry = f.items[bag] and f.items[bag][slot]
        return entry and { itemID = entry[1], stackCount = entry[2] }
      end,
    },
    C_Item = {
      GetItemInfoInstant = function(id)
        local item = ITEMS[id]
        if not item or item.unloaded then return nil end
        return id, "type", "subtype", "", item.icon, item.class
      end,
      RequestLoadItemDataByID = function(id) f.requests[#f.requests + 1] = id end,
      GetItemNameByID = function(id) return ITEMS[id] and ITEMS[id].name end,
      GetItemIconByID = function(id) return ITEMS[id] and ITEMS[id].icon end,
      GetWeaponEnchantInfo = function(slot) return f.enchants[slot] end,
    },
    C_Minimap = {
      GetNumTrackingTypes = function() return #f.tracking end,
      GetTrackingInfo = function(index) return f.tracking[index] end,
    },
    UnitGroupRolesAssigned = function() return f.role end,
    GetShapeshiftFormID = function() return f.formID end,
    GetShapeshiftForm = function() return f.formPosition or 0 end,
    C_TooltipInfo = { GetInventoryItem = function()
      local lines = {}
      for i, text in ipairs(f.tooltip) do lines[i] = { leftText = text } end
      return { lines = lines }
    end },
    INVSLOT_MAINHAND = 16, INVSLOT_OFFHAND = 17,
    GetTime = function() return f.now end,
    UnitClass = function() return "Paladin", "PALADIN" end,
    C_ClassTalents = { GetActiveConfigID = function() return f.config end },
    C_Traits = {
      GetConfigInfo = function() return { treeIDs = { 1100 } } end,
      GetTreeNodes = function()
        local ids = {}
        for id in pairs(f.nodes) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids
      end,
      GetNodeInfo = function(_, id) return f.nodes[id] end,
    },
    GetInventoryItemDurability = function(slot)
      local d = f.durability[slot]
      if d then return d[1], d[2] end
    end,
    GetInventoryItemID = function(_, slot) return f.equipped[slot] and f.equipped[slot].id end,
    GetInventoryItemCount = function(_, slot) return f.equipped[slot] and f.equipped[slot].count or 0 end,
    GetInventoryItemTexture = function(_, slot) return f.equipped[slot] and f.equipped[slot].icon end,
    C_Timer = { NewTicker = function(interval, fn)
      local ticker = { interval = interval, fn = fn }
      f.tickers[#f.tickers + 1] = ticker
      return ticker
    end },
    UnitExists = function(unit) return f.units[unit] == true end,
    LibStub = function()
      local function iterate(list) return function() local i = 0 return function() i = i + 1 return list[i] end end end
      return { GetFriendCheckers = iterate({ 30, 5 }), GetHarmCheckers = iterate({ 10, 40 }), GetMiscCheckers = iterate({}) }
    end,
    C_ActionBar = { FindSpellActionButtons = function(id) return f.slots[id] end },
  }, { __index = _G })
  env.C_Spell = {
    GetSpellName = function(id) return ({ [20271] = "Judgement", [853] = "Hammer of Justice" })[id] end,
    GetSpellInfo = function(spell)
      if spell == 20271 or spell == "Judgement" then return { name = "Judgement", iconID = 135959, spellID = 20271 } end
      if spell == 133 or spell == "Fireball" then return { name = "Fireball", iconID = 135812, spellID = 133 } end
    end,
    IsSpellInRange = function(spell, unit)
      f.asked[#f.asked + 1] = spell
      if not env.C_Spell.GetSpellInfo(spell) then return nil end
      return f.inRange[unit]
    end,
    EnableSpellRangeCheck = function(spell, on) f.enabled[#f.enabled + 1] = { spell, on } end,
  }
  setfenv(assert(loadfile(T.repoRoot .. "/EverythingAuras/EA/Triggers.lua")), env)("EverythingAuras", private)
  f.private, f.env, f.addon = private, env, addon
  return f
end

-- Built-in trigger code sees only Private.ExecEnv, so any other global read fails here.
local function run(f, trigger, globals)
  local prototype = f.private.event_prototypes[trigger.event]
  if prototype.loadFunc then prototype.loadFunc(trigger) end
  local code = ConstructFunction(prototype, trigger)
  local chunk = assert(loadstring(code))
  local runEnv = setmetatable({ Private = { ExecEnv = f.private.ExecEnv }, issecretvalue = issecret,
    hasanysecretvalues = hassecret }, { __index = function(_, key) error("trigger code read global " .. key) end })
  for key, value in pairs(globals or {}) do rawset(runEnv, key, value) end
  setfenv(chunk, runEnv)
  local state = {}
  local ok, shown = pcall(chunk(), state, "EVENT")
  assert(ok, shown)
  return shown, state
end

local function framesFor(f, event)
  local list = {}
  for _, fr in ipairs(f.frames) do
    if fr.events[event] then list[#list + 1] = fr end
  end
  return list
end

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.001 end

T.section("Registered on WoW Forever only")
local retail = fixture(false)
T.expect(retail.private.event_prototypes["Bag Space"] == nil and next(retail.private.category_event_prototype.item) == nil,
  "Retail gets no new triggers")
T.expect(retail.private.event_prototypes.Money.args[3].hidden == true, "Retail keeps the stock Money trigger")
local f = fixture(true)
for _, event in ipairs({ "Bag Space", "Equipment Durability", "Ammo" }) do
  T.expect(f.private.event_prototypes[event] and f.private.event_prototypes[event].type == "item"
    and f.private.category_event_prototype.item[event] == f.private.event_prototypes[event].name,
    event .. " is an item trigger under its saved name")
end

T.section("Bag Space")
f.bags = { [0] = { slots = 16, free = 4, family = 0 }, [1] = { slots = 10, free = 2, family = 0 },
  [2] = { slots = 12, free = 6, family = 1 }, [3] = { slots = 0, free = 0, family = 0 } }
local shown, state = run(f, { type = "item", event = "Bag Space", bagType = "general" })
T.expect(shown and state.free == 6 and state.totalSlots == 26 and state.used == 20, "general bags: 6 of 26 free")
T.expect(near(state.freePercent, 600 / 26), "free space in percent, not rounded")
T.expect(state.freeGeneral == 6 and state.freeSpecialty == 6, "both free counts for texts")
T.expect(state.value == 6 and state.total == 26 and state.progressType == "static", "progress is free over total")
T.expect(state.name == "Bag Space" and state.icon == 133633, "name and icon")
shown, state = run(f, { type = "item", event = "Bag Space", bagType = "specialty" })
T.expect(shown and state.free == 6 and state.totalSlots == 12, "specialty bags only: the quiver")
shown, state = run(f, { type = "item", event = "Bag Space", bagType = "all" })
T.expect(shown and state.free == 12 and state.totalSlots == 38, "all bags")
shown = run(f, { type = "item", event = "Bag Space", bagType = "general", use_free = true, free = "5", free_operator = "<=" })
T.expect(shown == false, "a Free Slots filter of 5 or less does not pass with 6 free")
shown = run(f, { type = "item", event = "Bag Space", bagType = "general", use_free = true, free = "6", free_operator = "<=" })
T.expect(shown == true, "and passes at 6")
shown, state = run(f, { type = "item", event = "Bag Space", bagType = "nonsense" })
T.expect(shown and state.totalSlots == 26, "an unknown bag choice counts general bags")
f.bags[1].free = secret
shown, state = run(f, { type = "item", event = "Bag Space", bagType = "all" })
T.expect(shown and state.free == 12, "a secret reading keeps the last plain one")
f.bags[1].free = 2
f.bags[2].family = 0
shown = run(f, { type = "item", event = "Bag Space", bagType = "specialty" })
T.expect(shown == false, "no specialty bag: the aura hides")
local fresh = fixture(true)
fresh.bags = { [0] = { slots = 16, free = secret, family = 0 } }
shown = run(fresh, { type = "item", event = "Bag Space", bagType = "general" })
T.expect(shown == false, "secret with nothing read before: the aura hides")

T.section("Equipment Durability")
f.durability = { [1] = { 50, 100 }, [3] = { 0, 60 }, [5] = { 100, 100 }, [10] = { 30, 40 } }
f.equipped = { [3] = { id = 2516, icon = 5003 } }
shown, state = run(f, { type = "item", event = "Equipment Durability", durabilitySlot = 0, durabilityProgress = "overall" })
T.expect(shown and near(state.overall, 60), "overall adds the points: 180 of 300 is 60")
T.expect(state.lowest == 0 and state.broken == 1 and state.itemCount == 4, "lowest, broken and items with durability")
T.expect(state.value == 60 and state.total == 100, "progress follows Overall")
T.expect(state.name == "Light Shot" and state.icon == 5003, "the most worn item's name and icon")
shown, state = run(f, { type = "item", event = "Equipment Durability", durabilitySlot = 0, durabilityProgress = "lowest" })
T.expect(state.value == 0, "progress follows Lowest")
shown, state = run(f, { type = "item", event = "Equipment Durability", durabilitySlot = 10 })
T.expect(shown and state.lowest == 75 and state.overall == 75, "one slot: lowest and overall are the same")
shown = run(f, { type = "item", event = "Equipment Durability", durabilitySlot = 2 })
T.expect(shown == false, "a slot without durability hides")
shown = run(f, { type = "item", event = "Equipment Durability", durabilitySlot = 25 })
T.expect(shown == false, "a slot past 19 never shows")
shown, state = run(f, { type = "item", event = "Equipment Durability", use_lowest = true, lowest = "25", lowest_operator = "<" })
T.expect(shown == true, "Lowest below 25 passes with a broken item")
f.durability = { [1] = { 50, 100 }, [7] = { 40, 80 } }
f.equipped = { [1] = { id = 2512, icon = 5001 }, [7] = { id = 2516, icon = 5007 } }
shown, state = run(f, { type = "item", event = "Equipment Durability" })
T.expect(state.icon == 5001, "a tie goes to the slot higher on the character sheet")
f.durability = { [1] = { 100, 100 }, [5] = { 80, 80 } }
shown, state = run(f, { type = "item", event = "Equipment Durability" })
T.expect(shown and state.name == "Equipment Durability" and state.icon == 132530, "nothing worn: the fixed name and icon")
f.durability[5] = { secret, 80 }
shown, state = run(f, { type = "item", event = "Equipment Durability" })
T.expect(shown and state.overall == 100, "a secret reading keeps the last plain one")

T.section("Ammo")
local ammo = fixture(true)
ammo.bags = { [0] = { slots = 4 }, [1] = { slots = 2 } }
ammo.items = { [0] = { { 2512, 200 }, { 2512, 150 }, { 6948, 1 }, { 9999, 50 } }, [1] = { { 2516, 100 } } }
ammo.equipped = { [0] = { id = 2512, count = 350 } }
shown, state = run(ammo, { type = "item", event = "Ammo", ammoItemIDs = "", ammoMode = "equipped" })
T.expect(shown and state.count == 350 and state.stacks == 350 and state.value == 350, "equipped: the larger of slot and bags")
T.expect(state.name == "Rough Arrow" and state.icon == 1001, "equipped ammo's name and icon")
T.expect(#ammo.requests == 1 and ammo.requests[1] == 9999, "an item without data is asked for once")
local watcher = framesFor(ammo, "BAG_UPDATE_DELAYED")[1]
T.expect(#framesFor(ammo, "BAG_UPDATE_DELAYED") == 1 and watcher.events.BAG_UPDATE_DELAYED and watcher.events.GET_ITEM_INFO_RECEIVED
  and watcher.events.PLAYER_ENTERING_WORLD and watcher.unitEvents.UNIT_INVENTORY_CHANGED == "player",
  "one watcher for bags, item data and the ammo slot")
shown, state = run(ammo, { type = "item", event = "Ammo", ammoMode = "all" })
T.expect(shown and state.count == 450 and state.name == "Ammo" and state.icon == 132382,
  "all carried: arrows and shot, two kinds so the plain name")
T.expect(#framesFor(ammo, "BAG_UPDATE_DELAYED") == 1 and #ammo.requests == 1, "the watcher and the request are not repeated")
shown, state = run(ammo, { type = "item", event = "Ammo", ammoItemIDs = "2516" })
T.expect(shown and state.count == 100 and state.name == "Light Shot", "one listed ID: that item")
shown, state = run(ammo, { type = "item", event = "Ammo", ammoItemIDs = " 2512 , 2516, 2516" })
T.expect(shown and state.count == 450 and state.name == "Ammo", "several IDs, spaces and a repeat")
shown = run(ammo, { type = "item", event = "Ammo", ammoItemIDs = "2512," })
T.expect(shown == false, "a broken ID list never shows")
local idArg = ammo.private.event_prototypes.Ammo.args[1]
T.expect(idArg.validate(nil, "2512, 2516") == true and type(idArg.validate(nil, "abc")) == "string"
  and idArg.validate(nil, "") == true, "the options refuse a broken ID list")
T.expect(ammo.private.event_prototypes.Ammo.args[2].hidden({ ammoItemIDs = "2516" }) == true
  and ammo.private.event_prototypes.Ammo.args[2].hidden({ ammoItemIDs = " " }) == false, "Count hides while IDs are set")
shown = run(ammo, { type = "item", event = "Ammo", use_count = true, count = { "199", "1" }, count_operator = { "<=", ">" } })
T.expect(shown == false, "two count entries both have to pass")
shown = run(ammo, { type = "item", event = "Ammo", ammoItemIDs = "2516", use_count = true, count = { "199", "1" },
  count_operator = { "<=", ">" } })
T.expect(shown == true, "100 shot is 199 or less and more than 1")
shown = run(ammo, { type = "item", event = "Ammo", use_count = true, count = "5", count_operator = "<" })
T.expect(shown == true, "a single count value is no filter")

ITEMS[9999].unloaded = false
watcher.OnEvent(watcher, "GET_ITEM_INFO_RECEIVED", 6948)
T.expect(#ammo.events == 0, "item data nobody asked for changes nothing")
watcher.OnEvent(watcher, "GET_ITEM_INFO_RECEIVED", 9999)
T.expect(#ammo.events == 1 and ammo.events[1].event == "FA_AMMO_UPDATE" and ammo.events[1].n == 0,
  "the asked-for item arrives: FA_AMMO_UPDATE with no arguments")
shown, state = run(ammo, { type = "item", event = "Ammo", ammoMode = "all" })
T.expect(state.count == 500, "and it is counted")
watcher.OnEvent(watcher, "BAG_UPDATE_DELAYED")
T.expect(#ammo.events == 2 and ammo.events[2].event == "FA_AMMO_UPDATE", "bag changes send it too")

ammo.equipped = {}
shown, state = run(ammo, { type = "item", event = "Ammo" })
T.expect(shown and state.count == 500, "nothing equipped: Equipped counts all carried ammo")
ammo.items = { [0] = {}, [1] = {} }
ammo.equipped = { [0] = { id = 2516, count = 80 } }
watcher.OnEvent(watcher, "UNIT_INVENTORY_CHANGED", "player")
shown, state = run(ammo, { type = "item", event = "Ammo", ammoMode = "all" })
T.expect(shown and state.count == 80 and state.name == "Light Shot", "ammo only in the slot is counted once")
ammo.equipped[0].count = secret
shown, state = run(ammo, { type = "item", event = "Ammo", ammoMode = "all" })
T.expect(shown and state.count == 80, "a secret slot count keeps the last plain one")
ammo.equipped = {}
watcher.OnEvent(watcher, "UNIT_INVENTORY_CHANGED", "player")
shown, state = run(ammo, { type = "item", event = "Ammo" })
T.expect(shown == true and state.count == 0, "no ammo at all: count 0 and filters decide")

-- Measured on WoW Forever 2026-11-11: an empty ammo slot reads as item 0 with a count of 1.
local empty = fixture(true)
empty.bags = { [0] = { slots = 1 } }
empty.items = { [0] = { { 2512, 1 } } }
empty.equipped = { [0] = { id = 0, count = 1 } }
shown, state = run(empty, { type = "item", event = "Ammo", ammoItemIDs = "", ammoMode = "equipped" })
T.expect(shown and state.count == 1 and state.name == "Rough Arrow", "an empty slot is not ammo: Equipped counts the bags")
shown, state = run(empty, { type = "item", event = "Ammo", ammoMode = "all" })
T.expect(shown and state.count == 1 and state.name == "Rough Arrow", "and All Carried adds nothing for it")

T.section("Money filters")
local money = f.private.event_prototypes.Money.args
T.expect(money[1].hidden == nil and money[1].test == nil and money[1].conditionType == "number"
  and money[1].display == "Money (total in copper)", "total money is a filter and a condition")
T.expect(money[3].hidden == nil and money[3].conditionType == "number" and money[4].hidden == nil
  and money[4].conditionType == "number", "silver and copper too")
local code = ConstructFunction(f.private.event_prototypes.Money,
  { use_silver = true, silver = "50", silver_operator = ">=", use_money = true, money = "100", money_operator = ">" })
T.expect(code:find("silver>=50", 1, true) and code:find("money>100", 1, true), "both become tests")

T.section("Range functions for custom code (0.6.0 round 2)")
T.expect(retail.addon.GetRange == retail.rawGetRange, "Retail keeps the library calls as they are")
local r = fixture(true)
local minR, maxR = r.addon.GetRange("target", true)
T.expect(minR == 25 and maxR == 30, "a readable range passes through")
r.range = { secret, 30 }
T.expect(r.addon.GetRange("target", true) == nil, "a hidden reading is unknown")
r.range = "error"
T.expect(r.addon.GetRange("target", true) == nil and r.addon.CheckRange("target", 10, "<=") == false,
  "a library error is unknown, and CheckRange treats unknown as out of range")
r.range = { 25, 30 }
T.expect(r.addon.CheckRange("target", 30, "<=") == true and r.addon.CheckRange("target", 20, ">=") == true
  and r.addon.CheckRange("target", "x", "<=") == nil, "CheckRange with a readable range")
r.spellRange = secret
T.expect(r.addon.IsSpellInRange(20271, "target") == nil, "a hidden spell range is unknown")
r.spellRange = "error"
T.expect(r.addon.IsSpellInRange(20271, "target") == nil, "and so is an error")
r.spellRange = 1
T.expect(r.addon.IsSpellInRange(20271, "target") == 1, "a readable answer passes through")

T.section("Range Check")
local rc = fixture(true)
shown, state = run(rc, { type = "unit", event = "Range Check", unit = "target" })
T.expect(shown and state.minRange == 25 and state.maxRange == 30 and state.unit == "target", "no filter: shows the estimate")
T.expect(#rc.tickers == 1 and rc.tickers[1].interval == 0.1, "checked 10 times a second")
rc.tickers[1].fn()
T.expect(rc.events[#rc.events].event == "EA_RANGE_UPDATE", "each tick scans the range triggers")
run(rc, { type = "unit", event = "Range Check" })
T.expect(#rc.tickers == 1, "one timer for every range trigger")
shown = run(rc, { type = "unit", event = "Range Check", use_range = true, range = "5", range_operator = "<=" })
T.expect(shown == false, "within 5 yards fails at 25-30")
shown = run(rc, { type = "unit", event = "Range Check", use_range = true, range = "30", range_operator = "<=" })
T.expect(shown == true, "within 30 yards passes")
shown = run(rc, { type = "unit", event = "Range Check", use_range = true, range = "20" })
T.expect(shown == true, "no operator means at least 20 yards")
shown = run(rc, { type = "unit", event = "Range Check", use_range = true, range = "", range_operator = "<=" })
T.expect(shown == false, "a blank distance counts as 8 yards")
rc.range = { 0, 5 }
shown = run(rc, { type = "unit", event = "Range Check", use_range = true, range = "", range_operator = "<=" })
T.expect(shown == true, "so a target within 5 yards passes it")
rc.range = { 25, 30 }
rc.range = { secret, secret }
shown, state = run(rc, { type = "unit", event = "Range Check", use_range = true, range = "40", range_operator = "<=" })
T.expect(shown == false, "an unknown range fails a distance filter")
shown, state = run(rc, { type = "unit", event = "Range Check" })
T.expect(shown and state.minRange == 0 and state.maxRange == 999, "and reads 0 to 999 without one")
rc.units.target = nil
shown = run(rc, { type = "unit", event = "Range Check" })
T.expect(shown == false, "no target: hidden")
local rangeArg = rc.private.event_prototypes["Range Check"].args[5]
rc.units.target, rc.range = true, { 25, 30 }
T.expect(rangeArg.name == "range" and rangeArg.conditionTest({ unit = "target" }, 30, "<=") == true,
  "the Distance condition asks the guarded range")
T.expect(rc.private.event_prototypes["Range Check"].args[1].text():find("30", 1, true) ~= nil,
  "the note lists the ranges this character can measure")

T.section("Spell in Range")
local sr = fixture(true)
sr.inRange.target = true
shown, state = run(sr, { type = "spell", event = "Spell in Range", spellName = 20271, unit = "target" })
T.expect(shown and state.name == "Judgement" and state.icon == 135959 and state.unit == "target", "in range: shown")
T.expect(sr.asked[#sr.asked] == "Judgement", "asked by name, which covers every rank")
T.expect(#sr.enabled == 1 and sr.enabled[1][1] == 20271 and sr.enabled[1][2] == true, "the range event is switched on once")
T.expect(#sr.tickers == 0, "the current target needs no timer")
local watch = framesFor(sr, "SPELL_RANGE_CHECK_UPDATE")[1]
T.expect(watch.events.SPELL_RANGE_CHECK_UPDATE and watch.events.PLAYER_TARGET_CHANGED, "range and target changes are heard")
watch.OnEvent(watch, "SPELL_RANGE_CHECK_UPDATE", 853, true, true)
T.expect(#sr.events == 0, "another addon's spell starts no scan")
watch.OnEvent(watch, "SPELL_RANGE_CHECK_UPDATE", 20271, false, true)
watch.OnEvent(watch, "PLAYER_TARGET_CHANGED")
watch.OnEvent(watch, "SPELL_RANGE_CHECK_UPDATE", secret, false, true)
T.expect(#sr.events == 3 and sr.events[1].event == "EA_SPELL_RANGE_UPDATE", "a watched spell, a new target or a hidden ID does")
sr.inRange.target = false
shown = run(sr, { type = "spell", event = "Spell in Range", spellName = 20271 })
T.expect(shown == false, "out of range: hidden")
shown = run(sr, { type = "spell", event = "Spell in Range", spellName = 20271, use_inverse = true })
T.expect(shown == true, "Inverse shows it out of range")
sr.inRange.target = nil
T.expect(run(sr, { type = "spell", event = "Spell in Range", spellName = 20271 }) == false
  and run(sr, { type = "spell", event = "Spell in Range", spellName = 20271, use_inverse = true }) == false,
  "no answer hides it either way")
sr.inRange.target = secret
T.expect(run(sr, { type = "spell", event = "Spell in Range", spellName = 20271, use_inverse = true }) == false,
  "a hidden answer too")
sr.inRange.target = true
shown = run(sr, { type = "spell", event = "Spell in Range", spellName = 20271, use_exact_spellName = true })
T.expect(shown and sr.asked[#sr.asked] == 20271, "Exact Spell Match asks by ID")
shown = run(sr, { type = "spell", event = "Spell in Range", spellName = "Judgement", use_exact_spellName = true })
T.expect(shown == false, "an exact match on a name is no spell")
sr.units.focus, sr.inRange.focus = true, true
shown = run(sr, { type = "spell", event = "Spell in Range", spellName = "Judgement", unit = "focus" })
T.expect(shown and #sr.tickers == 1, "focus is checked 10 times a second")
T.expect(#sr.enabled == 1, "the range event was switched on once over every load")
T.expect(sr.private.event_prototypes["Spell in Range"].internal_events({ unit = "focus" })[1] == "EA_RANGE_UPDATE"
  and sr.private.event_prototypes["Spell in Range"].internal_events({})[1] == "EA_SPELL_RANGE_UPDATE",
  "the target listens to the range event, other units to the timer")

T.section("Spell in Range (Action Bar)")
local ab = fixture(true)
ab.known.Judgement, ab.slots[20271], ab.inRange.target = true, { 7, 19 }, true
local bar = { type = "spell", event = "Spell in Range (Action Bar)", spellName = 20271 }
shown, state = run(ab, bar)
T.expect(shown and state.rangeState == "inRange" and state.inRange == true and state.slot == 7, "in range, slot 7")
ab.inRange.target = false
shown, state = run(ab, bar)
T.expect(shown and state.rangeState == "outOfRange" and state.inRange == false, "out of range still shows without Show On")
ab.inRange.target = nil
shown, state = run(ab, bar)
T.expect(shown and state.rangeState == "noTarget", "no target")
ab.inRange.target = true
shown = run(ab, { type = "spell", event = "Spell in Range (Action Bar)", spellName = 20271, use_rangeState = true,
  rangeState = "outOfRange" })
T.expect(shown == false, "Show On Out of Range hides it in range")
shown = run(ab, { type = "spell", event = "Spell in Range (Action Bar)", spellName = 20271, use_rangeState = false,
  rangeState = "inRange" })
T.expect(shown == true, "a Show On left unticked is no filter")
ab.slots[20271] = nil
shown, state = run(ab, bar)
T.expect(shown and state.slot == nil, "not on any bar: still shown, no slot")
shown = run(ab, { type = "spell", event = "Spell in Range (Action Bar)", spellName = "Fireball" })
T.expect(shown == false, "a spell you do not know never shows")

T.section("Tracking (0.6.0 round 3)")
local tr = fixture(true)
tr.tracking = { { name = "Sense Undead", spellID = 5502, active = false, texture = 11 },
  { name = "Flight Master", active = true, texture = 12 }, { name = "Banker", active = false, texture = 13 } }
local function tracking(key, show) return run(tr, { type = "unit", event = "Tracking", trackingType = key, trackingShow = show }) end
T.expect(tracking("5502", "active") == false, "Sense Undead off: Active hides")
shown, state = tracking("5502", "inactive")
T.expect(shown and state.name == "Sense Undead" and state.active == false and state.icon == 11, "and Inactive shows it")
T.expect(tracking("Flight Master", "active") == true, "a map filter is picked by name")
shown, state = tracking("anySpell", "inactive")
T.expect(shown and state.name == "Any Tracking Spell", "no tracking spell on: Any Tracking Spell, Inactive shows")
T.expect(tracking("anySpell", "active") == false, "map filters that are on do not count")
tr.tracking[1].active = true
shown, state = tracking("anySpell", "active")
T.expect(shown and state.name == "Sense Undead" and state.icon == 11, "Sense Undead on: Any Tracking Spell is active")
T.expect(tracking("anySpell", "inactive") == false, "and Inactive hides")
T.expect(tracking("2580", "always") == false and tracking(nil, "always") == false, "an entry this character lacks never shows")
T.expect(tracking("Banker", "always") == true, "Always shows an entry either way")
local values = tr.private.event_prototypes.Tracking.args[1].values({ trackingType = "2580" })
T.expect(values.anySpell and values["5502"] == "Sense Undead" and values["Flight Master"] and values["2580"] == "2580 (unavailable)",
  "the list has Any Tracking Spell, spells by ID, filters by name, and a missing saved entry")

T.section("Role")
local ro = fixture(true)
local function role(want) return run(ro, { type = "unit", event = "Role", role = want, use_role = true }) end
T.expect(role("TANK") == false, "no role assigned: hidden")
ro.role = "TANK"
shown, state = role("TANK")
T.expect(shown and state.role == "TANK" and state.name == "TANK", "the chosen role shows, its name is the role")
T.expect(role("HEALER") == false, "another role hides")
T.expect(run(ro, { type = "unit", event = "Role" }) == true, "no role chosen: any assigned role shows")
ro.role = secret
T.expect(role("TANK") == false and run(ro, { type = "unit", event = "Role" }) == false, "a hidden role hides")
ro.role = "NONE"
T.expect(run(ro, { type = "unit", event = "Role" }) == false, "no role chosen still hides while the game reports none")

T.section("Form ID on Stance/Form/Aura")
local fm = fixture(true)
local stanceArgs = fm.private.event_prototypes["Stance/Form/Aura"].args
T.expect(stanceArgs[2].name == "formID" and stanceArgs[3].name == "form" and stanceArgs[3].display == "Form (Bar Position)",
  "Form comes first, the old option becomes Form (Bar Position)")
local positions = stanceArgs[3].values()
T.expect(positions[1] == "1 - Devotion Aura" and positions[0] == "0 - Humanoid" and positions[10]
  and positions[10]:find("Not known", 1, true), "bar positions 1-10 stay pickable for imported auras")
T.expect(stanceArgs[3].hidden({ use_formID = true }) == true and stanceArgs[3].hidden({ use_formID = true, use_form = true }) == false
  and stanceArgs[3].hidden({}) == false, "Bar Position hides while Form is used alone")
T.expect(stanceArgs[4].enable({ use_formID = false }) == true and stanceArgs[4].enable({}) == false, "Inverse works with Form too")
local formValues = stanceArgs[2].values()
T.expect(formValues[0] == "Humanoid" and formValues[5] == "Druid: Bear Form" and formValues[17] == "Warrior: Battle Stance"
  and formValues[8] == nil, "the form list, with no separate Dire Bear")
local function form(id, trigger)
  fm.formID = id
  trigger.type, trigger.event = "unit", "Stance/Form/Aura"
  return run(fm, trigger)
end
T.expect(form(5, { use_formID = true, formID = { single = 5 } }) == true, "Bear Form matches Bear Form")
T.expect(form(8, { use_formID = true, formID = { single = 5 } }) == true, "Dire Bear counts as Bear Form")
T.expect(form(5, { use_formID = true, formID = { single = 8 } }) == true, "a saved Dire Bear matches Bear Form")
T.expect(form(33, { use_formID = true, formID = { single = 31 } }) == true, "every race's Moonkin ID matches Moonkin Form")
T.expect(form(18, { use_formID = false, formID = { multi = { [17] = true, ["19"] = true } } }) == false
  and form(19, { use_formID = false, formID = { multi = { [17] = true, ["19"] = true } } }) == true, "multi, keys as numbers or text")
T.expect(form(nil, { use_formID = true, formID = { single = 0 } }) == true, "no form, a paladin aura included, is Humanoid")
T.expect(form(18, { use_formID = true, formID = { single = 18 }, use_inverse = true }) == false, "Inverse flips it")
T.expect(form(18, { use_formID = false, formID = { multi = {} } }) == false, "an empty multi never shows")
fm.formPosition = 2
shown, state = form(18, { use_formID = true, formID = { single = 18 } })
T.expect(shown and state.form == 2 and state.formID == 18, "Form keeps storing the bar position too")
shown, state = form(18, { use_form = true, form = { single = 1 } })
T.expect(shown == true and state.formID == 18, "without Form the stock bar position code runs, and the form ID is stored")

T.section("Weapon Enchant kinds")
local we = fixture(true)
local enchantArgs = we.private.event_prototypes["Weapon Enchant"].args
T.expect(enchantArgs[2].name == "enchantKind" and enchantArgs[2].default == "any" and enchantArgs[5].display == "Charges"
  and enchantArgs[#enchantArgs].name == "charges", "Enchant Type after Weapon, Stack Count reads Charges, charges stored")
we.equipped = { [16] = { icon = 999 }, [17] = { icon = 998 } }
we.enchants[0] = { { enchantType = 2, timeLeft = 1774011, charges = 0, enchantID = 2623, enchantIconID = 0 },
  { enchantType = 0, timeLeft = 0, charges = 0, enchantID = 0, enchantIconID = 0 } }
we.tooltip = { "Mace of Testing", "Minor Wizard Oil (29 min)" }
local G = { GetTime = function() return we.now end, tonumber = tonumber }
local function weapon(trigger)
  trigger.type, trigger.event = "item", "Weapon Enchant"
  return run(we, trigger, G)
end
shown, state = weapon({ weapon = "main", enchantKind = "any" })
T.expect(shown and state.name == "Minor Wizard Oil" and state.icon == 999 and near(state.duration, 1774.011)
  and near(state.expirationTime, 100 + 1774.011) and state.enchanted == true and state.enchantID == 2623, "the oil, as measured")
T.expect(we.tenchInit, "the stock enchant events still drive it")
T.expect(weapon({ weapon = "main", enchantKind = "temporary" }) == true, "Oil, Stone or Poison finds it")
T.expect(weapon({ weapon = "main", enchantKind = "imbue" }) == false, "Imbue does not")
shown, state = weapon({ weapon = "main", enchantKind = "imbue", showOn = "showOnMissing" })
T.expect(shown and state.name == "None" and state.icon == 999, "Show On Missing: None with the weapon's icon")
we.enchants[0][2] = { enchantType = 3, timeLeft = 600000, charges = 5, enchantID = 5000, enchantIconID = 777 }
we.tooltip = { "Mace of Testing", "Flametongue 3 (10 min)", "Minor Wizard Oil (29 min)" }
shown, state = weapon({ weapon = "main", enchantKind = "any" })
T.expect(shown and state.name == "Flametongue 3" and state.charges == 5 and state.stacks == 5 and state.icon == 777,
  "both on one weapon: Any shows the imbue, named by its time left")
shown, state = weapon({ weapon = "main", enchantKind = "temporary" })
T.expect(shown and state.name == "Minor Wizard Oil", "and the oil apart")
shown, state = weapon({ weapon = "main", enchantKind = "any", use_enchant = true, enchant = "Minor Wizard Oil" })
T.expect(shown and state.enchantID == 2623, "Any with a typed name takes the one that carries it")
T.expect(weapon({ weapon = "main", enchantKind = "imbue", use_stacks = true, stacks = "3", stacks_operator = ">" }) == true
  and weapon({ weapon = "main", enchantKind = "imbue", use_stacks = true, stacks = "5", stacks_operator = "=" }) == true,
  "a Charges filter, an imported = included")
we.now = 160
we.enchants[0][1].timeLeft = 1714011
shown, state = weapon({ weapon = "main", enchantKind = "temporary" })
T.expect(near(state.duration, 1774.011) and near(state.expirationTime, 160 + 1714.011), "the full duration is the longest seen")
we.enchants[0][1].timeLeft = secret
shown, state = weapon({ weapon = "main", enchantKind = "temporary" })
T.expect(shown and near(state.expirationTime, 160 + 1714.011), "a hidden reading keeps the last plain one")
T.expect(weapon({ weapon = "off", enchantKind = "any" }) == false, "nothing on the off hand")
local both = fixture(true)
both.equipped = { [16] = { icon = 999 } }
both.enchants[0] = { { enchantType = 2, timeLeft = 1774011, charges = 0, enchantID = 2623, enchantIconID = 0 },
  { enchantType = 3, timeLeft = 600000, charges = 5, enchantID = 5000, enchantIconID = 777 } }
both.tooltip = { "Minor Wizard Oil (29 min)", "Flametongue 3 (10 min)" }
shown, state = run(both, { type = "item", event = "Weapon Enchant", weapon = "main", enchantKind = "imbue" },
  { GetTime = function() return both.now end, tonumber = tonumber })
T.expect(shown and state.name == "Flametongue 3", "two enchants seen first together are named by time left, not order")

T.section("Talent spec load option")
local sp = fixture(true)
local COLUMNS = { 1020, 1620, 2220, 2820, 5020, 5620, 6220, 6820, 9080, 9680, 10280, 10880 }
local function talents(holy, prot, ret)
  sp.nodes = {}
  for i, x in ipairs(COLUMNS) do sp.nodes[i] = { posX = x, ranksPurchased = 0 } end
  sp.nodes[3].ranksPurchased, sp.nodes[6].ranksPurchased, sp.nodes[10].ranksPurchased = holy, prot, ret
  sp.now = sp.now + 1
end
talents(5, 0, 1)
T.expect(sp.addon.EAForeverSpec() == nil, "Holy 5, Retribution 1 (the measured level 14 tree): no spec")
talents(21, 10, 0)
T.expect(sp.addon.EAForeverSpec() == "PALADIN_HOLY", "Holy at 21: Holy")
talents(20, 0, 31)
T.expect(sp.addon.EAForeverSpec() == "PALADIN_RETRIBUTION", "the most points wins")
talents(21, 0, 21)
T.expect(sp.addon.EAForeverSpec() == "PALADIN_HOLY", "a tie goes to the tree further left")
talents(21, 0, 0)
sp.nodes[13] = { posX = 14000, ranksPurchased = 0 }
T.expect(sp.addon.EAForeverSpec() == nil, "a fourth column group is unreadable: no spec")
talents(21, 0, 0)
sp.nodes[2].posX = secret
T.expect(sp.addon.EAForeverSpec() == nil, "a hidden reading: no spec")
local loadArgs = sp.private.load_prototype.args
T.expect(loadArgs[3].name == "forever_spec" and loadArgs[3].multiTristate and loadArgs[3].values().PALADIN_HOLY == "Paladin: Holy",
  "Specialization sits right after Player Class, with load and never-load boxes")
local function loads(load)
  local code, events = LoadConstruct(sp.private.load_prototype, load)
  local fn = setfenv(assert(loadstring(code)), setmetatable({ EverythingAuras = sp.addon }, { __index = _G }))()
  return fn("SCAN_ALL"), events
end
talents(31, 0, 20)
local result, events = loads({ use_forever_spec = true, forever_spec = { single = "PALADIN_HOLY" } })
T.expect(result == true and events.PLAYER_TALENT_UPDATE and events.SPELLS_CHANGED, "single Holy loads for Holy, on talent events")
T.expect(loads({ use_forever_spec = true, forever_spec = { single = "PALADIN_RETRIBUTION" } }) == false, "not for Retribution")
T.expect(loads({ use_forever_spec = false, forever_spec = { multi = { PALADIN_HOLY = true, WARRIOR_FURY = true } } }) == true,
  "multi with Holy loads")
T.expect(loads({ use_forever_spec = false, forever_spec = { multi = { PALADIN_HOLY = false } } }) == false, "never-load Holy")
T.expect(loads({ use_forever_spec = false, forever_spec = { multi = { PALADIN_PROTECTION = false } } }) == true,
  "only never-load trees: every other tree loads")
talents(5, 0, 1)
T.expect(loads({ use_forever_spec = false, forever_spec = { multi = { PALADIN_PROTECTION = false } } }) == true,
  "no spec yet loads under only never-load trees")
T.expect(loads({ use_forever_spec = false, forever_spec = { multi = { PALADIN_HOLY = true, PALADIN_PROTECTION = false } } })
  == false, "no spec never loads once a load tree is picked")
T.expect(loads({ use_forever_spec = true, forever_spec = { single = "PALADIN_HOLY" } }) == false, "nor in single mode")
T.expect(loads({ use_forever_spec = false, forever_spec = { multi = {} } }) == false, "nothing ticked never loads")
T.expect(loads({ forever_spec = { single = "PALADIN_HOLY" } }) == true, "the option off is ignored")
local specFrame = framesFor(sp, "TRAIT_CONFIG_UPDATED")[1]
specFrame.OnEvent(specFrame, "TRAIT_CONFIG_UPDATED")
T.expect(specFrame.events.ACTIVE_COMBAT_CONFIG_CHANGED and sp.loadScans[1] == "PLAYER_TALENT_UPDATE",
  "a talent tree save or a Primary and Secondary swap re-checks the loads")

T.finish()
