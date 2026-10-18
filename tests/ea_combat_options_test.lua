-- Everything Auras step 5c: the Aura trigger's "In combat:" status line and the When Unsure option.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local secrecy = { [6673] = 2, [999] = 0, ["Never Shout"] = 0 }
-- Like the real Options addon: no Private at load, it arrives when the options first open.
local options = {
  commonOptions = { PositionOptions = function() return {} end },
}
local corePrivate = {
  triggerTypesOptions = {
    aura2 = function(_, triggernum)
      return { ["trigger." .. triggernum .. ".aura_options"] = { restrictions12_1Warning = { name = "M33 text" },
        matchesShowOn = { desc = "M33 tooltip" }, neverSecretSpells = { type = "execute" } } }
    end,
    event = function(_, triggernum)
      return { ["trigger." .. triggernum .. ".Cooldown Progress (Spell)"] = { spellName = { type = "spell" },
        neverSecretSpells = { type = "execute" } } }
    end,
  },
}
local env = setmetatable({
  EverythingAuras = { IsLibsOK = function() return true end, L = setmetatable({}, { __index = function(_, k) return k end }),
    normalWidth = 1, Add = function() end, IsForever = function() return true end },
  Enum = { SecrecyLevel = { NeverSecret = 0, AlwaysSecret = 1, ContextuallySecret = 2 } },
  C_Secrets = { GetSpellAuraSecrecy = function(spell)
    if secrecy[spell] == nil then error("unknown spell") end
    return secrecy[spell]
  end },
  issecretvalue = function() return false end,
  tinsert = table.insert,
}, { __index = _G })
local chunk = assert(loadfile(T.repoRoot .. "/EverythingAurasOptions/EA/CombatOptions.lua"))
local ok, err = pcall(setfenv(chunk, env), "EverythingAurasOptions", options)
T.expect(ok, "the file loads before the options have Private" .. (ok and "" or (": " .. tostring(err))))
options.Private = corePrivate
for _, fn in ipairs(options.registerRegions) do
  fn()
end

local status = options.EACombatStatus
local function has(text, part) return text:find(part, 1, true) ~= nil end

T.section("Status line")
local data = {}
T.expect(has(status(data, { unit = "player", debuffType = "HELPFUL", useExactSpellId = true, auraspellids = { "6673" } }),
  "last known, and estimated again when you cast it on yourself"), "own buff: last known, estimated on your cast")
T.expect(has(status(data, { unit = "player", debuffType = "HELPFUL", useExactSpellId = true, auraspellids = { "999" } }),
  "In combat: exact."), "a never-secret spell ID: exact")
T.expect(has(status(data, { unit = "player", useName = true, auranames = { "Never Shout" } }), "In combat: exact."),
  "a never-secret name: exact")
T.expect(has(status(data, { unit = "player", useExactSpellId = true, auraspellids = { "999" } }), "On Hide actions do not fire"),
  "exact still says a hide in combat stays silent")
local missingByName = status(data, { unit = "player", useName = true, auranames = { "Never Shout" }, matchesShowOn = "showOnMissing" })
T.expect(has(missingByName, "holds what it showed") and not has(missingByName, "In combat: exact."),
  "a never-secret Missing reminder by name holds, it is not exact")
T.expect(has(status(data, { unit = "player", useExactSpellId = true, auraspellids = { "999" }, matchesShowOn = "showOnMissing" }),
  "In combat: exact."), "a never-secret Missing reminder by spell ID is exact")
T.expect(has(status(data, { unit = "target", debuffType = "HARMFUL", useName = true, auranames = { "Unknown" } }),
  "until its timer runs out or the unit changes"), "a name the API cannot place: last known on the target")
T.expect(has(status(data, { unit = "player", debuffType = "HELPFUL", useName = true, auranames = { "Never Shout" },
  useExactSpellId = true, auraspellids = { "6673" } }), "last known"), "exact only when every tracked spell is never secret")
T.expect(has(status(data, { unit = "player", debuffType = "HELPFUL" }), "last known"), "no names or IDs: not exact")
T.expect(has(status(data, { unit = "player", debuffType = "HELPFUL", matchesShowOn = "showOnMissing",
  useExactSpellId = true, auraspellids = { "6673" } }), "holds what it showed"), "a Missing reminder holds")
T.expect(has(status(data, { unit = "multi" }), "not available"), "multi-target needs the combat log")

T.section("Icons Blizzard draws (0.3.0)")
corePrivate.EANativeWanted = function(d) return d.eaNative == true end
local function NativeData(unit)
  return { eaNative = true, triggers = { { trigger = { unit = unit } } } }
end
local unsureOption = options.commonOptions.PositionOptions("Seal", NativeData("player")).eaUnsureDisplay
T.expect(unsureOption.disabled == nil and unsureOption.name():find("(not used)", 1, true)
  and unsureOption.desc():find("always hide while unsure", 1, true), "When Unsure in Combat on Player: gray and marked not used, the reason in its tooltip")
local targetOption = options.commonOptions.PositionOptions("HoJ", NativeData("target")).eaUnsureDisplay
T.expect(targetOption.name() == "When Unsure in Combat" and targetOption.desc():find("applies when Everything Auras draws it instead", 1, true),
  "on Target it still applies where Everything Auras draws the icon")
T.expect(options.commonOptions.PositionOptions("Seal", {}).eaUnsureDisplay.name() == "When Unsure in Combat", "plain label otherwise")
local targetLine = status(NativeData("target"), { unit = "target", debuffType = "HARMFUL", useExactSpellId = true, auraspellids = { "6673" } })
T.expect(targetLine:find("exact where Blizzard draws this icon", 1, true) and targetLine:find("Otherwise it is last known", 1, true),
  "the status line on Target says where it is exact")
local nativeLine = status(NativeData("player"), { unit = "player", debuffType = "HELPFUL", useExactSpellId = true, auraspellids = { "6673" } })
T.expect(has(nativeLine, "In combat: exact. Blizzard draws this icon.") and not has(nativeLine, "last known"),
  "an aura Blizzard draws says so instead of last known")
T.expect(has(status({}, { unit = "player", debuffType = "HELPFUL", useExactSpellId = true, auraspellids = { "6673" } }), "last known"),
  "without the switch it is last known as before")
corePrivate.EANativeWanted = nil

T.section("Look follows the When Unsure option")
local trigger = { unit = "player", debuffType = "HELPFUL", useExactSpellId = true, auraspellids = { "6673" } }
T.expect(has(status({}, trigger), "dimmed with a corner marker"), "default: dimmed")
T.expect(has(status({ eaUnsureDisplay = "hide" }, trigger), "hidden"), "Hide")
T.expect(has(status({ eaUnsureDisplay = "show" }, trigger), "shows normally"), "Show Normally")
T.expect(has(status({}, trigger), "never fires sounds"), "always says it stays silent")

T.section("The Aura trigger options carry the line")
data = { triggers = { [1] = { trigger = trigger } } }
local result = options.Private.triggerTypesOptions.aura2(data, 1)
local name = result["trigger.1.aura_options"].restrictions12_1Warning.name
T.expect(type(name) == "function" and has(name(), "Some auras are explicitly made") and has(name(), "In combat: last known"),
  "the old 'cannot track' sentence is replaced by the status line")
T.expect(has(result["trigger.1.aura_options"].matchesShowOn.desc, "holds until the fight ends"),
  "the Show On tooltip says a Missing reminder holds")

T.section("Never-secret browsers on Forever")
T.expect(result["trigger.1.aura_options"].neverSecretSpells == nil, "the Aura trigger has no never-secret browser")
local cooldownOptions = options.Private.triggerTypesOptions.event(data, 1)["trigger.1.Cooldown Progress (Spell)"]
T.expect(cooldownOptions.neverSecretSpells == nil and cooldownOptions.spellName ~= nil,
  "the cooldown trigger loses only its browser")
T.finish()
