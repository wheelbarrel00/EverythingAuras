-- Everything Auras' own migrations (EA/Migrate.lua), which change saved auras at every login.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local SPELLS = { [20154] = "Seal of Righteousness", [20287] = "Seal of Righteousness", [21084] = "Seal of Righteousness" }
local private, warningRuns, qualifies = {}, 0, true
private.EANativeQualifies = function() return qualifies end
private.EAUpdateWarnings = function() warningRuns = warningRuns + 1 end
local function CopyTable(t)
  local c = {}
  for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
  return c
end
local env = setmetatable({
  EverythingAuras = { IsLibsOK = function() return true end,
    SafeToNumber = function(v) local n = tonumber(v) return n and n < 2147483648 and n > -2147483649 and n or nil end },
  C_Spell = { GetSpellName = function(id)
    assert(id < 2147483648, "a spell ID past 32 bits reached the client")
    return SPELLS[id]
  end },
  CopyTable = CopyTable,
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
T.expect(data.eaVersion == 6, "and they reach the new counter")

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

T.section("Each step runs once")
warningRuns = 0
data = { triggers = {}, eaVersion = 3, texture = "Interface\\AddOns\\WeakAuras\\Media\\Textures\\Square" }
private.EAModernize(data)
T.expect(data.texture == "Interface\\AddOns\\WeakAuras\\Media\\Textures\\Square", "an aura already at version 3 is not migrated again")
T.expect(data.eaVersion == 6 and warningRuns == 1, "only the later steps run, and its warnings are refreshed at every load")
data = { triggers = {}, eaVersion = 7 }
private.EAModernize(data)
T.expect(data.eaVersion == 7, "a newer counter from a later build is never lowered")
T.finish()
