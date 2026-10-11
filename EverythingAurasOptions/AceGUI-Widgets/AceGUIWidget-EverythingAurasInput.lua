if not EverythingAuras.IsLibsOK() then return end

local Type, Version = "EverythingAurasInput", 2
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

local eventCallbacks = {
  OnEditFocusGained = "OnEditFocusGained",
  OnEditFocusLost = "OnEditFocusLost",
  OnEnterPressed = "OnEnterPressed",
  OnShow = "OnShow"
}

local function EventHandler(frame, event)
  local self = frame.obj
  local option = self.userdata.option
  if option and option.callbacks and option.callbacks[event] then
    option.callbacks[event](self)
  end
end

local function Constructor()
  local widget = AceGUI:Create("EditBox")
  widget.type = Type

  for event, callback in pairs(eventCallbacks) do
    widget.editbox:HookScript(event, function(frame) EventHandler(frame, callback) end)
  end

  return widget
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
-- Modified for Everything Auras by tools/ea_transform.py (identifiers renamed), see NOTICE.md
