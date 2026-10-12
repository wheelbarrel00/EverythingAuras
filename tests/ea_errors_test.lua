-- Everything Auras step 6: an aura that keeps erroring gets its custom code switched off for the session.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local reported, warnings, optionsOpen, renameCallback = 0, {}, false, nil
local auras = {
  Seal = { id = "Seal", uid = "uidSeal" },
  Text = { id = "Text", uid = "uidText" },
}
local private = {
  GetErrorHandlerId = function() return function() reported = reported + 1 end end,
  GetErrorHandlerUid = function() return function() reported = reported + 1 end end,
  GetDataByUID = function(uid)
    for _, data in pairs(auras) do if data.uid == uid then return data end end
  end,
  AuraWarnings = { UpdateWarning = function(uid, key, severity, message) warnings[uid .. key] = severity and message end },
  callbacks = { RegisterCallback = function(_, event, fn) if event == "Rename" then renameCallback = fn end end },
}
local addon = {
  IsLibsOK = function() return true end,
  L = setmetatable({}, { __index = function(_, k) return k end }),
  GetData = function(id) return auras[id] end,
  IsOptionsOpen = function() return optionsOpen end,
  LoadFunction = function(code) return function() return code end end,
}
local env = setmetatable({ EverythingAuras = addon }, { __index = _G })
local chunk = assert(loadfile(T.repoRoot .. "/EverythingAuras/EA/Errors.lua"))
setfenv(chunk, env)("EverythingAuras", private)

local function errorFrom(id, uid)
  local handler = id and private.GetErrorHandlerId(id, "ctx") or private.GetErrorHandlerUid(uid, "ctx")
  handler("boom")
end

T.section("Counting")
local sealCode = addon.LoadFunction("seal code", "Seal")
local sealAnimation = addon.LoadFunction("seal animation", "uidSeal")
local textCode = addon.LoadFunction("text code", "Text")
for _ = 1, 9 do errorFrom("Seal") end
T.expect(sealCode() == "seal code" and not private.EACustomCodeOff("uidSeal"), "9 errors: custom code still runs")
T.expect(reported == 9, "every error still reaches BugSack")
errorFrom(nil, "uidSeal")
T.expect(private.EACustomCodeOff("uidSeal"), "the 10th error, by uid, switches it off")
T.expect(sealCode() == nil and sealAnimation() == nil, "its custom code stops, by id and by uid")
T.expect(textCode() == "text code", "another aura's code keeps running")
T.expect(warnings.uidSealEACustomCodeOff and warnings.uidSealEACustomCodeOff:find("10", 1, true), "a warning names the count")
T.expect(reported == 10, "the 10th error was reported too")

T.section("Editing")
optionsOpen = true
for _ = 1, 20 do errorFrom("Text") end
T.expect(textCode() == "text code" and not private.EACustomCodeOff("uidText"), "errors while the options are open do not count")
optionsOpen = false

T.section("Turning it back on")
private.EATurnCustomCodeOn(auras.Seal)
T.expect(sealCode() == "seal code" and sealAnimation() == "seal animation", "the button turns it back on at once")
T.expect(not warnings.uidSealEACustomCodeOff, "and clears the warning")
for _ = 1, 9 do errorFrom("Seal") end
T.expect(not private.EACustomCodeOff("uidSeal"), "the count starts over")

T.section("Renaming keeps it off")
for _ = 1, 10 do errorFrom("Text") end
T.expect(private.EACustomCodeOff("uidText"), "Text switched off")
auras.Renamed, auras.Text = auras.Text, nil
auras.Renamed.id = "Renamed"
renameCallback(nil, "uidText", "Text", "Renamed")
local renamedCode = addon.LoadFunction("text code", "Renamed")
T.expect(renamedCode() == nil, "code loaded under the new name stays off")
T.finish()
