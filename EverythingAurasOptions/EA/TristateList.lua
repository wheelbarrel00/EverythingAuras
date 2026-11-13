if not EverythingAuras.IsLibsOK() then return end
if not EverythingAuras.IsForever() then return end
---@class OptionsPrivate
local OptionsPrivate = select(2, ...)

local L = EverythingAuras.L
local AceGUI = LibStub("AceGUI-3.0")

local widgetType, widgetVersion = "EverythingAurasTristateList", 1
local COLUMNS, ROW_HEIGHT, LABEL_HEIGHT, BOX = 3, 24, 20, 22
local TIP = L["Click once to load in this tree, twice to never load in it (red cross), and a third time to clear it."]

local function Paint(row)
  row.check:SetShown(row.state == true)
  row.cross1:SetShown(row.state == false)
  row.cross2:SetShown(row.state == false)
end

local function Row_OnClick(row)
  if row.state == true then
    row.state = false
  elseif row.state == false then
    row.state = nil
  else
    row.state = true
  end
  Paint(row)
  row.obj:Fire("OnValueChanged", row.key, row.state)
end

local function Row_OnEnter(row)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(row.text:GetText() or "", 1, 1, 1)
  GameTooltip:AddLine(TIP, 1, 0.82, 0, true)
  GameTooltip:Show()
end

local function Row_OnLeave()
  GameTooltip:Hide()
end

local function NewRow(widget)
  local row = CreateFrame("Button", nil, widget.frame)
  row:SetHeight(ROW_HEIGHT)
  local box = row:CreateTexture(nil, "ARTWORK")
  box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
  box:SetSize(BOX, BOX)
  box:SetPoint("LEFT", row, "LEFT", 0, 0)
  local check = row:CreateTexture(nil, "OVERLAY")
  check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  check:SetAllPoints(box)
  local cross1, cross2 = row:CreateLine(nil, "OVERLAY"), row:CreateLine(nil, "OVERLAY")
  for index, line in ipairs({ cross1, cross2 }) do
    line:SetColorTexture(1, 0.15, 0.15, 1)
    line:SetThickness(2.5)
    line:SetStartPoint(index == 1 and "TOPLEFT" or "TOPRIGHT", box, index == 1 and 5 or -5, -5)
    line:SetEndPoint(index == 1 and "BOTTOMRIGHT" or "BOTTOMLEFT", box, index == 1 and -5 or 5, 5)
  end
  local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", box, "RIGHT", 2, 0)
  text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  text:SetJustifyH("LEFT")
  text:SetWordWrap(false)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row:GetHighlightTexture():SetAlpha(0.3)
  row:SetScript("OnClick", Row_OnClick)
  row:SetScript("OnEnter", Row_OnEnter)
  row:SetScript("OnLeave", Row_OnLeave)
  row:SetMotionScriptsWhileDisabled(true)
  row.box, row.check, row.cross1, row.cross2, row.text, row.obj = box, check, cross1, cross2, text, widget
  return row
end

local function Layout(widget)
  local width = (widget.frame:GetWidth() or 0) / COLUMNS
  for index, row in ipairs(widget.shown) do
    local column, line = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", widget.frame, "TOPLEFT", column * width, -LABEL_HEIGHT - line * ROW_HEIGHT)
    row:SetWidth(width)
  end
  widget.frame:SetHeight(LABEL_HEIGHT + math.ceil(#widget.shown / COLUMNS) * ROW_HEIGHT + 4)
end

local methods = {
  OnAcquire = function(self)
    self:SetDisabled(false)
  end,
  OnRelease = function(self)
    for _, row in ipairs(self.shown) do
      row:Hide()
      row.state, row.key = nil, nil
      self.spare[#self.spare + 1] = row
    end
    self.shown, self.byKey = {}, {}
  end,
  OnWidthSet = function(self)
    Layout(self)
  end,
  SetList = function(self, list)
    self:OnRelease()
    local keys = {}
    for key in pairs(type(list) == "table" and list or {}) do
      keys[#keys + 1] = key
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
      local row = table.remove(self.spare) or NewRow(self)
      row.key = key
      row.text:SetText(list[key])
      Paint(row)
      row:Show()
      self.shown[#self.shown + 1] = row
      self.byKey[key] = row
    end
    Layout(self)
  end,
  SetItemValue = function(self, key, value)
    local row = self.byKey[key]
    if row then
      row.state = value
      Paint(row)
    end
  end,
  SetDisabled = function(self, disabled)
    for _, row in ipairs(self.shown) do
      row:SetEnabled(not disabled)
      row:SetAlpha(disabled and 0.5 or 1)
    end
  end,
  SetLabel = function(self, text)
    self.label:SetText(text or "")
  end,
  SetValue = function() end,
  SetMultiselect = function() end,
}

local function Constructor()
  local frame = CreateFrame("Frame", nil, UIParent)
  frame:Hide()
  local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -2)
  label:SetJustifyH("LEFT")
  local widget = { frame = frame, label = label, type = widgetType, shown = {}, spare = {}, byKey = {} }
  for name, method in pairs(methods) do
    widget[name] = method
  end
  return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(widgetType, Constructor, widgetVersion)

-- A plain checkbox list cannot show never load, so the Specialization list gets three-state boxes.
local GetLoadOptions = OptionsPrivate.GetLoadOptions
function OptionsPrivate.GetLoadOptions(data)
  local load = GetLoadOptions(data)
  local option = type(load.args) == "table" and load.args.multiselect_forever_spec
  if option then
    option.control = widgetType
    option.width = "full"
  end
  return load
end
