if not EverythingAuras.IsLibsOK() then return end

local Private = select(2, ...)
local L = EverythingAuras.L

local SLOT = "aura"
local UNITS = { player = true, target = true, focus = true }
local UNIT_EVENTS = { PLAYER_TARGET_CHANGED = "target", PLAYER_FOCUS_CHANGED = "focus" }
local SOUND_ACTIONS = { { when = "start", trigger = "Added" }, { when = "finish", trigger = "Removed" } }
local COOLDOWN_UPDATES = { "UpdateValue", "UpdateTime", "UpdateDuration", "PreShow" }
local FLAG_FILTERS = { "useStacks", "useRem", "useTotal", "useNamePattern", "use_debuffClass", "useIgnoreName",
  "useIgnoreExactSpellId" }
local TRISTATE_FILTERS = { "use_stealable", "use_isBossDebuff", "use_castByPlayer" }

local records = {}
local spare = {}
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

-- What Blizzard's aura slot can show exactly as the trigger would (research R3, probes N1 and N8).
function Private.EANativeQualifies(data)
  if data.regionType ~= "icon" then
    return false, L["Only an Icon can be drawn by Blizzard."]
  end
  for parent in Private.TraverseParents(data) do
    if parent.regionType == "dynamicgroup" then
      return false, L["Not available inside a dynamic group, which places its icons from Everything Auras' own state."]
    end
  end
  if type(data.triggers) ~= "table" or #data.triggers ~= 1 then
    return false, L["Needs exactly one trigger."]
  end
  local trigger = data.triggers[1].trigger
  if type(trigger) ~= "table" or trigger.type ~= "aura2" then
    return false, L["Needs an Aura trigger."]
  end
  local unit = trigger.unit or "player"
  if not UNITS[unit] then
    return false, L["Works on Player, Target and Focus."]
  end
  local debuffType = trigger.debuffType or "HELPFUL"
  if debuffType ~= "HELPFUL" and debuffType ~= "HARMFUL" then
    return false, L["Needs Buff or Debuff, not both."]
  end
  if unit == "player" and debuffType == "HARMFUL" then
    return false, L["Blizzard does not draw debuffs on you for addons."]
  end
  if (trigger.matchesShowOn or "showOnActive") ~= "showOnActive" then
    return false, L["Needs Show On set to Aura(s) Found."]
  end
  if trigger.showClones then
    return false, L["Does not work with Auto-Clone."]
  end
  local filtered = trigger.fetchTooltip and (trigger.use_tooltip or trigger.use_tooltipValue)
  for _, key in ipairs(FLAG_FILTERS) do
    filtered = filtered or trigger[key]
  end
  for _, key in ipairs(TRISTATE_FILTERS) do
    filtered = filtered or trigger[key] ~= nil
  end
  if filtered then
    return false, L["Blizzard cannot apply this trigger's extra filters, such as stacks, remaining time or ignore lists."]
  end
  if not HasSpells(trigger) then
    return false, L["Needs Name(s) or Exact Spell ID(s)."]
  end
  return true
end

function Private.EANativeWanted(data)
  return data.eaNative and Private.EANativeQualifies(data) or false
end

local function AddId(ids, value)
  local id = tonumber(value)
  if id and id > 0 then
    ids[id] = true
    return true
  end
end

-- A slot with no spell IDs shows any aura of its kind (probe N0), so it is never built without them.
local function SpellIds(data, record)
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
  if record then
    for id in pairs(record.seen) do
      ids[id] = true
    end
  end
  return ids
end

local function Key(ids)
  local list = {}
  for id in pairs(ids) do
    list[#list + 1] = id
  end
  table.sort(list)
  return table.concat(list, ",")
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

local function StackText(region)
  for _, subRegion in ipairs(region.subRegions or {}) do
    if subRegion.type == "subtext" and subRegion.text_text == "%s" and subRegion.text then
      return subRegion
    end
  end
end

-- Runs once per button, before Blizzard locks it while auras are secret, so all art is handed over here.
local function BuildButton(record, button)
  button:ClearAllPoints()
  button:SetAllPoints(button:GetParent())
  button:EnableMouse(false)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(button)
  button:SetIcon(icon)
  local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
  cooldown:SetAllPoints(button)
  cooldown:SetDrawBling(false)
  button:SetDurationCooldown(cooldown)
  local overlay = CreateFrame("Frame", nil, button)
  overlay:SetAllPoints(button)
  local count = overlay:CreateFontString(nil, "OVERLAY")
  count:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
  count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
  count:SetAlpha(0)
  button:SetApplicationCount(count)
  record.icon, record.cooldown, record.overlay, record.count = icon, cooldown, overlay, count
end

local function Style(record, data, region)
  local button, icon = record.button, record.icon
  local level = region:GetFrameLevel()
  button:SetFrameLevel(level)
  record.cooldown:SetFrameLevel(level)
  record.overlay:SetFrameLevel(level + 1)

  icon:SetTexCoord(region.icon:GetTexCoord())
  icon:SetDesaturation(region.icon:GetDesaturation())
  -- A texture's alpha is its vertex color's alpha (FCF_GetChatWindowInfo reads SetAlpha back that way),
  -- so the color comes from the aura's setting, never from Everything Auras' own icon.
  local r, g, b, a = region:GetColor()
  icon:SetVertexColor(r or 1, g or 1, b or 1, a or 1)

  local cooldown = record.cooldown
  cooldown:SetAlpha(data.cooldown and 1 or 0)
  cooldown:SetDrawSwipe(data.cooldownSwipe ~= false)
  cooldown:SetDrawEdge(data.cooldownEdge and true or false)
  cooldown:SetHideCountdownNumbers(data.cooldownTextDisabled and true or false)
  -- Icon.lua's UpdateEffectiveInverse for an aura state, which carries no inverse of its own.
  cooldown:SetReverse(not data.inverse)

  -- Blizzard's count takes over a text that shows only the stacks, in its font and place.
  local count, stack = record.count, StackText(region)
  local text = stack and stack.text
  if record.hiddenText and record.hiddenText ~= text then
    record.hiddenText:Show()
  end
  record.hiddenText = text
  if text then
    local font, size, flags = text:GetFont()
    if font then
      count:SetFont(font, size, flags)
    end
    count:SetTextColor(stack.color_r or 1, stack.color_g or 1, stack.color_b or 1, stack.color_a or 1)
    count:SetShadowColor(text:GetShadowColor())
    count:SetShadowOffset(text:GetShadowOffset())
    count:SetJustifyH(text:GetJustifyH())
    local point, relativeTo, relativePoint, x, y = text:GetPoint(1)
    if point then
      count:ClearAllPoints()
      count:SetPoint(point, relativeTo, relativePoint, x, y)
    end
    count:SetAlpha(1)
    text:SetShown(not record.active)
  else
    count:SetAlpha(0)
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
  local want = record.active and C_UnitAuras.AddAuraSound and SoundKey(record, data) or nil
  if want == record.soundKey and not force then
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
  local record = data and records[data.uid]
  return record and record.active and record.sounds[when] or false
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

local function SetActive(record, data, active)
  record.active = active
  record.container:SetShown(active)
  local region = record.region
  if region then
    region.eaNativeOn = active or nil
    -- Hidden, not faded: color conditions and animations set its vertex color, which would bring the alpha back.
    region.icon:SetShown(not active)
    if active and region.cooldown then
      region.cooldown:Hide()
    end
    if region.tooltipFrame then
      region.tooltipFrame:EnableMouseMotion(not active and data.useTooltip and true or false)
    end
  end
  if record.hiddenText then
    record.hiddenText:SetShown(not active)
  end
  if active and record.styled == false and not Secret() then
    Style(record, data, region)
  end
  UpdateSounds(record, data)
end

-- Mirrors what Everything Auras does to its own icon texture, while Blizzard allows touching the button.
local function MirrorIcon(region)
  if region.eaNativeMirror then
    return
  end
  region.eaNativeMirror = true
  for _, method in ipairs({ "SetTexCoord", "SetDesaturation", "SetDesaturated", "SetVertexColor" }) do
    hooksecurefunc(region.icon, method, function(_, ...)
      local record = region.eaNativeRecord
      if record and record.icon and not Secret() then
        pcall(record.icon[method], record.icon, ...)
      end
    end)
  end
end

local function NewRecord()
  local ok, container = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
  if not ok or not container then
    return nil
  end
  container:Hide()
  pcall(container.SetEditModePreviewEnabled, container, false)
  return { container = container, seen = {}, sounds = {}, soundHandles = {} }
end

-- Slots and containers cannot be removed (CustomAuraContainer.lua:641), so a freed one is reused out of combat.
local function TakeRecord()
  if not Secret() and #spare > 0 then
    return table.remove(spare)
  end
  return NewRecord()
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
  record.hiddenText = nil
  wipe(record.seen)
  if record.button then
    spare[#spare + 1] = record
  end
end

local function Configure(data, region)
  local uid = data.uid
  local record = records[uid]
  if region and region.cloneId and region.cloneId ~= "" then
    return
  end
  if not (region and Private.EANativeWanted(data)) then
    if record then
      SetActive(record, data, false)
    end
    return
  end
  local trigger = data.triggers[1].trigger
  local unit, filter = trigger.unit or "player", Filter(trigger)
  local ids = SpellIds(data, record)
  if not next(ids) then
    if record then
      SetActive(record, data, false)
    end
    return
  end
  if not record then
    record = TakeRecord()
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
  MirrorIcon(region)

  local container, idsKey = record.container, Key(ids)
  if not record.button then
    container:SetUnit(unit)
    record.button = container:AddAuraSlot(SLOT, filter, {
      candidateFilters = { includeSpellIDs = ids },
      initializeFrame = function(button) BuildButton(record, button) end,
    })
  else
    if record.unit ~= unit then
      container:SetUnit(unit)
    end
    if record.filter ~= filter then
      container:SetAuraSlotFilterString(SLOT, filter)
    end
    if record.idsKey ~= idsKey then
      container:SetAuraSlotCandidateFilters(SLOT, { includeSpellIDs = ids })
    end
  end
  record.unit, record.filter, record.ids, record.idsKey = unit, filter, ids, idsKey

  container:ClearAllPoints()
  container:SetAllPoints(region)
  container:SetFrameStrata(region:GetFrameStrata())
  -- One level under the region, so the button lands on the region's own level, under its texts and borders.
  container:SetFrameLevel(math.max(0, region:GetFrameLevel() - 1))
  container:SetAlpha(data.alpha or 1)
  KeepCooldownHidden(region)
  if Secret() then
    record.styled = false
  else
    Style(record, data, region)
  end
  SetActive(record, data, Private.loaded[data.id] == true and not EverythingAuras.IsPaused())
end

-- A failure here must never break the aura: it falls back to Everything Auras drawing the icon itself.
local function SafeConfigure(data, region)
  local ok, err = pcall(Configure, data, region)
  if not ok then
    local record = records[data.uid]
    if record then
      pcall(SetActive, record, data, false)
    end
    geterrorhandler()(err)
  end
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
end

local iconType = Private.regionTypes.icon
local modify = iconType.modify
iconType.modify = function(parent, region, data)
  -- Modify returns sub-regions to a shared pool, so a stack text Blizzard replaced must be visible again first.
  local record = region.eaNativeRecord
  if record and record.hiddenText then
    record.hiddenText:Show()
    record.hiddenText = nil
  end
  modify(parent, region, data)
  if data.eaNative or region.eaNativeRecord then
    SafeConfigure(data, region)
  end
end

local RunConditions = Private.RunConditions
function Private.RunConditions(region, uid, hideRegion)
  local record = region.eaNativeRecord
  if record and record.active then
    -- A rank read out of combat that the stored spell IDs missed joins the slot's list.
    local state = region.states and region.states[1]
    local spellId = state and state.show and not state.eaUnsure and state.spellId
    if spellId and not issecretvalue(spellId) and not record.ids[spellId] and not Secret() then
      record.seen[spellId] = true
      local data = EverythingAuras.GetData(region.id)
      if data then
        SafeConfigure(data, region)
      end
    end
  end
  return RunConditions(region, uid, hideRegion)
end

local Pause = Private.Pause
function Private.Pause(...)
  Pause(...)
  RefreshAll()
end

Private.callbacks:RegisterCallback("ScanForLoads", function()
  RefreshAll()
end)
Private.callbacks:RegisterCallback("Add", function(_, uid, id, data)
  if records[uid] then
    SafeConfigure(data, EverythingAuras.GetRegion(id))
  end
end)
Private.callbacks:RegisterCallback("Delete", function(_, uid)
  Release(uid)
end)

local events = CreateFrame("Frame")
Private.frames["Everything Auras Native Icons"] = events
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_FOCUS_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
events:SetScript("OnEvent", function(_, event)
  local unit = UNIT_EVENTS[event]
  if unit then
    -- The container does not follow unit changes itself (probe N1b).
    for _, record in pairs(records) do
      if record.active and record.unit == unit then
        record.container:UpdateAllAuras()
      end
    end
  elseif not Secret() then
    RefreshAll(true)
  end
end)
