-- Everything Auras 0.5.1: an imported aura names what it cannot do here instead of dropping it silently.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local warnings = {}
local private = {
  AuraWarnings = { UpdateWarning = function(uid, key, severity, message)
    warnings[uid] = warnings[uid] or {}
    warnings[uid][key] = severity and message or nil
  end },
  EAStandIns = {},
  EANativeWanted = function() return false end,
  category_event_prototype = { unit = true, item = true, spell = true },
  EAAddonTableOverrides = { GetBossStage = function() end },
  EAAddonTableBlocked = { ShowOptions = true },
  event_prototypes = { ["Stance/Form/Aura"] = {}, ["Weapon Enchant"] = {}, ["Health"] = {}, ["Swing Timer"] = {},
    ["Money"] = {}, ["Character Stats"] = {}, ["Cooldown Progress (Spell)"] = {} },
}
local L = setmetatable({}, { __index = function(_, key) return key end })
local addon = { IsLibsOK = function() return true end, IsForever = function() return false end, L = L,
  ScanEvents = function() end, GetData = function() end,
  SafeToNumber = function(v) local n = tonumber(v) return n and n < 2147483648 and n > -2147483649 and n or nil end }
local env = setmetatable({
  EverythingAuras = addon,
  C_Spell = { GetSpellName = function(id) return ({ [1] = "One", [2] = "Two" })[id] end },
}, { __index = _G })
setfenv(assert(loadfile(T.repoRoot .. "/EverythingAuras/EA/Warnings.lua")), env)("EverythingAuras", private)

local count = 0
local function Check(data)
  count = count + 1
  data.uid = "u" .. count
  data.triggers = data.triggers or {}
  private.EAUpdateWarnings(data)
  return warnings[data.uid] or {}
end

local function Has(message, part)
  return type(message) == "string" and message:find(part, 1, true) ~= nil
end

T.section("Nothing to say about an ordinary aura")
local plain = Check({ triggers = { { trigger = { type = "aura2", unit = "player", useName = true, auranames = { "One" } } } },
  load = {} })
T.expect(next(plain) == nil, "no warnings at all")

T.section("Settings that are not here yet")
local group = Check({ regionType = "group", blizzardFlow = true })
T.expect(Has(group.EANotHereYet, "Modern Aura Group layout"), "a Modern Aura Group says its layout is lost")
local flagged = Check({ load = { use_loadFlag = true, loadFlag = "x" } })
T.expect(Has(flagged.EANotHereYet, "Load Flag"), "a Load Flag is named")
local stance = Check({ triggers = { { trigger = { type = "unit", event = "Stance/Form/Aura", use_formID = false,
  formID = { multi = { [5] = true } } } } } })
T.expect(Has(stance.EANotHereYet, "Form ID filter"), "a form ID filter is named, in multi mode too")
local enchant = Check({ triggers = { { trigger = { type = "item", event = "Weapon Enchant", use_enchantKind = true,
  enchantKind = "temporary" } } } })
T.expect(Has(enchant.EANotHereYet, "Enchant Type filter"), "an enchant type other than Any is named")
local anyEnchant = Check({ triggers = { { trigger = { type = "item", event = "Weapon Enchant", use_enchantKind = true,
  enchantKind = "any" } } } })
T.expect(anyEnchant.EANotHereYet == nil, "Any changes nothing, so it is not named")
local leftover = Check({ triggers = { { trigger = { type = "unit", event = "Power", use_formID = true } } } })
T.expect(leftover.EANotHereYet == nil, "a key left over from another event is not named")

local converted = { type = "aura2", eaConvertedFrom = "secretAura", unit = "target", debuffType = "HARMFUL",
  useName = true, auranames = { "One", "Two" }, secretSpellList = "list", secretGainedSeconds = 1.5,
  secretApproximate = true, nativeFilters = { PLAYER = true, DISPELLABLE = true, CANCELABLE = true },
  useUnitClass = true, unitClass = { MAGE = true } }
local modern = Check({ triggers = { { trigger = converted } } })
for _, part in ipairs({ "Spell List", "Show On Gained", "Approximate Match", "aura type filters", "unit filters on this unit",
  "more than one icon" }) do
  T.expect(Has(modern.EANotHereYet, part), "converted Aura (Modern): " .. part)
end
local single = Check({ blizzardAuraDisplay = { maxIcons = 1 }, triggers = { { trigger = { type = "aura2",
  eaConvertedFrom = "secretAura", unit = "player", debuffType = "HELPFUL", useName = true, auranames = { "One", "Two" },
  nativeFilters = { PLAYER = true, CROWD_CONTROL = true } } } } })
T.expect(single.EANotHereYet == nil, "one icon allowed, a debuff-only flag on a buff and Own Only: nothing to say")

T.section("Health filters on a value that is always secret")
local health = Check({ triggers = { { trigger = { type = "unit", event = "Health", use_percenthealth = true,
  percenthealth = { "35" }, use_absorb = false } } } })
T.expect(Has(health.EASecretHealthFilters, "Health (%)") and not Has(health.EASecretHealthFilters, "Absorb"),
  "a percent health filter that is on is named, one that is off is not")

T.section("Custom code calling functions this addon does not have")
local function CodeAura(code)
  return Check({ triggers = { { trigger = { type = "custom", custom = code, custom_type = "status" }, untrigger = {} } } })
end
local missing = CodeAura("function() ForeverAuras.AuraOverlay(f, {}) WeakAuras.ScanEvents('X') ForeverAuras:SetLoadFlag('a', true) end")
T.expect(Has(missing.EAMissingAddonFunctions, "ForeverAuras.AuraOverlay")
  and Has(missing.EAMissingAddonFunctions, "ForeverAuras.SetLoadFlag"), "missing functions are named as the code wrote them")
T.expect(not Has(missing.EAMissingAddonFunctions, "ScanEvents"), "a function that exists is not")
local guarded = CodeAura("function() if ForeverAuras.AuraOverlay then ForeverAuras.AuraOverlay(f) end end")
T.expect(guarded.EAMissingAddonFunctions == nil, "code that tests for the function first is fine")
local commented = CodeAura("function()\n-- ForeverAuras.AuraOverlay(f)\nreturn true end")
T.expect(commented.EAMissingAddonFunctions == nil, "a call in a comment is ignored")
local boss = CodeAura("function() return WeakAuras.GetBossStage() == 2 end")
T.expect(boss.EAMissingAddonFunctions == nil, "a helper only the sandbox adds, such as GetBossStage, is fine")
local opener = CodeAura("function() WeakAuras.ShowOptions() return false end")
T.expect(opener.EAMissingAddonFunctions == nil, "a function the sandbox blocks never errors, so it is not named")
local f = assert(io.open(T.repoRoot .. "/EverythingAuras/AuraEnvironment.lua", "rb"))
local source = f:read("*a")
f:close()
T.expect(source:find("Private.EAAddonTableOverrides = FakeEverythingAurasMixin.override", 1, true) ~= nil
  and source:find("Private.EAAddonTableBlocked = FakeEverythingAurasMixin.blockedFunctions", 1, true) ~= nil,
  "the warning reads the sandbox's own helper and blocked lists")

T.section("A setting WeakAuras has too")
local heal = Check({ triggers = { { trigger = { type = "unit", event = "Health", use_showIncomingHeal = true } } } })
T.expect(Has(heal.EANotHereYet, "Incoming Heal display") and not Has(heal.EANotHereYet, "ForeverAuras"),
  "named without blaming ForeverAuras")

T.section("Money filters (0.6.0)")
local moneyTrigger = { type = "unit", event = "Money", use_silver = true, use_money = true }
local stock = Check({ triggers = { { trigger = moneyTrigger } } })
T.expect(Has(stock.EANotHereYet, "Silver filter") and Has(stock.EANotHereYet, "Money filter"),
  "Retail still names the Money filters it ignores")
addon.IsForever = function() return true end
setfenv(assert(loadfile(T.repoRoot .. "/EverythingAuras/EA/Warnings.lua")), env)("EverythingAuras", private)
local forever = Check({ triggers = { { trigger = moneyTrigger } } })
T.expect(forever.EANotHereYet == nil, "WoW Forever reads them, so nothing is named")

T.finish()
