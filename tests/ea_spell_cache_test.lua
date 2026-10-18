-- Everything Auras: on WoW Forever the spell cache scan must never reach the spell IDs above 1213143. Querying
-- spells there crashed the client on 2026-10-13 (ERROR #110, aura 1251678 used in PlayerCondition 144600), so the
-- scan has to stop 80000 misses after the last spell below the gap at 474742, as M33kAuras' scan does.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local spells = {
  [474742] = { name = "Last Before Gap", icon = 100 },
  [1213144] = { name = "First After Gap", icon = 100 },
  [1251678] = { name = "Crashes The Client", icon = 100 },
}
-- Probe P3 found no other gap of more than 40000 IDs below the gap.
for id = 1, 474741, 30000 do spells[id] = { name = "Before " .. id, icon = 100 } end

local queried = {}
local threads = {}
local wa = {
  IsLibsOK = function() return true end,
  IsForever = function() return true end,
  IsClassicEra = function() return false end,
  IsCataClassic = function() return false end,
  IsMists = function() return false end,
  IsRetail = function() return false end,
  IsCataOrMistsOrRetail = function() return false end,
  versionString = "test",
  L = setmetatable({}, { __index = function(_, key) return key end }),
}
local private = { Private = {
  ExecEnv = {
    GetSpellName = function(id) return spells[id] and spells[id].name end,
    GetSpellIcon = function(id)
      if id > 1213143 then queried[#queried + 1] = id end
      return spells[id] and spells[id].icon
    end,
  },
  Threads = { Add = function(_, _, co) threads[#threads + 1] = co end },
} }
local secrecy = function(id)
  if id > 1213143 then queried[#queried + 1] = id end
  return 2
end
local env = setmetatable({
  EverythingAuras = wa,
  C_Secrets = { GetSpellAuraSecrecy = secrecy, GetSpellCooldownSecrecy = secrecy, GetSpellCastSecrecy = secrecy },
  Enum = { SecrecyLevel = { NeverSecret = 0 } },
  IsTestBuild = function() return false end,
  GetBuildInfo = function() return "test", "100" end,
  GetLocale = function() return "enUS" end,
  wipe = function(t) for k in pairs(t) do t[k] = nil end end,
  LibStub = function() return {} end,
}, { __index = _G })
setfenv(assert(loadfile(T.repoRoot .. "/EverythingAurasOptions/Cache.lua")), env)("EverythingAurasOptions", private)
local data = { spellCache = {} }
wa.spellCache.Load(data)
wa.spellCache.Build()
local co = threads[#threads]
while coroutine.status(co) ~= "dead" do
  assert(coroutine.resume(co))
end

T.section("Forever")
T.expect(data.spellCache["Last Before Gap"] ~= nil, "spells below the gap are cached")
T.expect(#queried == 0, "no spell above 1213143 is ever queried")
T.expect(data.spellCache["First After Gap"] == nil and data.spellCache["Crashes The Client"] == nil,
  "the scan stops before the spells that crash the client")

T.section("Which saved cache is kept")
local function savedCache(names)
  local saved = { build = "100", locale = "enUS", version = "test", spellCacheStrings = true,
    neverSecretSpells = { aura = {}, cooldown = {}, cast = {} }, spellCache = {} }
  for i = 1, names do saved.spellCache["Spell " .. i] = { spells = i .. "=100" } end
  return saved
end
local complete = savedCache(12132)
wa.spellCache.Load(complete)
T.expect(not complete.needsRebuild and complete.spellCache["Spell 1"] ~= nil,
  "Forever keeps a complete cache of 12132 names (build 70450)")
local partial = savedCache(5000)
wa.spellCache.Load(partial)
T.expect(partial.needsRebuild and next(partial.spellCache) == nil, "Forever rebuilds a cache of 5000 names")
wa.IsForever = function() return false end
local retail = savedCache(12132)
wa.spellCache.Load(retail)
T.expect(retail.needsRebuild, "other clients still need 39000 names")
T.finish()
