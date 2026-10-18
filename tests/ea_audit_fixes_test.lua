-- Everything Auras audit fixes (2026-10-18) in inherited files too large to load whole.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local function read(path)
  local file = assert(io.open(T.repoRoot .. "/" .. path))
  local text = file:read("*a")
  file:close()
  return (text:gsub("\r\n", "\n"))
end

-- Each secret is its own value, typed "number", and any comparison with another secret throws (probe CMP, 2026-10-18).
local SECRET_MT = {}
local function throw() error("attempt to compare a secret value") end
SECRET_MT.__eq, SECRET_MT.__lt, SECRET_MT.__le = throw, throw, throw
local function newSecret() return setmetatable({}, SECRET_MT) end
local function issecretvalue(v) return getmetatable(v) == SECRET_MT end
local function hasanysecretvalues(...)
  for i = 1, select("#", ...) do
    if issecretvalue((select(i, ...))) then return true end
  end
  return false
end
local function secretType(v) return issecretvalue(v) and "number" or type(v) end

T.section("Background threads pause in combat")
local core = read("EverythingAuras/EverythingAuras.lua")
local handlerSource = core:match('threads%.frame:SetScript%("OnEvent", (function%(self, event%).-\n  end)%)')
T.expect(handlerSource ~= nil, "the thread frame's combat handler is found")
if handlerSource then
  local threads = { size = 1 }
  local handler = setfenv(assert(loadstring("return " .. handlerSource)), { threads = threads })()
  local frame = { shown = true }
  function frame:IsShown() return self.shown end
  function frame:Hide() self.shown = false end
  function frame:Show() self.shown = true end
  handler(frame, "PLAYER_REGEN_DISABLED")
  T.expect(not frame.shown, "combat start hides the thread frame, so a spell scan stops")
  handler(frame, "PLAYER_REGEN_ENABLED")
  T.expect(frame.shown, "combat end shows it again while threads are left")
  threads.size = 0
  frame.shown = false
  handler(frame, "PLAYER_REGEN_ENABLED")
  T.expect(not frame.shown, "with no threads left it stays hidden")
end

T.section("Secret Duration Info returns")
local generic = read("EverythingAuras/GenericTrigger.lua")
local activateSource = generic:match("\nfunction Private%.ActivateEvent%(.-\nend\n")
T.expect(activateSource ~= nil, "Private.ActivateEvent is found")
if activateSource then
  local private = {}
  local env = {
    Private = private, GetTime = function() return 100 end, type = secretType,
    issecretvalue = issecretvalue, hasanysecretvalues = hasanysecretvalues, xpcall = xpcall,
    callFunctionForActivateEvent = function() end, RunOverlayFuncs = function() end,
    L = setmetatable({}, { __index = function(_, k) return k end }),
  }
  setfenv(assert(loadstring(activateSource)), env)()
  private.GetErrorHandlerId = function() return function(err) error(err) end end
  local data = { trigger = {}, durationFunc = function() return newSecret(), newSecret(), true end }
  local state = {}
  local ok, err = pcall(private.ActivateEvent, "Health", 1, data, state)
  T.expect(ok, "a first secret static return does not throw" .. (ok and "" or (": " .. tostring(err))))
  ok, err = pcall(private.ActivateEvent, "Health", 1, data, state)
  T.expect(ok, "a second one does not throw either (secret ~= secret throws in game)" .. (ok and "" or (": " .. tostring(err))))
  T.expect(state.progressType == "static" and state.value == 0 and state.total == 0, "secret values count as none")
  data.durationFunc = function() return newSecret(), newSecret() end
  ok, err = pcall(private.ActivateEvent, "Cooldown", 1, data, state)
  T.expect(ok and state.progressType == "timed" and state.duration == 0, "a secret timed return counts as no timer"
    .. (ok and "" or (": " .. tostring(err))))
  data.durationFunc = function() return 50, 80, true end
  private.ActivateEvent("Health", 1, data, state)
  T.expect(state.value == 50 and state.total == 80, "plain values still pass through")
end

T.section("A GCD whose timing turns secret ends")
local gcdStart = generic:find("local function CheckGCD()", 1, true)
local gcdBody = gcdStart and generic:sub(gcdStart, gcdStart + 700)
T.expect(gcdBody ~= nil, "CheckGCD is found")
if gcdBody then
  local secretBranch = gcdBody:match("if C_Secrets%.ShouldSpellCooldownBeSecret%(GCD_SPELLID%) then(.-)\n      return\n    end")
  T.expect(secretBranch ~= nil, "it has a branch for a secret GCD")
  T.expect(secretBranch and secretBranch:find("gcdStart, gcdDuration, gcdModrate = nil, nil, nil", 1, true)
    and secretBranch:find('Private.ScanEvents("GCD_END")', 1, true), "that branch clears the GCD and sends GCD_END")
end
T.finish()
