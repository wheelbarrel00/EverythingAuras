-- Custom aura code runs through EverythingAuras.LoadFunction and must not reach the
-- real global table, the blocked WoW functions, or the data-changing EverythingAuras
-- API. Each check probes the boundary the way an aura author would.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")
local stubs = require("wow_stubs")

stubs.install()
local realG = _G
_G.EverythingAuras = stubs.newEverythingAuras()
local EverythingAuras = _G.EverythingAuras
local Private, warnings = stubs.newPrivate()

local auraData = { id = "test", uid = "test-uid", config = {}, information = {}, actions = {} }
EverythingAuras.GetData = function(id)
  if id == "test" then
    return auraData
  end
end
Private.UIDtoID = function(uid)
  if uid == "test-uid" then
    return "test"
  end
end

T.loadAddonFile("EverythingAuras/AuraEnvironment.lua", "EverythingAuras", Private)

--- Runs code the way a custom trigger runs it.
local function runCustom(body)
  local fn, err = EverythingAuras.LoadFunction("return function()\n" .. body .. "\nend", "test")
  assert(fn, err)
  return fn()
end

--- Runs code through the loader for generated code and options validation.
local function runBuiltin(body)
  local fn, err = Private.LoadFunction("return function()\n" .. body .. "\nend", "test", true)
  assert(fn, err)
  return fn()
end

local function warned(key)
  for _, warning in ipairs(warnings) do
    if warning.key == key then
      return true
    end
  end
  return false
end

local function clearWarnings()
  for i = #warnings, 1, -1 do
    warnings[i] = nil
  end
end

T.section("blocked functions and tables are not reachable from custom code")
for _, name in ipairs({ "loadstring", "getfenv", "setfenv", "pcall", "xpcall",
                        "EnumerateFrames", "RunScript", "SendMail", "securecall" }) do
  clearWarnings()
  local got = runCustom("return " .. name)
  T.expect(type(got) == "function" and got ~= realG[name], name .. " is replaced by a stub")
  T.expect(warned("SandboxForbidden"), name .. " raises a SandboxForbidden warning")
end
for _, name in ipairs({ "SlashCmdList", "EverythingAurasSaved", "EverythingAurasOptions" }) do
  clearWarnings()
  local got = runCustom("return " .. name)
  T.expect(type(got) == "table" and got ~= realG[name], name .. " is replaced by an empty table")
  T.expect(warned("SandboxForbidden"), name .. " raises a SandboxForbidden warning")
end

T.section("_G and getglobal resolve to the sandbox")
T.expect(runCustom("return _G") ~= realG, "_G is not the real global table")
T.expect(runCustom("return getglobal('_G')") ~= realG, "getglobal('_G') is not the real global table")
T.expect(runCustom("return _G._G._G") ~= realG, "nested _G stays inside the sandbox")
T.expect(runCustom("return _G.loadstring") ~= loadstring, "_G.loadstring is the stub")

T.section("dotted names resolve through the sandbox")
-- The frame chooser produces names like PlayerFrame.healthbar, so the sandbox
-- resolves dotted keys. The first segment must go through the sandbox, or
-- these names would return the real, blocked values.
local probes = {
  { '_G["_G.loadstring"]', loadstring },
  { 'getglobal("_G.pcall")', pcall },
  { '_G["_G.EnumerateFrames"]', realG.EnumerateFrames },
  { '_G["EverythingAuras.Add"]', EverythingAuras.Add },
  { '_G["WeakAuras.Add"]', EverythingAuras.Add },
  { 'getglobal("_G.WeakAuras.Delete")', EverythingAuras.Delete },
  { 'getglobal("EverythingAuras.PreAdd")', EverythingAuras.PreAdd },
  { '_G["_G.EverythingAuras.HideOptions"]', EverythingAuras.HideOptions },
  { '_G["_G.EverythingAurasSaved"]', realG.EverythingAurasSaved },
  { '_G["_G._G._G.loadstring"]', loadstring },
}
for _, probe in ipairs(probes) do
  local got = runCustom("return " .. probe[1])
  T.expect(got ~= probe[2], probe[1] .. " does not return the real value")
end
T.expect(runCustom('return getglobal("getglobal.anything")') == nil,
         "a dotted name that passes through a function returns nil instead of erroring")

T.section("custom code cannot obtain a loader with the real environment")
local leaked = runCustom([[
  local candidates = { loadstring, _G["_G.loadstring"], getglobal("_G.loadstring"), _G._G.loadstring }
  for _, candidate in ipairs(candidates) do
    if type(candidate) == "function" then
      local chunk = candidate("return _G")
      if type(chunk) == "function" then
        return chunk()
      end
    end
  end
]])
T.expect(leaked ~= realG, "no candidate loader compiles code against the real global table")

T.section("the EverythingAuras table is a guarded proxy")
T.expect(runCustom("return EverythingAuras") ~= EverythingAuras, "custom code sees a proxy, not the real EverythingAuras table")
for _, name in ipairs({ "Add", "PreAdd", "Import", "Delete", "HideOptions" }) do
  clearWarnings()
  local got = runCustom("return EverythingAuras." .. name)
  T.expect(got ~= EverythingAuras[name], "EverythingAuras." .. name .. " is blocked")
  T.expect(warned("SandboxForbidden"), "EverythingAuras." .. name .. " raises a SandboxForbidden warning")
end
clearWarnings()
runCustom("EverythingAuras.Injected = true")
T.expect(EverythingAuras.Injected == nil, "writing to EverythingAuras does not change the real table")
T.expect(warned("FakeEverythingAurasSet"), "writing to EverythingAuras raises a warning")
T.expect(runCustom("return EverythingAuras.IsLibsOK") == EverythingAuras.IsLibsOK, "allowed EverythingAuras functions pass through")

T.section("global writes from custom code stay inside the sandbox")
clearWarnings()
runCustom("BrandNewGlobal = 1")
T.expect(realG.BrandNewGlobal == nil, "a new global is not created in the real environment")
T.expect(runCustom("return BrandNewGlobal") == 1, "the aura still sees its own global")
runCustom("UnitExists = nil")
T.expect(type(realG.UnitExists) == "function", "overwriting an existing global does not change the real one")
T.expect(warned("OverridingGlobal"), "overwriting an existing global raises a warning")
clearWarnings()
runCustom("aura_env = {}")
T.expect(warned("OverridingAuraEnv"), "overwriting aura_env raises a warning")

T.section("aura code gets a copy of aura data")
Private.ActivateAuraEnvironment("test", nil, {}, {})
local env = runCustom("return aura_env")
T.expect(type(env) == "table" and env.id == "test", "aura_env is the environment of the active aura")
local seen = runCustom("local d = EverythingAuras.GetData('test'); d.actions.tampered = true; return d")
T.expect(seen ~= auraData, "EverythingAuras.GetData returns a copy")
T.expect(auraData.actions.tampered == nil, "writes to the copy do not reach the stored data")
Private.ActivateAuraEnvironment()

T.section("legitimate lookups keep working")
T.expect(Private.GetSanitizedGlobal("PlayerFrame") == realG.PlayerFrame, "a named frame resolves")
T.expect(Private.GetSanitizedGlobal("PlayerFrame.healthbar") == realG.PlayerFrame.healthbar,
         "a child frame without a name resolves through its parent")
T.expect(Private.GetSanitizedGlobal("PlayerFrame.missing") == nil, "an unknown child resolves to nil")
T.expect(runCustom("return UnitExists") == realG.UnitExists, "allowed API functions pass through")
T.expect(runCustom("return WA_Utf8Sub") == EverythingAuras.WA_Utf8Sub, "EverythingAuras helper functions are available")

T.section("the builtin environment has the same boundary")
for _, name in ipairs({ "loadstring", "getfenv", "setfenv", "EnumerateFrames" }) do
  T.expect(runBuiltin("return " .. name) ~= realG[name], "builtin: " .. name .. " is a stub")
end
T.expect(runBuiltin("return _G") ~= realG, "builtin: _G is not the real global table")
local builtinPrivate = runBuiltin("return Private")
T.expect(type(builtinPrivate) == "table" and builtinPrivate.ExecEnv == Private.ExecEnv
         and builtinPrivate.LoadFunction == nil, "builtin: Private exposes only ExecEnv")

T.finish()
-- Modified for Everything Auras by tools/ea_transform.py (identifiers renamed), see NOTICE.md
