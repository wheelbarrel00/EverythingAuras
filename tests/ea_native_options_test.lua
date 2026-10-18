-- Everything Auras 0.3.0: the "Blizzard Draws This Icon" switch and the rank IDs it stores from the spell cache.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local cache = { ["Seal of Righteousness"] = { [21084] = 1, [20287] = 1, [20154] = 1 }, ["Seal of the Crusader"] = { [21082] = 1 } }
local callbacks = { events = {} }
function callbacks:RegisterCallback(event, handler)
  self.events[event] = self.events[event] or {}
  table.insert(self.events[event], handler)
end
local function Fire(event, ...)
  for _, handler in ipairs(callbacks.events[event] or {}) do
    handler(event, ...)
  end
end

local qualifies = true
local corePrivate = {
  callbacks = callbacks,
  regionOptions = { icon = { create = function() return { icon = { color = { order = 1 } } } end } },
  EANativeQualifies = function()
    if qualifies then
      return true
    end
    return false, "Needs exactly one trigger."
  end,
}
local options = {}
local env = setmetatable({
  EverythingAuras = {
    IsLibsOK = function() return true end,
    L = setmetatable({}, { __index = function(_, k) return k end }),
    doubleWidth = 2,
    spellCache = { GetSpellsMatching = function(name) return cache[name] end },
  },
  tinsert = table.insert,
}, { __index = _G })
local chunk = assert(loadfile(T.repoRoot .. "/EverythingAurasOptions/EA/NativeOptions.lua"))
local ok, err = pcall(setfenv(chunk, env), "EverythingAurasOptions", options)
T.expect(ok, "the file loads before the options have Private" .. (ok and "" or (": " .. tostring(err))))
options.Private = corePrivate
for _, fn in ipairs(options.registerRegions) do
  fn()
end

T.section("The switch")
local data = { regionType = "icon", triggers = { { trigger = { useName = true, auranames = { "Seal of Righteousness" } } } } }
local result = corePrivate.regionOptions.icon.create("Seal", data)
local option = result.icon.eaNative
T.expect(option and option.type == "toggle" and option.name() == "Blizzard Draws This Icon" and option.order < 1,
  "an Icon gets the switch at the top of Icon Settings")
T.expect(not option.desc():find("Not available", 1, true), "available: no reason in the tooltip")
T.expect(option.disabled == nil, "never disabled, so its tooltip always shows (a disabled checkbox gets no mouse-over in game)")
qualifies = false
T.expect(option.name():find("(not available)", 1, true) and option.name():find("^|cff808080"), "unavailable: gray label marked not available")
T.expect(option.desc():find("Needs exactly one trigger.", 1, true), "unavailable: the reason is in the tooltip")
qualifies = true
local group = corePrivate.regionOptions.icon.create("Group", { controlledChildren = {} })
T.expect(group.icon.eaNative == nil, "not offered for a selection of several auras")

T.section("Rank IDs from the spell cache")
data.eaNative = true
Fire("Add", "Seal", "Seal", data)
T.expect(table.concat(data.eaNativeIds, ",") == "20154,20287,21084", "every rank of the name, sorted")
local stored = data.eaNativeIds
Fire("Add", "Seal", "Seal", data)
T.expect(data.eaNativeIds == stored, "an unchanged list is left as it is")
data.triggers[1].trigger.auranames = { "Seal of Righteousness", "Seal of the Crusader", "6673", "" }
Fire("Add", "Seal", "Seal", data)
T.expect(table.concat(data.eaNativeIds, ",") == "20154,20287,21082,21084", "several names, spell IDs typed as names skipped")
data.triggers[1].trigger.auranames = { "Not Cached Yet" }
Fire("Add", "Seal", "Seal", data)
T.expect(#data.eaNativeIds == 4, "a cache with nothing yet keeps the stored list")
options.savedVars = { odb = { rebuilding = true, needsRebuild = true } }
data.triggers[1].trigger.auranames = { "Seal of Righteousness" }
cache["Seal of Righteousness"] = { [20154] = 1 }
Fire("Add", "Seal", "Seal", data)
T.expect(#data.eaNativeIds == 4, "while the cache rebuilds, a stored list is not replaced by the ranks scanned so far")
local fresh = { regionType = "icon", eaNative = true,
  triggers = { { trigger = { useName = true, auranames = { "Seal of Righteousness" } } } } }
Fire("Add", "Fresh", "Fresh", fresh)
T.expect(fresh.eaNativeIds and fresh.eaNativeIds[1] == 20154, "an aura with no stored list still gets what the cache has")
options.savedVars.odb = { rebuilding = false, needsRebuild = false }
cache["Seal of Righteousness"] = { [21084] = 1, [20287] = 1, [20154] = 1 }
Fire("Add", "Seal", "Seal", data)
T.expect(table.concat(data.eaNativeIds, ",") == "20154,20287,21084", "after the rebuild the full list is stored again")
local off = { regionType = "icon", triggers = { { trigger = { useName = true, auranames = { "Seal of Righteousness" } } } } }
Fire("Add", "Off", "Off", off)
T.expect(off.eaNativeIds == nil, "nothing is stored while the switch is off")
T.finish()
