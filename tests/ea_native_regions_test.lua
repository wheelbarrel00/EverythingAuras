-- Everything Auras 0.7.0 round 4: the real EA/Native.lua's Textures, Texts and Progress Textures on a stub.
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
  end
  widget.GetLeft = function(self) return self.rect and self.rect[1] end
  widget.GetBottom = function(self) return self.rect and self.rect[2] end
  widget.GetRight = function(self) return self.rect and self.rect[3] end
  widget.GetTop = function(self) return self.rect and self.rect[4] end
  widget.CreateTexture = function(self) local t = NewWidget(self) self.textures = self.textures or {} table.insert(self.textures, t) return t end
  widget.CreateFontString = function(self) return NewWidget(self) end
  widget.CreateAnimationGroup = function(self) return NewAnimationGroup(self) end
  widget.SetAllPoints = function(self, target) self.allPoints = target or true end
  widget.ClearAllPoints = function(self) self.point, self.allPoints, self.points = nil, nil, nil end
  local setPoint = widget.SetPoint
  widget.SetPoint = function(self, point, relative, relativePoint, x, y)
    self.points = self.points or {}
    self.points[point] = { relative = relative, relativePoint = relativePoint or point, x = x or 0, y = y or 0 }
    setPoint(self, point, relative, relativePoint, x, y)
  end
  widget.SetTexCoord = function(self, ...) self.coords = { ... } end
  widget.GetTexCoord = function(self) return unpack(self.coords or { 0, 0, 0, 1, 1, 0, 1, 1 }) end
  widget.SetVertexOffset = function(self, vertex, x, y) self.offsets = self.offsets or {} self.offsets[vertex] = { x, y } end
  widget.SetRadialProgressBarStartOffset = function(self, v) self.radialStart = v end
  widget.SetRadialProgressBarEndOffset = function(self, v) self.radialEnd = v end
  widget.SetRadialProgressBarReverse = function(self, v) self.radialReverse = v end
  widget.SetTexture = function(self, file) self.file = file end
  widget.GetTexture = function(self) return self.file end
  widget.SetAtlas = function(self, atlas) self.atlas = atlas end
  widget.GetAtlas = function(self) return self.atlas end
  widget.SetDesaturated = function(self, on) self.desaturated = on and true or false end
  widget.SetDesaturation = function(self, value) self.desaturated = value ~= 0 and value or false end
  widget.GetDesaturation = function(self) return self.desaturated and 1 or 0 end
  widget.SetBlendMode = function(self, mode) self.blend = mode end
  widget.GetBlendMode = function(self) return self.blend or "BLEND" end
  widget.SetText = function(self, text) self.text = text end
  widget.GetStringWidth = function(self)
    local outlined = self.font and tostring(self.font[3]):find("OUTLINE")
    return #(self.text or "") * 4 + (outlined and 3 or 0)
  end
  widget.SetFont = function(self, font, size, flags) self.font = { font, size, flags } end
  widget.GetFont = function(self) return "font", 14, "OUTLINE" end
  widget.GetShadowColor = function() return 0, 0, 0, 1 end
  widget.GetShadowOffset = function() return 1, -1 end
  widget.GetTextColor = function(self) return unpack(self.textColor or { 1, 1, 1, 1 }) end
  widget.SetJustifyH = function(self, justify) self.justify = justify end
  widget.CreateMaskTexture = function(self) return NewWidget(self) end
  widget.AddMaskTexture = function(self, mask) self.mask = mask end
  widget.SetStatusBarTexture = function(self, file)
    self.barTexture = self.barTexture or NewWidget(self)
    self.barTexture.file = file
  end
  widget.GetStatusBarTexture = function(self)
    self.barTexture = self.barTexture or NewWidget(self)
    return self.barTexture
  end
  widget.SetRenderMode = function(self, mode) self.renderMode = mode end
  widget.SetOrientation = function(self, orientation) self.orientation = orientation end
  widget.SetReverseFill = function(self, reverse) self.reverse = reverse end
  widget.SetValue = function(self, value) self.value = value end
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
    button.SetDurationBar = function(b, bar, barOptions) b.barWidget, b.barOptions = bar, barOptions end
    button.SetApplicationCount = function(b, text, countOptions) b.countWidget, b.countOptions = text, countOptions end
    button.SetSpellName = function(b, text) b.nameWidget = text end
    button.SetIcon = function(b, texture) b.iconWidget = texture end
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
    texture = { modify = function(_, region, data) region.modified = data.id end },
    text = { modify = function(_, region, data) region.modified = data.id end },
    progresstexture = { modify = function(_, region, data)
      region.modified = data.id
      region.circular = data.orientation == "CLOCKWISE" or data.orientation == "ANTICLOCKWISE"
      region.foreground.visible, region.background.visible = not region.circular, not region.circular
      region.foregroundSpinner.visible, region.backgroundSpinner.visible = region.circular, region.circular
    end },
  },
  SetTextureOrAtlas = function(texture, path) texture.file = path end,
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
    StatusBarRenderMode = { Linear = 0, Radial = 1 },
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
  for index, settings in ipairs(subSettings or {}) do
    local live = NewWidget(region, { 100, 100, 132, 132 })
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

local function KindRegion(id, regionType, data)
  local region = NewWidget(nil, { 100, 100, 164, 132 })
  region.id, region.cloneId, region.regionType = id, "", regionType
  region.GetFrameLevel = function() return 10 end
  region.GetFrameStrata = function() return "MEDIUM" end
  region.subRegions = {}
  if regionType == "texture" then
    local source = NewWidget(region)
    source.file, source.coords, source.blend = "Interface\\Tex", { 1, 0, 1, 1, 0, 0, 0, 1 }, "ADD"
    source:SetVertexColor(1, 0, 0, 0.8)
    region.texture = { texture = source }
  elseif regionType == "text" then
    region.text = NewWidget(region)
    region.text.textColor = { 0, 1, 0, 1 }
  else
    for _, part in ipairs({ "foreground", "background", "foregroundSpinner", "backgroundSpinner" }) do
      region[part] = { visible = true, Show = function(self) self.visible = true end,
        Hide = function(self) self.visible = false end }
    end
    region.color_r, region.color_g, region.color_b, region.color_a = 1, 0.5, 0, 1
    region.GetColor = function(self) return self.color_r, self.color_g, self.color_b, self.color_a end
    region.Color = function(self, r, g, b, a) self.color_r, self.color_g, self.color_b, self.color_a = r, g, b, a end
    region.SetBackgroundColor = function() end
    region.currentTexture = data.foregroundTexture
  end
  regions[id] = region
  return region
end

local function AddKind(data)
  local region = regions[data.id] or KindRegion(data.id, data.regionType, data)
  private.regionTypes[data.regionType].modify(nil, region, data)
  local container = world.created[#world.created]
  return region, container, container and container.button, region.eaNativeRecord
end

local serial = 0
local function Kind(regionType, extra)
  serial = serial + 1
  local data = Seal("K" .. serial, extra)
  data.regionType = regionType
  return data
end

T.section("Which Texts, Textures and Progress Textures Blizzard can draw (round 4)")
for _, text in ipairs({ "%p", "Seal: %p left", "%n is up", "Stacks: %s" }) do
  T.expect(qualifies(Kind("text", { displayText = text })), "a Text showing \"" .. text .. "\" qualifies")
end
for _, text in ipairs({ "%p %s", "%c", "%stacks", "50%", "{%p}", "no placeholder" }) do
  T.expect(not qualifies(Kind("text", { displayText = text })), "a Text showing \"" .. text .. "\" does not")
end
T.expect(not qualifies(Kind("text", { displayText = "%p", displayText_format_p_format = "none" })),
  "a %p that is not a time does not")
T.expect(not qualifies(Kind("text", { displayText = "%s", displayText_format_s_format = "BigNumber" })),
  "a %s with a number format does not")
auras.G4 = { id = "G4", uid = "G4", regionType = "dynamicgroup", controlledChildren = {} }
local grouped, groupedReason = qualifies(Kind("text", { displayText = "%p", parent = "G4" }))
T.expect(not grouped and groupedReason:find("fixed size", 1, true), "a Text in a dynamic group does not, and says why")
T.expect(qualifies(Kind("texture")), "a Texture qualifies")
auras.G6 = { id = "G6", uid = "G6", regionType = "dynamicgroup", grow = "RIGHT", sort = "none", controlledChildren = {} }
for index = 1, 2 do
  local child = Kind("texture", { parent = "G6" })
  auras.G6.controlledChildren[index] = child.id
end
T.expect(qualifies(auras[auras.G6.controlledChildren[1]]), "Textures of one size in a dynamic group set to Sort None qualify (round 4 Q6)")
T.expect(not qualifies(Kind("texture", { triggers = { { trigger = { type = "aura2", unit = "player", debuffType = "HELPFUL",
  useExactSpellId = true, auraspellids = { "20154" }, matchesShowOn = "showAlways" } } } })), "a Texture set to Show On Always does not, for now")
T.expect(qualifies(Kind("progresstexture", { orientation = "HORIZONTAL" })), "a straight Progress Texture qualifies")
for _, setting in ipairs({ { slanted = true }, { compress = true }, { smoothProgress = true }, { auraRotation = 20 },
  { overlays = { { 1, 1, 1, 1 } } } }) do
  local key = next(setting)
  setting.orientation = "HORIZONTAL"
  T.expect(not qualifies(Kind("progresstexture", setting)), "a Progress Texture with " .. key .. " does not")
end
T.expect(qualifies(Kind("progresstexture", { orientation = "CLOCKWISE", crop_x = 0.2, crop_y = 0.2 })), "a round one with equal crops does")
T.expect(not qualifies(Kind("progresstexture", { orientation = "CLOCKWISE", crop_x = 0.2, crop_y = 0.3 })), "unequal crops do not")
T.expect(not qualifies(Kind("progresstexture", { orientation = "HORIZONTAL", conditions = { { check = { trigger = 1,
  variable = "stacks" }, changes = { { property = "orientation", value = "VERTICAL" } } } } })), "a condition turning it does not")
T.expect(qualifies(Kind("progresstexture", { orientation = "HORIZONTAL", conditions = { { check = { trigger = 1,
  variable = "stacks" }, changes = { { property = "foregroundColor", value = { 1, 0, 0, 1 } } } } } })), "a condition coloring it does")

T.section("Textures")
local texture = Kind("texture")
local textureRegion, _, textureButton, textureRecord = AddKind(texture)
local art = textureRecord and textureRecord.art
T.expect(textureButton.iconWidget == nil and art and art.file == "Interface\\Tex", "Blizzard shows the aura's own texture, not an icon")
T.expect(art and art.coords[1] == 1 and art.color[1] == 1 and art.color[2] == 0 and art.alpha == 0.8 and art.blend == "ADD",
  "with its coordinates, color and blend mode")
T.expect(not textureRegion.texture.texture.visible, "the aura's own texture hides while Blizzard draws")
textureRegion.texture.texture:SetVertexColor(0, 0, 1, 1)
T.expect(art and art.color[3] == 1 and art.color[1] == 0, "a condition's color reaches it out of combat")
world.secret = true
textureRegion.texture.texture:SetVertexColor(0, 1, 0, 1)
T.expect(art and art.color[2] == 0, "but not while auras are secret")
world.secret = false
world.paused = true
private.Pause()
T.expect(textureRegion.texture.texture.visible, "paused, the aura's own texture is back")
world.paused = false
private.callbacks.events.ScanForLoads[1]()

T.section("Progress Textures, straight")
local fill = Kind("progresstexture", { orientation = "HORIZONTAL_INVERSE", mirror = true, crop_x = 0.2, crop_y = 0.2,
  foregroundTexture = "Interface\\Fill", backgroundColor = { 0.1, 0.2, 0.3, 0.4 }, backgroundOffset = 2, width = 120,
  height = 24 })
local fillRegion, _, fillButton, fillRecord = AddKind(fill)
local bar = fillButton.barWidget
T.expect(bar and fillButton.barOptions.direction == 1 and bar.points and bar.points.TOPRIGHT and bar.reverse == true
  and bar.orientation == "HORIZONTAL", "Blizzard's bar fills from the right, by the time left")
local fillArt = fillRecord.art
T.expect(fillArt.file == "Interface\\Fill" and fillArt.mask and fillArt.mask.allPoints and fillArt.mask.allPoints.allPoints
  == bar:GetStatusBarTexture(), "the aura's texture is masked by a frame on the bar's fill (probe 074 L2)")
local function TP(x, y)
  x, y = (x - 0.5) * 1.4142 / 1.2, (y - 0.5) * 1.4142 / 1.2
  return -x + 0.5, y + 0.5
end
local ulx, uly = TP(0, 0)
local lrx, lry = TP(1, 1)
T.expect(math.abs(fillArt.coords[1] - ulx) < 1e-9 and math.abs(fillArt.coords[2] - uly) < 1e-9
  and math.abs(fillArt.coords[7] - lrx) < 1e-9 and math.abs(fillArt.coords[8] - lry) < 1e-9,
  "with the coordinates the aura's own crop and mirror give it")
local backdrop = fillRecord.backdrop
T.expect(backdrop.points.BOTTOMLEFT.x == -2 and backdrop.points.TOPRIGHT.x == 2 and backdrop.color[1] == 0.1
  and backdrop.alpha == 0.4, "its background sits Background Offset out, in the background color")
T.expect(fillArt.color[1] == 1 and fillArt.color[2] == 0.5, "the foreground takes the aura's color")
T.expect(not fillRegion.foreground.visible and not fillRegion.background.visible, "the aura's own fill hides while Blizzard draws")
fillRegion:Color(0, 1, 0, 1)
T.expect(fillArt.color[2] == 1 and fillArt.color[1] == 0, "a condition's color reaches it out of combat")
world.paused = true
private.Pause()
T.expect(fillRegion.foreground.visible and not fillRegion.foregroundSpinner.visible, "paused, its own straight fill is back")
world.paused = false
private.callbacks.events.ScanForLoads[1]()
local up = Kind("progresstexture", { orientation = "VERTICAL", inverse = true })
local _, _, upButton = AddKind(up)
T.expect(upButton.barWidget.points.BOTTOMLEFT and upButton.barOptions.direction == 0, "an upward fill starts at the bottom, inverse by time spent")

T.section("Progress Textures, round")
local round = Kind("progresstexture", { orientation = "ANTICLOCKWISE", startAngle = 45, endAngle = 315, crop_x = 0.2,
  crop_y = 0.2, width = 56, height = 56, backgroundOffset = 0 })
local roundRegion, _, roundButton, roundRecord = AddKind(round)
local ring = roundRecord.art
T.expect(roundButton.barWidget.renderMode == 1 and ring == roundButton.barWidget:GetStatusBarTexture(),
  "Blizzard's bar draws the circle itself (probe 074 C1)")
T.expect(math.abs(ring.radialStart - 0.375) < 1e-9 and math.abs(ring.radialEnd - 0.25) < 1e-9 and ring.radialReverse == true,
  "from 315 back to 45, the probe's numbers (probe 074 C2)")
local corner = (-0.5 * 1.2 / 1.4142 + 0.5) * 56
T.expect(math.abs(ring.offsets[1][1] - corner) < 1e-9, "its crop moves the corners in")
T.expect(roundRecord.backdrop.value == 1 and roundRecord.backdrop.renderMode == 1, "its background is the whole arc")
T.expect(not roundRegion.foregroundSpinner.visible and not roundRegion.backgroundSpinner.visible, "the aura's own circle hides")
world.paused = true
private.Pause()
T.expect(roundRegion.foregroundSpinner.visible and not roundRegion.foreground.visible, "paused, its own circle is back")
world.paused = false
private.callbacks.events.ScanForLoads[1]()

T.section("Texts")
local timerText = Kind("text", { displayText = "Seal: %p", displayText_format_p_format = "timed",
  displayText_format_p_time_format = 0, displayText_format_p_time_dynamic_threshold = 3 })
local timerRegion, _, timerButton, timerRecord = AddKind(timerText)
local timerOptions = LastTimer(timerButton)
T.expect(timerOptions and timerOptions.textFormat and timerOptions.textFormat.formatString == "Seal: {}",
  "a %p with words is Blizzard's timer with the words around it (probe 074 T1)")
T.expect(timerOptions.textFormat.components[1].formatter.breakpoints[3].rounding == 1, "in the text's own time format")
T.expect(not timerRegion.text.visible and timerButton.timerWidget == timerRecord.pieces.main, "the aura's own text hides")
timerRegion.text:SetTextColor(1, 0, 0, 1)
T.expect(timerRecord.pieces.main.textColor[1] == 1 and timerRecord.pieces.main.textColor[2] == 0,
  "a condition's color reaches Blizzard's copy out of combat")
local stackText = Kind("text", { displayText = "Stacks: %s" })
local _, _, stackButton = AddKind(stackText)
local stackFormat = stackButton.countOptions and stackButton.countOptions.formatter
T.expect(stackFormat and stackFormat.breakpoints[1].format == "Stacks: " and stackFormat.breakpoints[2].format == "Stacks: %d",
  "a %s with words is the stack count with the words, the number blank at 0 (probe 074 T3)")
local nameText = Kind("text", { displayText = "%n is up" })
local _, _, nameButton, nameRecord = AddKind(nameText)
local after = nameRecord.pieces.after
T.expect(nameButton.nameWidget == nameRecord.pieces.main and after.text == " is up" and after.points.LEFT
  and after.points.LEFT.relative == nameRecord.pieces.main and after.points.LEFT.relativePoint == "RIGHT",
  "a %n with words is the name with the words placed after it (probe 074 T2)")
local rightText = Kind("text", { displayText = "Up: %n", justify = "RIGHT" })
local _, _, _, rightRecord = AddKind(rightText)
T.expect(rightRecord.pieces.after.points.RIGHT and rightRecord.pieces.before.points.RIGHT.relative == rightRecord.pieces.main,
  "a right-aligned one is built from the right")
T.expect(rightRecord.pieces.before.text == "Up: ", "words before the name keep their space")
T.expect(after.points.LEFT.x == -3 and nameRecord.pieces.main.points.LEFT.x == 0,
  "words after the name pull back by the outline's width, the name itself stays put (probe FW)")
T.expect(rightRecord.pieces.before.points.RIGHT.x == 3 and rightRecord.pieces.main.points.RIGHT.x == 0,
  "right-aligned, the words before the name move in by it, the name stays against the empty end")
local bothText = Kind("text", { displayText = "Up: %n is up" })
local _, _, _, bothRecord = AddKind(bothText)
T.expect(bothRecord.pieces.main.points.LEFT.x == -3 and bothRecord.pieces.after.points.LEFT.x == -3,
  "with words on both sides each join pulls back once")

local redText = Kind("text", { displayText = "%p", conditions = { { check = { trigger = 1, variable = "expirationTime",
  op = "<=", value = "5" }, changes = { { property = "color", value = { 1, 0, 0, 1 } } } } } })
local _, _, redButton = AddKind(redText)
T.expect(LastTimer(redButton).textColor and #LastTimer(redButton).textColor.curve.points == 2, "Remaining Time colors carry over")
local before = #world.created
stackText.displayText = "Stacks: %p"
AddKind(stackText)
T.expect(#world.created == before + 1, "a text that changes placeholder gets a button built for it")

T.section("Stack count from 1 (round 4 Q7)")
local counted = Seal("Counted", { subRegions = { { type = "subtext", text_text = "%s" } } })
local _, _, countedButton = Add(counted)
local countFormat = countedButton.countOptions and countedButton.countOptions.formatter
T.expect(countFormat and countFormat.breakpoints[1].format == "" and countFormat.breakpoints[2].format == "%d",
  "Blizzard's stack count shows 1 and up, blank at 0, like the aura's own %s")

T.expect(#errors == 0, "no errors")
T.finish()
