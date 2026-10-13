-- Everything Auras step 7b: the options window on the library's window, its minimize and its footer bar,
-- against a recording stand-in for the EverythingUI library.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local Stub
function Stub(fields)
  return setmetatable(fields or {}, { __index = function(_, k)
    if k:find("^Create") then return function() return Stub() end end
    return function() end
  end })
end

local function Texture()
  return Stub({ SetTexCoord = function(self, l, r, t, b) self.coords = { l, r, t, b } end })
end

local rec = { links = {}, opened = {}, painted = nil, buttons = {} }
local window
local ui = Stub()
function ui.CreateWindow(_, spec)
  window = Stub({ spec = spec, hooks = {}, header = Stub({ hooks = {} }), headerButtons = {} })
  function window.SetToplevel(self, on) self.toplevel = on end
  function window.ClearAllPoints(self) self.cleared = true end
  function window.HookScript(self, script, f) self.hooks[script] = f end
  function window.SetSize(self, w, h) self.w, self.h = w, h end
  function window.header.HookScript(self, script, f) self.hooks[script] = f end
  function window.AddHeaderButton(self, icon, title, body, onClick)
    local b = Stub({ icon = icon, title = title, body = body, onClick = onClick, normal = Texture(), disabled = Texture() })
    function b.GetNormalTexture(btn) return btn.normal end
    function b.GetDisabledTexture(btn) return btn.disabled end
    self.headerButtons[#self.headerButtons + 1] = b
    return b
  end
  return window
end
function ui.Paint(_, frame, fill, edge, sides) rec.painted = { frame = frame, fill = fill, edge = edge, sides = sides } end
function ui.CreateButton(_, parent, label, width, onClick, tooltip, style)
  local b = Stub({ parent = parent, label = label, onClick = onClick, style = style, points = {}, fits = 0 })
  function b.SetPoint(self, ...) self.points[#self.points + 1] = { ... } end
  function b.Fit(self) self.fits = self.fits + 1 end
  rec.buttons[#rec.buttons + 1] = b
  return b
end

local private = {
  EAUI = ui,
  EAShowLink = function(key) rec.links[#rec.links + 1] = key end,
  EAOpenSettings = function(page) rec.opened[#rec.opened + 1] = page end,
}
local options = { Private = private }
local L = setmetatable({}, { __index = function(_, key) return key end })
local env = setmetatable({
  EverythingAuras = { IsLibsOK = function() return true end, L = L },
}, { __index = _G })
local chunk = assert(loadfile(T.repoRoot .. "/EverythingAurasOptions/EA/OptionsWindow.lua"))
setfenv(chunk, env)("EverythingAurasOptions", options)

T.section("The window")
local odb = {}
local f = options.EACreateOptionsWindow(odb, 830, 665, 750, 240)
local spec = window.spec
T.expect(spec.name == "EverythingAurasOptions" and spec.title == "Everything Auras", "the same frame name, titled with the space")
T.expect(spec.width == 830 and spec.height == 665 and spec.minWidth == 750 and spec.minHeight == 240, "today's default and minimum sizes")
T.expect(spec.getMaximized == nil and spec.setMaximized == nil, "no maximize in 0.1.0")
local w, h = spec.getSize()
T.expect(w == nil and h == nil, "no saved size yet, so the library uses the default")
odb.frame = { width = 900, height = 700 }
w, h = spec.getSize()
T.expect(w == 900 and h == 700, "the saved size comes from the options' own table")
T.expect(f.toplevel == false, "not toplevel, so Blizzard's color picker stays on top")
T.expect(f.cleared, "the library's centering anchor is cleared for the saved one")
local committed = 0
options.EAWindowCommits(f, function() committed = committed + 1 end)
spec.setSize(950, 720)
T.expect(committed == 1, "letting go of the grip saves through the options' commit")
f.header.hooks.OnDragStop()
T.expect(committed == 2, "letting go of the header saves the position")

T.section("Minimize")
local folded, opened = 0, 0
local button = options.EAMinimizeButton(f)
button:SetOnMinimizedCallback(function() folded = folded + 1 end)
button:SetOnMaximizedCallback(function() opened = opened + 1 end)
T.expect(button.icon == "chevron-down" and #window.headerButtons == 1, "a header button with the library's chevron")
local c = button.normal.coords
T.expect(c[3] == 1 and c[4] == 0 and button.disabled.coords[3] == 1, "it points up while the window is open")
button.onClick()
c = button.normal.coords
T.expect(folded == 1 and opened == 0 and c[3] == 0 and c[4] == 1, "a click folds it and the chevron points down")
button.onClick()
T.expect(opened == 1 and button.normal.coords[3] == 1, "a second click opens it again")
f.minimized = true
f.hooks.OnShow()
T.expect(f.w == 300 and f.h == 48, "shown again while folded, it stays a 300 by 48 header")
f.minimized = false
f.w, f.h = nil, nil
f.hooks.OnShow()
T.expect(rawget(f, "w") == nil, "an open window keeps the size the library gave it")

T.section("Footer bar")
local bar = Stub({ hooks = {} })
function bar.SetHeight(self, height) self.height = height end
function bar.HookScript(self, script, fn) self.hooks[script] = fn end
local thanked
options.EAOptionsFooter(f, bar, function(b) thanked = b end)
T.expect(bar.height == 48 and options.EAFooterHeight == 48, "a 48 px bar")
T.expect(rec.painted and rec.painted.frame == bar and rec.painted.fill == "chrome" and rec.painted.edge == "divider" and rec.painted.sides == "T",
  "painted like the library's footers")
local labels = {}
for _, b in ipairs(rec.buttons) do labels[#labels + 1] = b.label end
T.expect(table.concat(labels, ",") == "Documentation,About,In Combat,Thanks,Report a Bug,Find Auras", "six links")
local allGhost = true
for _, b in ipairs(rec.buttons) do allGhost = allGhost and b.style == "ghost" and b.parent == bar end
T.expect(allGhost, "library text buttons on the bar")
for _, b in ipairs(rec.buttons) do b.onClick(b) end
T.expect(table.concat(rec.links, ",") == "docs,bug,wago", "Documentation, Report a Bug and Find Auras open copy-only links")
T.expect(table.concat(rec.opened, ",") == "about,combat", "About and In Combat open their pages")
T.expect(thanked == rec.buttons[4], "Thanks opens its list from its own button")
local bug = rec.buttons[5]
T.expect(bug.points[1][1] == "RIGHT" and bug.points[1][4] == -(24 + 20), "the right links leave room for the resize grip")
bar.hooks.OnShow()
local refit = true
for _, b in ipairs(rec.buttons) do refit = refit and b.fits == 1 end
T.expect(refit, "the labels are measured again when the bar shows")
T.finish()
