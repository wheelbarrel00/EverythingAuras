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
  EverythingAuras = { IsLibsOK = function() return true end },
  C_Spell = { GetSpellName = function(id) return SPELLS[id] end },
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

T.section("Each step runs once")
warningRuns = 0
data = { triggers = {}, eaVersion = 3, texture = "Interface\\AddOns\\WeakAuras\\Media\\Textures\\Square" }
private.EAModernize(data)
T.expect(data.texture == "Interface\\AddOns\\WeakAuras\\Media\\Textures\\Square", "an aura already at version 3 is not migrated again")
T.expect(data.eaVersion == 3 and warningRuns == 1, "but its warnings are refreshed at every load")
data = { triggers = {}, eaVersion = 7 }
private.EAModernize(data)
T.expect(data.eaVersion == 7, "a newer counter from a later build is never lowered")
T.finish()
