if not EverythingAuras.IsLibsOK() then return end
---@class Private
local Private = select(2, ...)

local L = EverythingAuras.L
local ui = Private.EAUI

local WHATS_NEW_VERSION = "0.7.0-beta"

local ENTRIES = {
  {
    title = L["Blizzard draws more of your auras"],
    desc = L["Many Texture, Text and Progress Texture auras are drawn by Blizzard, in combat too. A texture shows while the aura is there, a text shows one %p, %s or %n with fixed words, and a progress texture fills straight or round. Icon and bar timers use the aura's own time format and keep their Remaining Time colors in combat, and glows that are always on and Square Full White borders are drawn by Blizzard."],
  },
  {
    title = L["Dynamic groups in combat"],
    desc = L["A dynamic group set to Sort None is laid out by Blizzard when it can draw every aura in it, so an aura that drops mid-fight leaves no gap. An Auto-Clone aura there lists every match, the one ending soonest first. On WoW Forever, ForeverAuras' Modern Aura Groups now import as dynamic groups."],
  },
  {
    title = L["Reminders and filters"],
    desc = L["An icon set to Show On Always shows its missing look, and Blizzard draws the aura over it while it is there, when that look is the icon itself, desaturated, dimmed or recolored. Filters such as a Total Time of at most a number, a Debuff Type and cast by you keep an aura drawn by Blizzard, and Blizzard draws an aura that names no spell, debuffs on you included."],
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
