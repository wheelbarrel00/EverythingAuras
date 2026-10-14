if not EverythingAuras.IsLibsOK() then return end
---@class Private
local Private = select(2, ...)

local L = EverythingAuras.L
local ui = Private.EAUI
local LDBIcon = LibStub("LibDBIcon-1.0")

local KEY_COLUMN = 150
local EXAMPLE_ICON = 40
local EXAMPLE_WIDTH = 166
local QUESTION_MARK_ICON = 134400

local LIBRARIES = "Ace3, Archivist, Chomp, LibAdvFlyable, LibCompress, LibCustomGlow, LibDataBroker, LibDBIcon, LibDeflate, "
  .. "LibGetFrame, LibRangeCheck, LibSerialize, LibSharedMedia, LibSpecialization, LibSpellRange, LibUIDropDownMenu, "
  .. "LibAPIAutoComplete, TaintLess "
  .. L["and"] .. " EverythingUI."

local function Bright(text)
  local r, g, b = ui:Color("text")
  return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), text)
end

local function Stack()
  local prev
  return function(card)
    local gap = prev and -ui:Spacing("groupGap") or 0
    card:SetPoint("TOPLEFT", prev or card:GetParent(), prev and "BOTTOMLEFT" or "TOPLEFT", 0, gap)
    card:SetPoint("TOPRIGHT", prev or card:GetParent(), prev and "BOTTOMRIGHT" or "TOPRIGHT", 0, gap)
    prev = card
    return card
  end
end

local PARAGRAPH_GAP = 10

local function TextBlock(content, lines, style)
  local block = ui:CreateTextBlock(content)
  for i, line in ipairs(lines) do
    block:AddLine(line, style, i > 1 and { gap = PARAGRAPH_GAP } or nil)
  end
  return block
end

-- A term in the label column and a wrapping description beside it, measured like a text block.
local function KeyValue(content, key, value)
  local f = CreateFrame("Frame", nil, content)
  f:SetSize(600, 1)
  f._euiFill = true
  local k = ui:CreateText(f, key, "value")
  k:SetPoint("TOPLEFT")
  k:SetWidth(KEY_COLUMN)
  k:SetJustifyH("LEFT")
  local v = ui:CreateText(f, value, "label")
  v:SetPoint("TOPLEFT", KEY_COLUMN + ui:Spacing("controlGap"), 0)
  v:SetPoint("TOPRIGHT")
  v:SetJustifyH("LEFT")
  v:SetWordWrap(true)
  function f.Measure()
    local h = math.max(v:GetStringHeight() or 0, k:GetStringHeight() or 0)
    if h <= 0 then h = 13 end
    f:SetHeight(h)
    return h
  end
  f:Measure()
  return f
end

local function ButtonRow(content, buttons)
  local row = CreateFrame("Frame", nil, content)
  row:SetHeight(ui:Spacing("buttonHeight"))
  local prev
  for _, def in ipairs(buttons) do
    local b = ui:CreateButton(content, def[1], nil, def[2])
    if prev then
      b:SetPoint("LEFT", prev, "RIGHT", ui:Spacing("buttonGap"), 0)
    else
      b:SetPoint("LEFT", row, "LEFT")
    end
    prev = b
  end
  return row
end

-- Three sample auras: read now, last known and an estimate, the last two drawn as unsure auras are.
local function Examples(content)
  local samples = {
    { spell = 20289, unsure = false, title = L["Read now"], note = L["exact"] },
    { spell = 19740, unsure = true, title = L["Last known"], note = L["from before the fight"] },
    { spell = 20289, unsure = true, title = L["Estimate"], note = L["from your cast"] },
  }
  local f = CreateFrame("Frame", nil, content)
  f:SetSize(EXAMPLE_WIDTH * #samples, EXAMPLE_ICON + 44)
  for i, sample in ipairs(samples) do
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(EXAMPLE_ICON, EXAMPLE_ICON)
    icon:SetPoint("TOP", f, "TOPLEFT", (i - 0.5) * EXAMPLE_WIDTH, 0)
    icon:SetTexture(C_Spell.GetSpellTexture(sample.spell) or QUESTION_MARK_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if sample.unsure then
      icon:SetAlpha(0.5)
      local marker = f:CreateTexture(nil, "OVERLAY")
      local size = Private.EAMarkerSize(EXAMPLE_ICON, EXAMPLE_ICON)
      marker:SetSize(size, size)
      marker:SetTexture(Private.EAMarkerTexture)
      marker:SetPoint("TOPRIGHT", icon, "TOPRIGHT")
      marker:SetAlpha(0.5)
    end
    local title = ui:CreateText(f, sample.title, "value")
    title:SetPoint("TOP", icon, "BOTTOM", 0, -8)
    local note = ui:CreateText(f, sample.note, "hint")
    note:SetPoint("TOP", title, "BOTTOM", 0, -2)
  end
  return f
end

local function CombatPage(_, content)
  local stack = Stack()
  local auras = stack(ui:CreateGroup(content, L["Auras in combat"]))
  auras:Add(TextBlock(content, {
    L["In combat, WoW Forever hides the details of auras from addons. Everything Auras can tell that an aura was added or removed, but not which one."],
    L["So it keeps what it read before the fight. An aura it can no longer read stays shown as %s, dimmed with a marker, until its timer runs out."]:format(Bright(L["last known"])),
    L["When you cast one of your own buffs on yourself, it starts over from your cast as an %s, with the length Everything Auras learned out of combat. A buff of the same length that it replaces, such as another seal, goes away."]:format(Bright(L["estimate"])),
    L["A dimmed aura never plays a sound, glows, sends chat or runs its actions. A Missing reminder waits for the fight to end instead of appearing from a guess. When the fight ends, everything is read again."],
  }), { fitHeight = true })
  auras:Add(Examples(content), { height = EXAMPLE_ICON + 44 + 24 })
  auras:Add(TextBlock(content, {
    L["Each aura can show these dimmed, hidden or normally: Display tab, Position and Size Settings, When Unsure in Combat."],
  }, "hint"), { fitHeight = true })

  local works = stack(ui:CreateGroup(content, L["What else works in combat"]))
  for _, row in ipairs({
    { L["Spell cooldowns"], L["The swipe, and whether the spell is ready."] },
    { L["Item cooldowns"], L["Everything, including the time left."] },
    { L["Your casts"], L["Which spell you cast."] },
    { L["Health"], L["Bars draw, but the numbers can't be compared or used in math. Your maximum health can, a target's can't."] },
    { L["Combat log"], L["Closed to addons on WoW Forever. Auras that need it stay off and carry a warning."] },
  }) do
    works:Add(KeyValue(content, row[1], row[2]), { fitHeight = true })
  end

  local imports = stack(ui:CreateGroup(content, L["Imports"]))
  imports:Add(TextBlock(content, {
    L["Strings from WeakAuras, M33kAuras and ForeverAuras import. ForeverAuras' Aura (Modern) triggers become standard Aura triggers matched by spell name, its spec restrictions become class restrictions, and its media paths point at the same files here. Each converted aura carries a note."],
    L["An aura that uses something WoW Forever lacks, such as the combat log, secret health values or an old function with no stand-in, carries a warning icon that says what won't work."],
  }), { fitHeight = true })

  local code = stack(ui:CreateGroup(content, L["Custom code"]))
  code:Add(TextBlock(content, {
    L["Older Classic functions that WoW Forever lacks, such as GetSpellInfo and UnitBuff, have stand-ins inside aura custom code. UnitBuff and the other aura reads work out of combat and return nothing while auras are hidden."],
    L["If an aura's custom code causes 10 Lua errors in one session, Everything Auras switches that code off and says so. Fix the code, then use Turn Custom Code Back On in the aura's Information tab, or /reload."],
  }), { fitHeight = true })
end

local function GeneralPage(_, content)
  local stack = Stack()
  local updates = stack(ui:CreateGroup(content, L["Updates"]))
  updates:Add(ui:CreateCheckbox(content, L["Show What's New after an update"],
    function() return Private.db.eaShowWhatsNew ~= false end,
    function(on) Private.db.eaShowWhatsNew = on end,
    L["Opens What's New once after Everything Auras updates."]))
  updates:Add(ButtonRow(content, { { L["Show What's New"], function() Private.EAShowWhatsNew() end } }), { fill = true })

  local minimap = stack(ui:CreateGroup(content, L["Minimap"]))
  minimap:Add(ui:CreateCheckbox(content, L["Show Minimap Button"],
    function() return not (Private.db.minimap and Private.db.minimap.hide) end,
    function(on)
      Private.db.minimap.hide = not on
      if on then
        LDBIcon:Show("EverythingAuras")
      else
        LDBIcon:Hide("EverythingAuras")
      end
    end,
    L["A left-click on the minimap button opens the options. The same as /eauras minimap."]))

  local commands = stack(ui:CreateGroup(content, L["Commands"]))
  local shortTip = L["/wa and /ea are taken at login only when no other addon uses them."]
  for _, row in ipairs({
    { "/eauras", L["Open or close the options. Also /everythingauras."] },
    { "/eauras settings", L["Open this window."] },
    { "/eauras help", L["List every command in chat."] },
    { "/wa", Private.EAShortCommands["/wa"] and "Everything Auras" or L["Used by another addon"], shortTip },
    { "/ea", Private.EAShortCommands["/ea"] and "Everything Auras" or L["Used by another addon"], shortTip },
  }) do
    local line = ui:CreateTextRow(content, row[1], row[2])
    line.label:SetTextColor(ui:Color("text"))
    if row[3] then ui:AttachTooltip(line, row[1], row[3]) end
    commands:Add(line, { height = ui:Spacing("listRowHeight") })
  end
end

local function AboutPage(_, content)
  local stack = Stack()
  local hero = stack(ui:CreateGroup(content, nil))
  local intro = ui:CreateTextBlock(content)
  intro:AddLine("Everything Auras", "title")
  intro:AddLine(L["Version %s"]:format((EverythingAuras.versionString:gsub("^v", ""))), "hint", { gap = 2 })
  intro:AddLine(L["A modified fork of WeakAuras for WoW Forever, built on M33kAuras. Maintained by Wheelbarrel00."], "label")
  hero:Add(intro, { fitHeight = true })

  local credits = stack(ui:CreateGroup(content, L["Credits"]))
  for _, row in ipairs({
    { "WeakAuras", L["By the WeakAuras Team and its contributors."] },
    { "M33kAuras", L["m33shoq's port of WeakAuras to the Midnight engine, by m33shoq and its contributors."] },
    { L["Libraries"], LIBRARIES },
    { L["Sounds and media"], L["Each keeps its own license. The license texts are in the addon's Media folder."] },
  }) do
    credits:Add(KeyValue(content, row[1], row[2]), { fitHeight = true })
  end

  local license = stack(ui:CreateGroup(content, L["License"]))
  license:Add(TextBlock(content, {
    L["Everything Auras is free software under the GNU General Public License, version 2, and comes with no warranty. It is not an official release of, or endorsed by, WeakAuras or M33kAuras."],
  }), { fitHeight = true })
  license:Add(ButtonRow(content, { { L["Copy Source Link"], function() Private.EAShowLink("source") end } }), { fill = true })

  local help = stack(ui:CreateGroup(content, L["Help"]))
  help:Add(ButtonRow(content, {
    { L["Report a Bug"], function() Private.EAShowLink("bug") end },
    { L["Find Auras on Wago"], function() Private.EAShowLink("wago") end },
    { L["Join our Discord"], function() Private.EAShowLink("discord") end },
    { L["What's New"], function() Private.EAShowWhatsNew() end },
  }), { fill = true })
end

ui:RegisterTab({ id = "combat", title = L["In Combat"], order = 10, icon = Private.EAMedia .. "icon-combat.tga", build = CombatPage })
ui:RegisterTab({ id = "general", title = L["General"], order = 20, icon = ui:Texture("icon-general"), build = GeneralPage })
ui:RegisterTab({ id = "about", title = L["About"], order = 30, icon = ui:Texture("icon-about"), build = AboutPage })
