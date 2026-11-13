-- Everything Auras 0.6.0 round 4: Load Flag, the swing timer helpers and AuraOverlay (EA/Helpers.lua).
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local function read(path)
  local file = assert(io.open(T.repoRoot .. "/" .. path))
  local text = file:read("*a"):gsub("\r\n", "\n")
  file:close()
  return text
end

local secret = newproxy(true)

local loadSource = read("EverythingAuras/EverythingAuras.lua")
local loadFirst = assert(loadSource:find("local function EvalBooleanArg", 1, true))
local loadLast = assert(loadSource:find("function EverythingAuras.GetActiveConditions", loadFirst, true))
local loadEnv = setmetatable({ tinsert = table.insert,
  Private = { QuotedString = function(s) return ("%q"):format(s) end } }, { __index = _G })
local LoadConstruct = setfenv(assert(loadstring(loadSource:sub(loadFirst, loadLast - 1) .. "\nreturn ConstructFunction")),
  loadEnv)()

local function Stub(fields)
  return setmetatable(fields or {}, { __index = function() return function() end end })
end

local function fixture(forever)
  local f = { timers = {}, scans = {}, frames = {}, containers = {}, swingCalls = {}, inits = 0, fonts = {} }
  f.private = {
    load_prototype = { args = { { name = "class" }, { name = "playerTitle" }, { name = "size" } } },
    ScanForLoads = function(_, event) f.scans[#f.scans + 1] = event end,
    EACurrentAuraUid = function() return f.currentUid end,
    ClearAuraEnvironment = function(id) f.cleared[#f.cleared + 1] = id end,
  }
  f.cleared, f.auras = {}, { ["Aura A"] = { uid = "auraA" }, ["Aura B"] = { uid = "auraB" } }
  f.addon = {
    IsLibsOK = function() return true end,
    IsForever = function() return forever end,
    L = setmetatable({}, { __index = function(_, key) return key end }),
    newFeatureString = "",
    GetSwingTimerInfo = function(hand) f.swingCalls[#f.swingCalls + 1] = hand return 2, 10, "Sword" end,
    InitSwingTimer = function() f.inits = f.inits + 1 end,
    SafeToNumber = function(v) local n = tonumber(v) return n and n < 2147483648 and n or nil end,
    GetData = function(id) return f.auras[id] end,
  }
  local function Texture(kind)
    local tex = Stub({ kind = kind })
    function tex.SetColorTexture(self, r, g, b, a) self.color = { r, g, b, a } end
    function tex.SetTexture(self, path) self.path = path end
    function tex.SetTexCoord(self, ...) self.coords = { ... } end
    function tex.SetHeight(self, h) self.height = h end
    function tex.SetWidth(self, w) self.width = w end
    return tex
  end
  local function Button()
    local b = Stub({ textures = {} })
    function b.CreateTexture(self, _, layer) local t = Texture(layer) self.textures[#self.textures + 1] = t return t end
    function b.CreateFontString(self) self.count = Stub() return self.count end
    function b.SetIcon(self, icon) self.icon = icon end
    function b.SetDurationCooldown(self, cd) self.cooldown = cd end
    function b.SetApplicationCount(self, fs) self.applications = fs end
    function b.EnableMouse(self, on) self.mouse = on end
    return b
  end
  local function Container(parent)
    local c = Stub({ parent = parent, slots = {}, shown = true, updates = 0 })
    function c.AddAuraSlot(self, slot, filter, opts)
      if f.refuseSlots then error("refused") end
      local button = Button()
      self.slots[slot] = { filter = filter, ids = opts.candidateFilters.includeSpellIDs, enabled = true, button = button }
      if not f.lateInit then opts.initializeFrame(button) end
      if f.failAfterInit then error("refused after init") end
      return button
    end
    function c.SetAuraSlotCandidateFilters(self, slot, filters) self.slots[slot].ids = filters.includeSpellIDs end
    function c.SetAuraSlotEnabled(self, slot, on)
      if not self.slots[slot] then error("no slot") end
      self.slots[slot].enabled = on
    end
    function c.SetUnit(self, unit) self.unit = unit end
    function c.UpdateAllAuras(self) self.updates = self.updates + 1 end
    function c.SetShown(self, on) self.shown = on end
    function c.Hide(self) self.shown = false end
    function c.SetFrameLevel(self, level) self.level = level end
    return c
  end
  f.env = setmetatable({
    EverythingAuras = f.addon,
    C_Timer = { After = function(delay, fn) f.timers[#f.timers + 1] = { delay = delay, fn = fn } end },
    C_SwingTimer = { IsTargetWithinSwingRange = function(kind)
      f.rangeKind = kind
      if f.rangeError then error("bad") end
      return f.rangeAnswer
    end },
    issecretvalue = function(v) return rawequal(v, secret) end,
    CreateFrame = function(kind, _, parent, template)
      if kind == "AuraContainer" then
        if f.noContainer then error("unknown frame type") end
        assert(template == "CustomAuraContainerTemplate", "the custom container template")
        local c = Container(parent)
        f.containers[#f.containers + 1] = c
        return c
      end
      local frame = Stub({ events = {}, kind = kind })
      function frame.RegisterEvent(self, event) self.events[event] = true end
      function frame.SetScript(self, _, fn) self.handler = fn end
      function frame.SetAllPoints(self, to) self.anchor = to end
      function frame.SetReverse(self, on) self.reverse = on end
      function frame.SetHideCountdownNumbers(self, on) self.hideNumbers = on end
      function frame.SetCountdownFont(self, name) self.font = name end
      function frame.GetCountdownFontString(self)
        self.countdownText = rawget(self, "countdownText") or Stub({ points = {} })
        function self.countdownText.SetPoint(text, ...) text.points[#text.points + 1] = { ... } end
        return self.countdownText
      end
      f.frames[#f.frames + 1] = frame
      return frame
    end,
    CreateFont = function(name)
      local font = Stub({ name = name })
      function font.GetName(self) return self.name end
      function font.SetFont(self, ...) self.spec = { ... } end
      f.fonts[#f.fonts + 1] = font
      return font
    end,
    STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF",
  }, { __index = _G })
  setfenv(assert(loadfile(T.repoRoot .. "/EverythingAuras/EA/Helpers.lua")), f.env)("EverythingAuras", f.private)
  return f
end

local function flush(f)
  local timers = f.timers
  f.timers = {}
  for _, timer in ipairs(timers) do timer.fn() end
end

T.section("Forever only")
local retail = fixture(false)
T.expect(retail.addon.SetLoadFlag == nil and #retail.private.load_prototype.args == 3, "nothing is added on Retail")

T.section("Load Flag")
local f = fixture(true)
local args = f.private.load_prototype.args
T.expect(args[2].name == "loadFlag" and args[3].name == "playerTitle", "the Load Flag option sits before Player Title")
T.expect(args[2].type == "string" and args[2].events[1] == "EA_LOAD_FLAG", "a text box, rechecked on its own scan")
T.expect(f.addon.LoadFlag("raid") == false, "an unset flag is off")
f.addon.SetLoadFlag("raid", true)
f.addon.SetLoadFlag("solo", true)
f.addon.SetLoadFlags({ tank = true, [1] = true })
T.expect(f.addon.LoadFlag("raid") and f.addon.LoadFlag("solo") and f.addon.LoadFlag("tank"), "set flags read as on")
T.expect(#f.scans == 0 and #f.timers == 1 and f.timers[1].delay == 0, "every change in one frame waits for one recheck")
flush(f)
T.expect(#f.scans == 1 and f.scans[1] == "EA_LOAD_FLAG", "which scans the auras that use a flag")
f.addon.SetLoadFlag("raid", 1)
T.expect(#f.timers == 0, "setting a flag to the value it has changes nothing")
f.addon.SetLoadFlag("raid", false)
T.expect(f.addon.LoadFlag("raid") == false and #f.timers == 1, "false clears it and rechecks")
flush(f)
f.addon.SetLoadFlag("", true)
f.addon.SetLoadFlag(nil, true)
f.addon.SetLoadFlags("raid")
T.expect(#f.timers == 0 and f.addon.LoadFlag(nil) == false, "names that are not text are ignored")
T.expect(f.addon.LoadFlag("Solo") == false, "names are case-sensitive")

local function loads(load)
  local code, events = LoadConstruct(f.private.load_prototype, load)
  local fn = setfenv(assert(loadstring(code)), setmetatable({ EverythingAuras = f.addon }, { __index = _G }))()
  return fn("SCAN_ALL"), events
end
local result, events = loads({ use_loadFlag = true, loadFlag = "solo" })
T.expect(result == true and events.EA_LOAD_FLAG, "an aura with a set flag loads, and listens for flag changes")
T.expect(loads({ use_loadFlag = true, loadFlag = "raid" }) == false, "a cleared flag does not load")
local _, unused = loads({ use_loadFlag = false, loadFlag = "raid" })
T.expect(not unused.EA_LOAD_FLAG and loads({ use_loadFlag = false, loadFlag = "raid" }) == true,
  "the option off is ignored and not watched")
f.addon.SetLoadFlag('a"b\nc', true)
T.expect(loads({ use_loadFlag = true, loadFlag = 'a"b\nc' }) == true, "quotes and line breaks in a name stay text")

T.section("Swing timer helpers")
f.addon.GetSwingTimerInfo(1)
f.addon.GetSwingTimerInfo("ranged")
f.addon.GetSwingTimerInfo(0)
T.expect(f.swingCalls[1] == "off" and f.swingCalls[2] == "ranged" and f.swingCalls[3] == "main",
  "0, 1 and 2 read the main, off and ranged hand, names still work")
f.addon.WatchSwingTimer()
T.expect(f.inits == 1, "WatchSwingTimer starts the swing watcher")
f.rangeAnswer = true
T.expect(f.addon.IsTargetInSwingRange("main") == true and f.rangeKind == 0, "range by hand name")
f.rangeAnswer = secret
T.expect(f.addon.IsTargetInSwingRange(2) == nil and f.rangeKind == 2, "a hidden answer reads as unknown")
f.rangeError = true
T.expect(f.addon.IsTargetInSwingRange(0) == nil, "an error reads as unknown")
T.expect(f.addon.SetupClassPackCDM("PALADIN") == false, "SetupClassPackCDM never sets anything up")

T.section("AuraOverlay")
local unitFrame = Stub({ level = 3 })
function unitFrame.GetObjectType() return "Button" end
function unitFrame.GetFrameLevel(self) return self.level end
local handle = f.addon.AuraOverlay(unitFrame, { spellIDs = { "20154", 20154, 0, "x", 21084 }, icon = true, stacks = true,
  border = { 1, 0, 0, 1 }, borderSize = 3, countdownSize = 14, unit = "target" })
local container = f.containers[1]
T.expect(handle ~= nil and container.parent == unitFrame and container.level == 8, "drawn over the frame, five levels up")
T.expect(container.unit == "target" and container.slots.main.filter == "HELPFUL", "on the asked unit, buffs by default")
local ids = container.slots.main.ids
T.expect(#ids == 2 and ids[1] == 20154 and ids[2] == 21084, "only real spell IDs, each once")
T.expect(container.slots.harmful == nil, "no debuff slot without debuff IDs")
local button = handle:GetButton()
T.expect(rawget(button, "icon") and rawget(button, "cooldown") and rawget(button, "applications"), "icon, swipe and stack count are handed to Blizzard")
T.expect(button.mouse == false, "the overlay does not take the frame's clicks")
T.expect(#button.textures == 5 and button.textures[2].color[1] == 1 and button.textures[2].height == 3,
  "a red border of the asked size")
T.expect(f.fonts[1] and f.fonts[1].spec[2] == 14 and button.cooldown.font == f.fonts[1].name, "the countdown in its own size")
handle:SetBorderColor(0, 1, 0)
T.expect(button.textures[3].color[2] == 1 and button.textures[3].color[1] == 0, "SetBorderColor recolors every edge")
local before = container.updates
handle:SetSpellIDs({ 853 }, { 25771 })
T.expect(container.slots.main.ids[1] == 853 and container.slots.harmful.filter == "HARMFUL"
  and container.slots.harmful.ids[1] == 25771 and container.updates == before + 1, "SetSpellIDs adds the debuff slot and redraws")
handle:SetSpellIDs({}, { 25771 })
T.expect(container.slots.main.enabled == false and container.slots.harmful.enabled, "an empty list switches its slot off")
handle:SetSpellIDs({ 853 }, {})
T.expect(container.slots.main.enabled == true and container.slots.harmful.enabled == false, "and back on")
handle:SetUnit("focus")
T.expect(container.unit == "focus", "SetUnit moves it")
handle:SetEnabled(false)
T.expect(container.shown == false, "SetEnabled hides it")
handle:SetEnabled(true)
local watcher
for _, frame in ipairs(f.frames) do
  if frame.events.PLAYER_TARGET_CHANGED then watcher = frame end
end
local focusUpdates = container.updates
watcher.handler(watcher, "PLAYER_TARGET_CHANGED")
T.expect(container.updates == focusUpdates, "a target change leaves a focus overlay alone")
watcher.handler(watcher, "PLAYER_FOCUS_CHANGED")
T.expect(container.updates == focusUpdates + 1, "a focus change redraws it")
T.expect(handle:Release() == true and handle:IsReleased() and container.shown == false
  and container.slots.main.enabled == false, "Release switches the slots off and hides it")
handle:SetSpellIDs({ 1 })
watcher.handler(watcher, "PLAYER_FOCUS_CHANGED")
T.expect(container.slots.main.ids[1] == 853 and container.updates == focusUpdates + 1, "a released overlay ignores calls")
T.expect(handle:CleanupPending() == false and handle:Release() == true, "nothing pending, and a second Release is fine")

local plain = f.addon.AuraOverlay(unitFrame, { spellIDs = { 1 }, swipe = false, border = false, texture = "Interface\\x",
  textureCoords = { 0, 1, 0, 1 }, filter = "HELPFUL|PLAYER" })
local plainButton = plain:GetButton()
T.expect(f.containers[2].unit == "player" and f.containers[2].slots.main.filter == "HELPFUL|PLAYER",
  "the player by default, with the asked filter")
T.expect(rawget(plainButton, "cooldown") == nil and #plainButton.textures == 1 and plainButton.textures[1].path == "Interface\\x",
  "no swipe, no border, the asked texture")
plain:SetTexture("Interface\\y")
T.expect(plainButton.textures[1].path == "Interface\\y", "SetTexture swaps it")
local empty = f.addon.AuraOverlay(unitFrame, {})
T.expect(empty ~= nil and next(f.containers[3].slots) == nil, "an overlay can start empty")
empty:SetSpellIDs({ 5 })
T.expect(f.containers[3].slots.main.ids[1] == 5, "and get its spells later")

f.lateInit = true
local late = f.addon.AuraOverlay(unitFrame, { spellIDs = { 7 } })
T.expect(late ~= nil and late:GetButton() ~= nil, "the slot's own button counts when Blizzard sets it up later")
f.lateInit = nil

local none, why = f.addon.AuraOverlay(nil, {})
T.expect(none == nil and why == "AuraOverlay needs a frame.", "no frame, no overlay, with a reason")
f.refuseSlots = true
none, why = f.addon.AuraOverlay(unitFrame, { spellIDs = { 1 } })
T.expect(none == nil and why == "Blizzard refused the aura slot." and f.containers[#f.containers].shown == false,
  "a refused slot gives no overlay")
f.refuseSlots, f.noContainer = nil, true
none, why = f.addon.AuraOverlay(unitFrame, { spellIDs = { 1 } })
T.expect(none == nil and why == "This client cannot draw aura overlays.", "nor does a client without aura containers")
f.noContainer = nil

T.section("AuraOverlay, the second time round")
local slotFrame = Stub({ level = 1 })
function slotFrame.GetObjectType() return "Button" end
function slotFrame.GetFrameLevel(self) return self.level end
local first = f.addon.AuraOverlay(slotFrame, { spellIDs = { 1 }, debuffSpellIDs = { 2 }, countdownPoint = "BOTTOM",
  countdownY = 2, countdownColor = { 1, 0, 0, 1 } })
local firstCooldown = first:GetButton().cooldown
T.expect(firstCooldown.countdownText.points[1][1] == "BOTTOM" and firstCooldown.countdownText.points[1][5] == 2
  and rawget(firstCooldown, "font") ~= nil, "the countdown sits where it was asked, in its own color")
first:SetSpellIDs({ 3 })
local firstContainer = f.containers[#f.containers]
T.expect(firstContainer.slots.harmful.enabled == true and firstContainer.slots.main.ids[1] == 3,
  "SetSpellIDs without a debuff list leaves the debuff slot alone")
f.refuseSlots = true
T.expect(f.addon.AuraOverlay(slotFrame, { spellIDs = { 1 } }) == nil and not first:IsReleased(),
  "a new overlay that fails keeps the one already on the frame")
f.refuseSlots = nil
local otherFrame = Stub({ level = 1 })
function otherFrame.GetObjectType() return "Button" end
function otherFrame.GetFrameLevel(self) return self.level end
local sharedFrame = Stub({ level = 1 })
function sharedFrame.GetObjectType() return "Button" end
function sharedFrame.GetFrameLevel(self) return self.level end
f.currentUid = "auraA"
local fromA = f.addon.AuraOverlay(sharedFrame, { spellIDs = { 1 } })
local fromA2 = f.addon.AuraOverlay(sharedFrame, { spellIDs = { 3 }, border = { 0, 0, 1, 1 } })
f.currentUid = "auraB"
local fromB = f.addon.AuraOverlay(sharedFrame, { spellIDs = { 2 } })
f.currentUid = nil
local loose = f.addon.AuraOverlay(otherFrame, { spellIDs = { 1 } })
T.expect(not fromA:IsReleased() and not fromA2:IsReleased() and not fromB:IsReleased(),
  "one aura can lay two overlays on a frame, and another aura can share it")
f.private.ClearAuraEnvironment("Aura A")
T.expect(fromA:IsReleased() and fromA2:IsReleased() and not fromB:IsReleased() and not loose:IsReleased()
  and f.cleared[#f.cleared] == "Aura A", "when an aura's init is about to run again, only its own overlays retire")
f.private.ClearAuraEnvironment("Aura A")
T.expect(f.cleared[#f.cleared] == "Aura A" and not first:IsReleased(),
  "clearing again is harmless, and overlays made outside aura code stay until released")
f.failAfterInit = true
none, why = f.addon.AuraOverlay(otherFrame, { spellIDs = { 1 } })
T.expect(none == nil and why == "Blizzard refused the aura slot.", "a slot Blizzard refuses after setting it up does not count")
f.failAfterInit = nil

T.finish()
