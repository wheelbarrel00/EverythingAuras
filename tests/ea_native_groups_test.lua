-- Everything Auras 0.7.0: dynamic groups Blizzard lays out, the real EA/Native.lua against a stub AuraContainer.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local world = { secret = false, paused = false, created = {}, sounds = {}, nextSound = 0, units = {} }

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

local function NewWidget(parent)
  local widget = Object({ parent = parent, alpha = 1, visible = true, color = { 1, 1, 1 } })
  widget.GetParent = function(self) return self.parent end
  widget.SetAlpha = function(self, alpha) self.alpha = alpha end
  widget.SetVertexColor = function(self, r, g, b, a) self.color = { r, g, b }; self.alpha = a or 1 end
  widget.GetVertexColor = function(self) return self.color[1], self.color[2], self.color[3], self.alpha end
  widget.Show = function(self) self.visible = true end
  widget.Hide = function(self) self.visible = false end
  widget.SetShown = function(self, shown) self.visible = shown and true or false end
  widget.SetFrameLevel = function(self, level) self.level = level end
  widget.GetFrameLevel = function(self) return self.level or 5 end
  widget.GetFrameStrata = function() return "MEDIUM" end
  widget.GetEffectiveScale = function() return 1 end
  widget.SetSize = function(self, width, height) self.width, self.height = width, height end
  widget.CreateTexture = function(self) return NewWidget(self) end
  widget.CreateFontString = function(self) return NewWidget(self) end
  return widget
end

world.uiParent = NewWidget(nil)

local function NewContainer()
  local container = NewWidget(nil)
  container.shown = true
  container.groups = {}
  container.Hide = function(self) self.shown = false end
  container.SetShown = function(self, shown) self.shown = shown end
  container.SetUnit = function(self, unit) self.unit = unit end
  container.HasAuraGroup = function(self, key) return self.groups[key] ~= nil end
  container.AddAuraGroup = function(self, key, filter, options)
    if world.failGroup then
      error("group failed")
    end
    local group = { key = key, filter = filter, options = options, enabled = true, buttons = {} }
    self.groups[key] = group
    for _ = 1, 2 do
      local button = NewWidget(self)
      button.EnableMouse = function(b, on) b.mouse = on end
      button.SetIcon = function(b, texture) b.iconWidget = texture end
      button.SetDurationCooldown = function(b, cooldown) b.cooldownWidget = cooldown end
      button.SetApplicationCount = function(b, count) b.countWidget = count end
      button.SetDurationBar = function(b, bar) b.barWidget = bar end
      button.SetSpellName = function(b, text) b.nameWidget = text end
      button.SetDurationText = function(b, text) b.timerWidget = text end
      options.initializeFrame(button)
      group.buttons[#group.buttons + 1] = button
    end
  end
  container.SetAuraGroupEnabled = function(self, key, enabled)
    self.groups[key].enabled = enabled
  end
  container.SetAuraGroupLayout = function(self, key, layout)
    self.groups[key].options.layout = layout
  end
  container.SetAuraGroupCandidateFilters = function(self, key, filters)
    self.groups[key].options.candidateFilters = filters
  end
  container.SetAuraGroupMaxFrameCount = function(self, key, count)
    self.groups[key].options.maxFrameCount = count
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
  frame.RegisterEvent = function() end
  frame.RegisterUnitEvent = function() end
  frame.SetScript = function(self, name, handler) self.scripts = self.scripts or {}; self.scripts[name] = handler end
  return frame
end

local auras, regions, errors = {}, {}, {}
local private = {
  frames = {},
  loaded = {},
  clones = {},
  regionTypes = {
    icon = { modify = function(_, region, data) region.modified = data.id end },
    aurabar = { modify = function(_, region, data) region.modified = data.id end },
    dynamicgroup = { modify = function(_, region, data) region.modified = data.id end },
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
    IsForever = function() return true end,
    L = setmetatable({}, { __index = function(_, key) return key end }),
    GetData = function(id) return auras[id] end,
    GetRegion = function(id) return regions[id] end,
    IsPaused = function() return world.paused end,
  },
  C_Secrets = { ShouldAurasBeSecret = function() return world.secret end },
  C_Spell = { GetSpellInfo = function() return nil end, GetSpellTexture = function() return 1 end },
  UnitExists = function(unit) return world.units[unit] ~= nil end,
  UnitCanAssist = function(_, unit) return world.units[unit] == "friend" end,
  UnitIsPlayerControlledOrGroupMember = function(unit) return unit == "player" end,
  C_UnitAuras = {
    AddAuraSound = function(trigger, info)
      world.nextSound = world.nextSound + 1
      world.sounds[world.nextSound] = { trigger = trigger, info = info }
      return world.nextSound
    end,
    RemoveAuraSound = function(handle) world.sounds[handle] = nil end,
  },
  Enum = { UnitAuraSoundTrigger = { Added = 0, Removed = 2 }, StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 } },
  AnchorUtil = { FlowLayoutAxis = { Horizontal = 0, Vertical = 1 }, FlowDirection = { Left = -1, Right = 1, Up = 1, Down = -1 } },
  CreateFrame = CreateFrame,
  UIParent = world.uiParent,
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
local chunk = assert(loadfile(T.repoRoot .. "/EverythingAuras/EA/Native.lua"))
setfenv(chunk, env)("EverythingAuras", private)
local qualifies = private.EANativeQualifies

-- Like a real frame: the aura sits at 100, 200 and its %s text's BOTTOMRIGHT 2 px in from its corner.
local function NewRegion(id, regionType)
  local region = NewWidget(nil)
  region.id, region.cloneId, region.regionType = id, "", regionType or "icon"
  region.icon = NewWidget(region)
  region.icon.GetTexCoord = function() return 0, 0, 0, 1, 1, 0, 1, 1 end
  region.icon.GetDesaturation = function() return 0 end
  region.GetColor = function() return 1, 1, 1, 1 end
  region.cooldown = NewWidget(region)
  region.cooldown.Hide = function(self) self.hidden = true end
  region.cooldown.Show = function(self) self.hidden = false end
  region.GetLeft, region.GetBottom, region.GetRight, region.GetTop = function() return 100 end,
    function() return 200 end, function() return 132 end, function() return 232 end
  local text = NewWidget(region)
  text.GetFont = function() return "font", 12, "OUTLINE" end
  text.GetShadowColor = function() return 0, 0, 0, 1 end
  text.GetShadowOffset = function() return 1, -1 end
  text.GetJustifyH = function() return "RIGHT" end
  text.GetPoint = function() return "BOTTOMRIGHT", region, "BOTTOMRIGHT", -2, 2 end
  text.GetLeft, text.GetBottom, text.GetRight, text.GetTop = function() return 120 end,
    function() return 202 end, function() return 130 end, function() return 214 end
  region.subRegions = { { type = "subtext", text_text = "%s", text = text } }
  region.countText = text
  regions[id] = region
  return region
end

local function Member(id, parent, extra, trigger)
  local data = { id = id, uid = id, parent = parent, regionType = "icon", eaNative = true, width = 32, height = 32,
    alpha = 1, cooldown = true, actions = {},
    subRegions = { { type = "subbackground" }, { type = "subtext", text_text = "%s" }, { type = "subglow", glow = false } },
    triggers = { { trigger = trigger or { type = "aura2", unit = "player", debuffType = "HELPFUL", useExactSpellId = true,
      auraspellids = { tostring(1000 + #regions) } } } } }
  for key, value in pairs(extra or {}) do
    data[key] = value
  end
  auras[id] = data
  if not regions[id] then
    NewRegion(id, data.regionType)
  end
  return data
end

local function Group(id, children, extra)
  local data = { id = id, uid = id, regionType = "dynamicgroup", grow = "RIGHT", selfPoint = "LEFT", sort = "none",
    space = 4, stagger = 0, alpha = 1, controlledChildren = children }
  for key, value in pairs(extra or {}) do
    data[key] = value
  end
  auras[id] = data
  if not regions[id] then
    regions[id] = NewWidget(nil)
  end
  return data
end

local function Modify(data)
  local regionType = data.regionType
  private.regionTypes[regionType].modify(nil, regions[data.id], data)
end

T.section("Which dynamic groups Blizzard lays out")
local group = Group("G", { "A", "B" })
Member("A", "G")
Member("B", "G")
T.expect(qualifies(auras.A) and qualifies(auras.B), "two icons of one size on one unit, grow Right, sort None: both qualify")
local function GroupWith(extra)
  for key, value in pairs(extra) do
    group[key] = value
  end
  local ok, reason = qualifies(auras.A)
  for key in pairs(extra) do
    group[key] = nil
  end
  group.grow, group.sort, group.space, group.stagger, group.selfPoint = "RIGHT", "none", 4, 0, "LEFT"
  return ok, reason
end
T.expect(not GroupWith({ sort = "ascending" }), "a sorted group does not")
T.expect(not GroupWith({ grow = "CIRCLE" }) and not GroupWith({ grow = "CUSTOM" }), "Circle and Custom do not")
T.expect(GroupWith({ grow = "HORIZONTAL", centerType = "RL" }) and not GroupWith({ grow = "HORIZONTAL", centerType = "CLR" }),
  "a centered group in list order does, one that starts from the middle does not")
T.expect(GroupWith({ grow = "GRID", gridType = "RU" }) and not GroupWith({ grow = "GRID", gridType = "HD" }),
  "a grid from a corner does, a centered grid does not")
T.expect(not GroupWith({ stagger = 2 }), "a stagger does not")
T.expect(not GroupWith({ anchorFrameType = "NAMEPLATE" }) and not GroupWith({ useAnchorPerUnit = true })
  and GroupWith({ anchorFrameType = "SELECTFRAME" }), "nameplates and unit frames do not, a chosen frame does")
local limitOk, limitReason = GroupWith({ useLimit = true, limit = 1 })
T.expect(not limitOk and limitReason:find("Limit", 1, true) and GroupWith({ useLimit = true, limit = 2 }),
  "a Limit below the number of auras does not, and says why, a Limit that covers them does")
T.expect(not GroupWith({ border = true }), "a group border does not")
auras.B.eaNative = false
T.expect(not qualifies(auras.A), "every aura needs its switch on")
auras.B.eaNative = true
auras.B.width = 40
T.expect(not qualifies(auras.A), "every aura the same size")
auras.B.width = 32
auras.B.triggers[1].trigger.unit = "target"
T.expect(not qualifies(auras.A), "every aura on the same unit")
auras.B.triggers[1].trigger.unit = "player"
auras.B.subRegions[2].text_text = "%p"
T.expect(not qualifies(auras.B), "an icon text other than %s keeps the group as it is")
auras.B.subRegions[2].text_text = "%s"
auras.B.subRegions[3].glow = true
T.expect(not qualifies(auras.B), "a glow that shows keeps it as it is")
auras.B.subRegions[3].glow = false
auras.B.conditions = { { check = { trigger = 1, variable = "stacks" }, changes = { { property = "sub.3.glow", value = true } } } }
T.expect(not qualifies(auras.B), "so does a condition that turns a glow on")
auras.B.conditions = { { check = { trigger = 1, variable = "stacks" }, changes = { { property = "sub.2.text_color" } } } }
T.expect(qualifies(auras.B), "a condition on the stack text is fine")
auras.B.conditions = nil
auras.B.triggers[1].trigger.matchesShowOn = "showAlways"
T.expect(not qualifies(auras.B), "Show On Always inside a group does not")
auras.B.triggers[1].trigger.matchesShowOn = nil
auras.B.triggers[1].trigger.showClones = true
T.expect(qualifies(auras.B), "Auto-Clone inside a group does, as a list")
auras.B.triggers[1].trigger.showClones = nil
auras.Solo = { id = "Solo", uid = "Solo", regionType = "icon", eaNative = true, triggers = { { trigger = { type = "aura2",
  unit = "player", debuffType = "HELPFUL", useExactSpellId = true, auraspellids = { "5" }, showClones = true } } } }
T.expect(not qualifies(auras.Solo), "Auto-Clone outside a dynamic group still does not")
auras.Plain = { id = "Plain", uid = "Plain", regionType = "group", parent = "G" }
auras.Deep = { id = "Deep", uid = "Deep", regionType = "icon", parent = "Plain", eaNative = true,
  triggers = { { trigger = { type = "aura2", unit = "player", useExactSpellId = true, auraspellids = { "6" } } } } }
T.expect(not qualifies(auras.Deep), "an aura in a group inside a dynamic group does not")

T.section("Laying out the group")
private.loaded.A, private.loaded.B = true, true
Modify(group)
local container = world.created[#world.created]
T.expect(container and container.template == "CustomAuraContainerTemplate" and container.unit == "player",
  "one container for the group, on the group's unit")
local keyA, keyB = "A:icon", "B:icon"
T.expect(container.groups[keyA] and container.groups[keyB], "one Blizzard aura group per aura")
local layoutA, layoutB = container.groups[keyA].options.layout, container.groups[keyB].options.layout
T.expect(layoutA.layoutIndex == 1 and layoutB.layoutIndex == 2 and layoutA.elementSpacing == 4
  and layoutA.elementWidth == 32, "in list order, with the group's spacing and the auras' size")
T.expect(container.groups[keyA].options.maxFrameCount == 1 and container.groups[keyA].options.sortMethod == 4,
  "one aura each, by time left")
T.expect(Last(container, "SetFlowLayoutAxis")[1] == 0 and Last(container, "SetFlowLayoutGrowthDirection")[1] == 1
  and Last(container, "SetFlowLayoutAnchorPoint")[1] == "TOPLEFT", "grow Right: a row from the top left")
local anchor = Last(container, "SetPoint")
T.expect(anchor[1] == "LEFT" and anchor[2] == regions.G and anchor[3] == "LEFT",
  "the container sits on the group's own anchor point")
T.expect(container.shown and container.groups[keyA].enabled and regions.A.eaNativeOn and not regions.A.icon.visible,
  "loaded: Blizzard lays them out and the auras' own icons step aside")
local button = container.groups[keyA].buttons[1]
T.expect(button.width == 32 and button.height == 32 and Count(button, "SetAllPoints") == 0,
  "each button gets the aura's size and is placed by Blizzard, not pinned to the container")
T.expect(button.iconWidget and button.cooldownWidget and button.countWidget, "icon, swipe and stack count handed over")
local countPoint = Last(button.countWidget, "SetPoint")
T.expect(countPoint and countPoint[1] == "BOTTOMRIGHT" and countPoint[2] == button and countPoint[4] == 30 and countPoint[5] == 2,
  "the stack count sits where it does on the aura, measured from the button")
T.expect(not regions.A.countText.visible, "the aura's own stack text steps aside")
T.expect(#errors == 0, "no errors" .. (errors[1] and (": " .. tostring(errors[1])) or ""))

T.section("Grow directions")
local function FlowFor(extra)
  for key, value in pairs(extra) do
    group[key] = value
  end
  Modify(group)
  local result = { Last(container, "SetFlowLayoutAxis")[1], Last(container, "SetFlowLayoutGrowthDirection")[1],
    Last(container, "SetFlowLayoutGrowthDirection")[2], Last(container, "SetFlowLayoutAnchorPoint")[1],
    Last(container, "SetFlowLayoutMaximumLineSize")[1] }
  for key in pairs(extra) do
    group[key] = nil
  end
  group.grow, group.selfPoint = "RIGHT", "LEFT"
  return result
end
local up = FlowFor({ grow = "UP", selfPoint = "BOTTOM" })
T.expect(up[1] == 1 and up[3] == 1 and up[4] == "BOTTOMLEFT", "Up: a column from the bottom")
local left = FlowFor({ grow = "LEFT", selfPoint = "RIGHT" })
T.expect(left[1] == 0 and left[2] == -1 and left[4] == "TOPRIGHT", "Left: a row from the right")
local centered = FlowFor({ grow = "HORIZONTAL", centerType = "RL", selfPoint = "CENTER" })
T.expect(centered[2] == -1 and Last(container, "SetPoint")[1] == "CENTER", "Centered right to left, held on the center")
local vertical = FlowFor({ grow = "VERTICAL", centerType = "LR", selfPoint = "CENTER" })
T.expect(vertical[1] == 1 and vertical[3] == 1, "Centered vertical, bottom to top")
local grid = FlowFor({ grow = "GRID", gridType = "RU", gridWidth = 3, columnSpace = 5, rowSpace = 7, selfPoint = "BOTTOMLEFT" })
T.expect(grid[1] == 0 and grid[2] == 1 and grid[3] == 1 and grid[4] == "BOTTOMLEFT" and grid[5] == 3 * 32 + 2 * 5 + 0.5,
  "a grid wraps after its row width, with column space between auras")
T.expect(container.groups[keyA].options.layout.lineSpacing == 7, "and row space between rows")
Modify(group)
T.expect(Last(container, "SetFlowLayoutMaximumLineSize")[1] == nil, "back to a row: no wrapping")

T.section("Loading, pausing, changes")
private.loaded.B = false
Modify(group)
T.expect(not container.groups[keyB].enabled and container.groups[keyA].enabled and regions.B.icon.visible and not regions.B.eaNativeOn,
  "an aura that is not loaded is left out")
private.loaded.B = true
world.paused = true
Modify(group)
T.expect(not container.shown and regions.A.icon.visible and not regions.A.eaNativeOn, "paused: the auras draw themselves")
world.paused = false
Modify(group)
T.expect(container.shown and regions.A.eaNativeOn, "unpaused: Blizzard again")
group.controlledChildren = { "B", "A" }
Modify(group)
T.expect(container.groups[keyB].options.layout.layoutIndex == 1 and container.groups[keyA].options.layout.layoutIndex == 2,
  "a new order reaches Blizzard's layout")
group.controlledChildren = { "B" }
auras.A.parent = nil
Modify(group)
T.expect(not container.groups[keyA].enabled and not regions.A.eaNativeOn and regions.A.icon.visible,
  "an aura moved out of the group leaves it and draws itself")
group.controlledChildren = { "A", "B" }
auras.A.parent = "G"
Modify(group)
T.expect(container.groups[keyA].enabled and regions.A.eaNativeOn, "and comes back")
local buildsBefore = #world.created
group.sort = "ascending"
Modify(group)
T.expect(not container.shown and not regions.A.eaNativeOn and regions.B.icon.visible and #world.created == buildsBefore,
  "sorting turned on: Everything Auras lays it out again")
group.sort = "none"
Modify(group)
T.expect(container.shown and #world.created == buildsBefore, "sort None again: the same container comes back")

T.section("Ranks learned out of combat")
local named = Member("N", "G", nil, { type = "aura2", unit = "player", debuffType = "HELPFUL", useName = true,
  auranames = { "Holy Might" } })
group.controlledChildren = { "A", "B", "N" }
private.loaded.N = true
Modify(group)
T.expect(not container.shown and regions.N.eaNativeWanted, "an aura known only by name: the group waits and learns its ID")
regions.N.states = { [1] = { show = true, spellId = 4242 } }
private.RunConditions(regions.N, "N")
T.expect(named.eaNativeIds and named.eaNativeIds[1] == 4242 and container.shown and container.groups["N:icon"],
  "the ID read out of combat brings the whole group to Blizzard")

T.section("Sounds and clones")
auras.A.actions = { start = { do_sound = true, sound = "Interface\\Alert.ogg" } }
Modify(auras.A)
T.expect(private.EANativeSound(auras.A, "start"), "a member's On Show sound plays through Blizzard")
auras.B.triggers[1].trigger.showClones = true
local clone = NewRegion("B-clone")
clone.cloneId = "x"
regions["B-clone"] = nil
private.clones.B = { x = clone }
Modify(group)
T.expect(container.groups[keyB].options.maxFrameCount == math.huge, "an Auto-Clone aura becomes a list showing every match")
T.expect(clone.eaNativeOn and not clone.icon.visible and not clone.countText.visible, "its own clones step aside")
world.paused = true
Modify(group)
T.expect(clone.icon.visible and not clone.eaNativeOn, "paused: the clones draw themselves")
world.paused = false
Modify(group)

T.section("Delete and failure")
private.callbacks:Fire("Delete", "G")
T.expect(not container.shown and regions.A.icon.visible and not regions.A.eaNativeOn, "a deleted group gives its auras back")
local failing = Group("F", { "F1" })
Member("F1", "F")
private.loaded.F1 = true
world.failGroup = true
Modify(failing)
world.failGroup = false
T.expect(#errors == 1 and not regions.F1.eaNativeOn and regions.F1.icon.visible, "a failure is reported once and the aura draws itself")
Modify(failing)
T.expect(#errors == 1 and not regions.F1.eaNativeOn, "and not again: the group draws itself for the rest of the session")
T.finish()
