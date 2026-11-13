-- Everything Auras 0.6.0 round 4: the summary shown after importing a string another addon built on WoW Forever.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local function fixture(forever)
  local f = { timers = {}, dialogs = {}, opened = {}, auras = {}, warned = {} }
  f.options = {
    OpenUpdate = function(data, children, target, linkedAuras, sender, callbackFunc)
      f.opened[#f.opened + 1] = { data = data, callback = callbackFunc }
      return "opened"
    end,
    Private = {
      TraverseAll = function(root)
        local list = {}
        local function walk(data)
          list[#list + 1] = data
          for _, id in ipairs(data.controlledChildren or {}) do walk(f.auras[id]) end
        end
        walk(root)
        local i = 0
        return function() i = i + 1 return list[i] end
      end,
      EAHasWarning = function(uid) return f.warned[uid] == true end,
      EAShowDialog = function(opts) f.dialogs[#f.dialogs + 1] = opts end,
      EAForeignImports = {},
    },
  }
  f.env = setmetatable({
    EverythingAuras = {
      IsLibsOK = function() return true end,
      IsForever = function() return forever end,
      L = setmetatable({}, { __index = function(_, key) return key end }),
      GetData = function(id) return f.auras[id] end,
    },
    C_Timer = { After = function(delay, fn) f.timers[#f.timers + 1] = { delay = delay, fn = fn } end },
  }, { __index = _G })
  setfenv(assert(loadfile(T.repoRoot .. "/EverythingAurasOptions/EA/ImportSummary.lua")), f.env)(
    "EverythingAurasOptions", f.options)
  return f
end

local function aura(f, id, fields)
  fields.id, fields.uid = id, "uid-" .. id
  fields.triggers = fields.triggers or {}
  f.auras[id] = fields
  return fields
end

local function import(f, data, success, id)
  local result = f.options.OpenUpdate(data, {}, nil, nil, nil, function(...) f.called = { ... } end)
  f.opened[#f.opened].callback(success, id, "extra")
  local timers = f.timers
  f.timers = {}
  for _, timer in ipairs(timers) do timer.fn() end
  return result
end

T.section("Retail")
local retail = fixture(false)
T.expect(retail.options.EAImportSummary == nil and debug.getinfo(retail.options.OpenUpdate).source:find("ea_import_summary"),
  "nothing changes on Retail")

T.section("After a ForeverAuras import")
local f = fixture(true)
aura(f, "Pack", { regionType = "group", controlledChildren = { "Row", "Swing", "Broken" } })
aura(f, "Row", { regionType = "group", blizzardFlow = true, eaFlowLaidOut = true, controlledChildren = { "Seal", "Might" } })
aura(f, "Seal", { triggers = { { trigger = { type = "aura2", eaConvertedFrom = "secretAura" } } } })
aura(f, "Might", { triggers = { { trigger = { type = "aura2", eaConvertedFrom = "secretAura" } },
  { trigger = { type = "spell", eaConvertedFrom = "cdm" } } } })
aura(f, "Swing", { triggers = { { trigger = { type = "unit", event = "Swing Timer", swingType = 1, hand = "off" } } } })
aura(f, "Broken", { triggers = { { trigger = { type = "cdm" } } } })
f.warned["uid-Broken"], f.warned["uid-Swing"] = true, true
-- Import notes the origin, then PreAdd stamps eaVersion, all before the window opens.
local fromFA = { tocversion = 16001, eaVersion = 7 }
f.options.Private.EAForeignImports[fromFA] = true
T.expect(import(f, fromFA, true, "Pack") == "opened", "the import window opens as before")
T.expect(f.called[1] == true and f.called[2] == "Pack" and f.called[3] == "extra", "the import's own callback still runs")
local dialog = f.dialogs[1]
T.expect(dialog and dialog.title == "Import Summary" and dialog.button1 == "Got it" and dialog.button2 == nil,
  "a summary closes with Got it")
local text = dialog and dialog.text or ""
T.expect(text:find("Converted on import:", 1, true)
  and text:find("- 2 Aura (Modern) triggers, now standard Aura triggers", 1, true), "it counts the Aura (Modern) triggers")
T.expect(text:find("- 1 Cooldown Manager trigger, now a standard trigger", 1, true)
  and text:find("- 1 Modern Aura Group, now a fixed row", 1, true)
  and text:find("- 1 Swing Timer trigger, now on its hand setting", 1, true), "and the other pieces, in the singular")
T.expect(text:find("aura list to see what does not work yet:\nBroken, Swing", 1, true), "it names the auras with a warning")

T.section("When it stays quiet")
local before = #f.dialogs
import(f, { tocversion = 16001, eaVersion = 7 }, true, "Pack")
T.expect(#f.dialogs == before, "not for a string Everything Auras made or one from another client")
import(f, fromFA, false, "Pack")
T.expect(#f.dialogs == before and f.called[1] == false, "not when the import fails")
aura(f, "Clean", { triggers = { { trigger = { type = "aura2" } } } })
import(f, fromFA, true, "Clean")
T.expect(#f.dialogs == before, "not when nothing was converted or is missing")
aura(f, "Framed", { regionType = "group", blizzardFlow = true, eaFlowLaidOut = true, blizzardFlowFrames = "NAMEPLATE" })
import(f, fromFA, true, "Framed")
T.expect(#f.dialogs == before, "a group on nameplates was not laid out, so it is not counted")

T.section("Long lists")
local many = { regionType = "group", controlledChildren = {} }
for i = 1, 12 do
  local id = ("A%02d"):format(i)
  many.controlledChildren[i] = id
  aura(f, id, {})
  f.warned["uid-" .. id] = true
end
aura(f, "Many", many)
import(f, fromFA, true, "Many")
text = f.dialogs[#f.dialogs].text
T.expect(text:find("A01, A02", 1, true) and text:find("A10 and 2 more", 1, true) and not text:find("A11", 1, true)
  and not text:find("Converted", 1, true), "ten names, then how many more")

T.finish()
