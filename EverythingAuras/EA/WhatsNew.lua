if not EverythingAuras.IsLibsOK() then return end
---@class Private
local Private = select(2, ...)

local L = EverythingAuras.L
local ui = Private.EAUI

local WHATS_NEW_VERSION = "0.3.0-beta"

local ENTRIES = {
  {
    title = L["Blizzard draws your icons"],
    desc = L["Turn on Blizzard Draws This Icon on an Icon aura, and Blizzard draws its icon, swipe and timer, in combat too, the moment the aura changes. It works for one Aura trigger on Player, Target or Focus, but not for debuffs on you. You find it at the top of the Display tab."],
  },
  {
    title = L["Sounds in combat"],
    desc = L["When Blizzard draws an icon, its On Show and On Hide sound files play through Blizzard, so they play in combat too. Blizzard stops a sound after 5 seconds, and with Own Only set the aura keeps its own sounds."],
  },
  {
    title = L["ForeverAuras imports"],
    desc = L["Aura (Modern) icons that Blizzard can draw have it switched on, also the ones you imported before, and their note says so."],
  },
  {
    title = L["Equipment slots"],
    desc = L["Item triggers list the Ammo and Ranged slots, and no longer list profession slots WoW Forever doesn't have."],
  },
}

local WIDTH, HEIGHT = 600, 560
local PAD_TOP, PAD_SIDE, PAD_BOTTOM = 20, 24, 24
local HEAD_GAP, SECTION_GAP = 4, 16
local FOOTER_H, BAR_ROOM = 56, 10

local frame

local function MarkSeen()
  if Private.db then Private.db.eaSeenWhatsNew = WHATS_NEW_VERSION end
end

local function Build()
  if frame then return frame end
  local f = ui:CreateWindow({ name = "EverythingAurasWhatsNew", title = L["What's New"], width = WIDTH, height = HEIGHT })
  f:SetSection("Everything Auras " .. WHATS_NEW_VERSION)
  f:AddHeaderButton("icon-discord", L["Join our Discord"], L["Click to copy the invite link."],
    function() Private.EAShowLink("discord") end)
  -- Closing it any way at all, Escape included, counts as having seen it.
  f:HookScript("OnHide", MarkSeen)

  local area = ui:CreateScrollArea(f.body, {})
  area:SetPoint("TOPLEFT", f.body, "TOPLEFT")
  area:SetPoint("BOTTOMRIGHT", f.body, "BOTTOMRIGHT", 0, FOOTER_H)
  local notes = ui:CreateTextBlock(area.content)
  notes:SetPoint("TOPLEFT", area.content, "TOPLEFT", PAD_SIDE, -PAD_TOP)
  notes:SetPoint("TOPRIGHT", area.content, "TOPRIGHT", -PAD_SIDE, -PAD_TOP)
  for i, entry in ipairs(ENTRIES) do
    notes:AddLine(entry.title, "title", { gap = (i > 1) and SECTION_GAP or nil })
    notes:AddLine(entry.desc, "label", { gap = HEAD_GAP })
  end

  local footer = CreateFrame("Frame", nil, f.body)
  footer:SetPoint("BOTTOMLEFT")
  footer:SetPoint("BOTTOMRIGHT")
  footer:SetHeight(FOOTER_H)
  footer._controls = {}
  ui:Paint(footer, "chrome", "divider", "T")

  f.dontShow = ui:CreateCheckbox(footer, L["Don't show this again"],
    function() return Private.db and Private.db.eaShowWhatsNew == false end,
    function(on) if Private.db then Private.db.eaShowWhatsNew = not on end end)
  f.dontShow:SetPoint("LEFT", footer, "LEFT", PAD_SIDE, 0)

  f.gotIt = ui:CreateButton(footer, L["Got it"], nil, function() f:Hide() end, nil, "primary")
  f.gotIt:SetPoint("RIGHT", footer, "RIGHT", -PAD_SIDE, 0)
  f.combat = ui:CreateButton(footer, L["What Works in Combat"], nil, function()
    f:Hide()
    Private.EAOpenSettings("combat")
  end)
  f.combat:SetPoint("RIGHT", f.gotIt, "LEFT", -ui:Spacing("buttonGap"), 0)

  -- Text measured while hidden can be short of the text as drawn, so it is measured again once shown.
  local function Layout()
    local h = PAD_TOP + notes:Measure() + PAD_BOTTOM
    -- The scroll frame's own width, which leaves room for the bars, so the notes never scroll sideways.
    local w = area.scroll:GetWidth() or 0
    if w <= 0 then w = WIDTH - BAR_ROOM end
    area:SetContentSize(w, h)
    f.gotIt:Fit()
    f.combat:Fit()
  end
  Layout()
  f:HookScript("OnShow", function()
    f.dontShow:Refresh()
    C_Timer.After(0, Layout)
  end)

  frame = f
  return f
end

function Private.EAShowWhatsNew()
  local f = Build()
  f:Show()
  f:Raise()
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  local db = Private.db
  if db and db.eaShowWhatsNew ~= false and db.eaSeenWhatsNew ~= WHATS_NEW_VERSION then
    -- After the login burst, so the chat messages and other addons' windows have settled.
    C_Timer.After(2, Private.EAShowWhatsNew)
  end
end)
