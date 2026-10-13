if not EverythingAuras.IsLibsOK() then return end
---@class OptionsPrivate
local OptionsPrivate = select(2, ...)

local L = EverythingAuras.L

local FOOTER_HEIGHT = 48
local FOOTER_PADDING = 24
local BUTTON_GAP = 10
-- The library's resize grip sits in the footer's bottom-right corner.
local GRIP_ROOM = 20

OptionsPrivate.EAFoldedWidth = 300
OptionsPrivate.EAFoldedHeight = 48
OptionsPrivate.EAFooterHeight = FOOTER_HEIGHT

-- The options window on the library's window (design round 2). Its size is saved through the
-- grip, its position by the options' own code, which places it right after this returns.
function OptionsPrivate.EACreateOptionsWindow(odb, width, height, minWidth, minHeight)
  local f
  f = OptionsPrivate.Private.EAUI:CreateWindow({
    name = "EverythingAurasOptions",
    title = "Everything Auras",
    width = width,
    height = height,
    minWidth = minWidth,
    minHeight = minHeight,
    getSize = function()
      local saved = odb.frame
      return saved and saved.width, saved and saved.height
    end,
    setSize = function()
      if f.eaCommit then f.eaCommit() end
    end,
  })
  -- Not toplevel, or a click on it would cover Blizzard's color picker, which shares its strata.
  f:SetToplevel(false)
  -- The library centers a new window. Cleared so the saved anchor is the only one.
  f:ClearAllPoints()
  -- After the library's own OnShow, which sizes the window back to its saved size.
  f:HookScript("OnShow", function()
    if f.minimized then
      f:SetSize(OptionsPrivate.EAFoldedWidth, OptionsPrivate.EAFoldedHeight)
    end
  end)
  return f
end

function OptionsPrivate.EAWindowCommits(f, commit)
  f.eaCommit = commit
  f.header:HookScript("OnDragStop", commit)
end

-- A header button with the callbacks of Blizzard's MaximizeMinimizeButtonFrameTemplate, which
-- the options used here before.
function OptionsPrivate.EAMinimizeButton(f)
  local button
  local minimized = false
  local onMinimized, onMaximized
  local function Paint()
    local top, bottom = 0, 1
    if not minimized then top, bottom = 1, 0 end
    for _, texture in ipairs({ button:GetNormalTexture(), button:GetDisabledTexture() }) do
      texture:SetTexCoord(0, 1, top, bottom)
    end
  end
  button = f:AddHeaderButton("chevron-down", nil, L["Fold the window to its header, or open it again."], function()
    minimized = not minimized
    Paint()
    if minimized then
      if onMinimized then onMinimized() end
    elseif onMaximized then
      onMaximized()
    end
  end)
  Paint()
  function button.SetOnMinimizedCallback(_, fn) onMinimized = fn end
  function button.SetOnMaximizedCallback(_, fn) onMaximized = fn end
  return button
end

-- The bar under the aura list: library text buttons in place of the old link tooltips.
function OptionsPrivate.EAOptionsFooter(f, bar, onThanks)
  local Private = OptionsPrivate.Private
  local ui = Private.EAUI
  bar:ClearAllPoints()
  bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
  bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
  bar:SetHeight(FOOTER_HEIGHT)
  ui:Paint(bar, "chrome", "divider", "T")

  local buttons = {}
  local function Add(label, onClick)
    local b = ui:CreateButton(bar, label, nil, onClick, nil, "ghost")
    buttons[#buttons + 1] = b
    return b
  end

  local prev
  for _, def in ipairs({
    { L["Documentation"], function() Private.EAShowLink("docs") end },
    { L["About"], function() Private.EAOpenSettings("about") end },
    { L["In Combat"], function() Private.EAOpenSettings("combat") end },
    { L["Thanks"], function(self) onThanks(self) end },
  }) do
    local b = Add(def[1], def[2])
    if prev then
      b:SetPoint("LEFT", prev, "RIGHT", BUTTON_GAP, 0)
    else
      b:SetPoint("LEFT", bar, "LEFT", FOOTER_PADDING, 0)
    end
    prev = b
  end
  local bug = Add(L["Report a Bug"], function() Private.EAShowLink("bug") end)
  bug:SetPoint("RIGHT", bar, "RIGHT", -(FOOTER_PADDING + GRIP_ROOM), 0)
  local find = Add(L["Find Auras"], function() Private.EAShowLink("wago") end)
  find:SetPoint("RIGHT", bug, "LEFT", -BUTTON_GAP, 0)

  -- A label measured while hidden can be short of its drawn width.
  bar:HookScript("OnShow", function()
    for _, b in ipairs(buttons) do b:Fit() end
  end)
  bar.eaButtons = buttons
end
