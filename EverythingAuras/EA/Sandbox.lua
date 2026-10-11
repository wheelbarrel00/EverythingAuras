if not EverythingAuras.IsLibsOK() then return end

local Private = select(2, ...)

local standIns = {}

local function Alias(name, func)
  if func then
    standIns[name] = func
  end
end

-- Classic returned 1 and 0 where the new API returns booleans, and a secret value cannot be tested.
local function ToFlag(value, falseValue)
  if issecretvalue(value) or value == nil then
    return value
  end
  if value then
    return 1
  end
  return falseValue
end

local function SpellBank(bookType)
  if bookType == "pet" or bookType == Enum.SpellBookSpellBank.Pet then
    return Enum.SpellBookSpellBank.Pet
  end
  return Enum.SpellBookSpellBank.Player
end

local function SpellBookSpellID(index, bookType)
  local info = C_SpellBook.GetSpellBookItemInfo(index, SpellBank(bookType))
  return info and info.spellID
end

function standIns.GetSpellInfo(spell)
  local info = spell ~= nil and C_Spell.GetSpellInfo(spell)
  if info then
    return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID, info.originalIconID
  end
end

function standIns.GetSpellCooldown(spell)
  local cooldown = spell ~= nil and C_Spell.GetSpellCooldown(spell)
  if cooldown then
    return cooldown.startTime, cooldown.duration, ToFlag(cooldown.isEnabled, 0), cooldown.modRate
  end
end

function standIns.IsSpellInRange(spell, bookType, unit)
  if unit == nil then
    unit = bookType
  else
    spell = SpellBookSpellID(spell, bookType)
  end
  if spell ~= nil then
    return ToFlag(C_Spell.IsSpellInRange(spell, unit), 0)
  end
end

Alias("GetSpellTexture", C_Spell.GetSpellTexture)
Alias("GetSpellPowerCost", C_Spell.GetSpellPowerCost)
Alias("IsCurrentSpell", C_Spell.IsCurrentSpell)

Alias("GetItemInfo", C_Item.GetItemInfo)
Alias("GetItemInfoInstant", C_Item.GetItemInfoInstant)
Alias("GetItemCount", C_Item.GetItemCount)
Alias("GetItemIcon", C_Item.GetItemIconByID)
Alias("GetItemQualityColor", C_Item.GetItemQualityColor)

Alias("GetPetHappiness", C_PetInfo and C_PetInfo.GetPetHappiness)
Alias("GetPetLoyalty", C_PetInfo and C_PetInfo.GetPetLoyalty)

function standIns.GetQuestLogTitle(index)
  local info = C_QuestLog.GetInfo(index)
  if not info then
    return
  end
  local isComplete
  if not info.isHeader and info.questID then
    if C_QuestLog.IsFailed(info.questID) then
      isComplete = -1
    elseif C_QuestLog.IsComplete(info.questID) then
      isComplete = 1
    end
  end
  return info.title, info.level, info.suggestedGroup, info.isHeader, info.isCollapsed, isComplete, info.frequency,
    info.questID, info.startEvent, false, info.isOnMap, info.hasLocalPOI, info.isTask, info.isBounty, info.isStory,
    info.isHidden, info.isScaling
end

Alias("GetQuestLogIndexByID", C_QuestLog.GetLogIndexForQuestID)
Alias("GetNumQuestLogEntries", C_QuestLog.GetNumQuestLogEntries)

function standIns.GetSpellTabInfo(tab)
  local info = C_SpellBook.GetSpellBookSkillLineInfo(tab)
  if info then
    return info.name, info.iconID, info.itemIndexOffset, info.numSpellBookItems, info.isGuild, info.offSpecID
  end
end

function standIns.GetSpellBookItemName(index, bookType)
  local name, subName = C_SpellBook.GetSpellBookItemName(index, SpellBank(bookType))
  if name then
    return name, subName, SpellBookSpellID(index, bookType)
  end
end

Alias("GetNumSpellTabs", C_SpellBook.GetNumSpellBookSkillLines)

function standIns.IsSpellKnown(spellID, isPet)
  return C_SpellBook.IsSpellInSpellBook(spellID, isPet and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player, false)
end

function standIns.IsPlayerSpell(spellID)
  return C_SpellBook.IsSpellKnown(spellID, Enum.SpellBookSpellBank.Player)
end

Alias("IsAddOnLoaded", C_AddOns.IsAddOnLoaded)

if C_PartyInfo and C_PartyInfo.GetLootMethod and Enum.LootMethod then
  local lootMethodNames = {
    [Enum.LootMethod.Freeforall] = "freeforall",
    [Enum.LootMethod.Roundrobin] = "roundrobin",
    [Enum.LootMethod.Masterlooter] = "master",
    [Enum.LootMethod.Group] = "group",
    [Enum.LootMethod.Needbeforegreed] = "needbeforegreed",
    [Enum.LootMethod.Personal] = "personalloot",
  }
  function standIns.GetLootMethod()
    local method, partyID, raidID = C_PartyInfo.GetLootMethod()
    return lootMethodNames[method], partyID, raidID
  end
end

-- Reading the player's auras by index throws while Blizzard keeps them secret, so this answers nothing then.
local function UnitAuraByIndex(unit, index, filter)
  local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
  if ok and aura and not issecrettable(aura) and not issecretvalue(aura.name) then
    return AuraUtil.UnpackAuraData(aura)
  end
end

standIns.UnitAura = UnitAuraByIndex

function standIns.UnitBuff(unit, index, filter)
  return UnitAuraByIndex(unit, index, filter and filter .. "|HELPFUL" or "HELPFUL")
end

function standIns.UnitDebuff(unit, index, filter)
  return UnitAuraByIndex(unit, index, filter and filter .. "|HARMFUL" or "HARMFUL")
end

Private.EAStandIns = {}
for name, func in pairs(standIns) do
  if _G[name] == nil then
    Private.EASandboxOverrides[name] = func
    Private.EAStandIns[name] = true
  end
end
