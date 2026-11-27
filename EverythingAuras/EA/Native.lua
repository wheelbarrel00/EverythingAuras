if not EverythingAuras.IsLibsOK() then return end

local Private = select(2, ...)
local L = EverythingAuras.L

local SLOT = "aura"
local UNITS = { player = true, target = true, focus = true, pet = true }
local UNIT_EVENTS = { PLAYER_TARGET_CHANGED = "target", PLAYER_FOCUS_CHANGED = "focus" }
local SOUND_ACTIONS = { { when = "start", trigger = "Added" }, { when = "finish", trigger = "Removed" } }
local COOLDOWN_UPDATES = { "UpdateValue", "UpdateTime", "UpdateDuration", "PreShow" }
local FLAG_FILTERS = { "useStacks", "useRem", "useNamePattern", "useIgnoreName" }
-- Blizzard's candidate flags test the same aura fields the trigger reads (BuffTrigger2.lua UpdateMatchData).
local TRISTATE_FILTERS = { { "use_stealable", "isStealable" }, { "use_isBossDebuff", "isBossAura" },
  { "use_castByPlayer", "isFromPlayerOrPlayerPet" } }
-- Blizzard keys dispel types by name (AuraUtil.lua DEBUFF_DISPLAY_INFO), and an aura with no type has no name to list.
local DISPEL_TYPES = { magic = "Magic", curse = "Curse", disease = "Disease", poison = "Poison", bleed = "Bleed" }
local LOOK_PROPERTIES = { iconSource = true, displayIcon = true, progressSource = true, adjustedMin = true,
  adjustedMax = true }
local ALWAYS_LOOK = { desaturate = true, color = true, alpha = true }
local SQUARE = "Interface\\AddOns\\EverythingAuras\\Media\\Textures\\Square_FullWhite"
-- The same fill as the bar's own secret bar for each orientation (AuraBar.lua SetOrientation).
local FILL = { HORIZONTAL = { "HORIZONTAL", false }, HORIZONTAL_INVERSE = { "HORIZONTAL", true },
  VERTICAL = { "VERTICAL", true }, VERTICAL_INVERSE = { "VERTICAL", false } }
local TAKEOVERS = {
  { key = "count", format = "%s" },
  { key = "name", format = "%n" },
  { key = "timer", format = "%p" },
}
local RT_TESTS = { ["<"] = function(v, n) return v < n end, ["<="] = function(v, n) return v <= n end,
  [">"] = function(v, n) return v > n end, [">="] = function(v, n) return v >= n end }
-- Blizzard keys a dispel color by the aura's dispel name, "" for an enrage and None for none (GetDispelTypeMapKey).
local DISPEL_KEYS = { magic = "Magic", curse = "Curse", disease = "Disease", poison = "Poison", bleed = "Bleed",
  enrage = "", none = "None" }
-- Blizzard's border pieces are plain strips, which match only a solid edge file.
local PLAIN_EDGES = { ["Square Full White"] = true }
local GLOW_TYPES = { buttonOverlay = true, Pixel = true, ACShine = true, Proc = true }
-- The smallest positive number, so a formatter's 0 breakpoint covers exactly 0 (Types.lua GetTimeFormatter).
local MIN_POSITIVE = 2 ^ -1074
-- Expiration puts your own auras first (AuraUtil.lua), while the trigger picks the least time left, an aura that never ends aside.
local SORT_TIME_LEFT = AuraContainerSortMethod and (AuraContainerSortMethod.ExpirationOnly or AuraContainerSortMethod.Expiration) or 5
local REGION_KINDS = { icon = "icon", aurabar = "bar", texture = "texture", text = "text", progresstexture = "progress" }
local VARIANT_KINDS = { icon = "icon", remaining = "bar", elapsed = "bar", texture = "texture", ["text-p"] = "text",
  ["text-s"] = "text", ["text-n"] = "text", ["fill-remaining"] = "progress", ["fill-elapsed"] = "progress",
  ["circle-remaining"] = "progress", ["circle-elapsed"] = "progress" }
-- Blizzard's copy keeps the shape it was given out of combat, so a condition may not change these.
local REGION_LOOKS = {
  progresstexture = { orientation = true, auraRotation = true, inverse = true, mirror = true, rotation = true,
    crop_x = true, crop_y = true, width = true, height = true, desaturateForeground = true, desaturateBackground = true },
  text = { fontSize = true, displayText = true },
}
local ORIENTATIONS = { HORIZONTAL = true, HORIZONTAL_INVERSE = true, VERTICAL = true, VERTICAL_INVERSE = true,
  CLOCKWISE = true, ANTICLOCKWISE = true }
local TEXTURE_COPIES = { "SetTexture", "SetAtlas", "SetTexCoord", "SetVertexColor", "SetDesaturated", "SetDesaturation",
  "SetBlendMode" }

local records = {}
local spare = {}
local groups, members = {}, {}
local wrappers = setmetatable({}, { __mode = "k" })

local function Secret()
  return C_Secrets.ShouldAurasBeSecret()
end

local function HasSpells(trigger)
  if trigger.useExactSpellId and type(trigger.auraspellids) == "table" then
    for _, value in ipairs(trigger.auraspellids) do
      if tonumber(value) then
        return true
      end
    end
  end
  if trigger.useName and type(trigger.auranames) == "table" then
    for _, value in ipairs(trigger.auranames) do
      if type(value) == "string" and value ~= "" then
        return true
      end
    end
  end
  return false
end

-- A trigger that names no aura matches any aura of its kind, as a slot with no spell IDs does (probe P6).
local function AnyAura(trigger)
  return not trigger.useName and not trigger.useExactSpellId
end

-- With Show On Always and no Auto-Clone the trigger skips every filter but Own Only and the name pattern (BuffTrigger2.lua CanHaveMatchCheck).
local function MatchCheck(trigger)
  return trigger.matchesShowOn ~= "showAlways" or trigger.showClones and true or false
end

-- Blizzard fills one placeholder per text piece, so a Text shows one %p, %s or %n with fixed words around it.
local function TextParts(text)
  if type(text) ~= "string" then
    return nil
  end
  local first, last, symbol = text:find("%%([psn])")
  if not first or text:sub(last + 1, last + 1):find("[%w_%.]") then
    return nil
  end
  local prefix, suffix = text:sub(1, first - 1), text:sub(last + 1)
  if prefix:find("%%") or suffix:find("%%") or symbol == "p" and (prefix .. suffix):find("[{}]") then
    return nil
  end
  return symbol, prefix, suffix
end

local function IsRound(data)
  return data.orientation == "CLOCKWISE" or data.orientation == "ANTICLOCKWISE"
end

-- A container watches one unit, so the units that clone an aura for each group member stay Everything Auras' own.
local function UnitOf(trigger)
  local unit = trigger.unit or "player"
  if unit == "member" then
    local token = type(trigger.specificUnit) == "string" and trigger.specificUnit:lower() or ""
    local party, raid = tonumber(token:match("^party(%d)$")), tonumber(token:match("^raid(%d%d?)$"))
    if (party and party >= 1 and party <= 4) or (raid and raid >= 1 and raid <= 40) then
      return token
    end
    return nil
  end
  return UNITS[unit] and unit or nil
end

-- Blizzard's maxDuration is an inclusive cap on the full duration (CustomAuraContainer.lua:106-108).
local function TotalLimit(trigger)
  if not trigger.useTotal or trigger.total == nil then
    return nil, true
  end
  local total = tonumber(trigger.total)
  if trigger.totalOperator == "<=" and total and total >= 0 then
    return total, true
  end
  return nil, false
end

local function DispelTypes(trigger)
  if not trigger.use_debuffClass then
    return nil, true
  end
  local types = {}
  for key, on in pairs(type(trigger.debuffClass) == "table" and trigger.debuffClass or {}) do
    if on then
      if not DISPEL_TYPES[key] then
        return nil, false
      end
      types[DISPEL_TYPES[key]] = true
    end
  end
  return types, true
end

local function IsAlways(data)
  local trigger = data.triggers[1].trigger
  return data.regionType == "icon" and trigger.matchesShowOn == "showAlways"
end

-- Blizzard's icon covers Everything Auras' missing look, so that look may change only by whether the aura is found.
local function AlwaysConditions(data)
  for index, condition in ipairs(type(data.conditions) == "table" and data.conditions or {}) do
    local check = type(condition) == "table" and condition.check
    if type(check) ~= "table" or check.trigger ~= 1 or check.variable ~= "buffed" or check.checks ~= nil
      or condition.linked and index > 1 then
      return false
    end
    for _, change in ipairs(type(condition.changes) == "table" and condition.changes or {}) do
      if type(change) ~= "table" or not ALWAYS_LOOK[change.property] then
        return false
      end
    end
  end
  return true
end

local function AlwaysLook(data, found)
  local color = type(data.color) == "table" and data.color or {}
  local look = { desaturate = data.desaturate and true or false, r = color[1] or 1, g = color[2] or 1,
    b = color[3] or 1, a = color[4] or 1, alpha = tonumber(data.alpha) or 1 }
  for _, condition in ipairs(type(data.conditions) == "table" and data.conditions or {}) do
    local value = tonumber(condition.check.value)
    if value ~= nil and (value == 1) == found then
      for _, change in ipairs(type(condition.changes) == "table" and condition.changes or {}) do
        local value = change.value
        if change.property == "desaturate" then
          look.desaturate = value and true or false
        elseif change.property == "color" and type(value) == "table" then
          look.r, look.g, look.b, look.a = value[1] or 1, value[2] or 1, value[3] or 1, value[4] or 1
        elseif change.property == "alpha" and tonumber(value) then
          look.alpha = tonumber(value)
        end
      end
    end
  end
  return look
end

local MEMBER_TEXTS = { icon = { ["%s"] = true, ["%p"] = true }, aurabar = { ["%s"] = true, ["%n"] = true, ["%p"] = true },
  texture = { ["%s"] = true, ["%n"] = true, ["%p"] = true }, progresstexture = { ["%s"] = true, ["%n"] = true, ["%p"] = true } }
local GROWS = { RIGHT = true, LEFT = true, UP = true, DOWN = true, HORIZONTAL = true, VERTICAL = true, GRID = true }
local CENTER_TYPES = { LR = true, RL = true }
local GRID_TYPES = { RD = true, RU = true, LD = true, LU = true, DR = true, DL = true, UR = true, UL = true }
local GROUP_ANCHORS = { SCREEN = true, UIPARENT = true, SELECTFRAME = true }

local function SubChanges(data, index)
  local prefix, list = "sub." .. index .. ".", {}
  for _, condition in ipairs(type(data.conditions) == "table" and data.conditions or {}) do
    for _, change in ipairs(type(condition) == "table" and type(condition.changes) == "table" and condition.changes or {}) do
      if type(change) == "table" and type(change.property) == "string" and change.property:sub(1, #prefix) == prefix then
        list[#list + 1] = { check = condition.check, change = change, property = change.property:sub(#prefix + 1) }
      end
    end
  end
  return list
end

-- A glow a condition switches on follows the trigger, which Blizzard cannot, so only an always-on glow is Blizzard's.
local function GlowKind(data, index)
  local sub = data.subRegions[index]
  if #SubChanges(data, index) > 0 then
    return "own"
  end
  if not sub.glow then
    return nil
  end
  return GLOW_TYPES[sub.glowType or "buttonOverlay"] and "blizzard" or "own"
end

-- Blizzard picks a strip's color by the aura's dispel type, so only Debuff Type tests can carry over.
local function DispelColors(data, index)
  local sub = data.subRegions[index]
  local colors = {}
  for _, key in pairs(DISPEL_KEYS) do
    colors[key] = type(sub.border_color) == "table" and sub.border_color or { 1, 1, 1, 1 }
  end
  for _, entry in ipairs(SubChanges(data, index)) do
    local check = entry.check
    local key = type(check) == "table" and check.trigger == 1 and check.variable == "debuffClass" and check.checks == nil
      and DISPEL_KEYS[check.value]
    if not key or (check.op ~= "==" and check.op ~= "~=") or entry.property ~= "border_color"
      or type(entry.change.value) ~= "table" then
      return nil
    end
    for _, other in pairs(DISPEL_KEYS) do
      if (check.op == "==") == (other == key) then
        colors[other] = entry.change.value
      end
    end
  end
  return colors
end

local function BorderKind(data, index)
  local sub = data.subRegions[index]
  -- A pixel perfect border ignores its parent's scale (Border.lua modify), so it cannot be measured against the aura.
  if not PLAIN_EDGES[sub.border_edge or "Square Full White"] or sub.border_ppscale then
    return "own"
  end
  if #SubChanges(data, index) == 0 then
    return sub.border_visible ~= false and "plain" or nil
  end
  return sub.border_visible ~= false and DispelColors(data, index) and "dispel" or "own"
end

local function HasBlizzardLooks(data)
  for index, sub in ipairs(type(data.subRegions) == "table" and data.subRegions or {}) do
    if type(sub) == "table" and (sub.type == "subglow" and GlowKind(data, index) == "blizzard"
      or sub.type == "subborder" and (BorderKind(data, index) == "plain" or BorderKind(data, index) == "dispel")) then
      return true
    end
  end
  return false
end

-- Blizzard places a group's buttons itself, so any part it does not draw would stay where Everything Auras put the aura.
local function OnlyBlizzardParts(data)
  local allowed = MEMBER_TEXTS[data.regionType] or {}
  local subRegions = type(data.subRegions) == "table" and data.subRegions or {}
  for index, sub in ipairs(subRegions) do
    if type(sub) ~= "table" then
      return false
    elseif sub.type == "subtext" then
      if not (sub.text_visible == false or allowed[sub.text_text] == true) then
        return false
      end
    elseif sub.type == "subglow" then
      if GlowKind(data, index) == "own" then
        return false
      end
    elseif sub.type == "subborder" then
      if BorderKind(data, index) == "own" then
        return false
      end
    elseif sub.type ~= "subbackground" then
      return false
    end
  end
  for _, condition in ipairs(type(data.conditions) == "table" and data.conditions or {}) do
    for _, change in ipairs(type(condition) == "table" and type(condition.changes) == "table" and condition.changes or {}) do
      local index = type(change) == "table" and type(change.property) == "string" and change.property:match("^sub%.(%d+)%.")
      local sub = index and subRegions[tonumber(index)]
      if index and not (sub and (sub.type == "subborder" or sub.type == "subtext" and allowed[sub.text_text])) then
        return false
      end
    end
  end
  return true
end

local function Check(data, inGroup)
  if not REGION_KINDS[data.regionType] then
    return false, L["Only an Icon, Progress Bar, Texture, Text or Progress Texture can be drawn by Blizzard."]
  end
  if type(data.triggers) ~= "table" or #data.triggers ~= 1 then
    return false, L["Needs exactly one trigger."]
  end
  local trigger = data.triggers[1].trigger
  if type(trigger) ~= "table" or trigger.type ~= "aura2" then
    return false, L["Needs an Aura trigger."]
  end
  local unit = UnitOf(trigger)
  if not unit then
    return false, L["Works on Player, Target, Focus, Pet, or a Specific Unit from party1 to party4 or raid1 to raid40."]
  end
  if unit ~= "player" and trigger.unitExists then
    return false, L["Blizzard draws nothing while the unit is not there, so Show If Unit Does Not Exist must be off."]
  end
  local debuffType = trigger.debuffType or "HELPFUL"
  if debuffType ~= "HELPFUL" and debuffType ~= "HARMFUL" then
    return false, L["Needs Buff or Debuff, not both."]
  end
  local any = AnyAura(trigger)
  -- Blizzard matches a debuff's spell ID only on a unit you cannot assist (AuraContainerUtil.lua:78-80).
  local restricted = debuffType == "HARMFUL" and unit ~= "target" and unit ~= "focus"
  if restricted and not any then
    if unit == "player" then
      return false, L["Blizzard draws debuffs on you only for an aura that names none: untick Name(s) and Exact Spell ID(s), and narrow it with the trigger's filters."]
    end
    return false, L["Blizzard draws debuffs on your pet or your group only for an aura that names none: untick Name(s) and Exact Spell ID(s), and narrow it with the trigger's filters."]
  end
  local showOn = trigger.matchesShowOn or "showOnActive"
  if showOn == "showOnMissing" then
    return false, L["A Missing reminder holds what it showed when the fight started, because Blizzard draws an aura only while it is there."]
  elseif showOn == "showAlways" then
    if inGroup then
      return false, L["In a dynamic group Blizzard draws only auras set to show while found."]
    end
    if data.regionType ~= "icon" then
      return false, L["Blizzard draws Show On Always only on icons for now."]
    end
    if not AlwaysConditions(data) then
      return false, L["With Show On Always, Blizzard draws the icon over its missing look, so conditions may only change Desaturate, Color or Alpha by Aura(s) Found."]
    end
    if HasBlizzardLooks(data) then
      return false, L["With Show On Always, an always-on glow or a border would vanish while the aura is missing, so Everything Auras draws this icon."]
    end
  elseif showOn ~= "showOnActive" then
    return false, L["Needs Show On set to Aura(s) Found."]
  end
  if any then
    if showOn ~= "showOnActive" then
      return false, L["An aura that names none needs Show On set to Aura(s) Found."]
    end
    if restricted and trigger.useIgnoreExactSpellId then
      return false, L["Blizzard cannot ignore spell IDs on debuffs on you, your pet or your group."]
    end
  end
  if not trigger.showClones and (trigger.combineMode or "showLowest") ~= "showLowest" then
    return false, L["Blizzard shows the aura that ends soonest, so Preferred Match must be Least remaining time."]
  end
  -- Blizzard shows only the aura's own icon and time, and Everything Auras hides its own while Blizzard draws.
  local progressSource = type(data.progressSource) == "table" and data.progressSource[1] or -1
  local changed = data.iconSource == 0 or progressSource ~= -1 or data.useAdjustededMin or data.useAdjustededMax
  for _, condition in ipairs(type(data.conditions) == "table" and data.conditions or {}) do
    for _, change in ipairs(type(condition) == "table" and type(condition.changes) == "table" and condition.changes or {}) do
      changed = changed or type(change) == "table" and LOOK_PROPERTIES[change.property] or false
    end
  end
  if changed then
    return false, L["Blizzard shows the aura's own icon and time, so it cannot follow a manual icon, Set Minimum or Maximum Progress, or a progress source other than Automatic, set directly or by a condition."]
  end
  local looks = REGION_LOOKS[data.regionType]
  for _, condition in ipairs(looks and type(data.conditions) == "table" and data.conditions or {}) do
    for _, change in ipairs(type(condition) == "table" and type(condition.changes) == "table" and condition.changes or {}) do
      if type(change) == "table" and looks[change.property] then
        return false, L["Blizzard cannot follow a condition that changes this aura's shape, size, direction or text."]
      end
    end
  end
  for _, condition in ipairs(inGroup and type(data.conditions) == "table" and data.conditions or {}) do
    for _, change in ipairs(type(condition) == "table" and type(condition.changes) == "table" and condition.changes or {}) do
      if type(change) == "table" and (change.property == "width" or change.property == "height") then
        return false, L["Blizzard lays out a group by one fixed size, so a condition may not change an aura's width or height."]
      end
    end
  end
  if data.regionType == "text" then
    local symbol = TextParts(data.displayText)
    if not symbol then
      return false, L["A Text Blizzard draws shows one %p, %s or %n with fixed words, with no custom text or other placeholders."]
    end
    local format = data["displayText_format_" .. symbol .. "_format"]
    if symbol == "p" and format ~= nil and format ~= "timed" then
      return false, L["Blizzard shows %p as a time, so its format must be Time Format."]
    elseif symbol ~= "p" and format ~= nil and format ~= "none" then
      return false, L["Blizzard shows %s and %n as they are, so their format must be None."]
    end
    if inGroup then
      return false, L["Blizzard lays out a group by one fixed size, so a group with a Text aura stays as it is."]
    end
  elseif data.regionType == "progresstexture" then
    if not ORIENTATIONS[data.orientation or "VERTICAL"] or data.slanted or data.compress or data.smoothProgress
      or (tonumber(data.auraRotation) or 0) ~= 0 or type(data.overlays) == "table" and next(data.overlays) ~= nil then
      return false, L["Blizzard fills a Progress Texture straight or round, without Slanted, Compress, Smooth Progress, Rotation or overlays."]
    end
    -- A circle's crop moves its corners equally, keeping the angles (ProgressTexture.lua UpdateSecretTexCoords).
    if IsRound(data) and (tonumber(data.crop_x) or 0.41) ~= (tonumber(data.crop_y) or 0.41) then
      return false, L["Blizzard draws a round Progress Texture only with equal Crop X and Crop Y."]
    end
  end
  if trigger.showClones and not inGroup then
    return false, L["Auto-Clone works only inside a dynamic group, where Blizzard lists every match."]
  end
  if inGroup and not OnlyBlizzardParts(data) then
    return false, L["In a dynamic group Blizzard places each aura itself, so the aura may show only what Blizzard draws: a text that shows only %s or %p (or %n on anything but an icon), a glow that is always on, and a Square Full White border, plain or colored by Debuff Type."]
  end
  local matchCheck = MatchCheck(trigger)
  local filtered = matchCheck and trigger.fetchTooltip and (trigger.use_tooltip or trigger.use_tooltipValue)
  for _, key in ipairs(FLAG_FILTERS) do
    filtered = filtered or (matchCheck or key == "useNamePattern") and trigger[key]
  end
  local _, totalOk = TotalLimit(trigger)
  local _, dispelOk = DispelTypes(trigger)
  if filtered or matchCheck and (not totalOk or not dispelOk) then
    return false, L["Blizzard cannot apply some of this trigger's filters: stacks, remaining time, name patterns, ignored names, a Total Time other than <=, or the Enrage and None debuff types."]
  end
  if not any and not HasSpells(trigger) then
    return false, L["Needs Name(s) or Exact Spell ID(s)."]
  end
  return true
end

-- One container lays out the whole group, and it watches one unit and keeps its auras in list order.
local function GroupQualifies(group)
  local grow = group.grow or "DOWN"
  if not GROWS[grow] then
    return false, L["Blizzard lays out a dynamic group only when it grows Right, Left, Up, Down, Centered or in a Grid."]
  end
  if (grow == "HORIZONTAL" or grow == "VERTICAL") and not CENTER_TYPES[group.centerType or "LR"] then
    return false, L["Blizzard adds a centered group's auras in list order, not from the middle out."]
  end
  if grow == "GRID" and not GRID_TYPES[group.gridType or "RD"] then
    return false, L["Blizzard starts a grid in a corner, not centered."]
  end
  if (group.sort or "none") ~= "none" then
    return false, L["Blizzard keeps a group's auras in list order, so the group's Sort must be None."]
  end
  if grow ~= "GRID" and (tonumber(group.stagger) or 0) ~= 0 then
    return false, L["Blizzard cannot stagger a group's auras."]
  end
  if not GROUP_ANCHORS[group.anchorFrameType or "SCREEN"] or group.useAnchorPerUnit then
    return false, L["The group must be anchored to the screen or a frame, not to nameplates, unit frames, the Personal Resource Display, the mouse or a custom anchor."]
  end
  if group.border then
    return false, L["Blizzard cannot draw the group's border."]
  end
  local children = type(group.controlledChildren) == "table" and group.controlledChildren or {}
  if #children == 0 then
    return false, L["The group has no auras."]
  end
  local limit = group.useLimit and tonumber(group.limit) or nil
  if limit and limit < #children then
    return false, L["Blizzard cannot limit the whole group, so its Limit must be at least its number of auras."]
  end
  local first, clones
  for _, id in ipairs(children) do
    local child = EverythingAuras.GetData(id)
    if type(child) ~= "table" then
      return false, L["The group has no auras."]
    end
    if not child.eaNative then
      return false, L["Every aura in the group needs its Blizzard Draws switch on, such as Blizzard Draws This Icon."]
    end
    local ok, reason = Check(child, true)
    if not ok then
      return false, child.id .. ": " .. reason
    end
    first = first or child
    if child.regionType ~= first.regionType or child.width ~= first.width or child.height ~= first.height then
      return false, L["Every aura in the group must be the same kind and size."]
    end
    if UnitOf(child.triggers[1].trigger) ~= UnitOf(first.triggers[1].trigger) then
      return false, L["Every aura in the group must watch the same unit."]
    end
    clones = clones or child.triggers[1].trigger.showClones
  end
  if limit and clones and #children > 1 then
    return false, L["Blizzard limits each aura's list, not the whole group, so a group with a Limit may hold an Auto-Clone aura only as its one aura."]
  end
  return true
end

-- Anything Blizzard's slot cannot match exactly would make its icon and the trigger disagree (probes N1, N8).
function Private.EANativeQualifies(data)
  local direct = true
  for parent in Private.TraverseParents(data) do
    if parent.regionType == "dynamicgroup" then
      if not direct then
        return false, L["Not available in a group inside a dynamic group."]
      end
      local ok, reason = Check(data, true)
      if not ok then
        return false, reason
      end
      return GroupQualifies(parent)
    end
    direct = false
  end
  return Check(data, false)
end

function Private.EANativeWanted(data)
  return data.eaNative and Private.EANativeQualifies(data) or false
end

-- A duration bar's direction is set once, when it is handed to Blizzard, so each direction keeps its own buttons.
local function Variant(data)
  local kind = REGION_KINDS[data.regionType] or "icon"
  local direction = data.inverse and "elapsed" or "remaining"
  if kind == "bar" then
    return direction
  elseif kind == "progress" then
    return (IsRound(data) and "circle-" or "fill-") .. direction
  elseif kind == "text" then
    return "text-" .. (TextParts(data.displayText) or "p")
  end
  return kind
end

local function AddId(ids, value)
  local id = tonumber(value)
  if id and id > 0 then
    ids[id] = true
    return true
  end
end

-- A slot with no spell IDs shows any aura of its kind (probe N0), so it is never built without them.
local function SpellIds(data)
  local trigger = data.triggers[1].trigger
  local ids = {}
  if trigger.useExactSpellId and type(trigger.auraspellids) == "table" then
    for _, value in ipairs(trigger.auraspellids) do
      AddId(ids, value)
    end
  end
  if trigger.useName and type(trigger.auranames) == "table" then
    for _, name in ipairs(trigger.auranames) do
      if not AddId(ids, name) and type(name) == "string" and name ~= "" then
        local info = C_Spell.GetSpellInfo(name)
        if info and info.spellID then
          AddId(ids, info.spellID)
        end
      end
    end
    for _, list in pairs({ stored = data.eaNativeIds, ranks = trigger.auraRankSpellIDs }) do
      if type(list) == "table" then
        for _, value in ipairs(list) do
          AddId(ids, value)
        end
      end
    end
  end
  -- The slot only ever matches the IDs listed here, so leaving one out ignores it exactly.
  if MatchCheck(trigger) and trigger.useIgnoreExactSpellId and type(trigger.ignoreAuraSpellids) == "table" then
    for _, value in ipairs(trigger.ignoreAuraSpellids) do
      local id = tonumber(value)
      if id then
        ids[id] = nil
      end
    end
  end
  return ids
end

-- A name gives only its cast's ID, and a buff often carries another, so Blizzard waits for an ID known to be the aura's.
local function KnownIds(data)
  local trigger = data.triggers[1].trigger
  if trigger.useExactSpellId and type(trigger.auraspellids) == "table" then
    for _, value in ipairs(trigger.auraspellids) do
      if tonumber(value) then
        return true
      end
    end
  end
  for _, list in ipairs({ data.eaNativeIds or false, trigger.auraRankSpellIDs or false }) do
    for _, value in ipairs(type(list) == "table" and list or {}) do
      if tonumber(value) then
        return true
      end
    end
  end
  return false
end

local function HasId(list, id)
  for _, value in ipairs(type(list) == "table" and list or {}) do
    if tonumber(value) == id then
      return true
    end
  end
  return false
end

local function Key(ids)
  local list = {}
  for id in pairs(ids) do
    list[#list + 1] = id
  end
  table.sort(list)
  return table.concat(list, ",")
end

local function CandidateFilters(trigger, ids)
  local any = AnyAura(trigger)
  if not MatchCheck(trigger) then
    return { includeSpellIDs = not any and ids or nil }
  end
  local filters = { includeSpellIDs = not any and ids or nil, maxDuration = (TotalLimit(trigger)),
    includeDispelTypes = (DispelTypes(trigger)) }
  if any and trigger.useIgnoreExactSpellId and type(trigger.ignoreAuraSpellids) == "table" then
    local excluded = {}
    for _, value in ipairs(trigger.ignoreAuraSpellids) do
      AddId(excluded, value)
    end
    filters.excludeSpellIDs = next(excluded) and excluded or nil
  end
  for _, pair in ipairs(TRISTATE_FILTERS) do
    if trigger[pair[1]] ~= nil then
      filters[pair[2]] = trigger[pair[1]] and true or false
    end
  end
  return filters
end

local function FiltersKey(filters)
  local parts = { filters.includeSpellIDs and Key(filters.includeSpellIDs) or "*", tostring(filters.maxDuration),
    filters.includeDispelTypes and Key(filters.includeDispelTypes) or "-",
    filters.excludeSpellIDs and Key(filters.excludeSpellIDs) or "-" }
  for _, pair in ipairs(TRISTATE_FILTERS) do
    parts[#parts + 1] = tostring(filters[pair[2]])
  end
  return table.concat(parts, ";")
end

local function Filter(trigger)
  local filter = trigger.debuffType or "HELPFUL"
  if trigger.ownOnly == true then
    return filter .. "|PLAYER"
  elseif trigger.ownOnly == false then
    return filter .. "|!PLAYER"
  end
  return filter
end

local function SubText(region, format)
  for _, subRegion in ipairs(region.subRegions or {}) do
    if subRegion.type == "subtext" and subRegion.text_text == format and subRegion.text then
      return subRegion
    end
  end
end

-- Texts, glows and borders stack like the aura's own sub-regions, whose levels ApplyFrameLevel sets by their place.
local function LevelOffset(sub, region)
  local own, base = sub:GetFrameLevel(), region:GetFrameLevel()
  return math.max(1, (tonumber(own) or 0) - (tonumber(base) or 0))
end

local function FirstTextOffset(region)
  for _, subRegion in ipairs(region.subRegions or {}) do
    for _, takeover in ipairs(TAKEOVERS) do
      if subRegion.type == "subtext" and subRegion.text_text == takeover.format then
        return LevelOffset(subRegion, region)
      end
    end
  end
end

-- Conditions name a text by its place in the settings, which the region skips for a type this client lacks.
local function TimerIndex(data)
  for index, settings in ipairs(type(data.subRegions) == "table" and data.subRegions or {}) do
    if type(settings) == "table" and settings.type == "subtext" and settings.text_text == "%p" then
      return index, settings
    end
  end
end

local function CeilFormatter(precision, threshold)
  local up, down = Enum.NumericRuleFormatRounding.Up, Enum.NumericRuleFormatRounding.Down
  local breakpoints = { { threshold = 0, format = "" } }
  if threshold > 0 then
    breakpoints[#breakpoints + 1] = { threshold = MIN_POSITIVE, format = "%." .. precision .. "f" }
  end
  -- The aura's own text rounds whole seconds up (Types.lua time formatter 99), while "%d" alone truncates (probe 073).
  breakpoints[#breakpoints + 1] = { threshold = threshold > 0 and threshold or MIN_POSITIVE, step = 1, rounding = up,
    format = "%d" }
  breakpoints[#breakpoints + 1] = { threshold = 60.000001, step = 1, rounding = up, format = "%i:%02i",
    components = { { div = 60, step = 1, rounding = down }, { mod = 60, step = 1, rounding = down } } }
  local formatter = C_StringUtil.CreateNumericRuleFormatter()
  formatter:SetBreakpoints(breakpoints)
  return formatter
end

local formatters = {}
-- Blizzard formats the timer itself, so it gets a formatter built from the aura's own %p settings (Types.lua timed).
local function TimeFormatter(settings, prefix)
  if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Private.GetTimeFormatter) then
    return nil, "default"
  end
  prefix = prefix or "text_text_format_p_"
  local kind = settings[prefix .. "format"]
  if kind ~= nil and kind ~= "timed" then
    return nil, "default"
  end
  local format = tonumber(settings[prefix .. "time_format"]) or 0
  local threshold = math.min(tonumber(settings[prefix .. "time_dynamic_threshold"]) or 60, 60)
  local precision = tonumber(settings[prefix .. "time_precision"]) or 1
  local floor = settings[prefix .. "time_legacy_floor"] and true or false
  if kind == nil then
    -- An unformatted %p falls back to the built-in format with decimals under a minute (Prototypes.lua dynamic_texts p).
    format, threshold, precision, floor = 0, 60, 1, true
  end
  local key = table.concat({ format, threshold, precision, tostring(floor) }, ":")
  if formatters[key] == nil then
    if format ~= 0 or floor then
      formatters[key] = Private.GetTimeFormatter(format, precision, threshold)
    else
      formatters[key] = CeilFormatter(precision, threshold)
    end
  end
  return formatters[key], key
end

-- Blizzard's stack count shows 2 and up unless given a format, and the aura's own %s shows 1 and up, blank at 0.
local function CountFormatter(before, after)
  local key = "count:" .. before .. "%d" .. after
  if formatters[key] == nil and C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    formatter:SetBreakpoints({ { threshold = 0, format = before .. after },
      { threshold = MIN_POSITIVE, format = before .. "%d" .. after } })
    formatters[key] = formatter
  end
  return formatters[key], key
end

-- A color curve reads nothing but the time left, so only Remaining Time tests can become one.
local function TimerSteps(data, colorProperty, visibleProperty)
  local steps = {}
  for _, condition in ipairs(type(data.conditions) == "table" and data.conditions or {}) do
    local check = type(condition) == "table" and condition.check
    local test = type(check) == "table" and check.trigger == 1 and check.variable == "expirationTime"
      and check.checks == nil and RT_TESTS[check.op]
    local at = test and tonumber(check.value)
    if at then
      local step = { test = test, at = at, op = check.op }
      for _, change in ipairs(type(condition.changes) == "table" and condition.changes or {}) do
        if type(change) == "table" and change.property == colorProperty and type(change.value) == "table" then
          step.color = change.value
        elseif type(change) == "table" and visibleProperty and change.property == visibleProperty then
          step.visible = change.value and true or false
        end
      end
      if step.color or step.visible ~= nil then
        steps[#steps + 1] = step
      end
    end
  end
  return steps
end

local function StepAt(steps, value, base, baseVisible)
  local color, visible = base, baseVisible
  for _, step in ipairs(steps) do
    if step.test(value, step.at) then
      color = step.color or color
      if step.visible ~= nil then
        visible = step.visible
      end
    end
  end
  return color, visible
end

-- Later conditions in the aura's own list win, so each stretch of time left takes the last step that covers it.
local function TimerPoints(steps, base, baseVisible)
  local starts, seen = { 0 }, { [0] = true }
  for _, step in ipairs(steps) do
    if step.at > 0 and not seen[step.at] then
      seen[step.at] = true
      starts[#starts + 1] = step.at
    end
  end
  table.sort(starts)
  local points, parts = {}, {}
  for i, start in ipairs(starts) do
    local stop = starts[i + 1]
    local color, visible = StepAt(steps, stop and (start + stop) / 2 or start + 1, base, baseVisible)
    local alpha = visible and (color[4] or 1) or 0
    points[#points + 1] = { start, color[1] or 1, color[2] or 1, color[3] or 1, alpha }
    parts[#parts + 1] = string.format("%s=%s,%s,%s,%s", start, color[1] or 1, color[2] or 1, color[3] or 1, alpha)
  end
  return points, table.concat(parts, ";")
end

local function TimerCurve(points)
  local curve = C_CurveUtil.CreateColorCurve()
  curve:SetType(Enum.LuaCurveType.Step)
  for _, point in ipairs(points) do
    curve:AddPoint(point[1], CreateColor(point[2], point[3], point[4], point[5]))
  end
  return curve
end

local function StyleCooldown(cooldown, data)
  cooldown:SetAlpha(data.cooldown and 1 or 0)
  cooldown:SetDrawSwipe(data.cooldownSwipe ~= false)
  cooldown:SetDrawEdge(data.cooldownEdge and true or false)
  cooldown:SetHideCountdownNumbers(data.cooldownTextDisabled and true or false)
  -- Icon.lua's UpdateEffectiveInverse for an aura state, which carries no inverse of its own.
  cooldown:SetReverse(not data.inverse)
end

local function NewText(overlay, button)
  local text = overlay:CreateFontString(nil, "OVERLAY")
  text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
  text:SetPoint("CENTER", button, "CENTER")
  text:SetAlpha(0)
  return text
end

local CORNERS = { TOPLEFT = { 0, 1 }, TOPRIGHT = { 1, 1 }, BOTTOMRIGHT = { 1, 0 }, BOTTOMLEFT = { 0, 0 } }

local function Edges(w, h, order)
  local edges = {}
  for i, from in ipairs(order) do
    local to = order[i % #order + 1]
    local dx, dy = CORNERS[to][1] - CORNERS[from][1], CORNERS[to][2] - CORNERS[from][2]
    edges[i] = { len = dx ~= 0 and w or h, point = from, dx = dx, dy = dy,
      start = dx == 1 and "LEFT" or dx == -1 and "RIGHT" or dy == 1 and "BOTTOM" or "TOP",
      stop = dx == 1 and "RIGHT" or dx == -1 and "LEFT" or dy == 1 and "TOP" or "BOTTOM" }
  end
  return edges
end

-- Blizzard's button runs no addon scripts, so a moving glow is looping animation pieces, one texture per piece.
local function Mover(host, period)
  local group = host:CreateAnimationGroup()
  group:SetLooping("REPEAT")
  local keep = host:CreateTexture(nil, "BACKGROUND")
  keep:SetSize(1, 1)
  keep:SetPoint("CENTER")
  keep:SetAlpha(0)
  local length = group:CreateAnimation("Alpha")
  length:SetTarget(keep)
  length:SetFromAlpha(0)
  length:SetToAlpha(0)
  length:SetDuration(period)
  local mover = { group = group }
  function mover.Piece(texture, t0, duration, alpha, effect)
    duration = math.max(duration, 0.001)
    local on = group:CreateAnimation("Alpha")
    on:SetTarget(texture)
    on:SetFromAlpha(alpha)
    on:SetToAlpha(alpha)
    on:SetStartDelay(t0)
    on:SetDuration(duration)
    if t0 + duration < period - 0.002 then
      local off = group:CreateAnimation("Alpha")
      off:SetTarget(texture)
      off:SetFromAlpha(0)
      off:SetToAlpha(0)
      off:SetStartDelay(t0 + duration)
      off:SetDuration(0.001)
    end
    if effect.dx then
      local move = group:CreateAnimation("Translation")
      move:SetTarget(texture)
      move:SetOffset(effect.dx, effect.dy)
      move:SetStartDelay(t0)
      move:SetDuration(duration)
    end
    if effect.origin then
      local scale = group:CreateAnimation("Scale")
      scale:SetTarget(texture)
      scale:SetOrigin(effect.origin, 0, 0)
      scale:SetScaleFrom(effect.x0, effect.y0)
      scale:SetScaleTo(effect.x1, effect.y1)
      scale:SetStartDelay(t0)
      scale:SetDuration(duration)
    end
  end
  function mover.Span(f0, df, emit)
    local t0, duration = (f0 % 1) * period, df * period
    if t0 + duration <= period + 0.0005 then
      emit(t0, duration, 0, 1)
    else
      local split = period - t0
      emit(t0, split, 0, split / duration)
      emit(0, duration - split, split / duration, 1)
    end
  end
  return mover
end

local GLOW_YELLOW = { 0.95, 0.95, 0.32, 1 }

-- A line turning a corner is on two edges at once, so each edge has its own grow, slide and shrink pieces.
local function PixelGlow(host, w, h, sub, color)
  color = color or GLOW_YELLOW
  local count = tonumber(sub.glowLines) or 8
  count = count > 0 and count or 8
  local frequency = tonumber(sub.glowFrequency) or 0.25
  local period = frequency ~= 0 and math.abs(1 / frequency) or 4
  local length = math.min(tonumber(sub.glowLength) or math.floor((w + h) * (2 / count - 0.1)), w, h)
  local thickness = tonumber(sub.glowThickness) or 1
  if sub.glowBorder ~= false then
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
      { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
      local ring = host:CreateTexture(nil, "ARTWORK")
      ring:SetColorTexture(0.1, 0.1, 0.1, 0.8)
      ring:SetPoint(side[1])
      ring:SetPoint(side[2])
      if side[3] then ring:SetHeight(thickness + 1) else ring:SetWidth(thickness + 1) end
    end
  end
  local mover = Mover(host, period)
  local perimeter = 2 * (w + h)
  local edges = Edges(w, h, frequency < 0 and { "TOPLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "TOPRIGHT" }
    or { "TOPLEFT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMLEFT" })
  local function Line(edge, at)
    local texture = host:CreateTexture(nil, "OVERLAY")
    texture:SetColorTexture(color[1] or 1, color[2] or 1, color[3] or 1, 1)
    if edge.dx ~= 0 then texture:SetSize(length, thickness) else texture:SetSize(thickness, length) end
    texture:SetPoint(edge.point, host, edge.point, edge.dx * at, edge.dy * at)
    texture:SetAlpha(0)
    return texture
  end
  local function Scaled(edge, origin, from, to)
    from, to = math.max(from, 0.001), math.max(to, 0.001)
    if edge.dx ~= 0 then
      return { origin = origin, x0 = from, y0 = 1, x1 = to, y1 = 1 }
    end
    return { origin = origin, x0 = 1, y0 = from, x1 = 1, y1 = to }
  end
  local alpha = color[4] or 1
  for line = 1, count do
    local phase = (line - 1) / count
    local e0 = 0
    for _, edge in ipairs(edges) do
      local slide = edge.len - length
      mover.Span((e0 - length) / perimeter - phase, length / perimeter, function(t0, duration, a, z)
        mover.Piece(Line(edge, 0), t0, duration, alpha, Scaled(edge, edge.start, a, z))
      end)
      if slide > 0 then
        mover.Span(e0 / perimeter - phase, slide / perimeter, function(t0, duration, a, z)
          mover.Piece(Line(edge, slide * a), t0, duration, alpha,
            { dx = edge.dx * slide * (z - a), dy = edge.dy * slide * (z - a) })
        end)
      end
      mover.Span((e0 + slide) / perimeter - phase, length / perimeter, function(t0, duration, a, z)
        mover.Piece(Line(edge, slide), t0, duration, alpha, Scaled(edge, edge.stop, 1 - a, 1 - z))
      end)
      e0 = e0 + edge.len
    end
  end
  return { mover.group }
end

local function ShineGlow(host, w, h, sub, color)
  color = color or GLOW_YELLOW
  local count = tonumber(sub.glowLines) or 4
  count = count > 0 and count or 4
  local frequency = tonumber(sub.glowFrequency) or 0.125
  local period = frequency ~= 0 and math.abs(1 / frequency) or 8
  local scale = tonumber(sub.glowScale) or 1
  local retail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
  local perimeter = 2 * (w + h)
  local edges = Edges(w, h, frequency < 0 and { "BOTTOMLEFT", "BOTTOMRIGHT", "TOPRIGHT", "TOPLEFT" }
    or { "BOTTOMLEFT", "TOPLEFT", "TOPRIGHT", "BOTTOMRIGHT" })
  local rings = {}
  for ring, size in ipairs({ 7, 6, 5, 4 }) do
    local mover = Mover(host, period * ring)
    for spark = 1, count do
      local e0 = 0
      for _, edge in ipairs(edges) do
        local len = edge.len
        mover.Span(e0 / perimeter - spark / count, len / perimeter, function(t0, duration, a, z)
          local texture = host:CreateTexture(nil, "OVERLAY")
          if retail then
            texture:SetTexture("Interface\\Artifacts\\Artifacts")
            texture:SetTexCoord(0.8115234375, 0.9169921875, 0.8798828125, 0.9853515625)
          else
            texture:SetTexture("Interface\\ItemSocketingFrame\\UI-ItemSockets")
            texture:SetTexCoord(0.3984375, 0.4453125, 0.40234375, 0.44921875)
            texture:SetBlendMode("ADD")
          end
          texture:SetDesaturated(true)
          texture:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
          texture:SetSize(size * scale, size * scale)
          texture:SetPoint("CENTER", host, edge.point, edge.dx * len * a, edge.dy * len * a)
          texture:SetAlpha(0)
          mover.Piece(texture, t0, duration, 1, { dx = edge.dx * len * (z - a), dy = edge.dy * len * (z - a) })
        end)
        e0 = e0 + len
      end
    end
    rings[ring] = mover.group
  end
  return rings
end

local function FlipBook(group, texture, duration, rows, columns, frames, frameSize, alpha)
  local shown = group:CreateAnimation("Alpha")
  shown:SetTarget(texture)
  shown:SetFromAlpha(alpha)
  shown:SetToAlpha(alpha)
  shown:SetDuration(duration)
  local book = group:CreateAnimation("FlipBook")
  book:SetTarget(texture)
  book:SetDuration(duration)
  book:SetFlipBookRows(rows)
  book:SetFlipBookColumns(columns)
  book:SetFlipBookFrames(frames)
  book:SetFlipBookFrameWidth(frameSize)
  book:SetFlipBookFrameHeight(frameSize)
end

local function Tint(texture, color)
  if color then
    texture:SetDesaturated(true)
    texture:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
  end
end

local function ButtonGlow(host, w, h, sub, color)
  local alpha = color and color[4] or 1
  local outer = host:CreateTexture(nil, "OVERLAY")
  outer:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
  outer:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
  outer:SetAllPoints(host)
  Tint(outer, color)
  outer:SetAlpha(alpha)
  local ants = host:CreateTexture(nil, "OVERLAY", nil, 1)
  ants:SetTexture("Interface\\SpellActivationOverlay\\IconAlertAnts")
  ants:SetSize(w * 0.85, h * 0.85)
  ants:SetPoint("CENTER")
  Tint(ants, color)
  ants:SetAlpha(0)
  local frequency = tonumber(sub.glowFrequency) or 0
  local group = host:CreateAnimationGroup()
  group:SetLooping("REPEAT")
  -- The ants sheet holds 22 frames of 48 pixels (ActionButton's AnimateTexCoords), timed by the glow's frequency.
  FlipBook(group, ants, frequency > 0 and 0.15 / frequency or 0.6, 5, 5, 22, 48, alpha)
  return { group }
end

local function ProcGlow(host, w, h, sub, color)
  local list = {}
  local loop = host:CreateTexture(nil, "OVERLAY")
  loop:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook")
  loop:SetAllPoints(host)
  Tint(loop, color)
  loop:SetAlpha(0)
  local looping = host:CreateAnimationGroup()
  looping:SetLooping("REPEAT")
  FlipBook(looping, loop, tonumber(sub.glowDuration) or 1, 6, 5, 30, 0, color and color[4] or 1)
  list[1] = looping
  if sub.glowStartAnim then
    local start = host:CreateTexture(nil, "OVERLAY", nil, 1)
    start:SetBlendMode("ADD")
    start:SetAtlas("UI-HUD-ActionBar-Proc-Start-Flipbook")
    -- The start burst's size against its 42 pixel button (LibCustomGlow, from ActionButtonTemplate.xml).
    start:SetSize(w / 42 * 150 / 1.4, h / 42 * 150 / 1.4)
    start:SetPoint("CENTER")
    Tint(start, color)
    start:SetAlpha(0)
    local burst = host:CreateAnimationGroup()
    FlipBook(burst, start, 0.7, 6, 5, 30, 0, color and color[4] or 1)
    list[2] = burst
  end
  return list
end

local GLOW_BUILDERS = { Pixel = PixelGlow, ACShine = ShineGlow, buttonOverlay = ButtonGlow, Proc = ProcGlow }

local function Strips(host, size)
  local strips = {}
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
    { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
    local strip = host:CreateTexture(nil, "OVERLAY")
    strip:SetPoint(side[1])
    strip:SetPoint(side[2])
    if side[3] then strip:SetHeight(size) else strip:SetWidth(size) end
    strips[#strips + 1] = strip
  end
  return strips
end

local function ColorText(color)
  color = type(color) == "table" and color or {}
  return string.format("%s,%s,%s,%s", color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
end

local LOOK_FIELDS = { "glowType", "useGlowColor", "glowLines", "glowFrequency", "glowDuration", "glowLength",
  "glowThickness", "glowScale", "glowBorder", "glowXOffset", "glowYOffset", "glowStartAnim", "border_size" }

local function LookParts(data, region)
  local list = {}
  for index, settings in ipairs(type(data.subRegions) == "table" and data.subRegions or {}) do
    local live = region.subRegions and region.subRegions[index]
    local kind = live and type(settings) == "table" and live.type == settings.type
      and (settings.type == "subglow" and GlowKind(data, index) or settings.type == "subborder" and BorderKind(data, index))
      or nil
    if kind == "blizzard" or kind == "plain" or kind == "dispel" then
      list[#list + 1] = { index = index, settings = settings, live = live, kind = kind }
    end
  end
  return list
end

local function Measure(source, region)
  local left, bottom, right, top = source:GetLeft(), source:GetBottom(), source:GetRight(), source:GetTop()
  local regionLeft, regionBottom = region:GetLeft(), region:GetBottom()
  if left and bottom and right and top and regionLeft and regionBottom then
    return left - regionLeft, bottom - regionBottom, right - left, top - bottom
  end
end

local function ParkKit(button, kit)
  for _, group in ipairs(kit.groups) do
    pcall(group.Stop, group)
    pcall(button.RemoveAuraShownAnimation, button, group)
  end
  for _, strip in ipairs(kit.dispel) do
    pcall(button.RemoveDispelTypeTexture, button, strip)
  end
  kit.host:Hide()
end

local function UseKit(button, kit)
  kit.host:Show()
  for _, group in ipairs(kit.groups) do
    button:AddAuraShownAnimation(group)
    -- Blizzard starts these only when the aura appears, and it may already be showing.
    if not Secret() then
      pcall(group.Play, group)
    end
  end
  for _, strip in ipairs(kit.dispel) do
    button:AddDispelTypeTexture(strip, kit.options)
  end
end

-- Frames cannot be destroyed, so a kit put aside is kept by its size and look and used again when both come back.
local function LookKey(data, part)
  local settings = part.settings
  local color = settings.useGlowColor and type(settings.glowColor) == "table" and settings.glowColor or nil
  local parts = { part.kind, ColorText(color), ColorText(settings.border_color) }
  for _, field in ipairs(LOOK_FIELDS) do
    parts[#parts + 1] = tostring(settings[field])
  end
  local colors = part.kind == "dispel" and DispelColors(data, part.index)
  local entries = {}
  for name, value in pairs(colors or {}) do
    entries[#entries + 1] = name .. "=" .. ColorText(value)
  end
  table.sort(entries)
  for _, entry in ipairs(entries) do
    parts[#parts + 1] = entry
  end
  return table.concat(parts, ";"), colors
end

local function BuildKit(record, data, region, part)
  local settings, button = part.settings, record.button
  local x, y, w, h = Measure(part.live, region)
  if not x then
    x, y, w, h = 0, 0, tonumber(data.width) or 32, tonumber(data.height) or 32
  end
  local glowType = settings.glowType or "buttonOverlay"
  local color = settings.useGlowColor and type(settings.glowColor) == "table" and settings.glowColor or nil
  local glow = part.kind == "blizzard"
  local ex, ey, right, top = 0, 0, 0, 0
  local geometry
  if glow then
    local xo, yo = tonumber(settings.glowXOffset) or 0, tonumber(settings.glowYOffset) or 0
    if glowType == "buttonOverlay" then
      ex, ey = w * 0.2, h * 0.2
    elseif glowType == "Proc" then
      ex, ey = xo + w * 0.2, yo + h * 0.2
    else
      ex, ey = xo, yo
    end
    geometry = string.format("%.1f:%.1f:%.1f:%.1f", x, y, w, h)
  else
    local regionWidth, regionHeight = region:GetWidth(), region:GetHeight()
    right, top = x + w - (tonumber(regionWidth) or w), y + h - (tonumber(regionHeight) or h)
    geometry = string.format("%.1f:%.1f:%.1f:%.1f", x, y, right, top)
  end
  local look, colors = LookKey(data, part)
  local key = geometry .. ";" .. look
  local current = record.kits[part.index]
  if current and current.key == key then
    return current
  end
  if current then
    ParkKit(button, current)
  end
  record.kitCache = record.kitCache or {}
  local cache = record.kitCache[part.index] or {}
  record.kitCache[part.index] = cache
  local kit = cache[key]
  if not kit then
    local host = CreateFrame("Frame", nil, button)
    kit = { key = key, look = look, host = host, groups = {}, dispel = {} }
    if glow then
      host:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", x - ex, y - ey)
      host:SetSize(w + 2 * ex, h + 2 * ey)
      kit.groups = GLOW_BUILDERS[glowType](host, w + 2 * ex, h + 2 * ey, settings, color)
    else
      -- Held by two corners, a border follows the aura's size by itself.
      host:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", x, y)
      host:SetPoint("TOPRIGHT", button, "TOPRIGHT", right, top)
      local strips = Strips(host, tonumber(settings.border_size) or 2)
      if part.kind == "plain" then
        local border = type(settings.border_color) == "table" and settings.border_color or {}
        for _, strip in ipairs(strips) do
          strip:SetColorTexture(border[1] or 1, border[2] or 1, border[3] or 1, border[4] or 1)
        end
      else
        local map = {}
        for name, value in pairs(colors) do
          map[name] = CreateColor(value[1] or 1, value[2] or 1, value[3] or 1, value[4] or 1)
        end
        -- PreserveAsset keeps the strip's texture and colors it by the aura's dispel type, buffs too (probe 073).
        kit.options = { style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset, showWhenHarmful = true,
          showWhenHelpful = true, showWithoutDispelType = true, customDispelColorMap = map }
        for _, strip in ipairs(strips) do
          strip:SetTexture(SQUARE)
        end
        kit.dispel = strips
      end
    end
    cache[key] = kit
  end
  UseKit(button, kit)
  return kit
end

-- The aura's own copy hides while Blizzard draws, by alpha, because its glow and border show themselves again.
local function DimLooks(owner, drawn)
  for _, frame in pairs(owner.dimmed or {}) do
    frame:SetAlpha(drawn and 0 or 1)
  end
end

local function Animated(region)
  return math.abs(tonumber(region.scalex) or 1) ~= 1 or math.abs(tonumber(region.scaley) or 1) ~= 1
end

local function SizeKey(region)
  local width, height = region:GetWidth(), region:GetHeight()
  return string.format("%.1fx%.1f", tonumber(width) or 0, tonumber(height) or 0)
end

-- While the kits cannot be rebuilt, the aura's own glow or border stays wherever Blizzard has none with its look.
local function DimMatching(owner, kits, data, region)
  for _, part in ipairs(LookParts(data, region)) do
    local kit = kits and kits[part.index]
    if kit and kit.look == LookKey(data, part) then
      owner.dimmed[part.index] = part.live
    end
  end
end

local function StyleLooks(record, data, region, level)
  local owner = record.member or record
  record.kits = record.kits or {}
  record.lookSize = SizeKey(region)
  -- A scale animation resizes the aura every frame, so meanwhile its kits keep the size they were built at.
  local animated = Animated(region)
  local wanted, dimmed = {}, {}
  for _, part in ipairs(LookParts(data, region)) do
    local kit = record.kits[part.index]
    if not (animated and kit and kit.look == LookKey(data, part)) then
      kit = BuildKit(record, data, region, part)
      record.kits[part.index] = kit
    end
    kit.host:SetFrameLevel(level + LevelOffset(part.live, region))
    wanted[part.index] = true
    dimmed[part.index] = part.live
  end
  for index, kit in pairs(record.kits) do
    if not wanted[index] then
      ParkKit(record.button, kit)
      record.kits[index] = nil
    end
  end
  for index, frame in pairs(owner.dimmed or {}) do
    if dimmed[index] ~= frame then
      frame:SetAlpha(1)
    end
  end
  owner.dimmed = dimmed
  DimLooks(owner, owner.drawn)
end

local textOwners = setmetatable({}, { __mode = "k" })
local hookedTexts = setmetatable({}, { __mode = "k" })

local function Remaining(region)
  local state = region and region.state
  local expiration = state and state.progressType == "timed" and state.expirationTime
  if type(expiration) ~= "number" or issecretvalue(expiration) then
    return nil
  end
  return expiration - GetTime()
end

local StyleTimer, StyleText

-- An outline widens every FontString by the same amount, so two joined pieces sit that much further apart than one text (probe FW).
local function OutlinePad(piece)
  piece:SetText("l")
  local one = piece:GetStringWidth()
  piece:SetText("ll")
  local pad = 2 * (tonumber(one) or 0) - (tonumber(piece:GetStringWidth()) or 0)
  return pad > 0 and pad or 0
end

-- Blizzard's copy cannot see the aura's conditions, so their colors reach it through the aura's own text, out of combat only.
local function OnTextColor(text, r, g, b, a)
  local owner = textOwners[text]
  local record = owner and owner.record
  if not record or Secret() or record.hidden[owner.key] ~= text then
    return
  end
  local region, data = record.region, record.data
  local main = owner.key == "main"
  if region and data and (owner.key == "timer" or main and record.variant == "text-p") then
    local index = not main and TimerIndex(data)
    local steps = main and TimerSteps(data, "color")
      or index and TimerSteps(data, "sub." .. index .. ".text_color", "sub." .. index .. ".text_visible") or {}
    if #steps > 0 then
      local remaining = Remaining(region)
      if not remaining then
        return
      end
      for _, step in ipairs(steps) do
        if step.color and step.test(remaining, step.at) then
          return
        end
      end
      local base, old = { r or 1, g or 1, b or 1, a or 1 }, record.timerBase
      if old and old[1] == base[1] and old[2] == base[2] and old[3] == base[3] and old[4] == base[4] then
        return
      end
      record.timerBase = base
      for _, target in ipairs(record.parts or { record }) do
        if target.button then
          (main and StyleText or StyleTimer)(target, data, region)
        end
      end
      return
    end
  end
  local hidden = owner.sub and not owner.sub:IsShown()
  for _, target in ipairs(record.parts or { record }) do
    for _, widget in pairs(main and target.pieces or { target.texts and target.texts[owner.key] }) do
      widget:SetTextColor(r or 1, g or 1, b or 1, a or 1)
      -- Should a text's color alpha reach it, a text its settings hide must still stay hidden.
      if hidden then
        widget:SetAlpha(0)
      end
    end
  end
end

local hookedSubs = setmetatable({}, { __mode = "k" })

-- Blizzard's copy cannot see Show Text or a condition either, so visibility reaches it the same way, out of combat only.
local function OnTextVisible(sub, visible)
  local owner = sub.text and textOwners[sub.text]
  local record = owner and owner.record
  if not record or Secret() or record.hidden[owner.key] ~= sub.text then
    return
  end
  local region, data = record.region, record.data
  if owner.key == "timer" and region and data then
    local index = TimerIndex(data)
    local steps = index and TimerSteps(data, "sub." .. index .. ".text_color", "sub." .. index .. ".text_visible") or {}
    if #steps > 0 then
      local remaining = Remaining(region)
      if not remaining then
        return
      end
      for _, step in ipairs(steps) do
        if step.visible ~= nil and step.test(remaining, step.at) then
          return
        end
      end
      if record.timerVisible == visible then
        return
      end
      record.timerVisible = visible
      for _, target in ipairs(record.parts or { record }) do
        if target.button then
          StyleTimer(target, data, region)
        end
      end
      return
    end
  end
  for _, target in ipairs(record.parts or { record }) do
    local widget = target.texts and target.texts[owner.key]
    if widget then
      widget:SetAlpha(visible and 1 or 0)
    end
  end
end

function StyleTimer(record, data, region)
  local timer = record.texts and record.texts.timer
  if not timer then
    return
  end
  local index, settings = TimerIndex(data)
  settings = settings or {}
  local formatter, formatKey = TimeFormatter(settings)
  local steps = index and TimerSteps(data, "sub." .. index .. ".text_color", "sub." .. index .. ".text_visible") or {}
  local points, curveKey
  if #steps > 0 and C_CurveUtil and CreateColor then
    local owner = record.member or record
    local base = owner.timerBase or type(settings.text_color) == "table" and settings.text_color or { 1, 1, 1, 1 }
    local visible = owner.timerVisible
    if visible == nil then
      visible = settings.text_visible ~= false
    end
    points, curveKey = TimerPoints(steps, base, visible)
    -- The curve hides the timer itself, so the text stays visible.
    timer:SetAlpha(1)
  end
  local key = tostring(formatKey) .. "|" .. tostring(curveKey)
  if record.timerKey == key then
    return
  end
  local property = Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration
  local options = {}
  if formatter and property then
    options.textFormat = { formatString = "{}", components = { { property = property, formatter = formatter } } }
  end
  if points and property then
    options.textColor = { curve = TimerCurve(points), property = property }
  end
  record.button:SetDurationText(timer, options)
  record.timerKey = key
end

local function StyleTexture(record, data, region)
  local source, art = region.texture and region.texture.texture, record.art
  if not (source and art) then
    return
  end
  local atlas = source:GetAtlas()
  if atlas then
    art:SetAtlas(atlas)
  else
    local file = source:GetTexture()
    if file and not issecretvalue(file) then
      art:SetTexture(file, data.textureWrapMode, data.textureWrapMode)
    end
  end
  art:SetTexCoord(source:GetTexCoord())
  art:SetVertexColor(source:GetVertexColor())
  art:SetDesaturation(source:GetDesaturation())
  art:SetBlendMode(source:GetBlendMode())
end

local VERTICES = { { UPPER_LEFT_VERTEX or 1, 0, 0 }, { LOWER_LEFT_VERTEX or 2, 0, 1 }, { UPPER_RIGHT_VERTEX or 3, 1, 0 },
  { LOWER_RIGHT_VERTEX or 4, 1, 1 } }

-- The point transform the aura's own progress texture uses (TextureCoords.lua TransformPoint), angles in degrees.
local function TransformPoint(x, y, cropX, cropY, rotation, mirror, userX, userY)
  x, y = (x - 0.5) * 1.4142 / cropX, (y - 0.5) * 1.4142 / cropY
  if mirror then
    x = -x
  end
  local cosine, sine = math.cos(math.rad(rotation)), math.sin(math.rad(rotation))
  x, y = cosine * x - sine * y, sine * x + cosine * y
  return x + 0.5 + userX, y + 0.5 + userY
end

-- The radial fill shares the texture's coordinates, so a circle keeps them whole and moves its corners (UpdateSecretTexCoords).
local function Round(texture, file, w, h, look)
  Private.SetTextureOrAtlas(texture, file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  texture:SetTexCoord(0, 1, 0, 1)
  local cosine, sine = math.cos(math.rad(look.rotation)), math.sin(math.rad(look.rotation))
  local scaleX, scaleY = look.cropX / 1.4142 * (look.mirror and -1 or 1), look.cropY / 1.4142
  for _, vertex in ipairs(VERTICES) do
    local u, v = vertex[2] - 0.5, vertex[3] - 0.5
    local x, y = (cosine * u + sine * v) * scaleX, (-sine * u + cosine * v) * scaleY
    texture:SetVertexOffset(vertex[1], (x - u) * w, -(y - v) * h)
  end
  local origin = look.reverse and look.endAngle or look.startAngle
  origin = look.rotation + (look.mirror and -origin or origin)
  texture:SetRadialProgressBarStartOffset(((origin + 180) % 360) / 360)
  texture:SetRadialProgressBarEndOffset(1 - (look.endAngle - look.startAngle) / 360)
  texture:SetRadialProgressBarReverse(look.reverse ~= look.mirror)
  texture:SetRadialProgressBarFeather(0)
end

local function StyleProgress(record, data, region, level)
  local button, art, backdrop = record.button, record.art, record.backdrop
  local w, h = tonumber(data.width) or 200, tonumber(data.height) or 200
  local offset = tonumber(data.backgroundOffset) or 0
  local file = region.currentTexture or data.foregroundTexture
  local backFile = data.sameTexture and file or data.backgroundTexture
  local startAngle, endAngle = (tonumber(data.startAngle) or 0) % 360, (tonumber(data.endAngle) or 360) % 360
  if endAngle <= startAngle then
    endAngle = endAngle + 360
  end
  local look = { cropX = 1 + (tonumber(data.crop_x) or 0.41), cropY = 1 + (tonumber(data.crop_y) or 0.41),
    rotation = tonumber(region.effectiveTexRotation or data.rotation) or 0, mirror = data.mirror and true or false,
    startAngle = startAngle, endAngle = endAngle, reverse = data.orientation == "ANTICLOCKWISE" }
  local back = type(data.backgroundColor) == "table" and data.backgroundColor or {}
  local front = type(data.foregroundColor) == "table" and data.foregroundColor or {}
  local r, g, b, a = region:GetColor()
  if record.variant:find("^circle") then
    backdrop:ClearAllPoints()
    backdrop:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -offset, -offset)
    backdrop:SetPoint("TOPRIGHT", button, "TOPRIGHT", offset, offset)
    backdrop:SetFrameLevel(level)
    record.bar:SetFrameLevel(level + 1)
    Round(art, file, w, h, look)
    Round(record.backdropArt, backFile, w + 2 * offset, h + 2 * offset, look)
  else
    local orientation = data.orientation or "VERTICAL"
    local horizontal = orientation == "HORIZONTAL" or orientation == "HORIZONTAL_INVERSE"
    local reverse = orientation == "HORIZONTAL_INVERSE" or orientation == "VERTICAL_INVERSE"
    local origin = horizontal and (reverse and "TOPRIGHT" or "TOPLEFT") or (reverse and "TOPLEFT" or "BOTTOMLEFT")
    local bar = record.bar
    bar:ClearAllPoints()
    bar:SetPoint(origin, button, origin)
    bar:SetSize(w, h)
    bar:SetOrientation(horizontal and "HORIZONTAL" or "VERTICAL")
    bar:SetReverseFill(reverse)
    local userX, userY = -(tonumber(data.user_x) or 0), tonumber(data.user_y) or 0
    local coords = {}
    for _, vertex in ipairs({ { 0, 0 }, { 0, 1 }, { 1, 0 }, { 1, 1 } }) do
      local x, y = TransformPoint(vertex[1], vertex[2], look.cropX, look.cropY, look.rotation, look.mirror, userX, userY)
      coords[#coords + 1], coords[#coords + 2] = x, y
    end
    local wrap = data.textureWrapMode or "CLAMPTOBLACKADDITIVE"
    Private.SetTextureOrAtlas(art, file, wrap, wrap)
    art:SetTexCoord(unpack(coords))
    Private.SetTextureOrAtlas(backdrop, backFile, wrap, wrap)
    backdrop:SetTexCoord(unpack(coords))
    backdrop:ClearAllPoints()
    backdrop:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -offset, -offset)
    backdrop:SetPoint("TOPRIGHT", button, "TOPRIGHT", offset, offset)
  end
  art:SetVertexColor(r or front[1] or 1, g or front[2] or 1, b or front[3] or 1, a or front[4] or 1)
  art:SetDesaturated(data.desaturateForeground and true or false)
  art:SetBlendMode(data.blendMode or "BLEND")
  local backArt = record.backdropArt
  backArt:SetVertexColor(back[1] or 0.5, back[2] or 0.5, back[3] or 0.5, back[4] or 0.5)
  backArt:SetDesaturated(data.desaturateBackground and true or false)
  backArt:SetBlendMode(data.blendMode or "BLEND")
end

function StyleText(record, data, region)
  local pieces, text, button = record.pieces, region.text, record.button
  local symbol, before, after = TextParts(data.displayText)
  if not (pieces and text and symbol) then
    return
  end
  before, after = EverythingAuras.ReplaceRaidMarkerSymbols(before), EverythingAuras.ReplaceRaidMarkerSymbols(after)
  local hidden = record.hidden.main
  if hidden and hidden ~= text then
    hidden:Show()
  end
  record.hidden.main = text
  textOwners[text] = { record = record, key = "main" }
  if not hookedTexts[text] then
    hookedTexts[text] = true
    hooksecurefunc(text, "SetTextColor", OnTextColor)
  end
  local font, size, flags = text:GetFont()
  local justify = data.justify or "LEFT"
  for _, piece in pairs(pieces) do
    if font then
      piece:SetFont(font, size, flags)
    end
    piece:SetShadowColor(text:GetShadowColor())
    piece:SetShadowOffset(text:GetShadowOffset())
    piece:SetTextColor(text:GetTextColor())
    piece:ClearAllPoints()
  end
  if symbol == "n" then
    local pad = OutlinePad(pieces.after)
    local beforePad, afterPad = before ~= "" and pad or 0, after ~= "" and pad or 0
    pieces.before:SetText(before)
    pieces.after:SetText(after)
    -- The name's width is secret in combat, so the words are anchored to it rather than placed by measuring (probe 074 T2).
    if justify == "RIGHT" then
      pieces.after:SetPoint("RIGHT", button, "RIGHT")
      pieces.main:SetPoint("RIGHT", pieces.after, "LEFT", afterPad, 0)
      pieces.before:SetPoint("RIGHT", pieces.main, "LEFT", beforePad, 0)
    elseif justify == "CENTER" then
      local beforeWidth = before ~= "" and (tonumber(pieces.before:GetStringWidth()) or 0) - beforePad or 0
      local afterWidth = after ~= "" and (tonumber(pieces.after:GetStringWidth()) or 0) - afterPad or 0
      pieces.main:SetPoint("CENTER", button, "CENTER", (beforeWidth - afterWidth) / 2, 0)
      pieces.before:SetPoint("RIGHT", pieces.main, "LEFT", beforePad, 0)
      pieces.after:SetPoint("LEFT", pieces.main, "RIGHT", -afterPad, 0)
    else
      pieces.before:SetPoint("LEFT", button, "LEFT")
      pieces.main:SetPoint("LEFT", pieces.before, "RIGHT", -beforePad, 0)
      pieces.after:SetPoint("LEFT", pieces.main, "RIGHT", -afterPad, 0)
    end
  else
    pieces.before:SetText("")
    pieces.after:SetText("")
    pieces.main:SetPoint(justify, button, justify)
    pieces.main:SetJustifyH(justify)
  end
  local key = "n"
  if symbol == "s" then
    local formatter
    formatter, key = CountFormatter(before, after)
    if record.textKey ~= key then
      button:SetApplicationCount(pieces.main, { formatter = formatter })
    end
  elseif symbol == "p" then
    local formatter, formatKey = TimeFormatter(data, "displayText_format_p_")
    local steps = TimerSteps(data, "color")
    local points, curveKey
    if #steps > 0 and C_CurveUtil and CreateColor then
      points, curveKey = TimerPoints(steps,
        record.timerBase or type(data.color) == "table" and data.color or { 1, 1, 1, 1 }, true)
    end
    key = before .. "{}" .. after .. "|" .. tostring(formatKey) .. "|" .. tostring(curveKey)
    local property = Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration
    if record.textKey ~= key and property and formatter then
      local options = { textFormat = { formatString = before .. "{}" .. after,
        components = { { property = property, formatter = formatter } } } }
      if points then
        options.textColor = { curve = TimerCurve(points), property = property }
      end
      button:SetDurationText(pieces.main, options)
    end
  end
  record.textKey = key
end

local Style, StyleIcon

-- A group's button sits where Blizzard puts it, so a part copies its place inside the aura's own frame, not that frame.
local function Corner(frame, point)
  local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
  if not (left and right and top and bottom) then
    return nil
  end
  local x = point:find("LEFT") and left or point:find("RIGHT") and right or (left + right) / 2
  local y = point:find("TOP") and top or point:find("BOTTOM") and bottom or (top + bottom) / 2
  return x, y
end

local function Relocate(widget, source, region, button)
  local left, bottom = source:GetLeft(), source:GetBottom()
  local regionLeft, regionBottom = region:GetLeft(), region:GetBottom()
  widget:ClearAllPoints()
  if left and bottom and regionLeft and regionBottom then
    widget:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", left - regionLeft, bottom - regionBottom)
    widget:SetSize(source:GetWidth(), source:GetHeight())
  else
    widget:SetAllPoints(button)
  end
end

local function BuildProgress(record, button)
  local direction = record.variant:find("elapsed$") and Enum.StatusBarTimerDirection.ElapsedTime
    or Enum.StatusBarTimerDirection.RemainingTime
  if record.variant:find("^circle") then
    local backdrop = CreateFrame("StatusBar", nil, button)
    backdrop:SetStatusBarTexture(SQUARE)
    backdrop:SetRenderMode(Enum.StatusBarRenderMode.Radial)
    backdrop:SetMinMaxValues(0, 1)
    backdrop:SetValue(1)
    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetAllPoints(button)
    bar:SetStatusBarTexture(SQUARE)
    bar:SetRenderMode(Enum.StatusBarRenderMode.Radial)
    record.backdrop, record.backdropArt, record.bar, record.art = backdrop, backdrop:GetStatusBarTexture(), bar,
      bar:GetStatusBarTexture()
    button:SetDurationBar(bar, { direction = direction })
    return
  end
  local backdrop = button:CreateTexture(nil, "BACKGROUND")
  local bar = CreateFrame("StatusBar", nil, button)
  bar:SetStatusBarTexture(SQUARE)
  bar:SetStatusBarColor(1, 1, 1, 0)
  -- The bar only measures the time left: its fill carries a mask over the aura's own texture (probe 074 L2).
  local fill = CreateFrame("Frame", nil, button)
  fill:SetAllPoints(bar:GetStatusBarTexture())
  local holder = CreateFrame("Frame", nil, button)
  holder:SetAllPoints(button)
  local art = holder:CreateTexture(nil, "ARTWORK")
  art:SetAllPoints(holder)
  local mask = holder:CreateMaskTexture()
  mask:SetTexture(SQUARE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
  mask:SetAllPoints(fill)
  art:AddMaskTexture(mask)
  record.backdrop, record.backdropArt, record.bar, record.art = backdrop, backdrop, bar, art
  button:SetDurationBar(bar, { direction = direction })
end

local function BuildText(record, button)
  local pieces = {}
  for _, key in ipairs({ "before", "main", "after" }) do
    pieces[key] = button:CreateFontString(nil, "OVERLAY")
    pieces[key]:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    pieces[key]:SetPoint("CENTER", button, "CENTER")
  end
  record.pieces = pieces
  if record.variant == "text-p" then
    button:SetDurationText(pieces.main, {})
  elseif record.variant == "text-s" then
    button:SetApplicationCount(pieces.main)
  else
    button:SetSpellName(pieces.main)
  end
end

-- Runs once per button, before Blizzard locks it while auras are secret, so all art is handed over here.
local function BuildButton(record, button)
  record.button = button
  if record.member then
    button:SetSize(tonumber(record.member.data.width) or 32, tonumber(record.member.data.height) or 32)
  else
    button:ClearAllPoints()
    button:SetAllPoints(button:GetParent())
  end
  button:EnableMouse(false)
  local kind = VARIANT_KINDS[record.variant] or "icon"
  record.kind = kind
  if kind == "icon" or kind == "bar" then
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    button:SetIcon(icon)
    record.icon = icon
  end
  if kind == "texture" then
    record.art = button:CreateTexture(nil, "ARTWORK")
    record.art:SetAllPoints(button)
  elseif kind == "progress" then
    BuildProgress(record, button)
  elseif kind == "text" then
    BuildText(record, button)
  elseif kind == "icon" then
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    cooldown:SetDrawBling(false)
    StyleCooldown(cooldown, record.data)
    button:SetDurationCooldown(cooldown)
    record.cooldown = cooldown
  else
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(button)
    local fill = CreateFrame("StatusBar", nil, button)
    fill:SetAllPoints(button)
    fill:SetStatusBarTexture(SQUARE)
    local direction = record.variant == "elapsed" and Enum.StatusBarTimerDirection.ElapsedTime
      or Enum.StatusBarTimerDirection.RemainingTime
    button:SetDurationBar(fill, { direction = direction })
    record.background, record.fill = background, fill
  end
  record.texts = {}
  -- A button has one count, one timer and one name, which a Text aura's own text already uses.
  if kind ~= "text" then
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(button)
    record.overlay = overlay
    record.texts.count = NewText(overlay, button)
    button:SetApplicationCount(record.texts.count, { formatter = (CountFormatter("", "")) })
    record.texts.timer = NewText(overlay, button)
    button:SetDurationText(record.texts.timer, {})
    if kind ~= "icon" then
      record.texts.name = NewText(overlay, button)
      button:SetSpellName(record.texts.name)
    end
  end
  -- A button built while auras are secret cannot be styled until they can be read again, so it is styled now.
  local region, data = record.region or record.member and record.member.region, record.data or record.member and record.member.data
  if region then
    Style(record, data, region)
  end
end

local function TakeOver(record, region, takeover)
  local widget = record.texts[takeover.key]
  if not widget then
    return
  end
  local sub = SubText(region, takeover.format)
  local text = sub and sub.text
  local hidden = record.hidden[takeover.key]
  if hidden and hidden ~= text then
    hidden:Show()
  end
  record.hidden[takeover.key] = text
  if not text then
    widget:SetAlpha(0)
    return
  end
  textOwners[text] = { record = record.member or record, key = takeover.key, sub = sub }
  if not hookedTexts[text] then
    hookedTexts[text] = true
    hooksecurefunc(text, "SetTextColor", OnTextColor)
  end
  -- SetVisible is made again on every modify (SubText.lua), while Show and Hide stay.
  if not hookedSubs[sub] then
    hookedSubs[sub] = true
    hooksecurefunc(sub, "Show", function(self) OnTextVisible(self, true) end)
    hooksecurefunc(sub, "Hide", function(self) OnTextVisible(self, false) end)
  end
  local font, size, flags = text:GetFont()
  if font then
    widget:SetFont(font, size, flags)
  end
  widget:SetTextColor(sub.color_r or 1, sub.color_g or 1, sub.color_b or 1, sub.color_a or 1)
  widget:SetShadowColor(text:GetShadowColor())
  widget:SetShadowOffset(text:GetShadowOffset())
  widget:SetJustifyH(text:GetJustifyH())
  local point, relativeTo, relativePoint, x, y = text:GetPoint(1)
  if point and record.member then
    local textX, textY = Corner(text, point)
    local regionX, regionY = Corner(region, "BOTTOMLEFT")
    widget:ClearAllPoints()
    if textX and regionX then
      widget:SetPoint(point, record.button, "BOTTOMLEFT", textX - regionX, textY - regionY)
    else
      widget:SetPoint("CENTER", record.button, "CENTER")
    end
  elseif point then
    widget:ClearAllPoints()
    widget:SetPoint(point, relativeTo, relativePoint, x, y)
  end
  widget:SetAlpha(sub:IsShown() and 1 or 0)
  text:SetShown(not (record.member or record).drawn)
end

local function StyleBar(record, region)
  local bar, background, fill = region.bar, record.background, record.fill
  if record.member then
    Relocate(background, bar, region, record.button)
    Relocate(fill, bar, region, record.button)
  else
    background:ClearAllPoints()
    background:SetAllPoints(bar)
    fill:ClearAllPoints()
    fill:SetAllPoints(bar)
  end
  local atlas = bar.fg:GetAtlas()
  if atlas then
    background:SetAtlas(atlas)
    fill:GetStatusBarTexture():SetAtlas(atlas)
  else
    local texture = bar.fg:GetTexture() or SQUARE
    background:SetTexture(texture)
    fill:SetStatusBarTexture(texture)
  end
  -- The bar's own parts are hidden with Show and Hide, so their colors stay readable here.
  background:SetVertexColor(bar.bg:GetVertexColor())
  fill:SetStatusBarColor(bar.fg:GetVertexColor())
  local orientation = FILL[region.effectiveOrientation or region.orientation or "HORIZONTAL"] or FILL.HORIZONTAL
  fill:SetOrientation(orientation[1])
  fill:SetReverseFill(orientation[2])
  fill:SetRotatesTexture(orientation[1] == "VERTICAL")
  local icon = record.icon
  if record.member then
    Relocate(icon, region.icon, region, record.button)
  else
    icon:ClearAllPoints()
    icon:SetAllPoints(region.icon)
  end
  icon:SetShown(region.iconVisible and true or false)
  icon:SetVertexColor(region.icon:GetVertexColor())
end

function Style(record, data, region, skipLooks)
  local button, icon, kind = record.button, record.icon, record.kind
  local level = record.member and record.member.group.container:GetFrameLevel() + 1 or region:GetFrameLevel()
  button:SetFrameLevel(level)
  if record.member then
    button:SetSize(tonumber(data.width) or 32, tonumber(data.height) or 32)
  end
  if record.overlay then
    record.overlay:SetFrameLevel(level + (FirstTextOffset(region) or 2))
  end
  if kind == "texture" then
    StyleTexture(record, data, region)
  elseif kind == "progress" then
    StyleProgress(record, data, region, level)
  elseif kind == "text" then
    StyleText(record, data, region)
  else
    StyleIcon(record, data, region, icon, level)
  end
  for _, takeover in ipairs(TAKEOVERS) do
    TakeOver(record, region, takeover)
  end
  StyleTimer(record, data, region)
  if not skipLooks then
    StyleLooks(record, data, region, level)
  end

  button:EnableMouse(false)
  if data.useTooltip then
    button:EnableMouseMotion(true)
    button:SetMouseClickEnabled(false)
  end
  record.styled = not skipLooks
end

function StyleIcon(record, data, region, icon, level)
  icon:SetTexCoord(region.icon:GetTexCoord())
  if record.always then
    -- The aura's own icon shows its missing look whenever it is missing, so Blizzard's takes the found look from the settings.
    local found, missing, under = AlwaysLook(data, true), AlwaysLook(data, false), record.under
    icon:SetDesaturated(found.desaturate)
    icon:SetVertexColor(found.r, found.g, found.b, found.a)
    local texture = region.icon:GetTexture()
    if issecretvalue(texture) or not texture then
      texture = record.ids and next(record.ids) and C_Spell.GetSpellTexture((next(record.ids)))
    end
    if texture then
      under.icon:SetTexture(texture)
    end
    under.icon:SetTexCoord(region.icon:GetTexCoord())
    under.icon:SetDesaturated(missing.desaturate)
    under.icon:SetVertexColor(missing.r, missing.g, missing.b, missing.a)
    under:SetAlpha(missing.alpha)
  else
    icon:SetDesaturation(region.icon:GetDesaturation())
  end
  if record.kind == "icon" then
    -- The icon is the button's own texture, so a swipe on the button's level draws under it.
    record.cooldown:SetFrameLevel(level + 1)
    if not record.always then
      -- A texture's alpha is its vertex color's alpha, so the color comes from the aura's setting, not its icon.
      local r, g, b, a = region:GetColor()
      icon:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
    end
    StyleCooldown(record.cooldown, data)
  else
    StyleBar(record, region)
  end
end

local function SoundFile(options)
  if type(options) ~= "table" or not options.do_sound or options.do_loop or options.sound_type == "Loop"
    or options.sound_type == "Stop" or options.sound == " KitID" then
    return nil
  end
  local file = options.sound == " custom" and options.sound_path or options.sound
  if file ~= nil and file ~= "" then
    return file
  end
end

local function SoundKey(record, data)
  local parts = { record.unit, record.idsKey }
  for _, action in ipairs(SOUND_ACTIONS) do
    local options = data.actions and data.actions[action.when]
    local file = SoundFile(options)
    parts[#parts + 1] = file and (tostring(file) .. "@" .. tostring(options.sound_channel or "Master")) or ""
  end
  return table.concat(parts, ";")
end

-- Blizzard plays these itself, in combat too, so the aura's own sound action steps aside (decision 19).
local function UpdateSounds(record, data, force)
  local trigger = type(data.triggers) == "table" and data.triggers[1] and data.triggers[1].trigger
  -- Blizzard's aura sounds have no caster filter (UnitAuraSoundInfo), so an Own Only trigger keeps its own sound.
  local anyCaster = type(trigger) == "table" and trigger.ownOnly == nil
  -- With Show On Always the icon shows the whole time, so its On Show and On Hide are not the aura coming or going.
  local want = record.drawn and anyCaster and not record.always and C_UnitAuras.AddAuraSound and SoundKey(record, data)
    or nil
  if want == record.soundKey and not force then
    return
  end
  -- Registering may not work while auras are secret, so a loaded aura keeps its sounds through a target swap.
  if want == nil and record.active and record.soundKey and Secret() then
    return
  end
  for _, handle in ipairs(record.soundHandles) do
    pcall(C_UnitAuras.RemoveAuraSound, handle)
  end
  wipe(record.soundHandles)
  wipe(record.sounds)
  record.soundKey, record.soundRetry = want, nil
  if not want then
    return
  end
  for _, action in ipairs(SOUND_ACTIONS) do
    local options = data.actions and data.actions[action.when]
    local file = SoundFile(options)
    if file then
      for id in pairs(record.ids) do
        local info = { unitToken = record.unit, spellID = id, outputChannel = options.sound_channel or "Master" }
        if tonumber(file) then
          info.soundFileID = tonumber(file)
        else
          info.soundFileName = file
        end
        local ok, handle = pcall(C_UnitAuras.AddAuraSound, Enum.UnitAuraSoundTrigger[action.trigger], info)
        if ok and handle then
          record.soundHandles[#record.soundHandles + 1] = handle
          record.sounds[action.when] = true
        elseif Secret() then
          record.soundRetry = true
        end
      end
    end
  end
end

function Private.EANativeSound(data, when)
  local record = data and (records[data.uid] or members[data.uid])
  return record and record.drawn and record.sounds[when] or false
end

local function KeepCooldownHidden(region)
  for _, name in ipairs(COOLDOWN_UPDATES) do
    local update = region[name]
    if update and not wrappers[update] then
      local wrapper = function(self, ...)
        update(self, ...)
        if self.eaNativeOn then
          self.cooldown:Hide()
        end
      end
      wrappers[wrapper] = true
      region[name] = wrapper
    end
  end
end

-- Blizzard matches spell IDs only for buffs on friends and debuffs on enemies (AuraContainerUtil.lua:52-87).
local function Drawable(record)
  local unit = record.unit
  if unit == "player" or not UnitExists(unit) then
    return true
  end
  -- The rule is about matching spell IDs, so a slot that lists none shows the same auras on any unit.
  if record.anyMode and not record.excludes then
    return true
  end
  local canAssist = UnitCanAssist("player", unit, true, true)
  if issecretvalue(canAssist) then
    return true
  end
  if record.filter:find("^HELPFUL") then
    local controlled = UnitIsPlayerControlledOrGroupMember(unit)
    return issecretvalue(controlled) or controlled or canAssist
  end
  return not canAssist
end

-- Showing every part would draw the straight and the round fill together, so only its orientation's set comes back.
local function ShowProgress(region, shown)
  for _, part in ipairs({ "foreground", "background" }) do
    if region[part] then
      region[part][shown and not region.circular and "Show" or "Hide"](region[part])
    end
  end
  for _, part in ipairs({ "foregroundSpinner", "backgroundSpinner" }) do
    if region[part] then
      region[part][shown and region.circular and "Show" or "Hide"](region[part])
    end
  end
end

local function ShowOwnKind(kind, region, shown)
  if kind == "icon" then
    -- Hidden, not faded: color conditions and animations set its vertex color, which would bring the alpha back.
    if region.icon then
      region.icon:SetShown(shown)
    end
  elseif kind == "bar" then
    if region.bar then
      region.bar:SetShown(shown)
      region.bar.bg:SetShown(shown)
      region.iconFrame:SetShown(shown)
    end
  elseif kind == "texture" then
    if region.texture and region.texture.texture then
      region.texture.texture:SetShown(shown)
    end
  elseif kind == "text" then
    if region.text then
      region.text:SetShown(shown)
    end
  elseif kind == "progress" then
    ShowProgress(region, shown)
  end
end

local function ShowOwnParts(record, region, shown)
  ShowOwnKind(record.kind or VARIANT_KINDS[record.variant], region, shown)
  for _, text in pairs(record.hidden) do
    text:SetShown(shown)
  end
  DimLooks(record, not shown)
end

-- With no unit the trigger shows nothing, so neither does the missing look under Blizzard's icon.
local function UnderShown(record)
  return record.drawn and record.always and (record.unit == "player" or UnitExists(record.unit)) or false
end

local function SetActive(record, data, active)
  record.active = active
  local drawn = active and Drawable(record) or false
  record.drawn = drawn
  record.container:SetShown(drawn)
  if record.under then
    record.under:SetShown(UnderShown(record))
  end
  local region = record.region
  if region then
    local wasDrawn = region.eaNativeOn
    region.eaNativeOn = drawn or nil
    ShowOwnParts(record, region, not drawn)
    if record.kind == "icon" then
      if drawn and region.cooldown then
        region.cooldown:Hide()
      elseif wasDrawn and region.state and region.UpdateProgress then
        -- A region that is not showing has no state, and its next show updates the swipe anyway.
        region:UpdateProgress()
      end
    end
    if region.tooltipFrame then
      region.tooltipFrame:EnableMouseMotion(not drawn and data.useTooltip and true or false)
    end
    if (wasDrawn or false) ~= drawn and Private.EAUpdateUnsureLook then
      Private.EAUpdateUnsureLook(region)
    end
  end
  if active and record.styled == false and not Secret() then
    Style(record, data, region)
  end
  UpdateSounds(record, data)
end

-- Conditions resize the aura from a timer that skips RunConditions (Conditions.lua recheck), so the frame's resize rebuilds a glow.
local function OnResize(region)
  local record = region.eaNativeRecord
  if not record or record.resizing or not (record.button and record.styled and record.lookSize) or Animated(region) then
    return
  end
  local glowing = false
  for _, kit in pairs(record.kits or {}) do
    glowing = glowing or #kit.groups > 0
  end
  if not glowing then
    return
  end
  record.resizing = true
  C_Timer.After(0, function()
    record.resizing = nil
    if region.eaNativeRecord == record and record.styled and not Secret() and not EverythingAuras.IsPaused()
      and not Animated(region) and record.lookSize ~= SizeKey(region) then
      Style(record, record.data, region)
    end
  end)
end

local function Mirror(region)
  if region.eaNativeMirror then
    return
  end
  region.eaNativeMirror = true
  region:HookScript("OnSizeChanged", OnResize)
  local source = region.regionType == "texture" and region.texture and region.texture.texture
  for _, method in ipairs(source and TEXTURE_COPIES or {}) do
    hooksecurefunc(source, method, function(_, ...)
      local record = region.eaNativeRecord
      if record and not Secret() then
        for _, target in ipairs(record.parts or { record }) do
          if target.art then
            pcall(target.art[method], target.art, ...)
          end
        end
      end
    end)
  end
  if region.regionType == "progresstexture" then
    hooksecurefunc(region, "Color", function(self)
      local record = region.eaNativeRecord
      if record and not Secret() then
        for _, target in ipairs(record.parts or { record }) do
          if target.art then
            pcall(target.art.SetVertexColor, target.art, self:GetColor())
          end
        end
      end
    end)
    hooksecurefunc(region, "SetBackgroundColor", function(_, ...)
      local record = region.eaNativeRecord
      if record and not Secret() then
        for _, target in ipairs(record.parts or { record }) do
          if target.backdropArt then
            pcall(target.backdropArt.SetVertexColor, target.backdropArt, ...)
          end
        end
      end
    end)
  end
  for _, method in ipairs(region.icon and { "SetTexCoord", "SetDesaturation", "SetDesaturated", "SetVertexColor" } or {}) do
    hooksecurefunc(region.icon, method, function(_, ...)
      local record = region.eaNativeRecord
      if not record or Secret() then
        return
      end
      if method == "SetTexCoord" and record.always then
        pcall(record.under.icon.SetTexCoord, record.under.icon, ...)
      end
      -- The aura's own icon wears the missing look while missing, which Blizzard's icon must never copy.
      if method == "SetTexCoord" or not record.always then
        for _, target in ipairs(record.parts or { record }) do
          if target.icon then
            pcall(target.icon[method], target.icon, ...)
          end
        end
      end
    end)
  end
  if region.bar then
    hooksecurefunc(region.bar.fg, "SetVertexColor", function(_, ...)
      local record = region.eaNativeRecord
      if record and not Secret() then
        for _, target in ipairs(record.parts or { record }) do
          if target.fill then
            pcall(target.fill.SetStatusBarColor, target.fill, ...)
          end
        end
      end
    end)
    hooksecurefunc(region.bar.bg, "SetVertexColor", function(_, ...)
      local record = region.eaNativeRecord
      if record and not Secret() then
        for _, target in ipairs(record.parts or { record }) do
          if target.background then
            pcall(target.background.SetVertexColor, target.background, ...)
          end
        end
      end
    end)
  end
end

local function NewRecord(variant)
  local ok, container = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
  if not ok or not container then
    return nil
  end
  container:Hide()
  pcall(container.SetEditModePreviewEnabled, container, false)
  return { container = container, variant = variant, kind = VARIANT_KINDS[variant], sounds = {}, soundHandles = {},
    hidden = {}, dimmed = {} }
end

-- Slots and containers cannot be removed (CustomAuraContainer.lua:641), so a freed one is reused out of combat.
local function TakeRecord(variant)
  local pool = spare[variant]
  if not Secret() and pool and #pool > 0 then
    return table.remove(pool)
  end
  return NewRecord(variant)
end

local function Release(uid, data)
  local record = records[uid]
  if not record then
    return
  end
  SetActive(record, data or record.data or { useTooltip = false, actions = {} }, false)
  if record.region and record.region.eaNativeRecord == record then
    record.region.eaNativeRecord = nil
  end
  records[uid] = nil
  record.region, record.unit, record.filter, record.idsKey, record.ids, record.styled = nil, nil, nil, nil, nil, nil
  record.data, record.filtersKey, record.always, record.timerBase, record.anyMode = nil, nil, nil, nil, nil
  record.timerVisible = nil
  wipe(record.hidden)
  wipe(record.dimmed)
  if record.button then
    spare[record.variant] = spare[record.variant] or {}
    table.insert(spare[record.variant], record)
  end
end

local failed = {}
-- The options store a name's ranks after this runs, so an aura with no spell IDs yet is tried again on refresh.
local pending = {}
local SafeConfigureGroup, DetachMember

local function GroupParent(data)
  local parent = data and data.parent and EverythingAuras.GetData(data.parent)
  return type(parent) == "table" and parent.regionType == "dynamicgroup" and parent or nil
end

local function Configure(data, region)
  local uid = data.uid
  local record = records[uid]
  if region and region.cloneId and region.cloneId ~= "" then
    return
  end
  -- A new region type gets a new region, and Add can still see the old one, so the new region's modify sets it up.
  if region and region.regionType and region.regionType ~= data.regionType then
    Release(uid, data)
    return
  end
  pending[uid] = nil
  local groupData = GroupParent(data)
  if groupData then
    Release(uid, data)
    SafeConfigureGroup(groupData)
    return
  end
  if members[uid] then
    DetachMember(members[uid])
  end
  local wanted = region and Private.EANativeWanted(data)
  if region then
    region.eaNativeWanted = wanted or nil
  end
  if failed[uid] or not wanted then
    if record then
      SetActive(record, data, false)
    end
    return
  end
  local trigger = data.triggers[1].trigger
  local unit, filter = UnitOf(trigger), Filter(trigger)
  local ids = SpellIds(data)
  local any = AnyAura(trigger)
  if not any and (not next(ids) or not KnownIds(data)) then
    pending[uid] = true
    if record then
      SetActive(record, data, false)
    end
    return
  end
  local variant = Variant(data)
  if record and record.variant ~= variant then
    Release(uid, data)
    record = nil
  end
  if not record then
    record = TakeRecord(variant)
    if not record then
      return
    end
    records[uid] = record
  end
  if record.region ~= region then
    if record.region and record.region.eaNativeRecord == record then
      record.region.eaNativeRecord = nil
    end
    record.region = region
  end
  region.eaNativeRecord = record
  record.data = data
  record.always = IsAlways(data)
  if record.always and not record.under then
    local under = CreateFrame("Frame", nil, UIParent)
    under:Hide()
    under.icon = under:CreateTexture(nil, "ARTWORK")
    under.icon:SetAllPoints(under)
    record.under = under
  end
  Mirror(region)

  local container, idsKey = record.container, Key(ids)
  local filters = CandidateFilters(trigger, ids)
  local filtersKey = FiltersKey(filters)
  record.anyMode, record.excludes = any, filters.excludeSpellIDs ~= nil
  if not record.button then
    container:SetUnit(unit)
    record.sorted = true
    record.button = container:AddAuraSlot(SLOT, filter, {
      candidateFilters = filters,
      sortMethod = SORT_TIME_LEFT,
      initializeFrame = function(button) BuildButton(record, button) end,
    })
  else
    if not record.sorted then
      container:SetAuraSlotSortMethod(SLOT, SORT_TIME_LEFT)
      record.sorted = true
    end
    if record.unit ~= unit then
      container:SetUnit(unit)
    end
    if record.filter ~= filter then
      container:SetAuraSlotFilterString(SLOT, filter)
    end
    if record.filtersKey ~= filtersKey then
      container:SetAuraSlotCandidateFilters(SLOT, filters)
    end
  end
  record.unit, record.filter, record.ids, record.idsKey, record.filtersKey = unit, filter, ids, idsKey, filtersKey

  container:ClearAllPoints()
  container:SetAllPoints(region)
  container:SetScale(region:GetEffectiveScale() / UIParent:GetEffectiveScale())
  container:SetFrameStrata(region:GetFrameStrata())
  -- One level under the region, so the button lands on the region's own level, under its texts and borders.
  container:SetFrameLevel(math.max(0, region:GetFrameLevel() - 1))
  container:SetAlpha(record.always and AlwaysLook(data, true).alpha or data.alpha or 1)
  if record.always then
    -- Under Blizzard's button, so its icon covers the missing look whenever the aura is there (probe P5).
    local under = record.under
    under:ClearAllPoints()
    under:SetAllPoints(region)
    under:SetFrameStrata(region:GetFrameStrata())
    under:SetFrameLevel(math.max(0, region:GetFrameLevel() - 2))
  end
  if record.variant == "icon" then
    KeepCooldownHidden(region)
  end
  local paused = EverythingAuras.IsPaused()
  if Secret() then
    -- Blizzard's button is locked while auras are secret, so it is styled once they can be read again.
    record.styled = false
    for _, takeover in ipairs(TAKEOVERS) do
      local sub = record.texts and record.texts[takeover.key] and SubText(region, takeover.format)
      if sub then
        record.hidden[takeover.key] = sub.text
      end
    end
  else
    -- The open options rebuild the aura at every edit, so its glows and borders wait for them to close.
    Style(record, data, region, paused)
  end
  if Secret() or paused then
    DimMatching(record, record.kits, data, region)
  end
  SetActive(record, data, Private.loaded[data.id] == true and not EverythingAuras.IsPaused())
end

-- Blizzard's container API can change during the beta, so a failure falls back to the aura's own icon, reported once.
local function SafeConfigure(data, region)
  local ok, err = pcall(Configure, data, region)
  if not ok then
    failed[data.uid] = true
    local record = records[data.uid]
    if record then
      pcall(SetActive, record, data, false)
    end
    geterrorhandler()(err)
  end
end

-- Dynamic groups: one container lays out every member, so an aura that is gone leaves no gap (decision 27).
local pendingGroups, failedGroups = {}, {}
local cloneHidden = setmetatable({}, { __mode = "k" })
local cloneDimmed = setmetatable({}, { __mode = "k" })

-- The same start corner and directions the group's own grower uses (DynamicGroup.lua growers).
local function Flow(groupData)
  local axes, directions = AnchorUtil.FlowLayoutAxis, AnchorUtil.FlowDirection
  local grow = groupData.grow or "DOWN"
  local axis, horizontal, vertical = axes.Horizontal, directions.Right, directions.Down
  if grow == "LEFT" then
    horizontal = directions.Left
  elseif grow == "UP" then
    axis, vertical = axes.Vertical, directions.Up
  elseif grow == "DOWN" then
    axis = axes.Vertical
  elseif grow == "HORIZONTAL" then
    horizontal = groupData.centerType == "RL" and directions.Left or directions.Right
  elseif grow == "VERTICAL" then
    -- A centered vertical group lists its first aura at the bottom unless it runs top to bottom.
    axis, vertical = axes.Vertical, groupData.centerType == "RL" and directions.Down or directions.Up
  elseif grow == "GRID" then
    local gridType = groupData.gridType or "RD"
    local first = gridType:sub(1, 1)
    axis = (first == "R" or first == "L") and axes.Horizontal or axes.Vertical
    horizontal = gridType:find("L") and directions.Left or directions.Right
    vertical = gridType:find("U") and directions.Up or directions.Down
  end
  local corner = (vertical == directions.Up and "BOTTOM" or "TOP") .. (horizontal == directions.Left and "RIGHT" or "LEFT")
  return axis, horizontal, vertical, corner
end

-- A grid that fills rows first spaces its auras by column space and its rows by row space (DynamicGroup.lua GRID).
local function Spacing(groupData)
  if (groupData.grow or "DOWN") ~= "GRID" then
    return tonumber(groupData.space) or 0, 0
  end
  local rowSpace, columnSpace = tonumber(groupData.rowSpace) or 0, tonumber(groupData.columnSpace) or 0
  if (groupData.gridType or "RD"):find("^[RL]") then
    return columnSpace, rowSpace
  end
  return rowSpace, columnSpace
end

local function HideClone(region, drawn, variant, data)
  region.eaNativeOn = drawn or nil
  local kind = VARIANT_KINDS[variant] or "icon"
  ShowOwnKind(kind, region, not drawn)
  if kind == "icon" and drawn and region.cooldown then
    region.cooldown:Hide()
  elseif kind == "icon" and not drawn and region.state and region.UpdateProgress then
    region:UpdateProgress()
  end
  local allowed = MEMBER_TEXTS[data and data.regionType or kind == "icon" and "icon" or "aurabar"] or {}
  local list = {}
  for _, takeover in ipairs(TAKEOVERS) do
    local sub = allowed[takeover.format] and SubText(region, takeover.format)
    if sub then
      sub.text:SetShown(not drawn)
      list[#list + 1] = sub.text
    end
  end
  cloneHidden[region] = drawn and list or nil
  local dimmed = {}
  for _, part in ipairs(data and LookParts(data, region) or {}) do
    part.live:SetAlpha(drawn and 0 or 1)
    dimmed[#dimmed + 1] = part.live
  end
  cloneDimmed[region] = drawn and dimmed or nil
  if Private.EAUpdateUnsureLook then
    Private.EAUpdateUnsureLook(region)
  end
end

-- Auto-Clone gives each match its own region, which Blizzard's list replaces while it draws.
local function SyncClones(member)
  local clones = member.data and Private.clones and Private.clones[member.data.id]
  for _, clone in pairs(clones or {}) do
    if member.variant == "icon" then
      KeepCooldownHidden(clone)
    end
    HideClone(clone, member.drawn and true or false, member.variant, member.data)
  end
end

function DetachMember(member)
  local group = member.group
  if group then
    if member.key then
      pcall(group.container.SetAuraGroupEnabled, group.container, member.key, false)
    end
    if group.members[member.uid] == member then
      group.members[member.uid] = nil
    end
  end
  member.active, member.drawn = false, false
  local region = member.region
  if region then
    local wasDrawn = region.eaNativeOn
    region.eaNativeOn = nil
    ShowOwnParts(member, region, true)
    if member.variant == "icon" and wasDrawn and region.state and region.UpdateProgress then
      region:UpdateProgress()
    end
    if region.tooltipFrame then
      region.tooltipFrame:EnableMouseMotion(member.data and member.data.useTooltip and true or false)
    end
    if wasDrawn and Private.EAUpdateUnsureLook then
      Private.EAUpdateUnsureLook(region)
    end
    if region.eaNativeRecord == member then
      region.eaNativeRecord = nil
    end
  end
  wipe(member.dimmed)
  UpdateSounds(member, member.data or { actions = {} })
  SyncClones(member)
  if members[member.uid] == member then
    members[member.uid] = nil
  end
end

local function ReleaseGroup(uid, forget)
  local group = groups[uid]
  if not group then
    return
  end
  for _, member in pairs(group.members) do
    DetachMember(member)
  end
  group.container:Hide()
  group.active, group.drawn = false, false
  if forget then
    groups[uid] = nil
  end
end

local function SetGroupActive(group, active)
  local drawable = true
  for _, member in pairs(group.members) do
    drawable = drawable and Drawable(member)
  end
  local anyDrawn = false
  group.active = active
  for _, member in pairs(group.members) do
    local loaded = active and Private.loaded[member.data.id] == true
    member.active = loaded
    member.drawn = loaded and drawable
    anyDrawn = anyDrawn or member.drawn
    if group.container:HasAuraGroup(member.key) then
      group.container:SetAuraGroupEnabled(member.key, member.drawn)
    end
    local region = member.region
    if region then
      local wasDrawn = region.eaNativeOn
      region.eaNativeOn = member.drawn or nil
      ShowOwnParts(member, region, not member.drawn)
      if member.variant == "icon" then
        if member.drawn and region.cooldown then
          region.cooldown:Hide()
        elseif wasDrawn and region.state and region.UpdateProgress then
          region:UpdateProgress()
        end
      end
      if region.tooltipFrame then
        region.tooltipFrame:EnableMouseMotion(not member.drawn and member.data.useTooltip and true or false)
      end
      if (wasDrawn or false) ~= member.drawn and Private.EAUpdateUnsureLook then
        Private.EAUpdateUnsureLook(region)
      end
      if member.drawn and not Secret() then
        for _, part in ipairs(member.parts) do
          if part.styled == false and part.button then
            Style(part, member.data, region)
          end
        end
      end
    end
    UpdateSounds(member, member.data)
    SyncClones(member)
  end
  group.drawn = anyDrawn
  group.container:SetShown(anyDrawn)
end

local function ConfigureGroup(groupData)
  local uid = groupData.uid
  local groupRegion = EverythingAuras.GetRegion(groupData.id)
  local ok = groupRegion and not failedGroups[uid] and GroupQualifies(groupData) or false
  local children = {}
  for _, id in ipairs(type(groupData.controlledChildren) == "table" and groupData.controlledChildren or {}) do
    local child = EverythingAuras.GetData(id)
    if type(child) == "table" then
      children[#children + 1] = child
    end
  end
  local ready = ok
  for _, child in ipairs(children) do
    if ready and not AnyAura(child.triggers[1].trigger) and (not next(SpellIds(child)) or not KnownIds(child)) then
      ready = false
    end
    local region = EverythingAuras.GetRegion(child.id)
    if region then
      -- IDs read out of combat are learned only while the group can be drawn.
      region.eaNativeWanted = ok or nil
    end
  end
  pendingGroups[uid] = ok and not ready or nil
  if not ready then
    ReleaseGroup(uid)
    return
  end
  local group = groups[uid]
  if not group then
    local created, container = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not created or not container then
      return
    end
    container:Hide()
    pcall(container.SetEditModePreviewEnabled, container, false)
    group = { uid = uid, container = container, members = {}, partsByKey = {}, keys = {} }
    groups[uid] = group
  end
  group.data, group.region = groupData, groupRegion
  local container, first = group.container, children[1]
  local unit = UnitOf(first.triggers[1].trigger)
  if group.unit ~= unit then
    container:SetUnit(unit)
    group.unit = unit
  end
  local axis, horizontal, vertical, corner = Flow(groupData)
  container:SetFlowLayoutAxis(axis)
  container:SetFlowLayoutGrowthDirection(horizontal, vertical)
  container:SetFlowLayoutAnchorPoint(corner)
  local spacing, lineSpacing = Spacing(groupData)
  local width, height = tonumber(first.width) or 32, tonumber(first.height) or 32
  local maximum
  if (groupData.grow or "DOWN") == "GRID" then
    local perLine = math.max(1, tonumber(groupData.gridWidth) or 5)
    local size = axis == AnchorUtil.FlowLayoutAxis.Horizontal and width or height
    maximum = perLine * size + (perLine - 1) * spacing + 0.5
  end
  container:SetFlowLayoutMaximumLineSize(maximum)
  -- The group places its auras from its own anchor point, which stays put while its size changes.
  local point = groupData.selfPoint or "TOP"
  container:ClearAllPoints()
  container:SetPoint(point, groupRegion, point)
  container:SetFrameStrata(groupRegion:GetFrameStrata())
  container:SetFrameLevel(groupRegion:GetFrameLevel() + 1)
  container:SetScale(groupRegion:GetEffectiveScale() / UIParent:GetEffectiveScale())
  container:SetAlpha(groupData.alpha or 1)

  local used = {}
  for index, child in ipairs(children) do
    local member = members[child.uid]
    if member and member.group ~= group then
      DetachMember(member)
      member = nil
    end
    if not member then
      member = { uid = child.uid, group = group, hidden = {}, dimmed = {}, sounds = {}, soundHandles = {} }
      members[child.uid] = member
    end
    group.members[child.uid] = member
    local variant = Variant(child)
    local key = child.uid .. ":" .. variant
    if member.key and member.key ~= key and container:HasAuraGroup(member.key) then
      container:SetAuraGroupEnabled(member.key, false)
    end
    member.key, member.variant, member.data = key, variant, child
    group.partsByKey[key] = group.partsByKey[key] or {}
    member.parts = group.partsByKey[key]
    for _, part in ipairs(member.parts) do
      part.member, part.hidden, part.data = member, member.hidden, child
    end
    used[key] = true
    local region = EverythingAuras.GetRegion(child.id)
    if member.region ~= region and member.region and member.region.eaNativeRecord == member then
      member.region.eaNativeRecord = nil
    end
    member.region = region
    if region then
      region.eaNativeRecord = member
      Mirror(region)
      if variant == "icon" then
        KeepCooldownHidden(region)
      end
    end
    local trigger = child.triggers[1].trigger
    local ids = SpellIds(child)
    local filter, filters = Filter(trigger), CandidateFilters(trigger, ids)
    local filtersKey = FiltersKey(filters)
    local count = trigger.showClones and (tonumber(groupData.useLimit and groupData.limit) or math.huge) or 1
    local layout = { layoutIndex = index, elementSpacing = spacing, lineSpacing = lineSpacing, elementWidth = width,
      elementHeight = height }
    if not container:HasAuraGroup(key) then
      -- Blizzard builds and styles the list's buttons as it is added, so a child with no region yet waits for one.
      if region then
        group.keys[key] = true
        local childUid = child.uid
        container:AddAuraGroup(key, filter, {
          candidateFilters = filters,
          sortMethod = SORT_TIME_LEFT,
          maxFrameCount = count,
          layout = layout,
          initializeFrame = function(button)
            local current = members[childUid] or member
            local part = { member = current, variant = variant, hidden = current.hidden, data = current.data }
            table.insert(current.parts, part)
            BuildButton(part, button)
          end,
        })
      end
    else
      if member.filter ~= filter then
        container:SetAuraGroupFilterString(key, filter)
      end
      if member.filtersKey ~= filtersKey then
        container:SetAuraGroupCandidateFilters(key, filters)
      end
      container:SetAuraGroupMaxFrameCount(key, count)
      container:SetAuraGroupLayout(key, layout)
    end
    member.unit, member.filter, member.ids, member.idsKey, member.filtersKey = unit, filter, ids, Key(ids), filtersKey
    member.anyMode, member.excludes = AnyAura(trigger), filters.excludeSpellIDs ~= nil
    if region then
      local paused = EverythingAuras.IsPaused()
      if Secret() then
        for _, part in ipairs(member.parts) do
          part.styled = false
        end
        for _, takeover in ipairs(TAKEOVERS) do
          local sub = MEMBER_TEXTS[child.regionType][takeover.format] and SubText(region, takeover.format)
          if sub then
            member.hidden[takeover.key] = sub.text
          end
        end
      else
        for _, part in ipairs(member.parts) do
          if part.button then
            Style(part, child, region, paused)
          end
        end
      end
      if Secret() or paused then
        DimMatching(member, member.parts[1] and member.parts[1].kits, child, region)
      end
    end
  end
  for childUid, member in pairs(group.members) do
    if not used[member.key] or member.group ~= group then
      DetachMember(member)
      group.members[childUid] = nil
    end
  end
  for key in pairs(group.keys) do
    if not used[key] then
      container:SetAuraGroupEnabled(key, false)
    end
  end
  SetGroupActive(group, not EverythingAuras.IsPaused())
end

function SafeConfigureGroup(groupData)
  local ok, err = pcall(ConfigureGroup, groupData)
  if not ok then
    failedGroups[groupData.uid] = true
    pcall(ReleaseGroup, groupData.uid)
    geterrorhandler()(err)
  end
end

local function HasNativeChild(groupData)
  for _, id in ipairs(type(groupData.controlledChildren) == "table" and groupData.controlledChildren or {}) do
    local child = EverythingAuras.GetData(id)
    if type(child) == "table" and child.eaNative then
      return true
    end
  end
  return false
end

local function RefreshAll(force)
  for uid, record in pairs(records) do
    local id = Private.UIDtoID(uid)
    local data = id and EverythingAuras.GetData(id)
    if data then
      SafeConfigure(data, EverythingAuras.GetRegion(id))
      if force and record.soundRetry then
        UpdateSounds(record, data, true)
      end
    end
  end
  local waiting = {}
  for uid in pairs(pending) do
    waiting[#waiting + 1] = uid
  end
  for _, uid in ipairs(waiting) do
    local id = Private.UIDtoID(uid)
    local data = id and EverythingAuras.GetData(id)
    if data and not records[uid] then
      SafeConfigure(data, EverythingAuras.GetRegion(id))
    else
      pending[uid] = nil
    end
  end
  local groupUids = {}
  for uid in pairs(groups) do
    groupUids[#groupUids + 1] = uid
  end
  for uid in pairs(pendingGroups) do
    if not groups[uid] then
      groupUids[#groupUids + 1] = uid
    end
  end
  for _, uid in ipairs(groupUids) do
    local id = Private.UIDtoID(uid)
    local data = id and EverythingAuras.GetData(id)
    if data and data.regionType == "dynamicgroup" then
      SafeConfigureGroup(data)
      local group = groups[uid]
      for _, member in pairs(force and group and group.members or {}) do
        if member.soundRetry then
          UpdateSounds(member, member.data, true)
        end
      end
    else
      ReleaseGroup(uid, true)
      pendingGroups[uid] = nil
    end
  end
end

local function WrapModify(regionData)
  local modify = regionData.modify
  regionData.modify = function(parent, region, data)
    -- Modify returns sub-regions to a shared pool, so a text Blizzard replaced must be visible again first.
    local record = region.eaNativeRecord
    if record then
      -- Conditions set these again after a modify, and nothing else does, so they are dropped only here.
      record.timerBase, record.timerVisible = nil, nil
      for key, text in pairs(record.hidden) do
        text:Show()
        record.hidden[key] = nil
      end
      for index, frame in pairs(record.dimmed) do
        frame:SetAlpha(1)
        record.dimmed[index] = nil
      end
    end
    for _, text in ipairs(cloneHidden[region] or {}) do
      text:Show()
    end
    cloneHidden[region] = nil
    for _, frame in ipairs(cloneDimmed[region] or {}) do
      frame:SetAlpha(1)
    end
    cloneDimmed[region] = nil
    modify(parent, region, data)
    if region.cloneId and region.cloneId ~= "" then
      local member = members[data.uid]
      if member and member.drawn then
        if member.variant == "icon" then
          KeepCooldownHidden(region)
        end
        HideClone(region, true, member.variant, data)
      elseif region.eaNativeOn then
        HideClone(region, false, Variant(data), data)
      end
      return
    end
    if data.eaNative or region.eaNativeRecord then
      SafeConfigure(data, region)
    else
      region.eaNativeWanted = nil
    end
  end
end
for regionType in pairs(REGION_KINDS) do
  if Private.regionTypes[regionType] then
    WrapModify(Private.regionTypes[regionType])
  end
end

local RunConditions = Private.RunConditions
function Private.RunConditions(region, uid, hideRegion)
  if region.eaNativeWanted and not Secret() then
    -- An ID read out of combat is the aura's own, so it is kept with the aura for every later fight.
    local state = region.states and region.states[1]
    local spellId = state and state.show and not state.eaUnsure and state.spellId
    if spellId and not issecretvalue(spellId) and type(spellId) == "number" then
      local data = EverythingAuras.GetData(region.id)
      local trigger = data and data.triggers[1].trigger
      if trigger and not AnyAura(trigger) and not HasId(data.eaNativeIds, spellId) and not HasId(trigger.auraspellids, spellId)
        and not HasId(trigger.auraRankSpellIDs, spellId) then
        data.eaNativeIds = data.eaNativeIds or {}
        table.insert(data.eaNativeIds, spellId)
        table.sort(data.eaNativeIds)
        SafeConfigure(data, region)
      end
    end
  end
  return RunConditions(region, uid, hideRegion)
end

function Private.EANativeRefresh()
  RefreshAll()
end

local Pause = Private.Pause
function Private.Pause(...)
  Pause(...)
  RefreshAll()
end

Private.callbacks:RegisterCallback("ScanForLoads", function()
  RefreshAll()
end)
local dynamicGroup = Private.regionTypes.dynamicgroup
if dynamicGroup then
  local modifyGroup = dynamicGroup.modify
  dynamicGroup.modify = function(parent, region, data)
    modifyGroup(parent, region, data)
    if groups[data.uid] or pendingGroups[data.uid] or HasNativeChild(data) then
      SafeConfigureGroup(data)
    end
  end
end

Private.callbacks:RegisterCallback("Add", function(_, uid, id, data)
  if groups[uid] and data.regionType ~= "dynamicgroup" then
    ReleaseGroup(uid, true)
  end
  local member = members[uid]
  if member then
    local groupData = GroupParent(data)
    if groupData then
      SafeConfigureGroup(groupData)
    else
      DetachMember(member)
    end
  end
  if not records[uid] then
    return
  end
  if not REGION_KINDS[data.regionType] then
    Release(uid, data)
  else
    SafeConfigure(data, EverythingAuras.GetRegion(id))
  end
end)

local function Reevaluate(match)
  for uid, record in pairs(records) do
    if record.active and match(record.unit) and Drawable(record) ~= record.drawn then
      local id = Private.UIDtoID(uid)
      local data = id and EverythingAuras.GetData(id)
      if data then
        SafeConfigure(data, EverythingAuras.GetRegion(id))
      end
    end
  end
  local changed = {}
  for _, group in pairs(groups) do
    if group.active and match(group.unit) then
      local drawable = true
      for _, member in pairs(group.members) do
        drawable = drawable and Drawable(member)
      end
      if drawable ~= group.drawn then
        changed[#changed + 1] = group
      end
    end
  end
  for _, group in ipairs(changed) do
    SetGroupActive(group, group.active)
  end
end
Private.callbacks:RegisterCallback("Delete", function(_, uid)
  Release(uid)
  if members[uid] then
    DetachMember(members[uid])
  end
  if groups[uid] then
    ReleaseGroup(uid, true)
  end
  pendingGroups[uid] = nil
end)

-- The container does not follow a unit token to a new unit by itself (probe N1b).
local function Follow(match)
  for _, record in pairs(records) do
    if record.active and match(record.unit) then
      record.container:UpdateAllAuras()
      if record.under then
        record.under:SetShown(UnderShown(record))
      end
    end
  end
  for _, group in pairs(groups) do
    if group.active and match(group.unit) then
      group.container:UpdateAllAuras()
    end
  end
  Reevaluate(match)
end

local function IsGroupUnit(unit)
  return unit ~= nil and (unit:find("^party") or unit:find("^raid")) ~= nil
end

local events = CreateFrame("Frame")
Private.frames["Everything Auras Native Icons"] = events
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_FOCUS_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterUnitEvent("UNIT_PET", "player")
events:RegisterUnitEvent("UNIT_FACTION", "target", "focus")
events:RegisterUnitEvent("UNIT_FLAGS", "target", "focus")
events:SetScript("OnEvent", function(_, event, eventUnit)
  local unit = UNIT_EVENTS[event]
  if unit then
    Follow(function(recordUnit) return recordUnit == unit end)
  elseif event == "UNIT_PET" then
    Follow(function(recordUnit) return recordUnit == "pet" end)
  elseif event == "GROUP_ROSTER_UPDATE" then
    Follow(IsGroupUnit)
  elseif event == "UNIT_FACTION" or event == "UNIT_FLAGS" then
    Reevaluate(function(recordUnit) return recordUnit == eventUnit end)
  elseif not Secret() then
    RefreshAll(true)
  end
end)
