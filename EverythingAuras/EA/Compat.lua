if not EverythingAuras.IsLibsOK() then return end

local Private = select(2, ...)

-- Same returns as Blizzard's GetWeaponEnchantInfo shim, which exists only while loadDeprecationFallbacks is on.
function Private.GetWeaponEnchantInfo()
  local values = {}
  local offset = 1
  for _, slot in ipairs({ INVSLOT_MAINHAND, INVSLOT_OFFHAND, INVSLOT_RANGED }) do
    local info = C_PaperDollInfo.GetTemporaryEnchantmentInfo(slot)
    if info then
      values[offset] = true
      values[offset + 1] = info.remainingTimeMs
      values[offset + 2] = info.chargesRemaining
      values[offset + 3] = info.enchantID
    else
      values[offset] = false
    end
    offset = offset + 4
  end
  return unpack(values, 1, offset - 1)
end

local logos = Private.texture_types.EverythingAuras
if logos then
  logos["Interface\\AddOns\\EverythingAuras\\Media\\Textures\\logo_64.tga"] = "WeakAuras logo 64px"
  logos["Interface\\AddOns\\EverythingAuras\\Media\\Textures\\logo_256.tga"] = "WeakAuras logo 256px"
  logos["Interface\\AddOns\\EverythingAuras\\Media\\EA\\logo.tga"] = "Everything Auras logo"
end

if not EverythingAuras.IsForever() then return end

-- Vanilla players and pets use only Mana, Rage, Focus, Energy and Combo Points.
local vanillaPowerTypes = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true }
for powerType in pairs(Private.power_types) do
  if not vanillaPowerTypes[powerType] then
    Private.power_types[powerType] = nil
  end
end

-- Types.lua adds these for clients before 8.1.5, a check Forever's interface 16001 passes.
for _, atlas in ipairs({ "worldstate-capturebar-spark-green", "worldstate-capturebar-spark-yellow" }) do
  if not C_Texture.GetAtlasInfo(atlas) then
    Private.texture_types.Sparks[atlas] = nil
  end
end

-- Forever's character window shows the third return, effectiveResistance (Blizzard's Camelot PaperDollFrame.lua:718).
local resistanceSchools = {
  resistanceholy = 1, resistancefire = 2, resistancenature = 3, resistancefrost = 4, resistanceshadow = 5,
  resistancearcane = 6,
}
for _, arg in ipairs(Private.event_prototypes["Character Stats"].args) do
  if arg.name == "resistanceHeader" then
    arg.enable = true
  elseif resistanceSchools[arg.name] then
    arg.enable = true
    arg.init = ("select(3, UnitResistance('player', %d))"):format(resistanceSchools[arg.name])
  end
end

function Private.ExecEnv.EANotSecret(value)
  if not issecretvalue(value) then
    return value
  end
end

-- The family and type filters compare with ==, which throws on a secret value.
for _, arg in ipairs(Private.event_prototypes["Unit Characteristics"].args) do
  if arg.name == "creatureFamilyIndex" then
    arg.enable, arg.hidden = true, false
    arg.init = "Private.ExecEnv.EANotSecret((select(2, UnitCreatureFamily(unit))))"
  elseif arg.name == "creatureFamily" then
    arg.enable = true
  elseif arg.name == "creatureTypeIndex" then
    arg.init = "Private.ExecEnv.EANotSecret((select(2, UnitCreatureType(unit))))"
  end
end

Private.creature_family_types = {}
for _, familyID in ipairs(C_CreatureInfo.GetCreatureFamilyIDs()) do
  local familyInfo = C_CreatureInfo.GetCreatureFamilyInfo(familyID)
  if familyInfo then
    Private.creature_family_types[familyID] = familyInfo.name
  end
end
