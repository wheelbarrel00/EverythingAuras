if not EverythingAuras.IsLibsOK() then return end
---@class Private
local Private = select(2, ...)

local L = EverythingAuras.L
local EUI = LibStub("EverythingUI-1.0")

Private.EAMedia = "Interface\\AddOns\\EverythingAuras\\Media\\EA\\"

local LINKS = {
  docs = {
    title = L["Documentation"],
    text = L["The M33kAuras wiki has a large collection of examples and snippets. Press Ctrl+C to copy the link."],
    url = "https://github.com/m33shoq/M33kAuras/wiki",
  },
  source = {
    title = L["Source Code"],
    text = L["Everything Auras is free software under the GNU General Public License, version 2. Press Ctrl+C to copy the link to its source code."],
    url = "https://github.com/wheelbarrel00/EverythingAuras",
  },
  bug = {
    title = L["Report a Bug"],
    text = L["Report bugs on the issue tracker. Press Ctrl+C to copy the link."],
    url = "https://github.com/wheelbarrel00/EverythingAuras/issues",
  },
  wago = {
    title = L["Find Auras"],
    text = L["Browse Wago, the largest collection of auras. Press Ctrl+C to copy the link."],
    url = "https://wago.io",
  },
  discord = {
    title = L["Join our Discord"],
    text = L["Join the community for help, feedback and updates. Press Ctrl+C to copy the invite."],
    url = "https://discord.gg/vm8K2WfQUE",
  },
}

local ui = EUI:NewContext({
  id = "EA",
  title = "Everything Auras",
  -- The library draws its own "v" before the version, and a tag name already starts with one.
  version = (EverythingAuras.versionString:gsub("^v", "")),
  -- Violet #8152D6, Everything Auras' accent (design round 1)
  accent = { 0x81 / 255, 0x52 / 255, 0xD6 / 255 },
  L = L,
  tooltip = function() return GameTooltip end,
  discord = function() Private.EAShowLink("discord") end,
  labels = {
    discord = L["Join our Discord!"],
    discordTipTitle = L["Join our Discord"],
    discordTip = L["Click to copy the invite link."],
  },
  getLastTab = function() return Private.db and Private.db.eaSettingsPage end,
  setLastTab = function(id) if Private.db then Private.db.eaSettingsPage = id end end,
})
Private.EAUI = ui

-- Field by field, because the library raises on a field it does not know.
function Private.EAShowDialog(opts)
  ui:ShowDialog({
    title = opts.title,
    text = opts.text,
    button1 = opts.button1,
    button2 = opts.button2,
    onAccept = opts.onAccept,
    onCancel = opts.onCancel,
    danger = opts.danger and true or nil,
  })
end

function Private.EAShowLink(key)
  local link = LINKS[key]
  ui:ShowDialog({
    title = link.title,
    text = link.text,
    button1 = L["Close"],
    hasEditBox = true,
    editBoxText = link.url,
    readOnly = true,
  })
end

function Private.EAOpenSettings(page)
  local f = ui:BuildSettings("EverythingAurasSettings")
  if page then ui:SelectTab(page) end
  if f:IsShown() then
    f:Raise()
  else
    ui:ToggleSettings()
  end
end
