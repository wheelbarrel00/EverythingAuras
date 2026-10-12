if not EverythingAuras.IsLibsOK() then return end

local Private = select(2, ...)

local DIM_ALPHA = 0.5

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
  if not (actions and region and UnsureState(region, true)) then
    return PerformActions(data, when, region)
  end
  data.actions[when] = setmetatable({
    do_message = false,
    do_sound = false,
    do_custom = false,
    do_glow = actions.do_glow and actions.glow_action == "hide" or false,
  }, { __index = actions })
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
  if factor ~= 1 and not issecretvalue(alpha) then
    alpha = (alpha or 1) * factor
  end
  return self.eaSetAlpha(self, alpha)
end

local function UpdateUnsureLook(region)
  local unsure = UnsureState(region)
  local data = unsure and EverythingAuras.GetData(region.id)
  local mode = data and data.eaUnsureDisplay or "dim"
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
    region.eaMarker = region:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    region.eaMarker:SetPoint("TOPRIGHT", region, "TOPRIGHT", 0, 0)
    region.eaMarker:SetText("~")
  end
  if region.eaMarker then
    region.eaMarker:SetShown(marked)
  end
end

local RunConditions = Private.RunConditions
function Private.RunConditions(region, uid, hideRegion)
  UpdateUnsureLook(region)
  return RunConditions(region, uid, hideRegion)
end
