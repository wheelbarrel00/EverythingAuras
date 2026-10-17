-- Everything Auras step 7a: the Everything Auras window, its dialogs, What's New and the slash commands,
-- against a recording stand-in for the EverythingUI library.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

-- Any frame method is a no-op, except the few the code reads back.
local Stub
function Stub(fields)
  return setmetatable(fields or {}, { __index = function(_, k)
    if k == "GetStringHeight" or k == "GetHeight" or k == "GetWidth" then
      return function() return 13 end
    end
    if k:find("^Create") then
      return function() return Stub() end
    end
    return function() end
  end })
end

local rec = { dialogs = {}, tabs = {}, selected = {}, toggles = 0, raises = 0, checkboxes = {}, buttons = {},
  rows = {}, lines = {}, timers = {}, events = {}, ldb = {} }
local settingsWindow = Stub({ shown = false })
function settingsWindow.IsShown(self) return self.shown end
function settingsWindow.Raise() rec.raises = rec.raises + 1 end

local ctx = Stub()
function ctx.RegisterTab(_, def) rec.tabs[#rec.tabs + 1] = def end
function ctx.BuildSettings(_, name) rec.windowName = name return settingsWindow end
function ctx.SelectTab(_, id) rec.selected[#rec.selected + 1] = id end
function ctx.ToggleSettings() rec.toggles = rec.toggles + 1 settingsWindow.shown = not settingsWindow.shown end
function ctx.ShowDialog(_, opts) rec.dialogs[#rec.dialogs + 1] = opts end
function ctx.Color() return 1, 1, 1 end
function ctx.Spacing() return 10 end
function ctx.Texture(_, name) return "lib/" .. name end
function ctx.CreateGroup(_, _, label)
  return Stub({ label = label, Add = function(_, control, opts) rec.rows[#rec.rows + 1] = { label = label, control = control, opts = opts } end })
end
function ctx.CreateTextBlock()
  return Stub({ AddLine = function(_, text, style, lineOpts) rec.lines[#rec.lines + 1] = { text = text, style = style, opts = lineOpts } end,
    Measure = function() return 40 end })
end
function ctx.CreateText(_, _, text) return Stub({ text = text }) end
function ctx.CreateTextRow(_, _, label, text)
  local row = Stub({ labelText = label, value = text, label = Stub() })
  return row
end
function ctx.CreateCheckbox(_, _, label, getter, setter, tip)
  local cb = Stub({ labelText = label, getter = getter, setter = setter, tip = tip })
  rec.checkboxes[label] = cb
  return cb
end
function ctx.CreateButton(_, _, label, _, onClick, _, style)
  local b = Stub({ labelText = label, onClick = onClick, style = style })
  rec.buttons[label] = b
  return b
end
local whatsNewWindow
function ctx.CreateWindow(_, spec)
  whatsNewWindow = Stub({ spec = spec, hooks = {}, body = Stub(), shown = false })
  function whatsNewWindow.HookScript(self, script, f) self.hooks[script] = f end
  function whatsNewWindow.SetSection(self, text) self.section = text end
  function whatsNewWindow.Show(self) self.shown = true if self.hooks.OnShow then self.hooks.OnShow() end end
  function whatsNewWindow.Hide(self) self.shown = false if self.hooks.OnHide then self.hooks.OnHide() end end
  return whatsNewWindow
end
function ctx.CreateScrollArea() return Stub({ content = Stub(), scroll = Stub() }) end

local EUI = { NewContext = function(_, opts) rec.contextOpts = opts return ctx end }
local LDBIcon = { Show = function(_, name) rec.ldb[#rec.ldb + 1] = "show " .. name end,
  Hide = function(_, name) rec.ldb[#rec.ldb + 1] = "hide " .. name end }

local L = setmetatable({}, { __index = function(_, key) return key end })
local printed = {}
local originalSlash = function(input) rec.slashInput = input end
local private = { db = { minimap = { hide = false } } }

local env = setmetatable({
  EverythingAuras = { IsLibsOK = function() return true end, L = L, versionString = "v0.1.0-beta" },
  LibStub = function(name) return name == "EverythingUI-1.0" and EUI or LDBIcon end,
  GameTooltip = {},
  C_Spell = { GetSpellTexture = function() return 135000 end },
  C_Timer = { After = function(delay, f) rec.timers[#rec.timers + 1] = { delay = delay, f = f } end },
  CreateFrame = function()
    local frame = Stub()
    function frame.RegisterEvent(self, event)
      rec.events[event] = rec.events[event] or {}
      table.insert(rec.events[event], self)
    end
    function frame.UnregisterEvent(self, event)
      for i, f in ipairs(rec.events[event] or {}) do
        if f == self then table.remove(rec.events[event], i) break end
      end
    end
    function frame.SetScript(self, _, f) self.handler = f end
    return frame
  end,
  IsSecureCmd = function() return false end,
  hash_SlashCmdList = {},
  SlashCmdList = { EverythingAuras = originalSlash },
  print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end,
}, { __index = _G })
_G.SLASH_OTHER1 = "/ea"
env.SlashCmdList.OTHER = function() end

for _, file in ipairs({ "Combat.lua", "Slash.lua", "UI.lua", "Settings.lua", "WhatsNew.lua" }) do
  private.regionPrototype = private.regionPrototype or { create = function() end }
  private.PerformActions = private.PerformActions or function() end
  private.RunConditions = private.RunConditions or function() end
  local chunk = assert(loadfile(T.repoRoot .. "/EverythingAuras/EA/" .. file))
  setfenv(chunk, env)("EverythingAuras", private)
end

-- A real login fires once, so each test login re-registers the frames that unregistered themselves.
local loginFrames
local function fire(event, ...)
  loginFrames = loginFrames or { unpack(rec.events[event]) }
  for _, frame in ipairs(loginFrames) do
    frame.handler(frame, event, ...)
  end
end

T.section("The library context")
local opts = rec.contextOpts
T.expect(opts.id == "EA" and opts.title == "Everything Auras", "its own context, titled with the space")
T.expect(math.abs(opts.accent[1] - 0x81 / 255) < 1e-9 and math.abs(opts.accent[2] - 0x52 / 255) < 1e-9
  and math.abs(opts.accent[3] - 0xD6 / 255) < 1e-9, "violet #8152D6")
T.expect(opts.version == "0.1.0-beta", "the tag's v is dropped, the library draws its own")
T.expect(opts.getLastTab() == nil, "no page saved yet, so the first page opens")
opts.setLastTab("about")
T.expect(private.db.eaSettingsPage == "about" and opts.getLastTab() == "about", "the page you left is saved")
T.expect(opts.discord ~= nil and opts.labels.discord ~= nil, "the family Discord button")

T.section("Dialogs")
private.EAShowDialog({ title = "Delete", text = "x", button1 = "Delete", button2 = "Cancel", danger = true, extra = 1 })
local d = rec.dialogs[#rec.dialogs]
T.expect(d.danger == true and d.extra == nil and d.button2 == "Cancel", "fields pass one by one, danger kept")
private.EAShowDialog({ title = "Import", text = "x", button1 = "Import" })
T.expect(rec.dialogs[#rec.dialogs].danger == nil, "no danger unless asked")
private.EAShowLink("bug")
d = rec.dialogs[#rec.dialogs]
T.expect(d.readOnly and d.hasEditBox and d.editBoxText == "https://github.com/wheelbarrel00/EverythingAuras/issues",
  "a link opens in a copy-only field")
opts.discord()
T.expect(rec.dialogs[#rec.dialogs].editBoxText == "https://discord.gg/vm8K2WfQUE", "the family invite")
private.EAShowLink("docs")
T.expect(rec.dialogs[#rec.dialogs].editBoxText == "https://github.com/m33shoq/M33kAuras/wiki", "Documentation is the M33kAuras wiki")

T.section("Opening the window")
private.EAOpenSettings("combat")
T.expect(rec.windowName == "EverythingAurasSettings" and rec.selected[#rec.selected] == "combat" and rec.toggles == 1,
  "a page opens the window on it")
private.EAOpenSettings("about")
T.expect(rec.selected[#rec.selected] == "about" and rec.toggles == 1 and rec.raises == 1,
  "an open window switches page and comes forward")

T.section("Pages")
T.expect(#rec.tabs == 3 and rec.tabs[1].id == "combat" and rec.tabs[2].id == "general" and rec.tabs[3].id == "about",
  "In Combat, General and About")
T.expect(rec.tabs[1].order < rec.tabs[2].order and rec.tabs[2].order < rec.tabs[3].order, "in that order")
T.expect(rec.tabs[1].icon == "Interface\\AddOns\\EverythingAuras\\Media\\EA\\icon-combat.tga", "In Combat has its own icon")
for _, tab in ipairs(rec.tabs) do
  local ok, err = pcall(tab.build, ctx, Stub({ _controls = {} }))
  T.expect(ok, tab.id .. " builds" .. (ok and "" or (": " .. tostring(err))))
end
local function hasLine(fragment)
  for _, line in ipairs(rec.lines) do
    if line.text:find(fragment, 1, true) then return true end
  end
end
T.expect(hasLine("hides the details of auras") and hasLine("10 Lua errors"), "In Combat carries its sentences")
local function lineOpts(fragment)
  for _, line in ipairs(rec.lines) do
    if line.text:find(fragment, 1, true) then return line.opts end
  end
end
T.expect(lineOpts("hides the details of auras") == nil and lineOpts("So it keeps what it read").gap == 10,
  "paragraphs after the first get a 10 px gap")
local function rowsOf(label)
  local out = {}
  for _, row in ipairs(rec.rows) do
    if row.label == label then out[#out + 1] = row end
  end
  return out
end
T.expect(#rowsOf("What else works in combat") == 5, "five things that work in combat")
T.expect(hasLine("Turn on Blizzard Draws This Icon") and hasLine("debuffs on you") and not hasLine("stack count"),
  "In Combat explains icons Blizzard draws, with only what was seen in game (no stack count yet)")

local whatsNewBox = rec.checkboxes["Show What's New after an update"]
T.expect(whatsNewBox.getter() == true, "What's New is on by default")
whatsNewBox.setter(false)
T.expect(private.db.eaShowWhatsNew == false and whatsNewBox.getter() == false, "and can be switched off")
whatsNewBox.setter(true)
local minimapBox = rec.checkboxes["Show Minimap Button"]
minimapBox.setter(false)
T.expect(private.db.minimap.hide == true and rec.ldb[#rec.ldb] == "hide EverythingAuras", "the minimap box hides the button")
minimapBox.setter(true)
T.expect(private.db.minimap.hide == false and rec.ldb[#rec.ldb] == "show EverythingAuras", "and shows it again")

local status = {}
for _, row in ipairs(rowsOf("Commands")) do status[row.control.labelText] = row.control.value end
T.expect(status["/eauras settings"] ~= nil, "the commands list /eauras settings")
T.expect(status["/wa"] == "Used by another addon" and status["/ea"] == "Used by another addon",
  "before login nothing short is ours")

rec.buttons["Copy Source Link"].onClick()
T.expect(rec.dialogs[#rec.dialogs].editBoxText == "https://github.com/wheelbarrel00/EverythingAuras", "About copies the source link")

T.section("Slash commands")
fire("PLAYER_LOGIN")
T.expect(private.EAShortCommands["/wa"] == true and not private.EAShortCommands["/ea"], "/wa is free and taken, /ea is not")
env.SlashCmdList.EverythingAuras("settings")
T.expect(rec.selected[#rec.selected] == "about" and rec.raises == 2, "/eauras settings opens the window")
env.SlashCmdList.EverythingAuras("minimap")
T.expect(rec.slashInput == "minimap", "every other command goes on as before")
printed = {}
private.PrintHelp()
local help = table.concat(printed, "\n")
T.expect(help:find("/eauras settings", 1, true) and help:find("/eauras minimap", 1, true), "help lists /eauras")
T.expect(not help:find("\n/wa ", 1, true), "no help line starts with /wa")
T.expect(help:find("Also available as /wa.", 1, true), "and says /wa works too, since it is ours")

T.section("What's New")
local function loginTimerCount()
  local n = 0
  for _, t in ipairs(rec.timers) do
    if t.delay == 2 then n = n + 1 end
  end
  return n
end
local loginTimers = loginTimerCount()
fire("PLAYER_LOGIN")
T.expect(loginTimerCount() == loginTimers + 1 and rec.timers[#rec.timers].delay == 2, "a new version shows What's New after login")
rec.timers[#rec.timers].f()
T.expect(whatsNewWindow.shown and whatsNewWindow.section == "Everything Auras 0.3.0-beta", "titled with the version")
rec.buttons["Got it"].onClick()
T.expect(not whatsNewWindow.shown and private.db.eaSeenWhatsNew == "0.3.0-beta", "closing it marks the version seen")
fire("PLAYER_LOGIN")
T.expect(loginTimerCount() == loginTimers + 1, "the same version does not show again")
private.db.eaSeenWhatsNew = nil
private.db.eaShowWhatsNew = false
fire("PLAYER_LOGIN")
T.expect(loginTimerCount() == loginTimers + 1, "switched off, it never shows by itself")
private.EAShowWhatsNew()
T.expect(whatsNewWindow.shown, "but opens on request")
rec.checkboxes["Don't show this again"].setter(false)
T.expect(private.db.eaShowWhatsNew == true, "its own box turns it back on")
rec.buttons["What Works in Combat"].onClick()
T.expect(not whatsNewWindow.shown and rec.selected[#rec.selected] == "combat", "What Works in Combat opens that page")
T.finish()
