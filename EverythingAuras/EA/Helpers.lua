if not EverythingAuras.IsLibsOK() then return end
if not EverythingAuras.IsForever() then return end

local Private = select(2, ...)
local L = EverythingAuras.L

local LOAD_FLAG_EVENT = "EA_LOAD_FLAG"
local loadFlags, flagScanQueued = {}, false

-- Flags live for the session, and one rescan per frame covers every change made in it.
function EverythingAuras.SetLoadFlag(name, value)
  if type(name) ~= "string" or name == "" then
    return
  end
  local set = value and true or nil
  if loadFlags[name] == set then
    return
  end
  loadFlags[name] = set
  if not flagScanQueued then
    flagScanQueued = true
    C_Timer.After(0, function()
      flagScanQueued = false
      Private.ScanForLoads(nil, LOAD_FLAG_EVENT)
    end)
  end
end

function EverythingAuras.SetLoadFlags(flags)
  if type(flags) ~= "table" then
    return
  end
  for name, value in pairs(flags) do
    if type(name) == "string" then
      EverythingAuras.SetLoadFlag(name, value)
    end
  end
end

function EverythingAuras.LoadFlag(name)
  return type(name) == "string" and loadFlags[name] == true
end

local function IndexOfArg(args, name)
  for index, arg in ipairs(args) do
    if arg.name == name then
      return index
    end
  end
end

local loadArgs = Private.load_prototype.args
table.insert(loadArgs, IndexOfArg(loadArgs, "playerTitle") or #loadArgs + 1, {
  name = "loadFlag",
  display = EverythingAuras.newFeatureString .. L["Load Flag"],
  type = "string",
  test = "EverythingAuras.LoadFlag(%q)",
  events = { LOAD_FLAG_EVENT },
  desc = L["Loads while custom code in another aura has set this flag with SetLoadFlag. The name must match exactly, and flags last until you reload."],
})

local SWING_TYPES = { main = 0, off = 1, ranged = 2 }
local SWING_HANDS = { [0] = "main", [1] = "off", [2] = "ranged" }

local StockSwingTimerInfo = EverythingAuras.GetSwingTimerInfo
function EverythingAuras.GetSwingTimerInfo(hand)
  return StockSwingTimerInfo(SWING_HANDS[hand] or hand)
end

function EverythingAuras.WatchSwingTimer()
  EverythingAuras.InitSwingTimer()
end

function EverythingAuras.IsTargetInSwingRange(swingType)
  local check = C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange
  if not check then
    return nil
  end
  local ok, result = pcall(check, SWING_TYPES[swingType] or swingType)
  if not ok or issecretvalue(result) then
    return nil
  end
  return result
end

-- Everything Auras never edits the player's Cooldown Manager or Edit Mode layouts.
function EverythingAuras.SetupClassPackCDM()
  return false
end

local MAIN_SLOT, HARMFUL_SLOT = "main", "harmful"
local overlays = {}
local overlaysByAura = {}
local fontCount = 0

local function SpellList(values)
  local list, seen = {}, {}
  for _, value in ipairs(type(values) == "table" and values or {}) do
    local id = EverythingAuras.SafeToNumber(value)
    if id and id > 0 and id % 1 == 0 and not seen[id] then
      seen[id] = true
      list[#list + 1] = id
    end
  end
  return list
end

local function Border(handle, button)
  local options = handle.options
  if options.border == false then
    return
  end
  local size = tonumber(options.borderSize) or 2
  local color = type(options.border) == "table" and options.border or { 1, 0.85, 0, 1 }
  local edges = {}
  for index, points in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
    { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local edge = button:CreateTexture(nil, "OVERLAY")
    edge:SetColorTexture(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    edge:SetPoint(points[1], button, points[1])
    edge:SetPoint(points[2], button, points[2])
    if index <= 2 then
      edge:SetHeight(size)
    else
      edge:SetWidth(size)
    end
    edges[#edges + 1] = edge
  end
  handle.borders[#handle.borders + 1] = edges
end

-- Runs once per slot button, before Blizzard locks it while auras are secret, so every part is handed over here.
local function BuildOverlayButton(handle, holder, button)
  local options = handle.options
  holder.button = button
  button:ClearAllPoints()
  button:SetAllPoints(handle.container)
  button:EnableMouse(false)
  if options.texture then
    local texture = button:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(button)
    texture:SetTexture(options.texture)
    if type(options.textureCoords) == "table" then
      texture:SetTexCoord(unpack(options.textureCoords, 1, 4))
    end
    holder.texture = texture
  end
  if options.icon then
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(icon)
  end
  if options.swipe ~= false then
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    cooldown:SetDrawBling(false)
    cooldown:SetDrawSwipe(options.swipeVisible ~= false)
    cooldown:SetReverse(options.reverse and true or false)
    cooldown:SetHideCountdownNumbers(options.countdown == false)
    if options.countdownFont or options.countdownSize or options.countdownFlags or options.countdownColor then
      fontCount = fontCount + 1
      local font = CreateFont("EverythingAurasOverlayFont" .. fontCount)
      font:SetFont(options.countdownFont or STANDARD_TEXT_FONT, tonumber(options.countdownSize) or 12,
        options.countdownFlags or "OUTLINE")
      if type(options.countdownColor) == "table" then
        font:SetTextColor(unpack(options.countdownColor, 1, 4))
      end
      cooldown:SetCountdownFont(font:GetName())
    end
    local countdownText = (options.countdownPoint or options.countdownX or options.countdownY)
      and cooldown.GetCountdownFontString and cooldown:GetCountdownFontString()
    if countdownText then
      local point = type(options.countdownPoint) == "string" and options.countdownPoint or "CENTER"
      countdownText:ClearAllPoints()
      countdownText:SetPoint(point, cooldown, point, tonumber(options.countdownX) or 0, tonumber(options.countdownY) or 0)
    end
    button:SetDurationCooldown(cooldown)
    holder.cooldown = cooldown
  end
  if options.stacks then
    local count = button:CreateFontString(nil, "OVERLAY")
    count:SetFont(STANDARD_TEXT_FONT, tonumber(options.stacksSize) or 12, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button:SetApplicationCount(count)
  end
  Border(handle, button)
end

local Handle = {}
Handle.__index = Handle

local function SetSlot(handle, slot, filter, ids)
  local container = handle.container
  local holder = slot == MAIN_SLOT and handle or handle.harmful
  if #ids == 0 then
    if holder and holder.button then
      container:SetAuraSlotEnabled(slot, false)
    end
    return true
  end
  if not holder then
    holder = {}
    handle.harmful = holder
  end
  if not holder.button then
    local ok, button = pcall(container.AddAuraSlot, container, slot, filter, {
      candidateFilters = { includeSpellIDs = ids },
      initializeFrame = function(new) BuildOverlayButton(handle, holder, new) end,
    })
    if not ok then
      holder.button = nil
      return false
    end
    holder.button = holder.button or button
    if not holder.button then
      return false
    end
  else
    container:SetAuraSlotCandidateFilters(slot, { includeSpellIDs = ids })
    container:SetAuraSlotEnabled(slot, true)
  end
  return true
end

function Handle:SetSpellIDs(buffs, debuffs)
  if self.released then
    return
  end
  if buffs ~= nil then
    SetSlot(self, MAIN_SLOT, self.options.filter or "HELPFUL", SpellList(buffs))
  end
  if debuffs ~= nil then
    SetSlot(self, HARMFUL_SLOT, "HARMFUL", SpellList(debuffs))
  end
  self.container:UpdateAllAuras()
end

function Handle:SetUnit(unit)
  if self.released or type(unit) ~= "string" then
    return
  end
  self.unit = unit
  self.container:SetUnit(unit)
  self.container:UpdateAllAuras()
end

function Handle:SetEnabled(enabled)
  if not self.released then
    self.container:SetShown(enabled and true or false)
  end
end

function Handle:SetBorderColor(r, g, b, a)
  for _, edges in ipairs(self.borders) do
    for _, edge in ipairs(edges) do
      edge:SetColorTexture(r or 1, g or 1, b or 1, a or 1)
    end
  end
end

function Handle:SetTexture(texture, coords)
  for _, holder in ipairs({ self, self.harmful }) do
    if holder and holder.texture then
      holder.texture:SetTexture(texture)
      if type(coords) == "table" then
        holder.texture:SetTexCoord(unpack(coords, 1, 4))
      end
    end
  end
end

function Handle:GetButton()
  return self.button
end

function Handle:IsReleased()
  return self.released == true
end

function Handle:CleanupPending()
  return false
end

-- Aura slots cannot be removed (CustomAuraContainer.lua:641), so a released overlay is switched off and hidden.
function Handle:Release()
  if not self.released then
    self.released = true
    overlays[self] = nil
    for _, slot in ipairs({ MAIN_SLOT, HARMFUL_SLOT }) do
      pcall(self.container.SetAuraSlotEnabled, self.container, slot, false)
    end
    self.container:Hide()
  end
  return true
end

function EverythingAuras.AuraOverlay(frame, options)
  if type(frame) ~= "table" or type(frame.GetObjectType) ~= "function" then
    return nil, L["AuraOverlay needs a frame."]
  end
  options = type(options) == "table" and options or {}
  local ok, container = pcall(CreateFrame, "AuraContainer", nil, frame, "CustomAuraContainerTemplate")
  if not ok or not container then
    return nil, L["This client cannot draw aura overlays."]
  end
  pcall(container.SetEditModePreviewEnabled, container, false)
  container:SetAllPoints(frame)
  container:SetFrameLevel(frame:GetFrameLevel() + (tonumber(options.levelOffset) or 5))
  container:EnableMouse(false)
  local handle = setmetatable({ container = container, options = options, borders = {},
    unit = options.unit or "player" }, Handle)
  container:SetUnit(handle.unit)
  if not SetSlot(handle, MAIN_SLOT, options.filter or "HELPFUL", SpellList(options.spellIDs))
    or not SetSlot(handle, HARMFUL_SLOT, "HARMFUL", SpellList(options.debuffSpellIDs)) then
    container:Hide()
    return nil, L["Blizzard refused the aura slot."]
  end
  container:SetShown(options.enabled ~= false)
  container:UpdateAllAuras()
  overlays[handle] = true
  local owner = Private.EACurrentAuraUid and Private.EACurrentAuraUid()
  if owner then
    overlaysByAura[owner] = overlaysByAura[owner] or {}
    overlaysByAura[owner][handle] = true
  end
  return handle
end

-- An aura's environment is cleared on every Add, right before its init runs again, so its overlays retire with it.
local StockClearAuraEnvironment = Private.ClearAuraEnvironment
function Private.ClearAuraEnvironment(id, ...)
  local data = EverythingAuras.GetData(id)
  local owned = data and overlaysByAura[data.uid]
  if owned then
    overlaysByAura[data.uid] = nil
    for handle in pairs(owned) do
      handle:Release()
    end
  end
  if StockClearAuraEnvironment then
    return StockClearAuraEnvironment(id, ...)
  end
end

-- An aura container does not follow target or focus changes on its own (measured, probe N1).
local overlayWatcher = CreateFrame("Frame")
overlayWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
overlayWatcher:RegisterEvent("PLAYER_FOCUS_CHANGED")
overlayWatcher:SetScript("OnEvent", function(_, event)
  local unit = event == "PLAYER_TARGET_CHANGED" and "target" or "focus"
  for handle in pairs(overlays) do
    if handle.unit == unit then
      handle.container:UpdateAllAuras()
    end
  end
end)
