-- Everything Auras 0.7.0 round 3: the real EA/Native.lua's timers, glows, borders and unnamed auras on a stub.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local world = { secret = false, paused = false, created = {}, now = 100, units = { target = "enemy", pet = "friend" } }

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

local function Count(object, method)
  return object.calls[method] and #object.calls[method] or 0
end

local NewWidget

local function NewAnimationGroup(owner)
  local group = Object({ owner = owner, anims = {} })
  group.SetLooping = function(self, looping) self.looping = looping end
  group.CreateAnimation = function(self, kind)
    local anim = { kind = kind, delay = 0, duration = 0 }
    function anim:SetTarget(target) self.target = target end
    function anim:SetFromAlpha(value) self.from = value end
    function anim:SetToAlpha(value) self.to = value end
    function anim:SetDuration(value) self.duration = value end
    function anim:SetStartDelay(value) self.delay = value end
    function anim:SetOffset(x, y) self.dx, self.dy = x, y end
    function anim:SetOrigin(point) self.origin = point end
    function anim:SetScaleFrom(x, y) self.x0, self.y0 = x, y end
    function anim:SetScaleTo(x, y) self.x1, self.y1 = x, y end
    function anim:SetFlipBookRows(value) self.rows = value end
    function anim:SetFlipBookColumns(value) self.columns = value end
    function anim:SetFlipBookFrames(value) self.frames = value end
    function anim:SetFlipBookFrameWidth(value) self.frameWidth = value end
    function anim:SetFlipBookFrameHeight(value) self.frameHeight = value end
    table.insert(self.anims, anim)
    return anim
  end
  return group
end

function NewWidget(parent, rect)
  local widget = Object({ parent = parent, alpha = 1, visible = true, color = { 1, 1, 1 }, rect = rect })
  widget.GetParent = function(self) return self.parent end
  widget.IsShown = function(self) return self.visible end
  widget.GetEffectiveScale = function(self) return self.scale or 1 end
  widget.SetAlpha = function(self, alpha) self.alpha = alpha end
  widget.SetVertexColor = function(self, r, g, b, a)
    self.color = { r, g, b }
    self.alpha = a or 1
  end
  widget.GetVertexColor = function(self) return self.color[1], self.color[2], self.color[3], self.alpha end
  widget.SetTextColor = function(self, r, g, b, a) self.textColor = { r, g, b, a } end
  widget.SetColorTexture = function(self, r, g, b, a) self.colorTexture = { r, g, b, a } end
  widget.Show = function(self) self.visible = true end
  widget.Hide = function(self) self.visible = false end
  widget.SetShown = function(self, shown) self.visible = shown and true or false end
  widget.SetFrameLevel = function(self, level) self.level = level end
  widget.GetFrameLevel = function(self) return self.level or 10 end
  widget.SetSize = function(self, w, h) self.w, self.h = w, h end
  widget.SetHeight = function(self, h) self.h = h end
  widget.SetWidth = function(self, w) self.w = w end
  widget.SetPoint = function(self, point, relative, relativePoint, x, y)
    self.point, self.relative, self.relativePoint, self.x, self.y = point, relative, relativePoint or point, x or 0, y or 0
    self.points = self.points or {}
    self.points[point] = { relative = relative, x = x or 0, y = y or 0 }
  end
  widget.GetLeft = function(self) return self.rect and self.rect[1] end
  widget.GetBottom = function(self) return self.rect and self.rect[2] end
  widget.GetRight = function(self) return self.rect and self.rect[3] end
  widget.GetTop = function(self) return self.rect and self.rect[4] end
  widget.GetWidth = function(self) return self.rect and self.rect[3] - self.rect[1] end
  widget.GetHeight = function(self) return self.rect and self.rect[4] - self.rect[2] end
  widget.CreateTexture = function(self) local t = NewWidget(self) self.textures = self.textures or {} table.insert(self.textures, t) return t end
  widget.CreateFontString = function(self) return NewWidget(self) end
  widget.CreateAnimationGroup = function(self) return NewAnimationGroup(self) end
  return widget
end

world.uiParent = NewWidget(nil)

local function NewContainer()
  local container = NewWidget(nil)
  container.shown = true
  container.Hide = function(self) self.shown = false end
  container.SetShown = function(self, shown) self.shown = shown end
  container.SetUnit = function(self, unit) self.unit = unit end
  container.AddAuraSlot = function(self, key, filter, options)
    self.slot = { key = key, filter = filter, options = options }
    local button = NewWidget(self)
    button.shownGroups, button.dispel, button.timerOptions = {}, {}, {}
    button.EnableMouse = function() end
    button.AddAuraShownAnimation = function(b, group) table.insert(b.shownGroups, group) end
    button.RemoveAuraShownAnimation = function(b, group)
      for i, g in ipairs(b.shownGroups) do
        if g == group then table.remove(b.shownGroups, i) return end
      end
    end
    button.AddDispelTypeTexture = function(b, texture, textureOptions) table.insert(b.dispel, { texture = texture, options = textureOptions }) end
    button.RemoveDispelTypeTexture = function(b, texture)
      for i, entry in ipairs(b.dispel) do
        if entry.texture == texture then table.remove(b.dispel, i) return end
      end
    end
    button.SetDurationText = function(b, text, textOptions)
      b.timerWidget = text
      table.insert(b.timerOptions, textOptions)
    end
    options.initializeFrame(button)
    self.button = button
    return button
  end
  return container
end

local function CreateFrame(kind, _, parent, template)
  if kind == "AuraContainer" then
    local container = NewContainer()
    container.template = template
    world.created[#world.created + 1] = container
    return container
  end
  local frame = NewWidget(parent)
  frame.kind = kind
  frame.RegisterEvent = function() end
  frame.RegisterUnitEvent = function() end
  frame.SetScript = function() end
  return frame
end

local auras, regions, errors = {}, {}, {}
local inherited = {}
local private = {
  frames = {},
  loaded = {},
  regionTypes = {
    icon = { modify = function(_, region, data) region.modified = data.id end },
    aurabar = { modify = function(_, region, data) region.modified = data.id end },
  },
  RunConditions = function() end,
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
  GetTimeFormatter = function(format, precision, threshold)
    local formatter = { inherited = true, format = format, precision = precision, threshold = threshold }
    inherited[#inherited + 1] = formatter
    return formatter
  end,
}
function private.callbacks:RegisterCallback(event, handler)
  self.events[event] = self.events[event] or {}
  table.insert(self.events[event], handler)
end

local env = setmetatable({
  EverythingAuras = {
    IsLibsOK = function() return true end,
    IsForever = function() return true end,
    SafeToNumber = function(v) return tonumber(v) end,
    L = setmetatable({}, { __index = function(_, key) return key end }),
    GetData = function(id) return auras[id] end,
    GetRegion = function(id) return regions[id] end,
    IsPaused = function() return world.paused end,
  },
  C_Secrets = { ShouldAurasBeSecret = function() return world.secret end },
  C_Spell = { GetSpellInfo = function() return nil end, GetSpellTexture = function() return nil end },
  C_StringUtil = { CreateNumericRuleFormatter = function()
    return { SetBreakpoints = function(self, breakpoints) self.breakpoints = breakpoints end }
  end },
  C_CurveUtil = { CreateColorCurve = function()
    return { points = {}, SetType = function(self, kind) self.kind = kind end,
      AddPoint = function(self, x, color) table.insert(self.points, { x = x, color = color }) end }
  end },
  CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end,
  UnitExists = function(unit) return world.units[unit] ~= nil end,
  UnitCanAssist = function(_, unit) return world.units[unit] == "friend" end,
  UnitIsPlayerControlledOrGroupMember = function(unit) return unit == "player" or unit == "pet" end,
  C_UnitAuras = { AddAuraSound = function() return 1 end, RemoveAuraSound = function() end },
  Enum = { UnitAuraSoundTrigger = { Added = 0, Removed = 2 }, StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 },
    DurationTextBindingProperty = { RemainingDuration = 0 }, LuaCurveType = { Step = 2 },
    NumericRuleFormatRounding = { Nearest = 0, Up = 1, Down = 2 },
    CustomAuraButtonDispelTypeTextureStyle = { PreserveAsset = 3 } },
  CreateFrame = CreateFrame,
  UIParent = world.uiParent,
  STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF",
  WOW_PROJECT_ID = 18,
  WOW_PROJECT_MAINLINE = 1,
  GetTime = function() return world.now end,
  issecretvalue = function() return false end,
  geterrorhandler = function() return function(err) errors[#errors + 1] = err end end,
  C_Timer = { After = function(_, callback) callback() end },
  hooksecurefunc = function(object, method, hook)
    local original = object[method]
    object[method] = function(...)
      original(...)
      hook(...)
    end
  end,
  wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
}, { __index = _G })
local chunk = assert(loadfile(T.repoRoot .. "/EverythingAuras/EA/Native.lua"))
setfenv(chunk, env)("EverythingAuras", private)
local modify = private.regionTypes.icon.modify
local qualifies = private.EANativeQualifies

local function NewRegion(id, subSettings)
  local region = NewWidget(nil, { 100, 100, 132, 132 })
  region.id, region.cloneId, region.regionType = id, "", "icon"
  region.icon = NewWidget(region)
  region.icon.GetTexCoord = function() return 0, 0, 0, 1, 1, 0, 1, 1 end
  region.icon.GetDesaturation = function() return 0 end
  region.GetColor = function() return 1, 1, 1, 1 end
  region.cooldown = NewWidget(region)
  region.GetFrameLevel = function() return 10 end
  region.GetFrameStrata = function() return "MEDIUM" end
  region.subRegions = {}
  -- ApplyFrameLevel puts a background on the region itself and every other part at the base level plus its place.
  local background = subSettings and subSettings[1] and subSettings[1].type == "subbackground"
  for index, settings in ipairs(subSettings or {}) do
    local live = NewWidget(region, { 100, 100, 132, 132 })
    live.level = (background and 9 or 10) + index
    live.type = settings.type
    if settings.type == "subtext" then
      live.text_text = settings.text_text
      live.text = NewWidget(live)
      live.text.GetFont = function() return "font", 12, "OUTLINE" end
      live.text.GetShadowColor = function() return 0, 0, 0, 1 end
      live.text.GetShadowOffset = function() return 1, -1 end
      live.text.GetJustifyH = function() return "CENTER" end
      live.text.GetPoint = function() return "CENTER", region, "CENTER", 0, 0 end
      local color = settings.text_color or { 1, 1, 1, 1 }
      live.color_r, live.color_g, live.color_b, live.color_a = color[1], color[2], color[3], color[4]
    elseif settings.type == "subborder" then
      local offset = settings.border_offset or 0
      live.rect = { 100 - offset, 100 - offset, 132 + offset, 132 + offset }
    end
    region.subRegions[index] = live
  end
  regions[id] = region
  return region
end

local function NewAura(id, trigger, extra)
  local data = { id = id, uid = id, regionType = "icon", eaNative = true, alpha = 1, cooldown = true, width = 32,
    height = 32, triggers = { { trigger = trigger } }, actions = {}, subRegions = {} }
  for key, value in pairs(extra or {}) do
    data[key] = value
  end
  auras[id] = data
  private.loaded[id] = true
  return data
end

local function Seal(id, extra)
  return NewAura(id, { type = "aura2", unit = "player", debuffType = "HELPFUL", useExactSpellId = true,
    auraspellids = { "20154" } }, extra)
end

local function Add(data)
  local region = NewRegion(data.id, data.subRegions)
  modify(nil, region, data)
  local container = world.created[#world.created]
  return region, container, container and container.button
end

local function LastTimer(button)
  return button.timerOptions[#button.timerOptions]
end

T.section("Auras that name no spell (round 3 Q6)")
local function AnyTrigger(changes)
  local trigger = { type = "aura2", unit = "player", debuffType = "HARMFUL" }
  for key, value in pairs(changes or {}) do
    trigger[key] = value
  end
  return trigger
end
T.expect(qualifies(NewAura("Q1", AnyTrigger())), "any debuff on you qualifies")
T.expect(qualifies(NewAura("Q2", AnyTrigger({ unit = "pet" }))) and qualifies(NewAura("Q3", AnyTrigger({ unit = "member",
  specificUnit = "party2" }))), "and on your pet or a group member")
local named, namedReason = qualifies(NewAura("Q4", AnyTrigger({ useName = true, auranames = { "Forbearance" } })))
T.expect(not named and namedReason:find("untick", 1, true), "a named debuff on you does not, and says how to make it work")
T.expect(not qualifies(NewAura("Q5", AnyTrigger({ useName = true, auranames = {} }))), "Name(s) ticked with no names does not")
T.expect(not qualifies(NewAura("Q6", AnyTrigger({ matchesShowOn = "showAlways" }))), "nor Show On Always")
T.expect(not qualifies(NewAura("Q7", AnyTrigger({ combineMode = "showHighest" }))), "nor a Preferred Match other than the default")
T.expect(qualifies(NewAura("Q8", AnyTrigger({ combineMode = "showLowest" }))), "the default Preferred Match does")
T.expect(not qualifies(NewAura("Q9", AnyTrigger({ useIgnoreExactSpellId = true, ignoreAuraSpellids = { "25771" } }))),
  "an ignore list on a debuff on you does not")
T.expect(qualifies(NewAura("Q10", AnyTrigger({ unit = "target", useIgnoreExactSpellId = true, ignoreAuraSpellids = { "1" } }))),
  "an ignore list on the target does")
T.expect(qualifies(NewAura("Q11", AnyTrigger({ use_debuffClass = true, debuffClass = { magic = true } }))),
  "a Debuff Type filter narrows it")

local _, anyContainer = Add(NewAura("Any", AnyTrigger({ use_debuffClass = true, debuffClass = { magic = true } })))
local anyFilters = anyContainer.slot.options.candidateFilters
T.expect(anyContainer.slot.filter == "HARMFUL" and anyFilters.includeSpellIDs == nil and anyFilters.includeDispelTypes.Magic,
  "built with no spell IDs, any debuff narrowed by its type")
T.expect(anyContainer.slot.options.sortMethod == 5, "sorted by time left only, as the trigger picks")
T.expect(anyContainer.shown and regions.Any.eaNativeOn, "drawn by Blizzard")
local _, exclContainer = Add(NewAura("AnyExcl", AnyTrigger({ unit = "target", useIgnoreExactSpellId = true,
  ignoreAuraSpellids = { "5588", "x" } })))
T.expect(exclContainer.slot.options.candidateFilters.excludeSpellIDs[5588], "the ignore list becomes excluded IDs")
local _, petContainer = Add(NewAura("AnyPet", AnyTrigger({ unit = "pet" })))
T.expect(petContainer.shown, "a debuff on your pet is drawn though you can assist it, since no ID is matched")
world.units.target = "friend"
local _, friendContainer = Add(NewAura("AnyFriend", AnyTrigger({ unit = "target", useIgnoreExactSpellId = true,
  ignoreAuraSpellids = { "5588" } })))
T.expect(not friendContainer.shown, "with excluded IDs on a friend Blizzard would ignore them, so Everything Auras draws it")
world.units.target = "enemy"

T.section("Timers on icons (round 3 Q1, Q2)")
local timed = Seal("Timed", { subRegions = { { type = "subtext", text_text = "%p", text_text_format_p_format = "timed",
  text_text_format_p_time_format = 0, text_text_format_p_time_dynamic_threshold = 3, text_text_format_p_time_precision = 1 } } })
local timedRegion, _, timedButton = Add(timed)
T.expect(timedButton.timerWidget and timedButton.timerWidget.alpha == 1, "an icon's %p text becomes Blizzard's timer")
T.expect(not timedRegion.subRegions[1].text.visible, "and the aura's own text hides while Blizzard draws")
local options = LastTimer(timedButton)
local breakpoints = options.textFormat and options.textFormat.components[1].formatter.breakpoints
T.expect(breakpoints and breakpoints[2].format == "%.1f" and breakpoints[3].threshold == 3 and breakpoints[3].step == 1
  and breakpoints[3].rounding == 1, "the built-in format: decimals under 3 s, whole seconds rounded up like the aura's text")
T.expect(breakpoints and breakpoints[4].format == "%i:%02i" and breakpoints[4].components[2].mod == 60,
  "minutes and seconds above a minute")
T.expect(options.textColor == nil, "no color steps without Remaining Time conditions")
local calls = #timedButton.timerOptions
modify(nil, timedRegion, timed)
T.expect(#timedButton.timerOptions == calls, "the same settings do not hand the timer over again")

local old = Seal("OldBlizzard", { subRegions = { { type = "subtext", text_text = "%p", text_text_format_p_format = "timed",
  text_text_format_p_time_format = 1, text_text_format_p_time_dynamic_threshold = 5, text_text_format_p_time_precision = 2 } } })
local _, _, oldButton = Add(old)
local oldFormatter = LastTimer(oldButton).textFormat.components[1].formatter
T.expect(oldFormatter.inherited and oldFormatter.format == 1 and oldFormatter.precision == 2 and oldFormatter.threshold == 5,
  "Old Blizzard uses the formatter the aura's own text uses")
local floor = Seal("Floor", { subRegions = { { type = "subtext", text_text = "%p", text_text_format_p_format = "timed",
  text_text_format_p_time_format = 0, text_text_format_p_time_legacy_floor = true } } })
local _, _, floorButton = Add(floor)
T.expect(LastTimer(floorButton).textFormat.components[1].formatter.format == 0, "legacy floor rounding keeps the floor format")
local bare = Seal("Bare", { subRegions = { { type = "subtext", text_text = "%p" } } })
local _, _, bareButton = Add(bare)
local bareFormatter = LastTimer(bareButton).textFormat.components[1].formatter
T.expect(bareFormatter.inherited and bareFormatter.threshold == 60, "an unformatted %p falls back like the aura's own text")
local plain = Seal("Plain", { subRegions = { { type = "subtext", text_text = "%p", text_text_format_p_format = "none" } } })
local _, _, plainButton = Add(plain)
T.expect(LastTimer(plainButton).textFormat == nil, "another format keeps Blizzard's default")
local noText = Seal("NoText")
local _, _, noTextButton = Add(noText)
T.expect(noTextButton.timerWidget.alpha == 0, "an icon without a %p text shows no timer")

T.section("Timer colors (round 3 Q3)")
local function Rt(op, value, changes)
  return { check = { trigger = 1, variable = "expirationTime", op = op, value = value }, changes = changes }
end
local colored = Seal("Colored", { subRegions = { { type = "subtext", text_text = "%p", text_color = { 1, 1, 1, 1 } } },
  conditions = { Rt("<=", "10", { { property = "sub.1.text_color", value = { 1, 0, 0, 1 } } }),
    Rt("<=", "3", { { property = "sub.1.text_visible", value = false } }),
    { check = { trigger = 1, variable = "stacks", op = ">", value = "2" },
      changes = { { property = "sub.1.text_color", value = { 0, 1, 0, 1 } } } } } })
local coloredRegion, _, coloredButton = Add(colored)
local curve = LastTimer(coloredButton).textColor and LastTimer(coloredButton).textColor.curve
local points = curve and curve.points or {}
T.expect(#points == 3 and points[1].x == 0 and points[2].x == 3 and points[3].x == 10, "a step at each threshold")
T.expect(points[1] and points[1].color.a == 0, "under 3 s the timer hides")
T.expect(points[2] and points[2].color.r == 1 and points[2].color.g == 0 and points[2].color.a == 1, "under 10 s it is red")
T.expect(points[3] and points[3].color.r == 1 and points[3].color.g == 1, "above that its own color")
local reversed = Seal("Reversed", { subRegions = { { type = "subtext", text_text = "%p" } },
  conditions = { Rt("<=", "5", { { property = "sub.1.text_color", value = { 0, 1, 0, 1 } } }),
    Rt("<=", "10", { { property = "sub.1.text_color", value = { 1, 0, 0, 1 } } }) } })
local _, _, reversedButton = Add(reversed)
local reversedPoints = LastTimer(reversedButton).textColor.curve.points
T.expect(reversedPoints[1].color.r == 1 and reversedPoints[1].color.g == 0, "a later condition wins, as in the aura's own conditions")

local coloredText = coloredRegion.subRegions[1].text
coloredRegion.state = { progressType = "timed", expirationTime = world.now + 25 }
local before = #coloredButton.timerOptions
coloredText:SetTextColor(0, 1, 0, 1)
local newest = LastTimer(coloredButton).textColor.curve.points
T.expect(#coloredButton.timerOptions == before + 1 and newest[3].color.g == 1 and newest[3].color.r == 0,
  "another condition's color becomes the timer's own color out of combat")
T.expect(newest[2].color.r == 1 and newest[2].color.g == 0, "and the red step stays")
before = #coloredButton.timerOptions
coloredRegion.state.expirationTime = world.now + 5
coloredText:SetTextColor(1, 0, 0, 1)
T.expect(#coloredButton.timerOptions == before, "a color set inside a step is the step's own, not a new base")
coloredRegion.state.expirationTime = world.now + 25
world.secret = true
coloredText:SetTextColor(0, 0, 1, 1)
T.expect(#coloredButton.timerOptions == before, "nothing changes while auras are secret")
world.secret = false

local count = Seal("Count", { subRegions = { { type = "subtext", text_text = "%s" } } })
local countRegion, _, countButton = Add(count)
countRegion.subRegions[1].text:SetTextColor(1, 0, 0, 1)
local countWidget = countButton.calls.SetApplicationCount and countButton.calls.SetApplicationCount[1][1]
T.expect(countWidget and countWidget.textColor and countWidget.textColor[1] == 1 and countWidget.textColor[2] == 0,
  "a condition's color on the stack text reaches Blizzard's copy")
world.secret = true
countRegion.subRegions[1].text:SetTextColor(0, 0, 1, 1)
T.expect(countWidget and countWidget.textColor[3] == 0, "but not while auras are secret")
world.secret = false

T.section("Glows (round 3 Q4)")
local function Glow(id, settings, extra)
  settings.type = "subglow"
  local data = Seal(id, extra)
  data.subRegions = { settings }
  return data
end
local pixel = Glow("Pixel", { glow = true, glowType = "Pixel", glowLines = 8, glowFrequency = 0.25, glowLength = 10,
  glowThickness = 1, glowBorder = false })
local pixelRegion, _, pixelButton = Add(pixel)
T.expect(#pixelButton.shownGroups == 1 and pixelButton.shownGroups[1].looping == "REPEAT", "a Pixel Glow is one looping group Blizzard plays")
T.expect(Count(pixelButton.shownGroups[1], "Play") == 1, "started at once, since the aura may already show")
T.expect(pixelRegion.subRegions[1].alpha == 0, "the aura's own glow hides while Blizzard draws")
for _, kind in ipairs({ { "ACShine", 4 }, { "buttonOverlay", 1 }, { "Proc", 1 } }) do
  local _, _, button = Add(Glow("Glow" .. kind[1], { glow = true, glowType = kind[1] }))
  T.expect(#button.shownGroups == kind[2], kind[1] .. " has " .. kind[2] .. " looping group(s)")
end
local _, _, burstButton = Add(Glow("Burst", { glow = true, glowType = "Proc", glowStartAnim = true }))
T.expect(#burstButton.shownGroups == 2 and burstButton.shownGroups[2].looping == nil, "a Proc start burst plays once")
local conditioned = Glow("Conditioned", { glow = false, glowType = "Pixel" }, { conditions = { { check = { trigger = 1,
  variable = "stacks" }, changes = { { property = "sub.1.glow", value = true } } } } })
local conditionedRegion, _, conditionedButton = Add(conditioned)
T.expect(#conditionedButton.shownGroups == 0 and conditionedRegion.subRegions[1].alpha == 1,
  "a glow a condition switches on stays the aura's own")
local onButConditioned = Glow("OnConditioned", { glow = true, glowType = "Pixel" }, { conditions = { { check = { trigger = 1,
  variable = "stacks" }, changes = { { property = "sub.1.glow", value = false } } } } })
local onRegion, _, onButton = Add(onButConditioned)
T.expect(#onButton.shownGroups == 0 and onRegion.subRegions[1].alpha == 1, "so does a glow a condition switches off")
local offGlow = Glow("OffGlow", { glow = false, glowType = "Pixel" })
local _, _, offButton = Add(offGlow)
T.expect(#offButton.shownGroups == 0, "a glow that is off draws nothing")

local first = pixelButton.shownGroups[1]
pixel.subRegions[1].glowType = "Proc"
modify(nil, pixelRegion, pixel)
T.expect(#pixelButton.shownGroups == 1 and pixelButton.shownGroups[1] ~= first and Count(first, "Stop") == 1,
  "a new glow type replaces the old pieces")
world.paused = true
private.Pause()
T.expect(pixelRegion.subRegions[1].alpha == 1, "the aura's own glow is back while Everything Auras draws")
world.paused = false
private.callbacks.events.ScanForLoads[1]()

local CORNERS = { TOPLEFT = { 0, 1 }, TOPRIGHT = { 1, 1 }, BOTTOMLEFT = { 0, 0 }, BOTTOMRIGHT = { 1, 0 } }
local function Rect(texture, anims, now, w, h)
  local alpha, dx, dy, sx, sy, origin = texture.alpha, 0, 0, 1, 1, nil
  for _, anim in ipairs(anims) do
    if anim.target == texture and now >= anim.delay and now < anim.delay + anim.duration then
      local p = (now - anim.delay) / anim.duration
      if anim.kind == "Alpha" then
        alpha = anim.from + (anim.to - anim.from) * p
      elseif anim.kind == "Translation" then
        dx, dy = anim.dx * p, anim.dy * p
      elseif anim.kind == "Scale" then
        sx, sy, origin = anim.x0 + (anim.x1 - anim.x0) * p, anim.y0 + (anim.y1 - anim.y0) * p, anim.origin
      end
    end
  end
  if alpha < 0.5 or not texture.w then
    return nil
  end
  local corner = CORNERS[texture.relativePoint]
  local cx, cy = corner[1] * w + texture.x, corner[2] * h + texture.y
  local left = texture.point:find("RIGHT") and cx - texture.w or cx
  local bottom = texture.point:find("TOP") and cy - texture.h or cy
  local sw, sh = texture.w * sx, texture.h * sy
  if origin == "RIGHT" then left = left + texture.w - sw elseif origin == "TOP" then bottom = bottom + texture.h - sh end
  return left + dx, bottom + dy, sw, sh
end
local measured = Glow("Measured", { glow = true, glowType = "Pixel", glowLines = 8, glowFrequency = 0.25, glowLength = 10,
  glowThickness = 1, glowBorder = false })
local _, _, measuredButton = Add(measured)
local group = measuredButton.shownGroups[1]
local host = group.owner
local worst, offBorder = 0, 0
for step = 0, 399 do
  local total = 0
  for _, texture in ipairs(host.textures) do
    local x, y, w, h = Rect(texture, group.anims, step / 100, 32, 32)
    if x then
      total = total + (texture.w > texture.h and w or h)
      local onEdge = math.abs(y) < 0.01 or math.abs(y + h - 32) < 0.01 or math.abs(x) < 0.01 or math.abs(x + w - 32) < 0.01
      if not onEdge then offBorder = offBorder + 1 end
    end
  end
  worst = math.max(worst, math.abs(total - 80))
end
T.expect(worst < 0.1 and offBorder == 0, "eight lines of 10 always lie on the border, as long as one loop lasts")
-- Clockwise from the top left corner, a line's trailing end at P * (t / period + (k - 1) / N).
local function BorderPoint(s)
  if s < 32 then return s, 31.5 elseif s < 64 then return 31.5, 32 - (s - 32) elseif s < 96 then return 32 - (s - 64), 0.5 end
  return 0.5, s - 96
end
local misplaced = 0
for step = 0, 39 do
  local now = step / 10 + 0.013
  local rects = {}
  for _, texture in ipairs(host.textures) do
    local x, y, w, h = Rect(texture, group.anims, now, 32, 32)
    if x then rects[#rects + 1] = { x, y, w, h } end
  end
  for i = 0, 255 do
    local s = i / 2 + 0.25
    local expected = false
    for k = 1, 8 do
      local u = (128 * (now / 4 + (k - 1) / 8)) % 128
      if (s - u) % 128 < 10 then expected = true end
    end
    local px, py = BorderPoint(s)
    local covered = false
    for _, r in ipairs(rects) do
      if px >= r[1] and px <= r[1] + r[3] and py >= r[2] and py <= r[2] + r[4] then covered = true end
    end
    -- The corner square belongs to both edges, so points within a pixel of a corner say nothing.
    local nearCorner = s % 32 < 1 or s % 32 > 31
    if covered ~= expected and not nearCorner then misplaced = misplaced + 1 end
  end
end
T.expect(misplaced == 0, "and each line sits where it should, turning the corners clockwise")
local ring = Add(Glow("Ring", { glow = true, glowType = "ACShine", glowLines = 8, glowFrequency = 0.25 }))
local ringGroups = ring.eaNativeRecord.button.shownGroups
local sparks, wrong, bunched = math.huge, 0, 0
for _, ringGroup in ipairs(ringGroups) do
  for step = 0, 19 do
    local now, visible, places = step * ringGroup.anims[1].duration / 20, 0, {}
    for _, texture in ipairs(ringGroup.owner.textures) do
      local mine, dx, dy = false, 0, 0
      for _, anim in ipairs(ringGroup.anims) do
        if anim.target == texture then mine = true end
      end
      if mine and texture.point == "CENTER" then
        local alpha = texture.alpha
        for _, anim in ipairs(ringGroup.anims) do
          if anim.target == texture and now >= anim.delay and now < anim.delay + anim.duration then
            if anim.kind == "Alpha" then
              alpha = anim.to
            elseif anim.kind == "Translation" then
              local p = (now - anim.delay) / anim.duration
              dx, dy = anim.dx * p, anim.dy * p
            end
          end
        end
        if alpha > 0.5 then
          visible = visible + 1
          local corner = CORNERS[texture.relativePoint]
          places[string.format("%.0f,%.0f", corner[1] * 32 + texture.x + dx, corner[2] * 32 + texture.y + dy)] = true
        end
      end
    end
    local distinct = 0
    for _ in pairs(places) do distinct = distinct + 1 end
    if distinct < visible then bunched = bunched + 1 end
    sparks = math.min(sparks, visible)
    if visible ~= 8 then wrong = wrong + 1 end
  end
end
T.expect(#ringGroups == 4 and wrong == 0 and sparks == 8, "Autocast Shine keeps eight sparks in each of its four rings")
T.expect(bunched == 0, "spread evenly around the ring, never on top of each other")
local _, _, antsButton = Add(Glow("Ants", { glow = true, glowType = "buttonOverlay" }))
local book
for _, anim in ipairs(antsButton.shownGroups[1].anims) do
  if anim.kind == "FlipBook" then book = anim end
end
T.expect(book and book.frames == 22 and book.frameWidth == 48 and book.rows == 5, "Action Button Glow's ants run 22 frames of 48 pixels")

T.section("Stacking like the aura's own sub-regions (round 4 LOOKS)")
local function Stacked(id, subRegions)
  local data = Seal(id, { subRegions = subRegions })
  local region = Add(data)
  return region.eaNativeRecord
end
local glowFirst = Stacked("GlowFirst", { { type = "subglow", glow = true, glowType = "Pixel" },
  { type = "subborder", border_edge = "Square Full White", border_color = { 1, 0, 0, 1 }, border_size = 2 },
  { type = "subtext", text_text = "%p" } })
T.expect(glowFirst.kits[2].host.level > glowFirst.kits[1].host.level, "a border listed after a glow draws over it")
T.expect(glowFirst.overlay.level > glowFirst.kits[2].host.level, "a text listed after both draws over them")
local textFirst = Stacked("TextFirst", { { type = "subtext", text_text = "%p" },
  { type = "subglow", glow = true, glowType = "Pixel" } })
T.expect(textFirst.kits[2].host.level > textFirst.overlay.level, "a glow listed after a text draws over it")
local plainIcon = Stacked("NoTexts", { { type = "subglow", glow = true, glowType = "Pixel" } })
T.expect(plainIcon.overlay.level == 12, "with no text taken over the texts keep their old place")

T.section("Borders (round 3 Q5)")
local plainBorder = Seal("PlainBorder", { subRegions = { { type = "subborder", border_edge = "Square Full White",
  border_color = { 1, 0, 0, 1 }, border_size = 3, border_offset = 2 } } })
local plainRegion, _, plainBorderButton = Add(plainBorder)
T.expect(#plainBorderButton.dispel == 0, "a plain border needs no dispel colors")
T.expect(plainRegion.subRegions[1].alpha == 0, "the aura's own border hides while Blizzard draws")
local borderHost = plainRegion.eaNativeRecord.kits[1].host
local corners = borderHost.points or {}
T.expect(corners.BOTTOMLEFT and corners.BOTTOMLEFT.x == -2 and corners.BOTTOMLEFT.y == -2 and corners.TOPRIGHT
  and corners.TOPRIGHT.x == 2 and corners.TOPRIGHT.y == 2,
  "Blizzard's border covers the aura's own border frame, offset included, held by two corners so it follows the size")
local colored4 = 0
for _, texture in ipairs(borderHost.textures or {}) do
  if texture.colorTexture and texture.colorTexture[1] == 1 and texture.colorTexture[2] == 0 then
    colored4 = colored4 + 1
  end
end
T.expect(colored4 == 4, "four strips in the border's color")

local dispelBorder = Seal("DispelBorder", { subRegions = { { type = "subborder", border_color = { 1, 1, 1, 1 }, border_size = 2 } },
  conditions = { { check = { trigger = 1, variable = "debuffClass", op = "==", value = "magic" },
    changes = { { property = "sub.1.border_color", value = { 0, 0.4, 1, 1 } } } },
    { check = { trigger = 1, variable = "debuffClass", op = "~=", value = "poison" },
      changes = { { property = "sub.1.border_color", value = { 1, 0.5, 0, 1 } } } } } })
local _, _, dispelButton = Add(dispelBorder)
local entry = dispelButton.dispel[1]
local map = entry and entry.options.customDispelColorMap or {}
T.expect(#dispelButton.dispel == 4 and entry.options.style == 3 and entry.options.showWhenHelpful, "four dispel strips, buffs too")
T.expect(map.Poison and map.Poison.r == 1 and map.Poison.g == 1, "a type no condition picks keeps the border's color")
T.expect(map.Magic and map.Magic.r == 1 and map.Magic.g == 0.5, "a later condition wins, here the not Poison one over Magic")
T.expect(map.None and map.None.g == 0.5 and map[""] and map[""].g == 0.5, "no type and enrage count as not Poison too")
local fancy = Seal("Fancy", { subRegions = { { type = "subborder", border_edge = "Blizzard Tooltip" } } })
local fancyRegion, _, fancyButton = Add(fancy)
T.expect(#fancyButton.dispel == 0 and fancyRegion.subRegions[1].alpha == 1, "another edge style stays the aura's own")
local stacked = Seal("Stacked", { subRegions = { { type = "subborder" } }, conditions = { { check = { trigger = 1,
  variable = "stacks", op = ">", value = "2" }, changes = { { property = "sub.1.border_color", value = { 1, 0, 0, 1 } } } } } })
local stackedRegion = Add(stacked)
T.expect(stackedRegion.subRegions[1].alpha == 1, "so does a border colored by anything but Debuff Type")

local skipped = Seal("Skipped", { subRegions = { { type = "subnewtype" }, { type = "subborder" }, { type = "subtext",
  text_text = "Hello" } } })
local skippedRegion = NewRegion("Skipped", { { type = "subborder" }, { type = "subtext", text_text = "Hello" } })
modify(nil, skippedRegion, skipped)
T.expect(skippedRegion.subRegions[2].alpha == 1 and not next(skippedRegion.eaNativeRecord.kits),
  "a sub-region type this client lacks shifts the region's list, so a mismatched place is left alone")

T.section("Pre-ship scan fixes (0.7.0)")
-- Its own function, so its locals stay under Lua 5.1's limit of 200 in one function.
local function ScanFixes()
local highest = Seal("Highest")
highest.triggers[1].trigger.combineMode = "showHighest"
T.expect(not qualifies(highest), "a named aura with a Preferred Match other than Least remaining time stays Everything Auras' own")

local function AlwaysSeal(id, extra)
  local data = Seal(id, extra)
  data.triggers[1].trigger.matchesShowOn = "showAlways"
  return data
end
local alwaysSkipped = AlwaysSeal("AlwaysSkipped")
local skippedTrigger = alwaysSkipped.triggers[1].trigger
skippedTrigger.use_castByPlayer, skippedTrigger.useTotal, skippedTrigger.total, skippedTrigger.totalOperator = true, true, "30", "<="
skippedTrigger.useStacks, skippedTrigger.stacks = true, "2"
skippedTrigger.useIgnoreExactSpellId, skippedTrigger.ignoreAuraSpellids = true, { "20154" }
T.expect(qualifies(alwaysSkipped), "Show On Always is not refused over filters its trigger skips")
local skippedRecord = Add(alwaysSkipped).eaNativeRecord
local skippedFilters = skippedRecord and skippedRecord.container.slot.options.candidateFilters or {}
T.expect(skippedRecord and skippedRecord.ids[20154] and skippedFilters.isFromPlayerOrPlayerPet == nil
  and skippedFilters.maxDuration == nil and skippedFilters.includeSpellIDs and skippedFilters.includeSpellIDs[20154],
  "and Blizzard gets none of them, the ignored ID included")
skippedTrigger.useNamePattern = true
T.expect(not qualifies(alwaysSkipped), "a name pattern still applies there, so it still refuses")
T.expect(not qualifies(AlwaysSeal("AlwaysGlow", { subRegions = { { type = "subglow", glow = true, glowType = "Pixel" } } })),
  "Show On Always with an always-on glow stays Everything Auras' own, as the glow would vanish while missing")
T.expect(not qualifies(AlwaysSeal("AlwaysBorder", { subRegions = { { type = "subborder", border_edge = "Square Full White" } } })),
  "so does one with a border Blizzard would draw")
T.expect(not qualifies(AlwaysSeal("AlwaysLinked", { conditions = {
  { check = { trigger = 1, variable = "buffed", value = 0 }, changes = { { property = "alpha", value = 0.5 } } },
  { linked = true, check = { trigger = 1, variable = "buffed", value = 1 }, changes = { { property = "alpha", value = 1 } } } } })),
  "and one whose conditions run as else-if")

local function StepTimer(id, op, at, property, value)
  return Seal(id, { subRegions = { { type = "subtext", text_text = "%p" } },
    conditions = { { check = { trigger = 1, variable = "expirationTime", op = op, value = at },
      changes = { { property = property, value = value } } } } })
end
local mixed = StepTimer("Mixed", "<=", "10", "sub.1.text_color", { 1, 0, 0, 1 })
local mixedRegion, _, mixedButton = Add(mixed)
mixedRegion.state = { progressType = "timed", expirationTime = world.now + 5 }
mixedRegion.subRegions[1]:Hide()
local mixedPoints = LastTimer(mixedButton).textColor.curve.points
T.expect(mixedPoints[1].color.a == 0 and mixedPoints[#mixedPoints].color.a == 0,
  "another condition hiding the timer reaches Blizzard's while a step only colors it")
local veiled = StepTimer("Veiled", "<=", "3", "sub.1.text_visible", false)
local veiledRegion, _, veiledButton = Add(veiled)
veiledRegion.state = { progressType = "timed", expirationTime = world.now + 2 }
veiledRegion.subRegions[1].text:SetTextColor(0, 1, 0, 1)
local veiledPoints = LastTimer(veiledButton).textColor.curve.points
T.expect(veiledPoints[#veiledPoints].color.g == 1 and veiledPoints[#veiledPoints].color.r == 0,
  "and another condition's color reaches it while a step only hides it")
local fadeA = StepTimer("FadeA", "<=", "10", "sub.1.text_color", { 1, 0, 0, 1 })
local fadeRegion = Add(fadeA)
fadeRegion.state = { progressType = "timed", expirationTime = world.now + 30 }
fadeRegion.subRegions[1]:Hide()
local fadeRecord = fadeRegion.eaNativeRecord
T.expect(fadeRecord.timerVisible == false, "a hidden timer is remembered")
private.callbacks.events.Delete[1](nil, "FadeA")
local fadeBRegion = Add(StepTimer("FadeB", "<=", "10", "sub.1.text_color", { 1, 0, 0, 1 }))
T.expect(fadeBRegion.eaNativeRecord == fadeRecord and fadeRecord.timerVisible == nil,
  "a freed record taken by the next aura forgets it")

local editing = Seal("Editing", { subRegions = { { type = "subglow", glow = true, glowType = "Pixel" } } })
Add(editing)
world.paused = true
editing.subRegions[2] = { type = "subtext", text_text = "%p" }
local editingRegion = NewRegion("Editing", editing.subRegions)
modify(nil, editingRegion, editing)
local editingRecord = editingRegion.eaNativeRecord
local editingKits = 0
for _ in pairs(editingRecord.kitCache[1]) do
  editingKits = editingKits + 1
end
T.expect(editingRecord.texts.timer.alpha == 1 and editingKits == 1,
  "with the options open a new %p text is handed to Blizzard at once, while glows wait")
world.paused = false
T.expect(qualifies(AlwaysSeal("AlwaysFirstLinked", { conditions = {
  { linked = true, check = { trigger = 1, variable = "buffed", value = 0 }, changes = { { property = "alpha", value = 0.5 } } } } })),
  "the first condition is never else-if, so a stray mark on it changes nothing")

local reuse = Seal("Reuse", { subRegions = { { type = "subglow", glow = true, glowType = "Pixel" } } })
local reuseRegion, _, reuseButton = Add(reuse)
local reuseRecord = reuseRegion.eaNativeRecord
local firstKit = reuseRecord.kits[1]
reuse.subRegions[1].glowLines = 4
modify(nil, reuseRegion, reuse)
local secondKit = reuseRecord.kits[1]
T.expect(secondKit ~= firstKit and not firstKit.host.visible and #reuseButton.shownGroups == 1,
  "a changed glow puts the old one aside")
reuse.subRegions[1].glowLines = nil
modify(nil, reuseRegion, reuse)
T.expect(reuseRecord.kits[1] == firstKit and firstKit.host.visible and #reuseButton.shownGroups == 1
  and reuseButton.shownGroups[1] == firstKit.groups[1], "and the old look comes back as the same kit, not a new one")
reuseRegion.scalex = 1.5
reuseRegion.subRegions[1].rect = { 100, 100, 148, 148 }
modify(nil, reuseRegion, reuse)
T.expect(reuseRecord.kits[1] == firstKit, "while a scale animation runs, the glow keeps the kit it has")
reuse.subRegions[1].glowLines = 6
modify(nil, reuseRegion, reuse)
T.expect(reuseRecord.kits[1] ~= firstKit, "but a changed look still gets its own")
reuseRegion.scalex = 1
reuseRegion.subRegions[1].rect = { 100, 100, 132, 132 }
reuse.subRegions[1].glowLines = nil

local grown = Seal("Grown", { subRegions = { { type = "subglow", glow = true, glowType = "Pixel" } } })
local grownRegion = Add(grown)
local grownRecord = grownRegion.eaNativeRecord
local smallKit = grownRecord.kits[1]
local function Resized(rect)
  grownRegion.rect, grownRegion.subRegions[1].rect = rect, rect
  for _, call in ipairs(grownRegion.calls.HookScript or {}) do
    if call[1] == "OnSizeChanged" then
      call[2](grownRegion)
    end
  end
end
Resized({ 100, 100, 148, 148 })
T.expect(grownRecord.kits[1] ~= smallKit, "a condition that resizes the aura gets Blizzard's glow built again at the new size")
Resized({ 100, 100, 132, 132 })
T.expect(grownRecord.kits[1] == smallKit, "and back at the old size it gets the old glow back")
local styles, timers = 0, 0
local enableMouse, after = grownRecord.button.EnableMouse, env.C_Timer.After
grownRecord.button.EnableMouse = function(...)
  styles = styles + 1
  return enableMouse(...)
end
env.C_Timer.After = function(...)
  timers = timers + 1
  return after(...)
end
Resized({ 100, 100, 132, 132 })
T.expect(styles == 0, "a size change event with the same size restyles nothing")
timers = 0
grownRegion.scalex = 1.4
Resized({ 100, 100, 145, 145 })
T.expect(grownRecord.kits[1] == smallKit and timers == 0 and styles == 0, "a scale animation's resizing schedules and builds nothing")
grownRegion.scalex = 1
grownRecord.button.EnableMouse, env.C_Timer.After = enableMouse, after

local slider = Seal("Slider", { subRegions = { { type = "subglow", glow = true, glowType = "Pixel" } } })
local sliderRegion = Add(slider)
local sliderRecord = sliderRegion.eaNativeRecord
world.paused = true
for lines = 2, 6 do
  slider.subRegions[1].glowLines = lines
  modify(nil, sliderRegion, slider)
end
local built = 0
for _ in pairs(sliderRecord.kitCache[1]) do
  built = built + 1
end
T.expect(built == 1, "dragging a slider with the options open builds nothing")
world.paused = false
private.callbacks.events.ScanForLoads[1]()
T.expect(sliderRecord.kits[1].key:find(";6;", 1, true) ~= nil, "closing the options styles it once, with the last value")

local scaledRegion = NewRegion("Scaled", {})
scaledRegion.scale = 1.5
modify(nil, scaledRegion, Seal("Scaled"))
local setScale = scaledRegion.eaNativeRecord.container.calls.SetScale
T.expect(setScale and setScale[#setScale][1] == 1.5, "a standalone aura's container takes the aura's own scale, as a group's does")

local based = Seal("Based", { subRegions = { { type = "subtext", text_text = "%p" } },
  conditions = { { check = { trigger = 1, variable = "expirationTime", op = "<=", value = "10" },
    changes = { { property = "sub.1.text_color", value = { 1, 0, 0, 1 } } } } } })
local basedRegion, _, basedButton = Add(based)
basedRegion.state = { progressType = "timed", expirationTime = world.now + 30 }
basedRegion.subRegions[1].text:SetTextColor(0, 1, 0, 1)
local function TopColor(button)
  local points = LastTimer(button).textColor.curve.points
  return points[#points].color
end
T.expect(TopColor(basedButton).g == 1 and TopColor(basedButton).r == 0, "another condition's color is the timer's above the step")
private.callbacks.events.ScanForLoads[1]()
T.expect(TopColor(basedButton).g == 1 and TopColor(basedButton).r == 0, "and stays after a refresh, such as the one when a fight ends")
local timerSets = #basedButton.timerOptions
basedRegion.subRegions[1].text:SetTextColor(0, 1, 0, 1)
T.expect(#basedButton.timerOptions == timerSets, "the same color again changes nothing, so a color animation costs nothing")

local made = 0
local makeCurve = env.C_CurveUtil.CreateColorCurve
env.C_CurveUtil.CreateColorCurve = function()
  made = made + 1
  return makeCurve()
end
private.callbacks.events.ScanForLoads[1]()
T.expect(made == 0, "a refresh that changes nothing builds no color curve")
env.C_CurveUtil.CreateColorCurve = makeCurve
local fading = Seal("Fading", { subRegions = { { type = "subtext", text_text = "%p" } },
  conditions = { { check = { trigger = 1, variable = "expirationTime", op = "<=", value = "5" },
    changes = { { property = "sub.1.text_visible", value = false } } } } })
local fadingRegion = NewRegion("Fading", fading.subRegions)
fadingRegion.subRegions[1].visible = false
modify(nil, fadingRegion, fading)
T.expect(fadingRegion.eaNativeRecord.texts.timer.alpha == 1,
  "a timer a Remaining Time step hides right now stays visible, since its color curve does the hiding")

local quiet = Seal("Quiet", { subRegions = { { type = "subtext", text_text = "%s" } } })
local quietRegion = NewRegion("Quiet", quiet.subRegions)
quietRegion.subRegions[1].visible = false
modify(nil, quietRegion, quiet)
local quietCount = quietRegion.eaNativeRecord.texts.count
T.expect(quietCount.alpha == 0, "a text hidden by its settings stays hidden on Blizzard's side")
quietRegion.subRegions[1]:Show()
T.expect(quietCount.alpha == 1, "shown by a condition out of combat, Blizzard's copy shows too")
quietRegion.subRegions[1]:Hide()
T.expect(quietCount.alpha == 0, "and hides again with it")
world.secret = true
quietRegion.subRegions[1]:Show()
T.expect(quietCount.alpha == 0, "in combat it holds")
world.secret = false

local pixelPerfect = Seal("PixelPerfect", { subRegions = { { type = "subborder", border_edge = "Square Full White",
  border_ppscale = true } } })
local ppRegion = Add(pixelPerfect)
T.expect(not next(ppRegion.eaNativeRecord.kits) and ppRegion.subRegions[1].alpha == 1, "a pixel perfect border stays the aura's own")

local combatEdit = Seal("CombatEdit", { subRegions = { { type = "subglow", glow = true, glowType = "Pixel" } } })
local editRegion = Add(combatEdit)
world.secret = true
modify(nil, editRegion, combatEdit)
T.expect(editRegion.subRegions[1].alpha == 0, "an edit in combat keeps the aura's own glow hidden behind Blizzard's")
world.secret = false

local swapped = Seal("Swapped", { subRegions = { { type = "subglow", glow = true, glowType = "Pixel" } } })
local swappedRegion = Add(swapped)
world.secret = true
swapped.subRegions[1].glowType = "Proc"
modify(nil, swappedRegion, swapped)
T.expect(swappedRegion.subRegions[1].alpha == 1,
  "a glow changed while its kit cannot be rebuilt keeps showing the aura's own, since Blizzard's has the old look")
world.secret = false

local anyStore = NewAura("AnyStore", { type = "aura2", unit = "player", debuffType = "HARMFUL" })
local anyRegion = Add(anyStore)
anyRegion.states = { { show = true, spellId = 25771 } }
private.RunConditions(anyRegion, "AnyStore")
T.expect(anyStore.eaNativeIds == nil, "an aura that names no spell keeps no spell IDs")

end
ScanFixes()

T.section("Restoring before a modify")
pixelRegion.subRegions[1].alpha = 0
local own = pixelRegion.subRegions[1]
private.regionTypes.icon.modify(nil, pixelRegion, { id = "Pixel", uid = "Pixel", regionType = "icon", triggers = { {} } })
T.expect(own.alpha == 1, "a pooled glow frame comes back visible before the region is modified")

T.expect(#errors == 0, "no errors")
T.finish()
