if not EverythingAuras.IsLibsOK() then return end
---@class OptionsPrivate
local OptionsPrivate = select(2, ...)

local AceGUI = LibStub("AceGUI-3.0")

-- A footer button like the options window's own, opening a page of the Everything Auras window.
function OptionsPrivate.EAFooterButton(title, texture, page)
  local button = AceGUI:Create("EverythingAurasToolbarButton")
  button:SetSmallFont(true)
  button:SetText(title)
  button:SetTexture(texture)
  button:SetCallback("OnClick", function()
    OptionsPrivate.Private.EAOpenSettings(page)
  end)
  button.frame:Show()
  return button.frame
end
