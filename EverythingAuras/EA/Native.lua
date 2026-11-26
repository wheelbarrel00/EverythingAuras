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

local records = {}
local spare = {}
-- Dynamic groups Blizzard lays out, by the group's uid, and their members, by the member's uid.
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

local function IsBar(data)
  return data.regionType == "aurabar"
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
  return not IsBar(data) and trigger.matchesShowOn == "showAlways"
end

-- Blizzard's icon covers Everything Auras' missing look, so that look may change only by whether the aura is found.
local function AlwaysConditions(data)
  for _, condition in ipairs(type(data.conditions) == "table" and data.conditions or {}) do
    local check = type(condition) == "table" and condition.check
    if type(check) ~= "table" or check.trigger ~= 1 or check.variable ~= "buffed" or check.checks ~= nil then
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
    if (tonumber(condition.check.value) == 1) == found then
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

local MEMBER_TEXTS = { icon = { ["%s"] = true }, aurabar = { ["%s"] = true, ["%n"] = true, ["%p"] = true } }
local GROWS = { RIGHT = true, LEFT = true, UP = true, DOWN = true, HORIZONTAL = true, VERTICAL = true, GRID = true }
local CENTER_TYPES = { LR = true, RL = true }
local GRID_TYPES = { RD = true, RU = true, LD = true, LU = true, DR = true, DL = true, UR = true, UL = true }
local GROUP_ANCHORS = { SCREEN = true, SELECTFRAME = true }

-- Blizzard places a group's buttons itself, so any part it does not draw would stay where Everything Auras put the aura.
local function OnlyBlizzardParts(data)
  local allowed = MEMBER_TEXTS[data.regionType] or {}
  local subRegions = type(data.subRegions) == "table" and data.subRegions or {}
  local function Plain(sub)
    if type(sub) ~= "table" then
      return false
    end
    if sub.type == "subtext" then
      return sub.text_visible == false or allowed[sub.text_text] == true
    end
    return sub.type == "subbackground" or (sub.type == "subglow" and not sub.glow)
  end
  for _, sub in ipairs(subRegions) do
    if not Plain(sub) then
      return false
    end
  end
  for _, condition in ipairs(type(data.conditions) == "table" and data.conditions or {}) do
    for _, change in ipairs(type(condition) == "table" and type(condition.changes) == "table" and condition.changes or {}) do
      local index = type(change) == "table" and type(change.property) == "string" and change.property:match("^sub%.(%d+)%.")
      local sub = index and subRegions[tonumber(index)]
      if index and not (sub and sub.type == "subtext" and allowed[sub.text_text]) then
        return false
      end
    end
  end
  return true
end

local function Check(data, inGroup)
  if data.regionType ~= "icon" and not IsBar(data) then
    return false, L["Only an Icon or a Progress Bar can be drawn by Blizzard."]
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
  local debuffType = trigger.debuffType or "HELPFUL"
  if debuffType ~= "HELPFUL" and debuffType ~= "HARMFUL" then
    return false, L["Needs Buff or Debuff, not both."]
  end
  if unit == "player" and debuffType == "HARMFUL" then
    return false, L["Blizzard does not draw debuffs on you for addons."]
  end
  -- Blizzard matches a debuff's spell ID only on a unit you cannot assist (AuraContainerUtil.lua:78-80).
  if unit ~= "target" and unit ~= "focus" and debuffType == "HARMFUL" then
    return false, L["Blizzard does not draw debuffs on your pet or your group for addons."]
  end
  local showOn = trigger.matchesShowOn or "showOnActive"
  if showOn == "showOnMissing" then
    return false, L["A Missing reminder holds what it showed when the fight started, because Blizzard draws an aura only while it is there."]
  elseif showOn == "showAlways" then
    if inGroup then
      return false, L["In a dynamic group Blizzard draws only auras set to show while found."]
    end
    if IsBar(data) then
      return false, L["Blizzard draws Show On Always only on icons for now."]
    end
    if not AlwaysConditions(data) then
      return false, L["With Show On Always, Blizzard draws the icon over its missing look, so conditions may only change Desaturate, Color or Alpha by Aura(s) Found."]
    end
  elseif showOn ~= "showOnActive" then
    return false, L["Needs Show On set to Aura(s) Found."]
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
  if trigger.showClones and not inGroup then
    return false, L["Auto-Clone works only inside a dynamic group, where Blizzard lists every match."]
  end
  if inGroup and not OnlyBlizzardParts(data) then
    return false, L["In a dynamic group Blizzard places each aura itself, so the aura may show only what Blizzard draws: no other texts, borders or glows."]
  end
  local filtered = trigger.fetchTooltip and (trigger.use_tooltip or trigger.use_tooltipValue)
  for _, key in ipairs(FLAG_FILTERS) do
    filtered = filtered or trigger[key]
  end
  local _, totalOk = TotalLimit(trigger)
  local _, dispelOk = DispelTypes(trigger)
  if filtered or not totalOk or not dispelOk then
    return false, L["Blizzard cannot apply some of this trigger's filters: stacks, remaining time, name patterns, ignored names, a Total Time other than <=, or the Enrage and None debuff types."]
  end
  if not HasSpells(trigger) then
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
    return false, L["The group must be anchored to the screen or a frame, not to nameplates, unit frames or the mouse."]
  end
  if group.border then
    return false, L["Blizzard cannot draw the group's border."]
  end
  local children = type(group.controlledChildren) == "table" and group.controlledChildren or {}
  if #children == 0 then
    return false, L["The group has no auras."]
  end
  if group.useLimit and (tonumber(group.limit) or 0) < #children then
    return false, L["Blizzard cannot limit the whole group, so its Limit must be at least its number of auras."]
  end
  local first
  for _, id in ipairs(children) do
    local child = EverythingAuras.GetData(id)
    if type(child) ~= "table" then
      return false, L["The group has no auras."]
    end
    if not child.eaNative then
      return false, L["Every aura in the group needs Blizzard Draws This Icon or Blizzard Draws This Bar switched on."]
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
  if not IsBar(data) then
    return "icon"
  end
  return data.inverse and "elapsed" or "remaining"
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
  if trigger.useIgnoreExactSpellId and type(trigger.ignoreAuraSpellids) == "table" then
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
  local filters = { includeSpellIDs = ids, maxDuration = (TotalLimit(trigger)),
    includeDispelTypes = (DispelTypes(trigger)) }
  for _, pair in ipairs(TRISTATE_FILTERS) do
    if trigger[pair[1]] ~= nil then
      filters[pair[2]] = trigger[pair[1]] and true or false
    end
  end
  return filters
end

local function FiltersKey(filters)
  local parts = { Key(filters.includeSpellIDs), tostring(filters.maxDuration),
    filters.includeDispelTypes and Key(filters.includeDispelTypes) or "-" }
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

local Style

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
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(button)
  button:SetIcon(icon)
  record.icon = icon
  if record.variant == "icon" then
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
  local overlay = CreateFrame("Frame", nil, button)
  overlay:SetAllPoints(button)
  record.overlay, record.texts = overlay, {}
  record.texts.count = NewText(overlay, button)
  button:SetApplicationCount(record.texts.count)
  if record.variant ~= "icon" then
    record.texts.name = NewText(overlay, button)
    button:SetSpellName(record.texts.name)
    record.texts.timer = NewText(overlay, button)
    button:SetDurationText(record.texts.timer, {})
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
  widget:SetAlpha(1)
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

function Style(record, data, region)
  local button, icon = record.button, record.icon
  local level = record.member and record.member.group.container:GetFrameLevel() + 1 or region:GetFrameLevel()
  button:SetFrameLevel(level)
  record.overlay:SetFrameLevel(level + 2)

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
  if record.variant == "icon" then
    record.cooldown:SetFrameLevel(level)
    if not record.always then
      -- A texture's alpha is its vertex color's alpha, so the color comes from the aura's setting, not its icon.
      local r, g, b, a = region:GetColor()
      icon:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
    end
    StyleCooldown(record.cooldown, data)
  else
    StyleBar(record, region)
  end
  for _, takeover in ipairs(TAKEOVERS) do
    TakeOver(record, region, takeover)
  end

  button:EnableMouse(false)
  if data.useTooltip then
    button:EnableMouseMotion(true)
    button:SetMouseClickEnabled(false)
  end
  record.styled = true
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

local function ShowOwnParts(record, region, shown)
  if record.variant == "icon" then
    -- Hidden, not faded: color conditions and animations set its vertex color, which would bring the alpha back.
    region.icon:SetShown(shown)
  else
    region.bar:SetShown(shown)
    region.bar.bg:SetShown(shown)
    region.iconFrame:SetShown(shown)
  end
  for _, text in pairs(record.hidden) do
    text:SetShown(shown)
  end
end

local function SetActive(record, data, active)
  record.active = active
  local drawn = active and Drawable(record) or false
  record.drawn = drawn
  record.container:SetShown(drawn)
  if record.under then
    record.under:SetShown(drawn and record.always or false)
  end
  local region = record.region
  if region then
    local wasDrawn = region.eaNativeOn
    region.eaNativeOn = drawn or nil
    ShowOwnParts(record, region, not drawn)
    if record.variant == "icon" then
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

local function Mirror(region)
  if region.eaNativeMirror then
    return
  end
  region.eaNativeMirror = true
  for _, method in ipairs({ "SetTexCoord", "SetDesaturation", "SetDesaturated", "SetVertexColor" }) do
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
  return { container = container, variant = variant, sounds = {}, soundHandles = {}, hidden = {} }
end

-- Slots and containers cannot be removed (CustomAuraContainer.lua:641), so a freed one is reused out of combat.
local function TakeRecord(variant)
  local pool = spare[variant]
  if not Secret() and pool and #pool > 0 then
    return table.remove(pool)
  end
  return NewRecord(variant)
end

local function Release(uid)
  local record = records[uid]
  if not record then
    return
  end
  local data = { useTooltip = false, actions = {} }
  SetActive(record, data, false)
  if record.region and record.region.eaNativeRecord == record then
    record.region.eaNativeRecord = nil
  end
  records[uid] = nil
  record.region, record.unit, record.filter, record.idsKey, record.ids, record.styled = nil, nil, nil, nil, nil, nil
  record.data, record.filtersKey, record.always = nil, nil, nil
  wipe(record.hidden)
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
    Release(uid)
    return
  end
  pending[uid] = nil
  local groupData = GroupParent(data)
  if groupData then
    Release(uid)
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
  if not next(ids) or not KnownIds(data) then
    pending[uid] = true
    if record then
      SetActive(record, data, false)
    end
    return
  end
  local variant = Variant(data)
  if record and record.variant ~= variant then
    Release(uid)
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
  if not record.button then
    container:SetUnit(unit)
    record.button = container:AddAuraSlot(SLOT, filter, {
      candidateFilters = filters,
      initializeFrame = function(button) BuildButton(record, button) end,
    })
  else
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
  if Secret() then
    record.styled = false
    for _, takeover in ipairs(TAKEOVERS) do
      local sub = record.texts and record.texts[takeover.key] and SubText(region, takeover.format)
      if sub then
        record.hidden[takeover.key] = sub.text
      end
    end
  else
    Style(record, data, region)
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
local SORT_EXPIRATION = AuraContainerSortMethod and AuraContainerSortMethod.Expiration or 4

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

local function HideClone(region, drawn, variant)
  region.eaNativeOn = drawn or nil
  if variant == "icon" then
    if region.icon then
      region.icon:SetShown(not drawn)
    end
    if drawn and region.cooldown then
      region.cooldown:Hide()
    end
  elseif region.bar then
    region.bar:SetShown(not drawn)
    region.bar.bg:SetShown(not drawn)
    region.iconFrame:SetShown(not drawn)
  end
  local allowed = MEMBER_TEXTS[variant == "icon" and "icon" or "aurabar"]
  local list = {}
  for _, takeover in ipairs(TAKEOVERS) do
    local sub = allowed[takeover.format] and SubText(region, takeover.format)
    if sub then
      sub.text:SetShown(not drawn)
      list[#list + 1] = sub.text
    end
  end
  cloneHidden[region] = drawn and list or nil
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
    HideClone(clone, member.drawn and true or false, member.variant)
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
    group.container:SetAuraGroupEnabled(member.key, member.drawn)
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
    if ready and (not next(SpellIds(child)) or not KnownIds(child)) then
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
      member = { uid = child.uid, group = group, hidden = {}, sounds = {}, soundHandles = {} }
      members[child.uid] = member
    end
    group.members[child.uid] = member
    local variant = Variant(child)
    local key = child.uid .. ":" .. variant
    if member.key and member.key ~= key then
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
    local count = trigger.showClones and math.huge or 1
    local layout = { layoutIndex = index, elementSpacing = spacing, lineSpacing = lineSpacing, elementWidth = width,
      elementHeight = height }
    if not container:HasAuraGroup(key) then
      group.keys[key] = true
      container:AddAuraGroup(key, filter, {
        candidateFilters = filters,
        sortMethod = SORT_EXPIRATION,
        maxFrameCount = count,
        layout = layout,
        initializeFrame = function(button)
          local part = { member = member, variant = variant, hidden = member.hidden, data = member.data }
          table.insert(member.parts, part)
          BuildButton(part, button)
        end,
      })
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
    if region then
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
            Style(part, child, region)
          end
        end
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

for _, regionType in ipairs({ "icon", "aurabar" }) do
  local regionData = Private.regionTypes[regionType]
  local modify = regionData.modify
  regionData.modify = function(parent, region, data)
    -- Modify returns sub-regions to a shared pool, so a text Blizzard replaced must be visible again first.
    local record = region.eaNativeRecord
    if record then
      for key, text in pairs(record.hidden) do
        text:Show()
        record.hidden[key] = nil
      end
    end
    for _, text in ipairs(cloneHidden[region] or {}) do
      text:Show()
    end
    cloneHidden[region] = nil
    modify(parent, region, data)
    if region.cloneId and region.cloneId ~= "" then
      local member = members[data.uid]
      if member and member.drawn then
        if member.variant == "icon" then
          KeepCooldownHidden(region)
        end
        HideClone(region, true, member.variant)
      elseif region.eaNativeOn then
        HideClone(region, false, Variant(data))
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

local RunConditions = Private.RunConditions
function Private.RunConditions(region, uid, hideRegion)
  if region.eaNativeWanted and not Secret() then
    -- An ID read out of combat is the aura's own, so it is kept with the aura for every later fight.
    local state = region.states and region.states[1]
    local spellId = state and state.show and not state.eaUnsure and state.spellId
    if spellId and not issecretvalue(spellId) and type(spellId) == "number" then
      local data = EverythingAuras.GetData(region.id)
      local trigger = data and data.triggers[1].trigger
      if trigger and not HasId(data.eaNativeIds, spellId) and not HasId(trigger.auraspellids, spellId)
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
  if data.regionType ~= "icon" and not IsBar(data) then
    Release(uid)
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
