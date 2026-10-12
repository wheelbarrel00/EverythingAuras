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
        matchesShowOn = { desc = "M33 tooltip" } } }
    end,
  },
}
local env = setmetatable({
  EverythingAuras = { IsLibsOK = function() return true end, L = setmetatable({}, { __index = function(_, k) return k end }),
    normalWidth = 1, Add = function() end },
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
T.expect(has(status(data, { unit = "target", debuffType = "HARMFUL", useName = true, auranames = { "Unknown" } }),
  "until its timer runs out or the unit changes"), "a name the API cannot place: last known on the target")
T.expect(has(status(data, { unit = "player", debuffType = "HELPFUL", useName = true, auranames = { "Never Shout" },
  useExactSpellId = true, auraspellids = { "6673" } }), "last known"), "exact only when every tracked spell is never secret")
T.expect(has(status(data, { unit = "player", debuffType = "HELPFUL" }), "last known"), "no names or IDs: not exact")
T.expect(has(status(data, { unit = "player", debuffType = "HELPFUL", matchesShowOn = "showOnMissing",
  useExactSpellId = true, auraspellids = { "6673" } }), "holds what it showed"), "a Missing reminder holds")
T.expect(has(status(data, { unit = "multi" }), "not available"), "multi-target needs the combat log")

T.section("Look follows the When Unsure option")
local trigger = { unit = "player", debuffType = "HELPFUL", useExactSpellId = true, auraspellids = { "6673" } }
T.expect(has(status({}, trigger), "dimmed with a ~"), "default: dimmed")
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
T.finish()
