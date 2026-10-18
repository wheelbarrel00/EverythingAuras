-- Everything Auras step 4b: custom-code stand-ins (EA/Sandbox.lua) and the names EA blocks in the sandbox.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local world = { secret = false }
local env = {
  EverythingAuras = { IsLibsOK = function() return true end },
  issecretvalue = function(v) return v == SECRET end,
  issecrettable = function() return false end,
  pcall = pcall, pairs = pairs, type = type,
  Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 },
    LootMethod = { Freeforall = 0, Roundrobin = 1, Masterlooter = 2, Group = 3, Needbeforegreed = 4, Personal = 5 } },
  C_Spell = {
    GetSpellInfo = function(spell)
      if spell == 20154 or spell == "Seal of Righteousness" then
        return { name = "Seal of Righteousness", iconID = 135961, castTime = 0, minRange = 0, maxRange = 0,
          spellID = 20154, originalIconID = 135961 }
      end
    end,
    GetSpellCooldown = function(spell)
      if spell == 20271 then return { startTime = 10, duration = 8, isEnabled = true, modRate = 1 } end
      if spell == 1 then return { startTime = SECRET, duration = SECRET, isEnabled = SECRET, modRate = 1 } end
    end,
    IsSpellInRange = function(spell) if spell == 20271 then return true elseif spell == 2 then return false end end,
    GetSpellTexture = function() return 1 end,
  },
  C_Item = {}, C_QuestLog = {}, C_AddOns = { IsAddOnLoaded = function() return "stand-in" end },
  C_SpellBook = { GetSpellBookItemInfo = function() return { spellID = 20271 } end },
  C_PartyInfo = { GetLootMethod = function() return 2, 1, nil end },
  C_UnitAuras = {
    GetAuraDataByIndex = function(unit, index, filter)
      if world.secret then error("Auras cannot be accessed when secret while tainted") end
      if unit == "player" and index == 1 and filter:find("HELPFUL") then return { name = "Seal of Righteousness" } end
    end,
  },
  AuraUtil = { UnpackAuraData = function(aura) return aura.name end },
  IsAddOnLoaded = function() return "real" end,
}
setmetatable(env, { __index = _G })
env._G = env
local private = { EASandboxOverrides = {} }
setfenv(assert(loadfile(T.repoRoot .. "/EverythingAuras/EA/Sandbox.lua")), env)("EverythingAuras", private)
local o = private.EASandboxOverrides

T.section("Stand-ins")
T.expect(o.GetSpellInfo and select(3, o.GetSpellInfo("Seal of Righteousness")) == 135961
  and select(7, o.GetSpellInfo(20154)) == 20154, "GetSpellInfo returns the old order: name, rank, icon, ... spellID")
local start, duration, enabled = o.GetSpellCooldown(20271)
T.expect(start == 10 and duration == 8 and enabled == 1, "GetSpellCooldown returns 1 for enabled, as Classic did")
local _, _, secretEnabled = o.GetSpellCooldown(1)
T.expect(secretEnabled == SECRET, "a secret enabled flag passes through untested, so it cannot throw")
T.expect(o.IsSpellInRange(20271, "target") == 1 and o.IsSpellInRange(2, "target") == 0
  and o.IsSpellInRange(3, "target") == nil, "IsSpellInRange answers 1, 0 or nil")
T.expect(o.IsSpellInRange(5, "spell", "target") == 1, "the spell book form reads the book's spell")
T.expect(select(1, o.GetLootMethod()) == "master", "GetLootMethod maps the enum to Classic's names")
T.expect(o.UnitBuff("player", 1) == "Seal of Righteousness", "out of combat UnitBuff reads the aura")
world.secret = true
local ok, value = pcall(o.UnitBuff, "player", 1)
T.expect(ok and value == nil, "while auras are secret UnitBuff answers nothing instead of an error")
T.expect(o.IsAddOnLoaded == nil and private.EAStandIns.IsAddOnLoaded == nil,
  "a function the client still has is never replaced")
T.expect(private.EAStandIns.GetSpellInfo and private.EAStandIns.UnitAura, "the stand-ins are listed for the warnings")

T.section("Names EA blocks in custom code")
local file = assert(io.open(T.repoRoot .. "/EverythingAuras/AuraEnvironment.lua"))
local source = file:read("*a")
file:close()
local function has(text) return source:find(text, 1, true) ~= nil end
T.expect(has("Private.EASandboxOverrides = overridden"), "the stand-ins hook into the sandbox")
T.expect(has("PetAbandon = true,") and has("DeleteMacro = true,") and has("AbandonSkill = true,"),
  "abandoning a pet or skill and deleting macros are blocked")
T.expect(has("C_PetInfo = {") and has("Disband = true,") and has("SetTradeMoney = true,"),
  "namespace functions that abandon, disband or move money are blocked")
T.expect(has("EverythingAurasArchive = true,") and has("WASYNC_MAIN_PRIVATE = true,")
  and has("WASYNC_OPTIONS_PRIVATE = true,"), "the archive and the old sync tables are out of reach")
T.expect(has("ForeverAuras = FakeEverythingAuras,"), "ForeverAuras answers like WeakAuras inside custom code")
T.finish()
