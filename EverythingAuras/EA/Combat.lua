if not EverythingAuras.IsLibsOK() then return end

local Private = select(2, ...)

local DIM_ALPHA = 0.5
local MARKER = "Interface\\AddOns\\EverythingAuras\\Media\\EA\\marker.tga"
local MARKER_LEVEL = 20

-- A quarter of the aura's shorter side, held between 6 and 14 px (design round 1).
local function MarkerSize(width, height)
  local side = math.min(width or 0, height or 0)
  return math.max(6, math.min(14, math.floor(side / 4 + 0.5)))
end
Private.EAMarkerSize = MarkerSize
Private.EAMarkerTexture = MARKER

-- A trigger state BuffTrigger2 could not confirm while auras are secret carries eaUnsure.
-- At a hide the hiding state is no longer shown but still marked changed for this update.
local function UnsureState(region, includeHiding)
  local states = region.states
  if type(states) ~= "table" then
    return nil
  end
  for triggernum, state in pairs(states) do
    if triggernum > 0 and type(state) == "table" and state.eaUnsure
      and (state.show or (includeHiding and state.changed)) then
      return state.eaUnsure
    end
  end
end
Private.EAUnsureState = UnsureState

-- Only cleanup runs for a guessed state: stopping sounds and hiding glows.
local PerformActions = Private.PerformActions
function Private.PerformActions(data, when, region)
  local actions = data.actions and data.actions[when]
  local unsure = actions and region and UnsureState(region, true)
  -- Blizzard plays the sound of an aura it draws (EA/Native.lua), so it never plays twice.
  local native = actions and actions.do_sound and Private.EANativeSound and Private.EANativeSound(data, when)
  if not (unsure or native) then
    return PerformActions(data, when, region)
  end
  local shadow = { do_sound = false }
  if unsure then
    shadow.do_message = false
    shadow.do_custom = false
    shadow.do_glow = actions.do_glow and actions.glow_action == "hide" or false
  end
  data.actions[when] = setmetatable(shadow, { __index = actions })
  local ok, err = pcall(PerformActions, data, when, region)
  data.actions[when] = actions
  if not ok then
    error(err, 0)
  end
end

local create = Private.regionPrototype.create
function Private.regionPrototype.create(region)
  create(region)
  local SoundPlay, SendChat, RunCode, GlowExternal = region.SoundPlay, region.SendChat, region.RunCode, region.GlowExternal
  function region.SoundPlay(self, ...)
    if not UnsureState(self) then
      return SoundPlay(self, ...)
    end
  end
  function region.SendChat(self, ...)
    if not UnsureState(self) then
      return SendChat(self, ...)
    end
  end
  function region.RunCode(self, ...)
    if not UnsureState(self) then
      return RunCode(self, ...)
    end
  end
  function region.GlowExternal(self, options, ...)
    if not (options and options.glow_action == "show" and UnsureState(self)) then
      return GlowExternal(self, options, ...)
    end
  end
end

-- Every alpha change ends in SetAlpha, so the dim factor survives conditions and animations.
local function FactorSetAlpha(self, alpha)
  local factor = self.eaAlphaFactor or 1
  if factor == 1 or issecretvalue(alpha) then
    return self.eaSetAlpha(self, alpha)
  end
  local shown = (alpha or 1) * factor
  local result = self.eaSetAlpha(self, shown)
  -- A Model region stores the alpha it is given, and GetRegionAlpha must keep returning its own one.
  if not issecretvalue(self.alpha) and self.alpha == shown then
    self.alpha = alpha
  end
  return result
end

local function UpdateUnsureLook(region)
  local unsure = UnsureState(region)
  local data = unsure and EverythingAuras.GetData(region.id)
  -- Blizzard draws the icon of a native aura, so its own parts step aside instead of showing a guess beside it.
  local mode = region.eaNativeOn and "hide" or data and data.eaUnsureDisplay or "dim"
  local factor = 1
  if unsure and mode == "dim" then
    factor = DIM_ALPHA
  elseif unsure and mode == "hide" then
    factor = 0
  end
  if (region.eaAlphaFactor or 1) ~= factor then
    if not region.eaSetAlpha then
      region.eaSetAlpha = region.SetAlpha
      region.SetAlpha = FactorSetAlpha
    end
    region.eaAlphaFactor = factor
    region:SetAlpha(region.GetRegionAlpha and region:GetRegionAlpha() or region.alpha or 1)
  end
  local marked = unsure and mode == "dim" or false
  if marked and not region.eaMarker then
    -- On a frame of its own, so it draws over the cooldown swipe and the texts, which are child frames.
    local holder = CreateFrame("Frame", nil, region)
    holder:SetAllPoints(region)
    local marker = holder:CreateTexture(nil, "OVERLAY")
    marker:SetTexture(MARKER)
    marker:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
    region.eaMarker = holder
    region.eaMarkerTexture = marker
  end
  if region.eaMarker then
    if marked then
      region.eaMarker:SetFrameLevel(region:GetFrameLevel() + MARKER_LEVEL)
      local size = MarkerSize(region:GetWidth(), region:GetHeight())
      region.eaMarkerTexture:SetSize(size, size)
    end
    region.eaMarker:SetShown(marked)
  end
end

Private.EAUpdateUnsureLook = UpdateUnsureLook

local RunConditions = Private.RunConditions
function Private.RunConditions(region, uid, hideRegion)
  UpdateUnsureLook(region)
  return RunConditions(region, uid, hideRegion)
end
