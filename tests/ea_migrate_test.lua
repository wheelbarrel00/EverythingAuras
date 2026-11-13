-- Everything Auras' own migrations (EA/Migrate.lua), which change saved auras at every login.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local SPELLS = { [20154] = "Seal of Righteousness", [20287] = "Seal of Righteousness", [21084] = "Seal of Righteousness",
  [8050] = "Flame Shock", [20271] = "Judgement", [853] = "Hammer of Justice", [19740] = "Blessing of Might" }
local HARMFUL = { [8050] = true, [853] = true }
local VIEWER = { [199385] = { spellID = 20271 }, [200288] = { spellID = 19740, linkedSpellIDs = { 19834 } } }
local private, warningRuns, qualifies = {}, 0, true
local forever, savedAuras = true, {}
private.EANativeQualifies = function() return qualifies end
private.EAUpdateWarnings = function() warningRuns = warningRuns + 1 end
local function CopyTable(t)
  local c = {}
  for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
  return c
end
local env = setmetatable({
  EverythingAuras = { IsLibsOK = function() return true end, IsForever = function() return forever end,
    GetData = function(id) return savedAuras[id] end,
    SafeToNumber = function(v) local n = tonumber(v) return n and n < 2147483648 and n > -2147483649 and n or nil end },
  C_Spell = {
    GetSpellName = function(id)
      assert(id < 2147483648, "a spell ID past 32 bits reached the client")
      return SPELLS[id]
    end,
    GetSpellInfo = function(name)
      for id, spell in pairs(SPELLS) do
        if spell == name then return { spellID = id } end
      end
    end,
    IsSpellHarmful = function(id) return HARMFUL[id] == true end,
  },
  C_CooldownViewer = { GetCooldownViewerCooldownInfo = function(id) return VIEWER[id] end },
  CopyTable = CopyTable,
  issecretvalue = function() return false end,
}, { __index = _G })
setfenv(assert(loadfile(T.repoRoot .. "/EverythingAuras/EA/Migrate.lua")), env)("EverythingAuras", private)

T.section("ForeverAuras' unbacked internalVersion 91")
local data, children = { tocversion = 16001, internalVersion = 91 }, { { internalVersion = 91 }, { internalVersion = 88 } }
private.EANormalizeImport(data, children)
T.expect(data.internalVersion == 90 and children[1].internalVersion == 90, "a Forever-built 91 becomes 90, children too")
T.expect(children[2].internalVersion == 88, "other versions stay")
local retail = { tocversion = 120000, internalVersion = 91 }
private.EANormalizeImport(retail)
T.expect(retail.internalVersion == 91, "a string built on another client keeps its number")
local ours = { tocversion = 16001, eaVersion = 7 }
private.EANormalizeImport(ours)
T.expect(private.EAForeignImports[data] == true and not private.EAForeignImports[ours]
  and not private.EAForeignImports[retail], "a Forever string another addon made is noted before PreAdd stamps it")

T.section("Aura (Modern) becomes the standard aura trigger")
local trigger = {
  type = "secretAura", debuffType = "Buff", secretShowOn = "showOnMissing",
  secretUseRem = true, secretRemOperator = "<", secretRem = "5",
  secretUseStacks = true, secretStacksOperator = ">=", secretStacks = "2",
  auraspellids = { "6673" }, secretUseRankSpellIDs = true, auraRankSpellIDs = { 20154, 20287, 21084 },
}
data = { triggers = { { trigger = trigger } }, regionType = "icon" }
private.EAModernize(data)
T.expect(trigger.type == "aura2" and trigger.eaConvertedFrom == "secretAura", "converted and marked")
T.expect(trigger.debuffType == "HELPFUL", "Buff maps to HELPFUL")
T.expect(trigger.matchesShowOn == "showOnMissing", "its Show On carries over")
T.expect(trigger.useRem and trigger.remOperator == "<" and trigger.rem == "5"
  and trigger.useStacks and trigger.stacksOperator == ">=" and trigger.stacks == "2", "remaining time and stacks carry over")
T.expect(trigger.useExactSpellId == true, "exact spell IDs stay in use")
T.expect(trigger.useName and #trigger.auranames == 1 and trigger.auranames[1] == "Seal of Righteousness",
  "rank seeds become one name, every rank shares it")
T.expect(trigger.secretShowOn == "showOnMissing" and trigger.auraRankSpellIDs[3] == 21084, "ForeverAuras' own fields stay")
T.expect(data.eaNative == true, "a converted icon that qualifies is drawn by Blizzard")

local unknown = { type = "secretAura", debuffType = "Debuff", secretUseSpellIDs = false,
  secretUseRankSpellIDs = true, auraRankSpellIDs = { 999999 } }
data = { triggers = { { trigger = unknown } }, eaNative = false }
private.EAModernize(data)
T.expect(unknown.debuffType == "HARMFUL", "Debuff maps to HARMFUL")
T.expect(unknown.useExactSpellId == true and unknown.auraspellids[1] == 999999,
  "rank seeds no name resolves for become exact spell IDs")
T.expect(data.eaNative == false, "a switch already off stays off")

T.section("Media from the old addon folders")
data = { triggers = {}, texture = "Interface\\AddOns\\WeakAuras\\Media\\Textures\\Circle_Smooth",
  sub = { { sound = "interface/addons/ForeverAuras/Media/Sounds/Ding.ogg" } },
  font = "Interface\\AddOns\\SomethingElse\\Font.ttf" }
private.EAModernize(data)
T.expect(data.texture == "Interface\\AddOns\\EverythingAuras\\Media\\Textures\\Circle_Smooth", "a WeakAuras texture is remapped")
T.expect(data.sub[1].sound == "Interface\\AddOns\\EverythingAuras\\Media/Sounds/Ding.ogg", "nested and any case")
T.expect(data.font == "Interface\\AddOns\\SomethingElse\\Font.ttf", "other addons' media stays")

T.section("Spec loads become class loads")
data = { triggers = {}, load = { use_class_and_spec = true, class_and_spec = { single = 1486 } } }
private.EAModernize(data)
T.expect(data.load.use_class == true and data.load.class.single == "PALADIN", "one spec becomes its class")
T.expect(data.load.class_and_spec.single == 1486, "the spec field stays")
data = { triggers = {}, load = { use_class_and_spec = false, class_and_spec = { multi = { [1486] = true, [1491] = true } } } }
private.EAModernize(data)
T.expect(data.load.use_class == false and data.load.class.multi.PALADIN and data.load.class.multi.WARRIOR
  and data.load.class.single == nil, "several specs become several classes")
data = { triggers = {}, load = { use_class_and_spec = true, class_and_spec = { single = 71 } } }
private.EAModernize(data)
T.expect(data.load.use_class == nil, "an unknown (retail) spec changes nothing")
data = { triggers = {}, load = { use_class = true, class = { single = "MAGE" }, use_class_and_spec = true,
  class_and_spec = { single = 1486 } } }
private.EAModernize(data)
T.expect(data.load.class.single == "MAGE", "an existing class load is kept")

T.section("Aura (Modern) settings the first conversion missed (0.5.1)")
local fresh = { type = "secretAura", debuffType = "Debuff", unit = "target",
  secretUseTotal = true, secretTotalOperator = "=", secretTotal = "30",
  secretUseStacks = true, secretStacksOperator = "=", secretStacks = "3",
  nativeFilters = { PLAYER = true }, secretUseRankSpellIDs = true, auraRankSpellIDs = { 20154, " Demon Skin " },
  secretUseExcludedSpellIDs = true, excludedAuraSpellIDs = { "408498", "409946" } }
data = { triggers = { { trigger = fresh } }, regionType = "icon" }
private.EAModernize(data)
T.expect(fresh.totalOperator == "==" and fresh.stacksOperator == "==", "an equals filter gets the operator Lua compiles")
local compiles = loadstring("return function(m) return not(m.duration / m.modRate " .. fresh.totalOperator .. " 30) end")
T.expect(compiles ~= nil and loadstring("return function(m) return not(m.duration / m.modRate = 30) end") == nil,
  "the old operator did not compile, the new one does")
T.expect(fresh.ownOnly == true, "Own Only comes from the saved PLAYER filter")
T.expect(fresh.useName and fresh.auranames[1] == "Seal of Righteousness" and fresh.auranames[2] == "Demon Skin",
  "a typed name is kept beside the names its IDs give")
T.expect(not fresh.useExactSpellId, "no exact IDs appear from a name")
T.expect(fresh.useIgnoreExactSpellId and fresh.ignoreAuraSpellids[1] == "408498" and fresh.ignoreAuraSpellids[2] == "409946",
  "excluded IDs become the ignore list")
T.expect(fresh.secretTotalOperator == "=" and fresh.nativeFilters.PLAYER == true, "ForeverAuras' own fields stay")

local notMine = { type = "secretAura", debuffType = "Buff", nativeFilters = { PLAYER = false }, ownOnly = nil,
  auraspellids = { "1" } }
private.EAModernize({ triggers = { { trigger = notMine } } })
T.expect(notMine.ownOnly == false, "a false PLAYER filter means not mine")
local kept = { type = "secretAura", debuffType = "Buff", nativeFilters = { PLAYER = true }, ownOnly = false,
  auraspellids = { "1" } }
private.EAModernize({ triggers = { { trigger = kept } } })
T.expect(kept.ownOnly == false, "an Own Only the aura already has is kept")

local names = { type = "secretAura", debuffType = "Buff", secretUseRankSpellIDs = true, auraRankSpellIDs = { "Well Fed" } }
private.EAModernize({ triggers = { { trigger = names } } })
T.expect(names.useName and names.auranames[1] == "Well Fed" and not names.useExactSpellId,
  "a list of typed names matches by name, not as text spell IDs")

-- The shape the old conversion left behind, saved by 0.5.0.
local saved = { type = "aura2", eaConvertedFrom = "secretAura", debuffType = "HARMFUL", unit = "target",
  useTotal = true, totalOperator = "=", total = "30", secretUseRankSpellIDs = true, auraRankSpellIDs = { "Demon Skin" },
  useExactSpellId = true, auraspellids = { "Demon Skin" }, nativeFilters = { PLAYER = true } }
data = { triggers = { { trigger = saved } }, eaVersion = 4 }
private.EAModernize(data)
T.expect(saved.totalOperator == "==" and saved.ownOnly == true, "auras imported before 0.5.1 are fixed too")
T.expect(saved.useName and saved.auranames[1] == "Demon Skin" and not saved.useExactSpellId and #saved.auraspellids == 0,
  "a name stored as an exact ID moves to the names")
T.expect(data.eaVersion == 7, "and they reach the new counter")

local dispel = { type = "secretAura", debuffType = "Debuff", auraspellids = { "1" }, includeDispelTypes = { Magic = true } }
private.EAModernize({ triggers = { { trigger = dispel } } })
T.expect(dispel.use_debuffClass and dispel.debuffClass.magic and not dispel.debuffClass.curse, "included dispel types")
local undispel = { type = "secretAura", debuffType = "Debuff", auraspellids = { "1" },
  excludeDispelTypes = { Bleed = true, Curse = true, Disease = true, Magic = true, Poison = true } }
private.EAModernize({ triggers = { { trigger = undispel } } })
T.expect(undispel.use_debuffClass and undispel.debuffClass.none and undispel.debuffClass.enrage
  and not undispel.debuffClass.magic, "excluded dispel types leave the others")

local units = { type = "secretAura", debuffType = "Buff", unit = "group", auraspellids = { "1" },
  useUnitClass = true, unitClass = { ROGUE = true }, useUnitRoles = true, unitRoles = { HEALER = true },
  useUnitNames = true, unitNames = { "Bob", "Ann" }, useIncludePets = true }
private.EAModernize({ triggers = { { trigger = units } } })
T.expect(units.useClass and units.class.ROGUE and units.useGroupRole and units.group_role.HEALER,
  "class and role filters carry over")
T.expect(units.useUnitName and units.unitName == "Ann, Bob" and units.use_includePets and units.includePets == "PlayersAndPets",
  "names and pets carry over")

local list = { type = "secretAura", debuffType = "Buff", secretSpellList = "my_list" }
private.EAModernize({ triggers = { { trigger = list } } })
T.expect(list.useName == true and type(list.auranames) == "table" and #list.auranames == 0,
  "a spell list it cannot read matches nothing instead of every aura")

T.section("Pre-ship scan fixes (0.5.1)")
local numeric = { type = "secretAura", debuffType = "Buff", auraspellids = { "1" }, secretUseExcludedSpellIDs = true,
  excludedAuraSpellIDs = { 408498 } }
private.EAModernize({ triggers = { { trigger = numeric } } })
T.expect(numeric.ignoreAuraSpellids and numeric.ignoreAuraSpellids[1] == "408498", "excluded IDs saved as numbers carry over")

local leftover = { type = "secretAura", debuffType = "Debuff", auraspellids = { "1" }, use_debuffClass = false,
  includeDispelTypes = { Magic = true } }
private.EAModernize({ triggers = { { trigger = leftover } } })
T.expect(leftover.use_debuffClass == true, "on a fresh import the export's own dispel types win over a leftover off")
local switchedOff = { type = "aura2", eaConvertedFrom = "secretAura", debuffType = "HARMFUL", auraspellids = { "1" },
  useExactSpellId = true, use_debuffClass = false, includeDispelTypes = { Magic = true } }
private.EAModernize({ triggers = { { trigger = switchedOff } }, eaVersion = 4 })
T.expect(switchedOff.use_debuffClass == false, "a dispel filter switched off on an aura saved before stays off")
local namesOff = { type = "aura2", eaConvertedFrom = "secretAura", debuffType = "HELPFUL", useName = false,
  secretUseRankSpellIDs = true, auraRankSpellIDs = { "Well Fed" }, useExactSpellId = true, auraspellids = { "Well Fed" } }
private.EAModernize({ triggers = { { trigger = namesOff } }, eaVersion = 4 })
T.expect(namesOff.useName == false and namesOff.useExactSpellId == true and #namesOff.auraspellids == 0,
  "Name(s) switched off stays off, and the trigger keeps matching nothing")

local exactNames = { type = "secretAura", debuffType = "Buff", secretUseSpellIDs = true, auraspellids = { "Well Fed" } }
private.EAModernize({ triggers = { { trigger = exactNames } } })
T.expect(exactNames.useName and exactNames.auranames[1] == "Well Fed" and not exactNames.useExactSpellId,
  "a name in the exact ID list matches by name")
local junk = { type = "secretAura", debuffType = "Buff", secretUseSpellIDs = true, auraspellids = { "  " } }
private.EAModernize({ triggers = { { trigger = junk } } })
T.expect(junk.useExactSpellId == true and #junk.auraspellids == 0 and not junk.useName,
  "an exact ID list with nothing usable left matches nothing, not every aura")

local huge = { type = "secretAura", debuffType = "Buff", secretUseRankSpellIDs = true,
  auraRankSpellIDs = { "99999999999", 20154 } }
local ok = pcall(private.EAModernize, { triggers = { { trigger = huge } } })
T.expect(ok and huge.auranames and huge.auranames[1] == "Seal of Righteousness", "a spell ID past 32 bits never reaches the client")

T.section("Swing timers keep their hand (0.5.1)")
local hands = {}
for swingType, expected in pairs({ [0] = "main", [1] = "off", [2] = "ranged" }) do
  local swing = { type = "unit", event = "Swing Timer", swingType = swingType, hand = "main" }
  private.EAModernize({ triggers = { { trigger = swing } }, eaVersion = 4 })
  hands[#hands + 1] = swing.hand == expected
end
T.expect(hands[1] and hands[2] and hands[3], "off hand and ranged follow the saved weapon")
local stale = { type = "unit", event = "Swing Timer", swingType = 0, hand = "ranged" }
private.EAModernize({ triggers = { { trigger = stale } } })
T.expect(stale.hand == "main", "a fresh import follows the saved weapon over a stale hand")
local picked = { type = "unit", event = "Swing Timer", swingType = 0, hand = "off" }
private.EAModernize({ triggers = { { trigger = picked } }, eaVersion = 4 })
T.expect(picked.hand == "off", "a hand picked on an aura saved before is kept")
local own = { type = "unit", event = "Swing Timer", hand = "off" }
private.EAModernize({ triggers = { { trigger = own } }, eaVersion = 4 })
T.expect(own.hand == "off", "a swing timer made here keeps its hand")
local later = { type = "unit", event = "Swing Timer", swingType = 2, hand = "main" }
private.EAModernize({ triggers = { { trigger = later } }, eaVersion = 5 })
T.expect(later.hand == "main", "the step runs once, so a hand changed afterwards stays")

T.section("Bag Space and Durability settings become dropdown values (0.6.0)")
local function migrated(item, version)
  private.EAModernize({ triggers = { { trigger = item } }, eaVersion = version })
  return item
end
T.expect(migrated({ type = "item", event = "Bag Space", use_includeSpecialty = true }).bagType == "all",
  "Include Specialty Bags on becomes All Bags")
T.expect(migrated({ type = "item", event = "Bag Space", use_includeSpecialty = false }).bagType == "general"
  and migrated({ type = "item", event = "Bag Space" }).bagType == "general", "off or unset becomes General Bags")
T.expect(migrated({ type = "item", event = "Bag Space", use_includeSpecialty = true }, 5).bagType == "all",
  "a Bag Space aura imported before 0.6.0 gets it too")
T.expect(migrated({ type = "item", event = "Bag Space", bagType = "specialty", use_includeSpecialty = true }).bagType
  == "specialty", "a bag choice already made stays")
T.expect(migrated({ type = "item", event = "Equipment Durability", durabilitySlot = "3" }).durabilitySlot == 3,
  "a slot saved as text becomes a number")
T.expect(migrated({ type = "item", event = "Equipment Durability" }).durabilitySlot == nil, "no slot stays unset")
T.expect(migrated({ type = "unit", event = "Bag Space" }).bagType == nil, "only item triggers are touched")
T.expect(migrated({ type = "item", event = "Bag Space" }, 6).bagType == nil, "the step runs once")

T.section("Modern Aura Groups become a fixed row (0.6.0)")
local function at(member, x, y)
  return member.selfPoint == "CENTER" and member.anchorPoint == "CENTER" and member.xOffset == x and member.yOffset == y
end
local function row(group, members, toc)
  local ids = {}
  for index, member in ipairs(members) do
    member.id = member.id or ("M" .. index)
    ids[index] = member.id
  end
  group.regionType, group.controlledChildren = group.regionType or "group", ids
  group.tocversion = toc or 16001
  if group.blizzardFlow == nil then group.blizzardFlow = true end
  private.EANormalizeImport(group, members)
  return members
end
local m = row({ blizzardFlowOrigin = "group", blizzardFlowSpacing = 2 }, { {}, { xOffset = 5 }, {} })
T.expect(at(m[1], 16, -16) and at(m[2], 55, -16) and at(m[3], 84, -16),
  "a new row starts at the group's point, and a member's own offset moves only that member")
local g = { blizzardFlowOrigin = "group" }
row(g, { {} })
T.expect(g.eaFlowLaidOut == true, "the group is marked laid out")
m = row({}, { { xOffset = 100, yOffset = 50 }, { width = 20, height = 20 }, {} })
T.expect(at(m[1], 100, 50) and at(m[2], 128, 56) and at(m[3], 156, 50),
  "an old row starts at its first member's place, members of other sizes line up at the top")
m = row({ blizzardFlowOrigin = "group", blizzardFlowGrowth = "LEFT" }, { {}, {} })
T.expect(at(m[1], -16, -16) and at(m[2], -50, -16), "Left starts at the top right")
m = row({ blizzardFlowOrigin = "group", blizzardFlowGrowth = "UP" }, { {}, {} })
T.expect(at(m[1], 16, 16) and at(m[2], 16, 50), "Up starts at the bottom left")
m = row({ blizzardFlowOrigin = "group", blizzardFlowGrowth = "DOWN" }, { {}, {} })
T.expect(at(m[1], 16, -16) and at(m[2], 16, -50), "Down starts at the top left")
m = row({ blizzardFlowOrigin = "group", blizzardFlowGrowth = "CENTER_HORIZONTAL" }, { {}, {} })
T.expect(at(m[1], -17, -16) and at(m[2], 17, -16), "Centered Horizontal centers on the top middle")
m = row({ blizzardFlowOrigin = "group", blizzardFlowGrowth = "CENTER_VERTICAL" }, { {}, {} })
T.expect(at(m[1], 16, 17) and at(m[2], 16, -17), "Centered Vertical centers on the left middle")
m = row({ blizzardFlowOrigin = "group", blizzardFlowGrid = true, blizzardFlowPerRow = 2 }, { {}, {}, {} })
T.expect(at(m[1], 16, -16) and at(m[2], 50, -16) and at(m[3], 16, -50), "a grid fills rows to the right, then down")
m = row({ blizzardFlowOrigin = "group", blizzardFlowGrid = true, blizzardFlowPerRow = 2, blizzardFlowGridType = "LU" },
  { {}, {}, {} })
T.expect(at(m[1], -16, 16) and at(m[2], -50, 16) and at(m[3], -16, 50), "a Left-Up grid starts at the bottom right")
m = row({ blizzardFlowOrigin = "group", blizzardFlowGrid = true, blizzardFlowPerRow = 2, blizzardFlowGridType = "HV" },
  { {}, {}, {} })
T.expect(at(m[3], 16, -50), "a centered grid code falls back to right, then down")
local framed = { blizzardFlowFrames = "NAMEPLATE" }
m = row(framed, { {}, {} })
T.expect(m[1].xOffset == nil and not framed.eaFlowLaidOut, "a group on unit frames or nameplates is left alone")
local notFlow = { blizzardFlow = false }
m = row(notFlow, { {}, {} })
T.expect(m[2].xOffset == nil and not notFlow.eaFlowLaidOut, "a plain group is left alone")
m = row({}, { {}, {} }, 120105)
T.expect(m[2].xOffset == nil, "a string from another client is left alone")
forever = false
m = row({}, { {}, {} })
T.expect(m[2].xOffset == nil, "Retail lays nothing out")
forever = true
local nested = { id = "Inner", regionType = "group", blizzardFlow = true, blizzardFlowOrigin = "group", controlledChildren = { "N1", "N2" } }
local n1, n2 = { id = "N1" }, { id = "N2" }
private.EANormalizeImport({ tocversion = 16001, regionType = "group", controlledChildren = { "Inner" } }, { nested, n1, n2 })
T.expect(at(n1, 16, -16) and at(n2, 50, -16), "a Modern Aura Group inside an imported group is laid out too")
local again = { blizzardFlowOrigin = "group" }
m = row(again, { {}, {} })
m[2].xOffset = 99
private.EANormalizeImport(again, m)
T.expect(m[2].xOffset == 99, "a group laid out once is not laid out again")

local function saveGroup(group)
  savedAuras[group.id] = group
  private.EAModernize(group)
  return group
end
savedAuras = { S1 = { id = "S1" }, S2 = { id = "S2" } }
local savedGroup = saveGroup({ id = "Saved", regionType = "group", blizzardFlow = true, blizzardFlowOrigin = "group",
  controlledChildren = { "S1", "S2" }, triggers = {}, eaVersion = 6 })
T.expect(at(savedAuras.S1, 16, -16) and at(savedAuras.S2, 50, -16) and savedGroup.eaFlowLaidOut,
  "a group imported before 0.6.0 is laid out at the next login")
savedAuras = { S1 = { id = "S1" }, S2 = { id = "S2", xOffset = 40 } }
savedGroup = saveGroup({ id = "Saved", regionType = "group", blizzardFlow = true, controlledChildren = { "S1", "S2" },
  triggers = {}, eaVersion = 6 })
T.expect(savedAuras.S2.xOffset == 40 and savedAuras.S1.xOffset == nil and not savedGroup.eaFlowLaidOut,
  "one whose auras were moved by hand keeps them where they are")
savedAuras = { S1 = { id = "S1" }, S2 = { id = "S2" } }
local incoming = { id = "Incoming", regionType = "group", blizzardFlow = true, blizzardFlowOrigin = "group",
  controlledChildren = { "S1", "S2" }, triggers = {}, eaVersion = 5 }
private.EAModernize(incoming)
T.expect(savedAuras.S1.xOffset == nil and savedAuras.S2.xOffset == nil and not incoming.eaFlowLaidOut,
  "a group still being imported or sent by chat link never moves my saved auras that share its children's names")
forever = false
savedGroup = saveGroup({ id = "Saved", regionType = "group", blizzardFlow = true, controlledChildren = { "S1", "S2" },
  triggers = {}, eaVersion = 6 })
T.expect(savedAuras.S2.xOffset == nil, "not on Retail")
forever = true
m = row({}, { { xOffset = 100, yOffset = 50, selfPoint = "LEFT" }, {} })
T.expect(at(m[1], 116, 50) and at(m[2], 150, 50), "an old row starts where its first member really is, whatever its anchor")
m = row({ blizzardFlowOrigin = "group" }, { {}, { xOffset = 5, selfPoint = "LEFT" } })
T.expect(at(m[2], 55, -16), "a member's own offset is a nudge whatever its anchor")
local dynamic = { regionType = "dynamicgroup", blizzardFlow = true, blizzardFlowOrigin = "group" }
m = row(dynamic, { {}, {} })
T.expect(m[2].xOffset == nil and not dynamic.eaFlowLaidOut, "a dynamic group is never laid out")

T.section("Cooldown Manager triggers become standard triggers (0.6.0)")
local function cdm(t, version, conditions)
  local aura = { triggers = { { trigger = t } }, eaVersion = version or 6, conditions = conditions }
  if t.type == nil then t.type = "cdm" end
  private.EAModernize(aura)
  return t, aura
end
local cd = cdm({ event = "Blizzard Cooldown Manager", cdmUseNames = true, cdmNames = { "Judgement", "853", "" } })
T.expect(cd.type == "spell" and cd.event == "Cooldown Progress (Spell)" and cd.use_spellName and cd.spellName == "Judgement"
  and cd.use_exact_spellName == false, "a named Cooldown watches its first spell by name")
T.expect(cd.genericShowOn == "showAlways" and cd.use_genericShowOn and cd.track == "auto", "shown always, as before")
T.expect(cd.eaCdmOthers and #cd.eaCdmOthers == 1 and cd.eaCdmOthers[1] == "Hammer of Justice",
  "the other spells are kept by name for the note")
T.expect(cd.eaConvertedFrom == "cdm" and cd.cdmNames[1] == "Judgement", "marked converted, the original keys stay")
cd = cdm({ event = "Blizzard Cooldown Manager", cdmUseExactIDs = true, cdmExactIDs = { "20271" }, cdmShow = "ready",
  cdmTrack = "charges", use_cdmShowGCD = true, cdmUseRemaining = true, cdmRemainingOperator = "<=", cdmRemainingTime = 5,
  cdmUseCharges = true, cdmChargeOperator = "!=", cdmChargeCount = 2 })
T.expect(cd.spellName == 20271 and cd.use_exact_spellName == true and cd.eaCdmOthers == nil, "an exact ID stays exact")
T.expect(cd.genericShowOn == "showOnReady" and cd.track == "charges" and cd.use_showgcd == true,
  "Show, Track and the global cooldown carry over")
T.expect(cd.use_remaining and cd.remaining_operator == "<=" and cd.remaining == "5", "the Remaining Time filter carries over")
T.expect(cd.use_charges and cd.charges_operator == ">=" and cd.charges == "2", "an operator EA lacks falls back to its default")
cd = cdm({ event = "Blizzard Cooldown Manager", cdmUseNames = true, cdmNames = { "853" } })
T.expect(cd.spellName == 853 and cd.use_exact_spellName == false, "a numeric name is read as that spell, any rank")
local _, withConditions = cdm({ event = "Blizzard Cooldown Manager", cdmUseNames = true, cdmNames = { "Judgement" } }, 6, {
  { check = { trigger = 1, variable = "stacks" } },
  { check = { trigger = -2, checks = { { trigger = 1, variable = "inRange" }, { trigger = 2, variable = "stacks" },
    { trigger = 1, variable = "onCooldown" }, { trigger = 1, variable = "recharging" } } } },
})
local checks = withConditions.conditions
T.expect(checks[1].check.variable == "charges" and checks[2].check.checks[1].variable == "spellInRange",
  "its conditions get the standard names, nested ones too")
T.expect(checks[2].check.checks[2].variable == "stacks" and checks[2].check.checks[3].variable == "onCooldown",
  "conditions of other triggers and names already shared stay")
T.expect(withConditions.triggers[1].trigger.eaCdmLostConditions[1] == "recharging", "Recharging has no match here, so it is named")
cd = cdm({ event = "Blizzard CDM Utility", cdmUseNames = true, cdmNames = { "Judgement" } })
T.expect(cd.event == "Cooldown Progress (Spell)", "the old Utility event is a Cooldown too")
cd = cdm({ type = "spell", event = "Blizzard Cooldown Manager", cdmUseNames = true, cdmNames = { "Judgement" } })
T.expect(cd.event == "Cooldown Progress (Spell)" and cd.eaConvertedFrom == "cdm", "so is the oldest saved form")
cd = cdm({ event = "Blizzard Cooldown Manager", cdmSpell = "853", cdmExact = true })
T.expect(cd.spellName == 853 and cd.use_exact_spellName == true, "the old single-spell field still converts")
cd = cdm({ event = "Blizzard Cooldown Manager", cdmSpells = { multi = { ["199385"] = true } } })
T.expect(cd.spellName == 20271 and cd.use_exact_spellName == true, "a picked entry is looked up on this client")
cd = cdm({ event = "Blizzard Cooldown Manager", cdmSpells = { multi = { ["5"] = true } } })
T.expect(cd.type == "cdm" and cd.eaConvertedFrom == nil, "an entry this client does not know stays as it was")

local buff = cdm({ event = "Blizzard CDM Buff", cdmUseNames = true, cdmNames = { "8050" }, cdmBuffShow = "missing",
  cdmRequireTarget = true })
T.expect(buff.type == "aura2" and buff.useName and buff.auranames[1] == "Flame Shock" and not buff.useExactSpellId,
  "a Buff/Debuff becomes an Aura trigger by name")
T.expect(buff.unit == "target" and buff.debuffType == "HARMFUL" and buff.ownOnly == true,
  "a harmful spell is watched as my debuff on the target")
T.expect(buff.matchesShowOn == "showOnMissing" and buff.unitExists == false and buff.showClones == false,
  "Missing, only with a target, one display")
buff = cdm({ event = "Blizzard CDM Buff", cdmUseNames = true, cdmNames = { "Blessing of Might", "20154" },
  cdmCombineMode = "showHighest", cdmUseStacks = true, cdmStackOperator = "==", cdmStackCount = 3 })
T.expect(buff.unit == "player" and buff.debuffType == "HELPFUL" and buff.ownOnly == nil, "a helpful one is a buff on me")
T.expect(buff.auranames[2] == "Seal of Righteousness" and buff.showClones == true and buff.combineMode == "showHighest",
  "every name, one display each")
T.expect(buff.matchesShowOn == "showOnActive" and buff.unitExists == true, "shown while found by default")
T.expect(buff.useStacks and buff.stacksOperator == "==" and buff.stacks == "3", "the Stack Count filter carries over")
cd = cdm({ event = "Blizzard Cooldown Manager", cdmUseNames = true, cdmNames = { "Judgement" }, cdmUseRemaining = true,
  cdmUseCharges = true })
T.expect(cd.remaining == "10" and cd.charges == "1", "a ticked filter with no value takes the defaults, 10 seconds and 1")
buff = cdm({ event = "Blizzard CDM Buff", cdmUseNames = true, cdmNames = { "Blessing of Might" }, cdmUseRemaining = true,
  cdmUseStacks = true })
T.expect(buff.rem == "10" and buff.stacks == "1", "on Buff/Debuff too")
local buffAura
buff, buffAura = cdm({ event = "Blizzard CDM Buff", cdmUseNames = true, cdmNames = { "Blessing of Might" }, cdmBuffShow = "always" },
  6, { { check = { trigger = 1, variable = "auraActive" } }, { check = { trigger = 1, variable = "show" } },
  { check = { trigger = 1, variable = "elapsedTime" } }, { check = { trigger = 1, variable = "activationTime" } },
  { check = { trigger = 1, variable = "elapsedTime" } } })
T.expect(buffAura.conditions[1].check.variable == "buffed" and buffAura.conditions[2].check.variable == "show"
  and buffAura.conditions[4].check.variable == "activationTime",
  "Show On Always: Aura Active becomes Aura(s) Found, Active and Since Active stay")
local lostKeys = 0
for _ in pairs(buff.eaCdmLostConditions or {}) do lostKeys = lostKeys + 1 end
T.expect(buff.eaCdmLostConditions and buff.eaCdmLostConditions[1] == "elapsedTime" and #buff.eaCdmLostConditions == 1
  and lostKeys == 1,
  "a condition with no match here is kept for the warning, once, as a plain list")
buff, buffAura = cdm({ event = "Blizzard CDM Buff", cdmUseNames = true, cdmNames = { "Blessing of Might" } }, 6,
  { { check = { trigger = 1, variable = "auraActive" } } })
T.expect(buffAura.conditions[1].check.variable == "show" and buff.eaCdmLostConditions == nil,
  "Found: Aura Active is the trigger's own state")
buff, buffAura = cdm({ event = "Blizzard CDM Buff", cdmUseNames = true, cdmNames = { "Blessing of Might" },
  cdmBuffShow = "missing" }, 6, { { check = { trigger = 1, variable = "auraActive", value = 1 } },
  { check = { trigger = 1, variable = "auraActive", value = 0 } } })
T.expect(buffAura.conditions[1].check.variable == "show" and buffAura.conditions[1].check.value == 0
  and buffAura.conditions[2].check.value == 1 and buff.eaCdmLostConditions == nil,
  "Missing: Aura Active is the trigger's own state turned around")
local itemTrigger, itemAura = cdm({ event = "Blizzard CDM Item", cdmUseItemIDs = true, cdmItemIDs = { "6948" } }, 6, {
  { check = { trigger = 1, variable = "isReady" } }, { check = { trigger = 1, variable = "onCooldown" } } })
T.expect(itemTrigger.eaCdmLostConditions and itemTrigger.eaCdmLostConditions[1] == "isReady" and itemAura.conditions[2].check.variable
  == "onCooldown", "the item cooldown has no Is Ready, so that one is named")
buff = cdm({ event = "Blizzard CDM Buff", cdmUseNames = true, cdmNames = { "Blessing of Might", "20154" },
  cdmBuffShow = "missing" })
T.expect(buff.showClones == false, "Missing is one display however many names it lists")
buff = cdm({ event = "Blizzard CDM Buff", cdmUseExactIDs = true, cdmExactIDs = { "19740" } })
T.expect(buff.useExactSpellId and buff.auraspellids[1] == "19740" and buff.useName == false, "exact IDs stay exact")
buff = cdm({ event = "Blizzard CDM Buff", cdmSpells = { multi = { ["200288"] = true } } })
T.expect(buff.auraspellids[1] == "19834" and buff.auraspellids[2] == "19740", "a picked buff gets its linked aura IDs")
buff = cdm({ event = "Blizzard CDM Buff", cdmSpells = { multi = { ["7"] = true } } })
T.expect(buff.type == "cdm", "an unknown picked buff stays as it was")

local item = cdm({ event = "Blizzard CDM Item", cdmUseItemIDs = true, cdmItemIDs = { "6948" } })
T.expect(item.type == "item" and item.event == "Cooldown Progress (Item)" and item.itemName == 6948
  and item.use_exact_itemName == true and item.genericShowOn == "showAlways", "an Item watches that item")
item = cdm({ event = "Blizzard CDM Item", cdmUseNames = true, cdmNames = { "Hearthstone" } })
T.expect(item.itemName == "Hearthstone" and item.use_exact_itemName == false, "or an item by name")
item = cdm({ event = "Blizzard CDM Item", cdmUseExactIDs = true, cdmExactIDs = { "8690" } })
T.expect(item.type == "cdm", "an Item known only by its use spell stays as it was")

forever = false
T.expect(cdm({ event = "Blizzard Cooldown Manager", cdmUseNames = true, cdmNames = { "Judgement" } }).type == "cdm",
  "Retail converts nothing")
forever = true
T.expect(cdm({ event = "Blizzard Cooldown Manager", cdmUseNames = true, cdmNames = { "Judgement" } }, 7).type == "cdm",
  "the step runs once")
local staleKeys = cdm({ type = "unit", event = "Power", cdmUseNames = true, cdmNames = { "Judgement" } })
T.expect(staleKeys.type == "unit" and staleKeys.eaConvertedFrom == nil, "leftover keys on other triggers are ignored")

T.section("Each step runs once")
warningRuns = 0
data = { triggers = {}, eaVersion = 3, texture = "Interface\\AddOns\\WeakAuras\\Media\\Textures\\Square" }
private.EAModernize(data)
T.expect(data.texture == "Interface\\AddOns\\WeakAuras\\Media\\Textures\\Square", "an aura already at version 3 is not migrated again")
T.expect(data.eaVersion == 7 and warningRuns == 1, "only the later steps run, and its warnings are refreshed at every load")
data = { triggers = {}, eaVersion = 7 }
private.EAModernize(data)
T.expect(data.eaVersion == 7, "a newer counter from a later build is never lowered")
T.finish()
