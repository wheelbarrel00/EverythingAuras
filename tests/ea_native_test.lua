-- Everything Auras 0.3.0: Blizzard draws a native aura's icon through an AuraContainer slot (decision 19).
-- Loads the real EA/Native.lua and EA/Migrate.lua with a recording stub of Blizzard's container, shaped after
-- probes N0 to N9 (2026-10-15): a slot without spell IDs shows any aura, buttons lock while auras are secret.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local world = { secret = false, paused = false, created = {}, sounds = {}, nextSound = 0, failContainer = false }

-- Any method not defined records its call, so the test can read what Native.lua asked Blizzard for.
-- Widget methods are capitalized, plain fields are not and read as nil.
local function Object(fields)
  local object = fields or {}
  object.calls = object.calls or {}
  return setmetatable(object, { __index = function(self, key)
    if type(key) ~= "string" or not key:find("^%u") then
      return nil
    end
    return function(_, ...)
      local list = self.calls[key] or {}
      self.calls[key] = list
      list[#list + 1] = { ... }
    end
  end })
end

local function Last(object, method)
  local list = object.calls[method]
  return list and list[#list]
end

local function Count(object, method)
  return object.calls[method] and #object.calls[method] or 0
end

local function Record(object, method, ...)
  local list = object.calls[method] or {}
  object.calls[method] = list
  list[#list + 1] = { ... }
end

-- Like a game texture, alpha and the vertex color's alpha are one value (FloatingChatFrame.lua:550, 1151).
local function NewWidget(parent)
  local widget = Object({ parent = parent, alpha = 1, visible = true, color = { 1, 1, 1 } })
  widget.GetParent = function(self) return self.parent end
  widget.SetAlpha = function(self, alpha) self.alpha = alpha end
  widget.SetVertexColor = function(self, r, g, b, a)
    Record(self, "SetVertexColor", r, g, b, a)
    self.color = { r, g, b }
    self.alpha = a or 1
  end
  widget.GetVertexColor = function(self) return self.color[1], self.color[2], self.color[3], self.alpha end
  widget.Show = function(self) self.visible = true end
  widget.Hide = function(self) self.visible = false end
  widget.SetShown = function(self, shown) self.visible = shown and true or false end
  widget.SetFrameLevel = function(self, level) self.level = level end
  widget.CreateTexture = function(self) return NewWidget(self) end
  widget.CreateFontString = function(self) return NewWidget(self) end
  return widget
end

local function NewContainer()
  local container = NewWidget(nil)
  container.shown = true
  container.Hide = function(self) self.shown = false end
  container.SetShown = function(self, shown) self.shown = shown end
  container.SetUnit = function(self, unit)
    self.unit = unit
    local list = self.calls.SetUnit or {}
    self.calls.SetUnit = list
    list[#list + 1] = { unit }
  end
  container.AddAuraSlot = function(self, key, filter, options)
    self.slot = { key = key, filter = filter, options = options }
    local button = NewWidget(self)
    button.mouse = true
    button.EnableMouse = function(b, on) b.mouse = on end
    button.SetIcon = function(b, texture) b.iconWidget = texture end
    button.SetDurationCooldown = function(b, cooldown) b.cooldownWidget = cooldown end
    button.SetApplicationCount = function(b, count) b.countWidget = count end
    options.initializeFrame(button)
    self.button = button
    return button
  end
  return container
end

local function CreateFrame(kind, _, parent, template)
  if kind == "AuraContainer" then
    if world.failContainer then
      error("no AuraContainer")
    end
    local container = NewContainer()
    container.template = template
    world.created[#world.created + 1] = container
    return container
  end
  local frame = NewWidget(parent)
  frame.kind = kind
  frame.RegisterEvent = function(self, event) self.events = self.events or {}; self.events[event] = true end
  frame.SetScript = function(self, name, handler) self.scripts = self.scripts or {}; self.scripts[name] = handler end
  return frame
end

local auras, regions, errors = {}, {}, {}
local private = {
  frames = {},
  loaded = {},
  regionTypes = { icon = { modify = function(_, region, data)
    region.modified = data.id
    if region.watchText then
      region.textShownAtModify = region.watchText.visible
    end
  end } },
  RunConditions = function(region) region.conditionsRun = (region.conditionsRun or 0) + 1 end,
  Pause = function() world.paused = true end,
  callbacks = { events = {} },
  UIDtoID = function(uid) return uid end,
  TraverseParents = function(data)
    return coroutine.wrap(function()
      local current = data
      while current.parent do
        local parent = auras[current.parent]
        coroutine.yield(parent)
        if not parent then return end
        current = parent
      end
    end)
  end,
}
function private.callbacks:RegisterCallback(event, handler)
  self.events[event] = self.events[event] or {}
  table.insert(self.events[event], handler)
end
function private.callbacks:Fire(event, ...)
  for _, handler in ipairs(self.events[event] or {}) do
    handler(event, ...)
  end
end

local env = setmetatable({
  EverythingAuras = {
    IsLibsOK = function() return true end,
    L = setmetatable({}, { __index = function(_, key) return key end }),
    GetData = function(id) return auras[id] end,
    GetRegion = function(id) return regions[id] end,
    IsPaused = function() return world.paused end,
  },
  C_Secrets = { ShouldAurasBeSecret = function() return world.secret end },
  C_Spell = { GetSpellInfo = function(name) if name == "Seal of Righteousness" then return { spellID = 20293 } end end },
  C_UnitAuras = {
    AddAuraSound = function(trigger, info)
      world.nextSound = world.nextSound + 1
      world.sounds[world.nextSound] = { trigger = trigger, info = info }
      return world.nextSound
    end,
    RemoveAuraSound = function(handle) world.sounds[handle] = nil end,
  },
  Enum = { UnitAuraSoundTrigger = { Added = 0, ApplicationsIncreased = 1, Removed = 2 } },
  CreateFrame = CreateFrame,
  UIParent = NewWidget(nil),
  STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF",
  issecretvalue = function() return false end,
  geterrorhandler = function() return function(err) errors[#errors + 1] = err end end,
  hooksecurefunc = function(object, method, hook)
    local original = object[method]
    object[method] = function(...)
      original(...)
      hook(...)
    end
  end,
  wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
}, { __index = _G })
for _, file in ipairs({ "EverythingAuras/EA/Native.lua", "EverythingAuras/EA/Migrate.lua" }) do
  local chunk = assert(loadfile(T.repoRoot .. "/" .. file))
  setfenv(chunk, env)("EverythingAuras", private)
end
local modify = private.regionTypes.icon.modify
local events = private.frames["Everything Auras Native Icons"]

local function NewRegion(id)
  local region = NewWidget(nil)
  region.id, region.cloneId = id, ""
  region.icon = NewWidget(region)
  region.icon.GetTexCoord = function() return 0.1, 0.1, 0.1, 0.9, 0.9, 0.1, 0.9, 0.9 end
  region.icon.GetDesaturation = function() return 0 end
  region.GetColor = function() return 1, 1, 1, 1 end
  region.cooldown = NewWidget(region)
  region.cooldown.Hide = function(self) self.hidden = true end
  region.cooldown.Show = function(self) self.hidden = false end
  region.GetFrameLevel = function() return 10 end
  region.GetFrameStrata = function() return "MEDIUM" end
  region.UpdateTime = function(self) self.cooldown:Show() end
  region.subRegions = {}
  regions[id] = region
  return region
end

local function NewAura(id, trigger, extra)
  local data = { id = id, uid = id, regionType = "icon", eaNative = true, alpha = 1, cooldown = true,
    triggers = { { trigger = trigger } }, actions = {} }
  for key, value in pairs(extra or {}) do
    data[key] = value
  end
  auras[id] = data
  return data
end

local function Seal(extra)
  return NewAura("Seal", { type = "aura2", unit = "player", debuffType = "HELPFUL", useName = true,
    auranames = { "Seal of Righteousness" } }, extra)
end

local function Add(data)
  local region = regions[data.id] or NewRegion(data.id)
  modify(nil, region, data)
  return region
end

T.section("Which auras Blizzard can draw")
local qualifies = private.EANativeQualifies
local base = { type = "aura2", unit = "player", debuffType = "HELPFUL", useName = true, auranames = { "Seal" } }
local function With(changes)
  local trigger = {}
  for k, v in pairs(base) do trigger[k] = v end
  for k, v in pairs(changes) do trigger[k] = v end
  return NewAura("Q", trigger)
end
T.expect(qualifies(With({})), "a player buff by name qualifies")
T.expect(qualifies(With({ unit = "target", debuffType = "HARMFUL" })), "a debuff on the target qualifies (probe N1a)")
T.expect(not qualifies(With({ debuffType = "HARMFUL" })), "a debuff on you does not (probe N8)")
T.expect(not qualifies(With({ unit = "group" })), "group units do not")
T.expect(not qualifies(With({ debuffType = "BOTH" })), "buff and debuff together do not")
T.expect(not qualifies(With({ matchesShowOn = "showOnMissing" })), "Missing does not")
T.expect(not qualifies(With({ showClones = true })), "Auto-Clone does not")
T.expect(not qualifies(With({ useStacks = true })), "a stacks filter does not")
T.expect(not qualifies(With({ use_stealable = false })), "a set tristate filter does not, even when false")
T.expect(not qualifies(With({ auranames = { "" } })), "no names or IDs does not")
local two = With({})
two.triggers[2] = { trigger = { type = "aura2" } }
T.expect(not qualifies(two), "a second trigger does not")
auras.DG = { id = "DG", regionType = "dynamicgroup" }
local inGroup = With({})
inGroup.parent = "DG"
T.expect(not qualifies(inGroup), "inside a dynamic group it does not")
auras.Plain = { id = "Plain", regionType = "group", parent = "DG" }
inGroup.parent = "Plain"
T.expect(not qualifies(inGroup), "nor in a group inside a dynamic group")
local ok, reason = qualifies(With({ debuffType = "HARMFUL" }))
T.expect(not ok and type(reason) == "string" and reason ~= "", "a refusal carries its reason for the tooltip")

T.section("Building the slot")
private.loaded.Seal = true
local data = Seal({ eaNativeIds = { 20154, 20287 } })
data.triggers[1].trigger.ownOnly = true
local region = Add(data)
local container = world.created[#world.created]
T.expect(container and container.template == "CustomAuraContainerTemplate", "one container from Blizzard's template")
T.expect(container.slot.filter == "HELPFUL|PLAYER", "own only becomes the PLAYER filter")
local ids = container.slot.options.candidateFilters.includeSpellIDs
T.expect(ids[20293] and ids[20154] and ids[20287], "names give the known rank plus the stored ranks")
T.expect(container.unit == "player" and Count(container, "SetEditModePreviewEnabled") == 1, "unit set, Edit Mode fakes off (probe N9)")
local button = container.button
T.expect(button.iconWidget and button.cooldownWidget and button.countWidget, "icon, cooldown and stack count handed to Blizzard")
T.expect(button.mouse == false, "the button never eats clicks (probe N0)")
T.expect(container.level == 9 and button.level == 10, "the button lands on the region's own level")
T.expect(container.shown and region.eaNativeOn and not region.icon.visible, "loaded: Blizzard draws, Everything Auras' icon steps aside")
T.expect(region.modified == "Seal", "the region is modified as usual first")
region:UpdateTime()
T.expect(region.cooldown.hidden, "Everything Auras' own swipe stays hidden")
T.expect(#errors == 0, "no errors")

T.section("Spell IDs")
local exact = NewAura("Exact", { type = "aura2", unit = "target", debuffType = "HARMFUL", useExactSpellId = true,
  auraspellids = { "5588", "x" } })
private.loaded.Exact = true
Add(exact)
local exactContainer = world.created[#world.created]
local exactIds = exactContainer.slot.options.candidateFilters.includeSpellIDs
T.expect(exactIds[5588] and exactContainer.unit == "target" and exactContainer.slot.filter == "HARMFUL", "exact IDs on the target")
local fa = NewAura("FA", { type = "aura2", unit = "player", debuffType = "HELPFUL", useName = true,
  auranames = { "Unknown Spell" }, auraRankSpellIDs = { 111, 222 } })
private.loaded.FA = true
Add(fa)
local faIds = world.created[#world.created].slot.options.candidateFilters.includeSpellIDs
T.expect(faIds[111] and faIds[222], "ForeverAuras' rank lists count")
local before = #world.created
local none = NewAura("None", { type = "aura2", unit = "player", debuffType = "HELPFUL", useName = true,
  auranames = { "Nothing Known" } })
private.loaded.None = true
local noneRegion = Add(none)
T.expect(#world.created == before and not noneRegion.eaNativeOn, "no spell IDs: no slot at all, Everything Auras draws it (probe N0)")

T.section("Loaded, paused, unloaded")
private.Pause()
T.expect(not container.shown and not region.eaNativeOn and region.icon.visible, "options open: Everything Auras draws for the preview")
world.paused = false
private.callbacks:Fire("ScanForLoads")
T.expect(container.shown and region.eaNativeOn, "options closed: Blizzard draws again")
private.loaded.Seal = false
private.callbacks:Fire("ScanForLoads")
T.expect(not container.shown, "unloaded: hidden")
private.loaded.Seal = true
private.callbacks:Fire("ScanForLoads")
T.expect(container.shown, "loaded again: shown")

T.section("Changes reuse the slot")
data.triggers[1].trigger.ownOnly = nil
data.eaNativeIds = { 20154 }
private.callbacks:Fire("Add", data.uid, data.id, data)
T.expect(Last(container, "SetAuraSlotFilterString")[2] == "HELPFUL", "filter updated in place")
local updated = Last(container, "SetAuraSlotCandidateFilters")[2].includeSpellIDs
T.expect(updated[20154] and not updated[20287], "spell IDs updated in place")
data.eaNative = false
Add(data)
T.expect(not container.shown and region.icon.visible and not region.eaNativeOn, "switched off: Everything Auras draws again")
data.eaNative = true
Add(data)
T.expect(container.shown and #world.created == before, "switched on again: the same container")

T.section("Stack count")
local text = NewWidget(region)
text.GetFont = function() return "Fonts\\ARIALN.TTF", 14, "OUTLINE" end
text.GetTextColor = function() return 1, 0.8, 0, 1 end
text.GetShadowColor = function() return 0, 0, 0, 1 end
text.GetShadowOffset = function() return 0, 0 end
text.GetJustifyH = function() return "CENTER" end
text.GetPoint = function() return "BOTTOMRIGHT", region.icon, "BOTTOMRIGHT", -2, 2 end
region.subRegions = { { type = "subtext", text_text = "%p", text = NewWidget(region) }, { type = "subtext", text_text = "%s", text = text,
  color_r = 1, color_g = 0.8, color_b = 0, color_a = 1 } }
Add(data)
local count = button.countWidget
T.expect(Last(count, "SetFont")[1] == "Fonts\\ARIALN.TTF" and Last(count, "SetPoint")[2] == region.icon, "Blizzard's count takes the stack text's font and place")
T.expect(count.alpha == 1 and not text.visible, "and replaces it, so it is never drawn twice")
region.watchText = text
Add(data)
T.expect(region.textShownAtModify and not text.visible, "visible again before modify returns it to the shared pool")
region.watchText = nil
private.Pause()
T.expect(text.visible, "Everything Auras' stack text is back while Blizzard does not draw")
world.paused = false
private.callbacks:Fire("ScanForLoads")
region.subRegions = {}
Add(data)
T.expect(count.alpha == 0 and text.visible, "no stack text: no count")

T.section("Look")
private.callbacks:Fire("ScanForLoads")
private.callbacks:Fire("ScanForLoads")
T.expect(button.iconWidget.alpha == 1, "Blizzard's icon keeps full alpha through refreshes (it went invisible in game 2026-10-15)")
region.icon:SetVertexColor(1, 0, 0, 1)
T.expect(not region.icon.visible, "a color change does not bring Everything Auras' own icon back")
T.expect(button.iconWidget.calls.SetVertexColor and Last(button.iconWidget, "SetVertexColor")[1] == 1
  and Last(button.iconWidget, "SetVertexColor")[2] == 0, "color changes reach Blizzard's icon out of combat")
local calls = Count(button.iconWidget, "SetVertexColor")
world.secret = true
region.icon:SetVertexColor(0, 1, 0, 1)
T.expect(Count(button.iconWidget, "SetVertexColor") == calls, "while auras are secret nothing touches the locked button (probe N2)")
local styled = Count(button.iconWidget, "SetTexCoord")
Add(data)
T.expect(Count(button.iconWidget, "SetTexCoord") == styled, "a change while secret waits")
world.secret = false
events.scripts.OnEvent(events, "ADDON_RESTRICTION_STATE_CHANGED")
T.expect(Count(button.iconWidget, "SetTexCoord") > styled, "and is applied when auras are readable again")
data.useTooltip = true
Add(data)
T.expect(Last(button, "EnableMouseMotion")[1] == true and Last(button, "SetMouseClickEnabled")[1] == false, "Tooltip on Mouseover: Blizzard's tooltip, clicks pass through (probe N6)")
data.useTooltip = nil

T.section("Target changes")
local targetCalls = Count(exactContainer, "UpdateAllAuras")
events.scripts.OnEvent(events, "PLAYER_TARGET_CHANGED")
T.expect(Count(exactContainer, "UpdateAllAuras") == targetCalls + 1 and Count(container, "UpdateAllAuras") == 0, "a new target refreshes target slots only (probe N1b)")

T.section("Learning a rank read out of combat")
region.states = { [1] = { show = true, spellId = 99999 } }
private.RunConditions(region, "Seal")
local learned = Last(container, "SetAuraSlotCandidateFilters")[2].includeSpellIDs
T.expect(learned[99999] and region.conditionsRun == 1, "a rank Everything Auras saw joins the slot's list")
region.states = { [1] = { show = true, spellId = 88888, eaUnsure = "lastKnown" } }
private.RunConditions(region, "Seal")
T.expect(not Last(container, "SetAuraSlotCandidateFilters")[2].includeSpellIDs[88888], "a guessed state teaches nothing")

T.section("Sounds")
data.actions = {
  start = { do_sound = true, sound = "Interface\\AddOns\\BigWigs\\Media\\Sounds\\Alert.ogg", sound_channel = "SFX" },
  finish = { do_sound = true, sound = " KitID", sound_kit_id = "8959" },
}
Add(data)
local added = 0
for _, sound in pairs(world.sounds) do
  if sound.trigger == 0 and sound.info.unitToken == "player" and sound.info.outputChannel == "SFX" then
    added = added + 1
  end
end
T.expect(added >= 2, "On Show registers Blizzard's sound for every rank")
T.expect(private.EANativeSound(data, "start") and not private.EANativeSound(data, "finish"), "a sound kit stays Everything Auras' own")
data.actions.finish = { do_sound = true, sound = " custom", sound_path = "Interface\\Custom.ogg" }
Add(data)
local removed = false
for _, sound in pairs(world.sounds) do
  removed = removed or (sound.trigger == 2 and sound.info.soundFileName == "Interface\\Custom.ogg")
end
T.expect(removed and private.EANativeSound(data, "finish"), "On Hide becomes Blizzard's Removed sound")
private.loaded.Seal = false
private.callbacks:Fire("ScanForLoads")
T.expect(next(world.sounds) == nil or not private.EANativeSound(data, "start"), "unloaded: Blizzard's sounds are removed")
local leftover = 0
for _, sound in pairs(world.sounds) do
  if sound.info.spellID and ids[sound.info.spellID] then
    leftover = leftover + 1
  end
end
T.expect(leftover == 0, "none left behind")
private.loaded.Seal = true
private.callbacks:Fire("ScanForLoads")

T.section("Delete and reuse")
local reused = #world.created
private.callbacks:Fire("Delete", "Exact", "Exact")
T.expect(not exactContainer.shown, "a deleted aura's container hides")
local later = NewAura("Later", { type = "aura2", unit = "focus", debuffType = "HARMFUL", useExactSpellId = true, auraspellids = { "7" } })
private.loaded.Later = true
Add(later)
T.expect(#world.created == reused and exactContainer.unit == "focus" and exactContainer.shown, "a new aura reuses it out of combat")

T.section("Failure keeps the aura working")
world.failContainer = true
local broken = NewAura("Broken", { type = "aura2", unit = "player", debuffType = "HELPFUL", useExactSpellId = true, auraspellids = { "1" } })
private.loaded.Broken = true
local brokenRegion = Add(broken)
T.expect(not brokenRegion.eaNativeOn and brokenRegion.icon.visible, "no container: Everything Auras draws the icon itself")
world.failContainer = false

T.section("ForeverAuras imports")
private.EAUpdateWarnings = function() end
local function Imported(trigger)
  local import = { id = "Imp", uid = "Imp", regionType = "icon", eaVersion = 2, triggers = { { trigger = trigger } } }
  trigger.type, trigger.eaConvertedFrom = "aura2", "secretAura"
  return import
end
local import = Imported({ unit = "player", debuffType = "HELPFUL", useName = true, auranames = { "Seal" } })
private.EAModernize(import)
T.expect(import.eaNative == true and import.eaVersion == 3, "a converted Aura (Modern) icon that qualifies is drawn by Blizzard")
local mine = NewAura("Mine", base)
mine.eaVersion, mine.eaNative = 2, nil
private.EAModernize(mine)
T.expect(mine.eaNative == nil, "an aura that was never Aura (Modern) is left alone")
local off = Imported({ unit = "player", debuffType = "HELPFUL", useName = true, auranames = { "Seal" } })
off.eaNative = false
private.EAModernize(off)
T.expect(off.eaNative == false, "switched off stays off")
local missing = Imported({ unit = "player", debuffType = "HELPFUL", useName = true, auranames = { "Seal" }, matchesShowOn = "showOnMissing" })
private.EAModernize(missing)
T.expect(missing.eaNative == nil, "one Blizzard cannot draw is left to Everything Auras")
T.expect(#errors == 0, "no errors at all" .. (errors[1] and (": " .. tostring(errors[1])) or ""))
T.finish()
