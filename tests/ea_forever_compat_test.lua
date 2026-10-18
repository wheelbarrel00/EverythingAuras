-- Everything Auras decision 20: Forever's power types, textures, resistances and creature family.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local function read(path)
  local file = assert(io.open(T.repoRoot .. "/" .. path))
  local source = file:read("*a")
  file:close()
  return source
end
local function has(source, text) return source:find(text, 1, true) ~= nil end
local function escaped(path) return (path:gsub("\\", "\\\\")) end

local LOGO_64 = "Interface\\AddOns\\EverythingAuras\\Media\\Textures\\logo_64.tga"
local LOGO_256 = "Interface\\AddOns\\EverythingAuras\\Media\\Textures\\logo_256.tga"
local OUR_LOGO = "Interface\\AddOns\\EverythingAuras\\Media\\EA\\logo.tga"
local SCHOOLS = { "holy", "fire", "nature", "frost", "shadow", "arcane" }
local SECRET = setmetatable({}, { __tostring = function() return "secret" end })

local function load(forever)
  local resistanceArgs = { { name = "resistanceHeader", enable = false } }
  for i, school in ipairs(SCHOOLS) do
    resistanceArgs[#resistanceArgs + 1] = { name = "resistance" .. school, enable = false,
      init = ("select(2, UnitResistance('player', %d))"):format(i) }
  end
  local private = {
    ExecEnv = {},
    power_types = { [0] = "Mana", [1] = "Rage", [2] = "Focus", [3] = "Energy", [4] = "Combo Points",
      [6] = "Runic Power", [9] = "Holy Power", [18] = "Pain" },
    texture_types = {
      Sparks = { ["worldstate-capturebar-spark-green"] = "green", ["worldstate-capturebar-spark-yellow"] = "yellow",
        ["honorsystem-bar-spark"] = "honor" },
      EverythingAuras = { [LOGO_64] = "EverythingAuras logo 64px", [LOGO_256] = "EverythingAuras logo 256px" },
    },
    event_prototypes = {
      ["Character Stats"] = { args = resistanceArgs },
      ["Unit Characteristics"] = { args = {
        { name = "creatureFamilyIndex", enable = false, hidden = true, init = "select(2, UnitCreatureFamily(unit))" },
        { name = "creatureFamily", enable = false, hidden = true, init = "UnitCreatureFamily(unit)" },
      } },
    },
  }
  local env = setmetatable({
    EverythingAuras = { IsLibsOK = function() return true end, IsForever = function() return forever end },
    C_Texture = { GetAtlasInfo = function(atlas) if atlas == "honorsystem-bar-spark" then return {} end end },
    C_CreatureInfo = {
      GetCreatureFamilyIDs = function() return { 1, 2 } end,
      GetCreatureFamilyInfo = function(id) return ({ { name = "Wolf" }, { name = "Cat" } })[id] end,
    },
    issecretvalue = function(value) return value == SECRET end,
  }, { __index = _G })
  setfenv(assert(loadfile(T.repoRoot .. "/EverythingAuras/EA/Compat.lua")), env)("EverythingAuras", private)
  return private
end

local function find(private, prototype, name)
  for _, entry in ipairs(private.event_prototypes[prototype].args) do
    if entry.name == name then return entry end
  end
end

local function eval(init, private, globals)
  local env = setmetatable({ Private = private, unit = "target" }, { __index = setmetatable(globals, { __index = _G }) })
  return setfenv(assert(loadstring("return " .. init)), env)()
end

T.section("The inherited code these changes rely on")
local prototypes = read("EverythingAuras/Prototypes.lua")
local types = read("EverythingAuras/Types.lua")
T.expect(has(prototypes, '["Character Stats"] = {') and has(prototypes, '["Unit Characteristics"] = {'),
  "both prototypes keep their names")
local schoolsRead = true
for i, school in ipairs(SCHOOLS) do
  schoolsRead = schoolsRead and has(prototypes, ('name = "resistance%s"'):format(school))
    and has(prototypes, ("init = \"select(2, UnitResistance('player', %d))\""):format(i))
end
T.expect(schoolsRead and has(prototypes, 'name = "resistanceHeader"'),
  "the inherited resistance filters read the second return, the old Classic order")
T.expect(has(prototypes, 'name = "creatureFamilyIndex"') and has(prototypes, 'init = "select(2, UnitCreatureFamily(unit))"')
  and has(prototypes, 'name = "creatureFamily"'), "the creature family filters keep their names")
T.expect(has(types, '["EverythingAuras"] = {') and has(types, escaped(LOGO_64)) and has(types, escaped(LOGO_256)),
  "the texture picker group still lists WeakAuras' two logos")
T.expect(has(types, '"worldstate-capturebar-spark-green"') and has(types, '"worldstate-capturebar-spark-yellow"'),
  "Types.lua still adds the two capture bar sparks")

T.section("Forever")
local private = load(true)
local powerTypes = {}
for powerType in pairs(private.power_types) do powerTypes[#powerTypes + 1] = powerType end
table.sort(powerTypes)
T.expect(table.concat(powerTypes, ",") == "0,1,2,3,4", "Power Type lists Mana, Rage, Focus, Energy and Combo Points")
local sparks = private.texture_types.Sparks
T.expect(sparks["worldstate-capturebar-spark-green"] == nil and sparks["worldstate-capturebar-spark-yellow"] == nil
  and sparks["honorsystem-bar-spark"] == "honor", "sparks Forever does not have are gone, the others stay")
local logos = private.texture_types.EverythingAuras
T.expect(logos[LOGO_64] == "WeakAuras logo 64px" and logos[LOGO_256] == "WeakAuras logo 256px"
  and logos[OUR_LOGO] == "Everything Auras logo", "WeakAuras' logos carry its name and ours is added")
T.expect(find(private, "Character Stats", "resistanceHeader").enable == true, "the Resistances header shows")
local resistances = { UnitResistance = function() return 0, 5, 7, 2 end }
local allSchools = true
for i, school in ipairs(SCHOOLS) do
  local entry = find(private, "Character Stats", "resistance" .. school)
  allSchools = allSchools and entry.enable == true
    and entry.init == ("select(3, UnitResistance('player', %d))"):format(i)
end
T.expect(allSchools, "all six resistances are on and read the third return")
T.expect(eval(find(private, "Character Stats", "resistanceshadow").init, private, resistances) == 7,
  "a resistance reads effectiveResistance, the value the character window shows")
local family = find(private, "Unit Characteristics", "creatureFamilyIndex")
T.expect(family.enable == true and family.hidden == false, "the Creature Family filter shows")
T.expect(eval(family.init, private, { UnitCreatureFamily = function() return "Wolf", 1 end }) == 1,
  "a plain family reads its ID")
T.expect(eval(family.init, private, { UnitCreatureFamily = function() return SECRET, SECRET end }) == nil,
  "a secret family reads as nothing, so the == test cannot throw")
T.expect(eval(family.init, private, { UnitCreatureFamily = function() end }) == nil, "no family reads as nothing")
T.expect(find(private, "Unit Characteristics", "creatureFamily").enable == true, "the family name is stored for texts")
T.expect(private.creature_family_types[1] == "Wolf" and private.creature_family_types[2] == "Cat",
  "the family list comes from C_CreatureInfo")

T.section("Other clients")
local other = load(false)
T.expect(other.power_types[6] == "Runic Power" and other.texture_types.Sparks["worldstate-capturebar-spark-green"] == "green",
  "power types and sparks stay as they are")
T.expect(other.texture_types.EverythingAuras[OUR_LOGO] == "Everything Auras logo", "the logo labels apply everywhere")
T.expect(find(other, "Character Stats", "resistanceholy").enable == false
  and find(other, "Character Stats", "resistanceholy").init == "select(2, UnitResistance('player', 1))",
  "resistances stay as inherited")
T.expect(other.creature_family_types == nil and find(other, "Unit Characteristics", "creatureFamilyIndex").enable == false,
  "creature family stays as inherited")
T.finish()
