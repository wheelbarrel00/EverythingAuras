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

local ITEMS = {
  [2512] = { name = "Rough Arrow", icon = 1001, class = 6 },
  [2516] = { name = "Light Shot", icon = 1002, class = 6 },
  [6948] = { name = "Hearthstone", icon = 1003, class = 15 },
  [9999] = { name = "Slow Arrow", icon = 1004, class = 6, unloaded = true },
}

local function fixture(forever)
  local f = { bags = {}, items = {}, durability = {}, equipped = {}, events = {}, requests = {}, frames = {} }
  local addon = { IsLibsOK = function() return true end, IsForever = function() return forever end,
    newFeatureString = "*", L = setmetatable({}, { __index = function(_, key) return key end }) }
  local private = { ExecEnv = {}, category_event_prototype = { item = {}, unit = {} },
    event_prototypes = { Money = { args = {} } },
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
    },
    GetInventoryItemDurability = function(slot)
      local d = f.durability[slot]
      if d then return d[1], d[2] end
    end,
    GetInventoryItemID = function(_, slot) return f.equipped[slot] and f.equipped[slot].id end,
    GetInventoryItemCount = function(_, slot) return f.equipped[slot] and f.equipped[slot].count or 0 end,
    GetInventoryItemTexture = function(_, slot) return f.equipped[slot] and f.equipped[slot].icon end,
  }, { __index = _G })
  setfenv(assert(loadfile(T.repoRoot .. "/EverythingAuras/EA/Triggers.lua")), env)("EverythingAuras", private)
  f.private, f.env = private, env
  return f
end

-- Built-in trigger code sees only Private.ExecEnv, so any other global read fails here.
local function run(f, trigger)
  local prototype = f.private.event_prototypes[trigger.event]
  if prototype.loadFunc then prototype.loadFunc(trigger) end
  local code = ConstructFunction(prototype, trigger)
  local chunk = assert(loadstring(code))
  local runEnv = setmetatable({ Private = { ExecEnv = f.private.ExecEnv }, issecretvalue = issecret,
    hasanysecretvalues = hassecret }, { __index = function(_, key) error("trigger code read global " .. key) end })
  setfenv(chunk, runEnv)
  local state = {}
  local ok, shown = pcall(chunk(), state, "EVENT")
  assert(ok, shown)
  return shown, state
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
local watcher = ammo.frames[1]
T.expect(#ammo.frames == 1 and watcher.events.BAG_UPDATE_DELAYED and watcher.events.GET_ITEM_INFO_RECEIVED
  and watcher.events.PLAYER_ENTERING_WORLD and watcher.unitEvents.UNIT_INVENTORY_CHANGED == "player",
  "one watcher for bags, item data and the ammo slot")
shown, state = run(ammo, { type = "item", event = "Ammo", ammoMode = "all" })
T.expect(shown and state.count == 450 and state.name == "Ammo" and state.icon == 132382,
  "all carried: arrows and shot, two kinds so the plain name")
T.expect(#ammo.frames == 1 and #ammo.requests == 1, "the watcher and the request are not repeated")
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

T.finish()
