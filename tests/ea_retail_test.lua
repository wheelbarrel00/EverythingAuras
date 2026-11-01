-- Everything Auras 0.4.0: retail wording lives in one file that Forever never loads.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local function read(rel)
  local f = assert(io.open(T.repoRoot .. "/" .. rel, "rb"))
  local text = f:read("*a")
  f:close()
  return text
end

local function runRetail(isRetail)
  local L = setmetatable({}, { __index = function(_, key) return key end })
  local private = {}
  local env = setmetatable({
    EverythingAuras = { IsLibsOK = function() return true end, IsRetail = function() return isRetail end, L = L },
  }, { __index = _G })
  local chunk = assert(loadfile(T.repoRoot .. "/EverythingAuras/EA/Retail.lua"))
  setfenv(chunk, env)("EverythingAuras", private)
  return L, private
end

do
  local L, private = runRetail(false)
  T.expect(next(L) == nil, "not retail: no string changes")
  T.expect(private.EARetailWhatsNew == nil and private.EARetailExampleSpells == nil, "not retail: nothing handed over")
end

local L, private = runRetail(true)
local sources = table.concat({
  read("EverythingAuras/EA/Settings.lua"),
  read("EverythingAuras/EA/Warnings.lua"),
  read("EverythingAuras/EA/WhatsNew.lua"),
  read("EverythingAurasOptions/EA/CombatOptions.lua"),
}, "\n")

local keys = 0
for key, value in pairs(L) do
  keys = keys + 1
  T.expect(sources:find('L["' .. key .. '"]', 1, true) ~= nil, "still the text the EA files use: " .. key:sub(1, 40))
  T.expect(not value:find("Forever", 1, true) or key == value, "no Forever in the retail text: " .. key:sub(1, 40))
  T.expect(select(2, key:gsub("%%s", "")) == select(2, value:gsub("%%s", "")), "same format slots: " .. key:sub(1, 40))
end
T.expect(keys == 18, "every Forever-only string has retail text, got " .. keys)

-- Every string naming Forever in these files is covered, so none reaches a retail player by accident.
for key in sources:gmatch('L%["([^"]*WoW Forever[^"]*)"%]') do
  local onWhatsNew = key:find("profession slots", 1, true) ~= nil
  T.expect(rawget(L, key) ~= nil or onWhatsNew, "retail text exists for: " .. key:sub(1, 50))
end

T.expect(private.EARetailWhatsNewVersion == "0.4.0-beta", "What's New has its own retail version")
T.expect(#private.EARetailWhatsNew == 4, "four What's New entries")
for _, entry in ipairs(private.EARetailWhatsNew) do
  T.expect(type(entry.title) == "string" and type(entry.desc) == "string", "entry has a title and text")
end
T.expect(#private.EARetailExampleSpells == 3, "three example spells for the In Combat page")

local camelot = read("EverythingAuras/EverythingAuras_Camelot.toc")
local retail = read("EverythingAuras/EverythingAuras.toc")
T.expect(not camelot:find("EA\\Retail.lua", 1, true), "Forever's TOC does not list the file")
T.expect(retail:find("EA\\Names.lua%s+EA\\Retail.lua") ~= nil, "the retail TOC loads it right after Names.lua")
T.expect(retail:find("for WoW Forever", 1, true) == nil, "the retail TOC notes do not name Forever")
T.expect(retail:match("## Interface: (12%d+)") ~= nil and not retail:find("16001", 1, true), "the retail TOC has only retail numbers")

-- Forever never sets these fields, so these fallbacks are what it runs.
T.expect(sources:find('Private.EARetailWhatsNewVersion or "0.3.0-beta"', 1, true) ~= nil, "Forever keeps its What's New version")
T.expect(sources:find("Private.EARetailWhatsNew or {", 1, true) ~= nil, "Forever keeps its What's New entries")
T.expect(sources:find("Private.EARetailExampleSpells or { 20289, 19740, 20289 }", 1, true) ~= nil, "Forever keeps its example spells")

local templates = io.open(T.repoRoot .. "/EverythingAurasTemplates/EverythingAurasTemplates.toc", "rb")
T.expect(templates == nil, "Templates has no retail TOC, which keeps Premade Auras off")
if templates then templates:close() end

T.finish()
