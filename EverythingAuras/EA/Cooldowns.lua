if not EverythingAuras.IsLibsOK() then return end

local Private = select(2, ...)
local L = EverythingAuras.L

-- A loading screen briefly reports every cooldown as ready, so readiness right after one proves nothing.
local SETTLE_SECONDS = 3

local spells = {}
local settleUntil = 0
local characterKey

local function Lengths()
  local db = Private.db
  if not db then
    return nil
  end
  if not characterKey then
    local name, realm = UnitName("player"), GetRealmName()
    if type(name) ~= "string" or type(realm) ~= "string" or issecretvalue(name) or issecretvalue(realm) then
      return nil
    end
    characterKey = name .. "-" .. realm
  end
  db.eaCooldownLengths = db.eaCooldownLengths or {}
  db.eaCooldownLengths[characterKey] = db.eaCooldownLengths[characterKey] or {}
  return db.eaCooldownLengths[characterKey]
end

local function Learned(id)
  local lengths = Lengths()
  local length = lengths and lengths[id]
  return type(length) == "number" and length > 0 and length or nil
end

local function Learn(id, length)
  local lengths = Lengths()
  if lengths then
    lengths[id] = math.floor(length * 1000 + 0.5) / 1000
  end
end

-- Only a plain read is kept, since it may be secret in combat. A GCD-length or zero value means no real cooldown.
local function BaseLength(id, entry)
  if entry.base == nil and GetSpellBaseCooldown then
    local ok, ms = pcall(GetSpellBaseCooldown, id)
    if ok and ms ~= nil and not issecretvalue(ms) then
      entry.base = type(ms) == "number" and ms > 1500 and ms / 1000 or false
    end
  end
  return entry.base or nil
end

local function HasCharges(maxCharges)
  return maxCharges ~= nil and (issecretvalue(maxCharges) or maxCharges > 1)
end

function Private.EAObserveSpellCooldown(id, restricted, ready, maxCharges, start, duration, modRate, paused, isGCD)
  local entry = spells[id]
  if not entry then
    entry = {}
    spells[id] = entry
  end
  local now = GetTime()
  if now < settleUntil then
    return
  end
  entry.charges = HasCharges(maxCharges)
  if not restricted then
    BaseLength(id, entry)
    if paused then
      entry.start, entry.length, entry.ready = nil, nil, nil
    elseif ready ~= true and duration > 0 and not isGCD and start + duration > now then
      local rate = modRate and modRate > 0 and modRate or 1
      local length = duration / rate
      entry.length = length
      entry.start = now + (start + duration - now) / rate - length
      entry.ready = false
      if not entry.charges then
        Learn(id, length)
      end
    else
      entry.start, entry.length, entry.ready = nil, nil, true
    end
    return
  end
  if paused then
    entry.start, entry.length, entry.ready = nil, nil, nil
  elseif ready == true then
    entry.start, entry.length, entry.ready = nil, nil, true
  elseif ready == false then
    if entry.ready == true then
      entry.start = now
      entry.length = Learned(id) or BaseLength(id, entry)
    end
    entry.ready = false
  end
end

function Private.EASpellCooldownEstimate(id)
  local entry = spells[id]
  if not entry or entry.charges then
    return nil
  end
  -- A refresh right after a cast can leave readiness unknown for a moment, and that is not ready.
  if EverythingAuras.IsSpellReady(id) == true then
    return 0, 0, false
  end
  local start, length = entry.start, entry.length
  if start and length and start + length > GetTime() then
    return start, length, true
  end
end

local ALERTS = { sound = true, chat = true, customcode = true, glowexternal = true }

function Private.EAConditionHasAlert(condition)
  if type(condition) ~= "table" or type(condition.changes) ~= "table" then
    return false
  end
  for _, change in ipairs(condition.changes) do
    local property = type(change) == "table" and change.property
    if type(property) == "string" and (ALERTS[property] or property:match("^sub%.%d+%.glow$")) then
      return true
    end
  end
  return false
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LEAVING_WORLD" then
    settleUntil = math.huge
    for _, entry in pairs(spells) do
      entry.ready = nil
    end
  else
    settleUntil = GetTime() + SETTLE_SECONDS
  end
end)

local prototype = Private.event_prototypes["Cooldown Progress (Spell)"]
for _, arg in ipairs(prototype and prototype.args or {}) do
  if arg.name == "secretValuesDescription" then
    arg.text = L["Cooldowns can become secret during combat, encounters, Mythic+ runs, or PvP matches. Some spells are always secret or never secret."]
      .. "\n\n" .. L["When cooldown is secret, progress can still be displayed. The time left is estimated from the spell's cooldown, learned each time you use it out of combat."]
  elseif arg.name == "remaining" then
    arg.desc = "|cffffd200" .. L["Secret values"] .. "|r\n"
      .. L["While the cooldown is secret, this uses the estimated time left: the spell's cooldown learned out of combat, or for some spells its base cooldown until you have used it once. While the cooldown is secret, the aura plays no sounds, sends no chat, runs no custom code and shows no glows. Spells with charges are not estimated."]
  end
end
