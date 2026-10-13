-- Everything Auras step 7a: what a player reads says "Everything Auras", code names and paths do not change.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local L = {
  ["About EverythingAuras"] = "About EverythingAuras",
  ["Malformed EverythingAuras link"] = "Malformed EverythingAuras link",
  ["Version"] = "This aura was created with a newer version of EverythingAuras.",
  ["Deprecated"] = "Using EverythingAuras.regions is deprecated. Use EverythingAuras.GetRegion(id) instead.",
  ["Path"] = "Interface\\AddOns\\EverythingAuras\\Media\\x.tga",
  ["Saved"] = "EverythingAurasSaved and EverythingAurasOptions stay",
  ["German"] = "Optionen f\195\188r EverythingAuras",
}
setmetatable(L, { __index = function(self, key)
  self[key] = (key or "")
  return key
end })

local loaded = {}
local private = {}
local env = setmetatable({
  EverythingAuras = { IsLibsOK = function() return true end, L = L },
  CreateFrame = function()
    return { RegisterEvent = function() end, UnregisterEvent = function() end,
      SetScript = function(self, _, f) loaded.handler = f; loaded.frame = self end }
  end,
}, { __index = _G })
local chunk = assert(loadfile(T.repoRoot .. "/EverythingAuras/EA/Names.lua"))
setfenv(chunk, env)("EverythingAuras", private)

T.section("Locale values")
T.expect(L["About EverythingAuras"] == "About Everything Auras", "a label gets the space")
T.expect(L["Malformed EverythingAuras link"] == "Malformed Everything Auras link", "mid-sentence")
T.expect(L["Version"] == "This aura was created with a newer version of Everything Auras.", "before a sentence's period")
T.expect(L["Deprecated"] == "Using EverythingAuras.regions is deprecated. Use EverythingAuras.GetRegion(id) instead.",
  "code names keep the identifier")
T.expect(L["Path"] == "Interface\\AddOns\\EverythingAuras\\Media\\x.tga", "paths keep the folder name")
T.expect(L["Saved"] == "EverythingAurasSaved and EverythingAurasOptions stay", "longer identifiers are untouched")
T.expect(L["German"] == "Optionen f\195\188r Everything Auras", "translations too")

T.section("Keys no locale has")
T.expect(L["EverythingAuras Anchor"] == "Everything Auras Anchor", "a missing key reads back renamed")
T.expect(rawget(L, "EverythingAuras Anchor") == "Everything Auras Anchor", "and is stored that way")

T.section("The options addon's strings")
L["Options added later by EverythingAuras"] = "Options added later by EverythingAuras"
T.expect(rawget(L, "Options added later by EverythingAuras") == "Options added later by Everything Auras",
  "a new key is renamed as it is written")
rawset(L, "Overwritten", "Translated EverythingAuras")
loaded.handler(loaded.frame, "ADDON_LOADED", "SomethingElse")
T.expect(rawget(L, "Overwritten") == "Translated EverythingAuras", "another addon's load changes nothing")
loaded.handler(loaded.frame, "ADDON_LOADED", "EverythingAurasOptions")
T.expect(rawget(L, "Overwritten") == "Translated Everything Auras", "an overwritten translation is renamed once the options load")

T.section("The function itself")
local name = private.EAShownName
T.expect(name("EverythingAuras") == "Everything Auras", "the whole string")
T.expect(name("EverythingAuras: hello") == "Everything Auras: hello", "before a colon")
T.expect(name("x/EverythingAuras/y") == "x/EverythingAuras/y", "a forward-slash path")
T.expect(name("Everything Auras") == "Everything Auras", "already spaced stays as it is")
T.finish()
