if not EverythingAuras.IsLibsOK() then return end
---@class Private
local Private = select(2, ...)

local L = EverythingAuras.L
local ui = Private.EAUI

local WHATS_NEW_VERSION = "0.1.0-beta"

local ENTRIES = {
  {
    title = L["Your auras on WoW Forever"],
    desc = L["Everything Auras is a fork of WeakAuras for WoW Forever, built on M33kAuras. Strings from WeakAuras, M33kAuras and ForeverAuras import, with a note wherever Forever works differently."],
  },
  {
    title = L["Auras that stay put in combat"],
    desc = L["When Forever hides an aura in combat, it stays shown as last known, dimmed with a marker, until its timer runs out. Your own buffs start over from your casts. Nothing unsure plays a sound or glows."],
  },
  {
    title = L["ForeverAuras imports"],
    desc = L["Aura (Modern) triggers become standard Aura triggers matched by spell name, spec restrictions become class restrictions, and old media paths point at the same files."],
  },
  {
    title = L["Warnings that say what won't work"],
    desc = L["Auras that use the combat log, secret health values or functions Forever lacks are marked, and older Classic functions get stand-ins inside custom code."],
  },
  {
    title = L["One broken aura can't flood your errors"],
    desc = L["After 10 Lua errors in a session, that aura's custom code switches off, with a button to turn it back on."],
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
