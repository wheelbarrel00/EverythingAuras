if not EverythingAuras.IsLibsOK() then return end
---@type string
local AddonName = ...
---@class OptionsPrivate
local OptionsPrivate = select(2, ...)

local L = EverythingAuras.L;

local function createOptions(parentData, data, index, subIndex)
  local areaAnchors = {}
  for child in OptionsPrivate.Private.TraverseLeafsOrAura(parentData) do
    Mixin(areaAnchors, OptionsPrivate.Private.GetAnchorsForData(child, "area"))
  end

  local options = {
    __title = L["Border %s"]:format(subIndex),
    __order = 1,
    border_visible = {
      type = "toggle",
      width = EverythingAuras.doubleWidth,
      name = L["Show Border"],
      order = 2,
    },
    border_edge = {
      type = "select",
      width = EverythingAuras.normalWidth,
      dialogControl = "LSM30_Border",
      name = L["Border Style"],
      order = 3,
      values = AceGUIWidgetLSMlists.border,
    },
    border_color = {
      type = "color",
      width = EverythingAuras.normalWidth,
      name = L["Border Color"],
      hasAlpha = true,
      order = 4,
    },
    border_offset = {
      type = "range",
      control = "EverythingAurasSpinBox",
      width = EverythingAuras.normalWidth,
      name = L["Border Offset"],
      order = 5,
      softMin = 0,
      softMax = 32,
      bigStep = 1,
    },
    border_size = {
      type = "range",
      control = "EverythingAurasSpinBox",
      width = EverythingAuras.normalWidth,
      name = L["Border Size"],
      order = 6,
      min = 1,
      softMax = 64,
      bigStep = 1,
    },
    anchor_area = {
      type = "select",
      width = EverythingAuras.normalWidth,
      control = "EverythingAurasTwoColumnDropdown",
      name = L["Border Anchor"],
      order = 7,
      values = areaAnchors,
      hidden = function() return parentData.regionType ~= "aurabar" end
    },
    border_ppscale = {
      type = "toggle",
      width = EverythingAuras.doubleWidth,
      name = L["Force pixel perfect scale"],
      order = 8,
    }
  }

  OptionsPrivate.AddUpDownDeleteDuplicate(options, parentData, index, "subborder")

  return options
end

EverythingAuras.RegisterSubRegionOptions("subborder", createOptions, L["Shows a border"]);
-- Modified for Everything Auras by tools/ea_transform.py (identifiers renamed), see NOTICE.md
