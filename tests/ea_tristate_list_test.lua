-- Everything Auras 0.6.0: the Specialization load list shows load, never load and off (EA/TristateList.lua).
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local function Region(kind)
  local r = { kind = kind, shown = true, scripts = {}, points = {} }
  function r.SetShown(self, on) self.shown = on and true or false end
  function r.Show(self) self.shown = true end
  function r.Hide(self) self.shown = false end
  function r.IsShown(self) return self.shown end
  function r.SetText(self, text) self.text = text end
  function r.GetText(self) return self.text end
  function r.SetWidth(self, w) self.width = w end
  function r.GetWidth(self) return self.width end
  function r.SetHeight(self, h) self.height = h end
  function r.ClearAllPoints(self) self.points = {} end
  function r.SetPoint(self, ...) self.points[#self.points + 1] = { ... } end
  function r.SetScript(self, name, fn) self.scripts[name] = fn end
  function r.SetEnabled(self, on) self.enabled = on end
  function r.SetAlpha(self, a) self.alpha = a end
  function r.GetHighlightTexture(self) return self.highlight end
  function r.SetHighlightTexture(self) self.highlight = Region("highlight") end
  function r.CreateTexture() return Region("texture") end
  function r.CreateLine() return Region("line") end
  function r.CreateFontString() return Region("fontstring") end
  return setmetatable(r, { __index = function(_, k) if k:match("^%u") then return function() end end end })
end

local function fixture(forever)
  local f = { registered = {}, tooltip = {} }
  f.options = {
    GetLoadOptions = function()
      return { args = {
        multiselect_forever_spec = { type = "multiselect", width = 2 },
        forever_spec = { type = "select" },
        multiselect_class = { type = "multiselect", width = 2 },
      } }
    end,
  }
  local AceGUI = {
    RegisterWidgetType = function(_, name, constructor, version) f.registered[name] = { constructor, version } end,
    RegisterAsWidget = function(_, widget)
      widget.fired = {}
      function widget.Fire(self, ...) self.fired[#self.fired + 1] = { ... } end
      return widget
    end,
  }
  f.env = setmetatable({
    EverythingAuras = { IsLibsOK = function() return true end, IsForever = function() return forever end,
      L = setmetatable({}, { __index = function(_, key) return key end }) },
    LibStub = function() return AceGUI end,
    CreateFrame = function(kind) return Region(kind) end,
    GameTooltip = {
      SetOwner = function() end,
      SetText = function(_, text) f.tooltip[#f.tooltip + 1] = text end,
      AddLine = function(_, text) f.tooltip[#f.tooltip + 1] = text end,
      Show = function() end,
      Hide = function() end,
    },
  }, { __index = _G })
  setfenv(assert(loadfile(T.repoRoot .. "/EverythingAurasOptions/EA/TristateList.lua")), f.env)("EverythingAurasOptions",
    f.options)
  return f
end

T.section("Retail")
local retail = fixture(false)
T.expect(next(retail.registered) == nil and retail.options.GetLoadOptions().args.multiselect_forever_spec.control == nil,
  "nothing changes on Retail")

T.section("The Specialization option")
local f = fixture(true)
local args = f.options.GetLoadOptions({}).args
T.expect(args.multiselect_forever_spec.control == "EverythingAurasTristateList" and args.multiselect_forever_spec.width == "full",
  "the Specialization list gets three-state boxes across the full width")
T.expect(args.forever_spec.control == nil and args.multiselect_class.control == nil, "the single choice and other lists keep theirs")

T.section("The boxes")
local widget = f.registered.EverythingAurasTristateList[1]()
widget.frame:SetWidth(600)
widget:SetLabel("Specialization")
widget:SetList({ PALADIN_RETRIBUTION = "Paladin: Retribution", DRUID_BALANCE = "Druid: Balance",
  PALADIN_HOLY = "Paladin: Holy", PALADIN_PROTECTION = "Paladin: Protection" })
local rows = widget.shown
T.expect(#rows == 4 and rows[1].key == "DRUID_BALANCE" and rows[2].key == "PALADIN_HOLY", "one box per tree, in key order")
T.expect(widget.label.text == "Specialization" and widget.frame.height == 20 + 2 * 24 + 4, "three to a row under the title")
T.expect(rows[2].points[1][4] == 200 and rows[4].points[1][4] == 0 and rows[4].points[1][5] == -44,
  "each tree in its column, the fourth starting a new row")
widget:SetItemValue("PALADIN_HOLY", false)
widget:SetItemValue("PALADIN_PROTECTION", true)
local holy, prot, druid = rows[2], rows[3], rows[1]
T.expect(holy.cross1.shown and holy.cross2.shown and not holy.check.shown, "never load shows a red cross")
T.expect(prot.check.shown and not prot.cross1.shown, "load shows a tick")
T.expect(not druid.check.shown and not druid.cross1.shown, "off shows an empty box")
druid.scripts.OnClick(druid)
T.expect(druid.state == true and druid.check.shown and widget.fired[1][1] == "OnValueChanged"
  and widget.fired[1][2] == "DRUID_BALANCE" and widget.fired[1][3] == true, "a click on an empty box loads in that tree")
druid.scripts.OnClick(druid)
T.expect(druid.state == false and druid.cross1.shown and widget.fired[2][3] == false, "a second click never loads")
druid.scripts.OnClick(druid)
T.expect(druid.state == nil and not druid.cross1.shown and #widget.fired == 3 and widget.fired[3][3] == nil,
  "a third click clears it")
holy.scripts.OnEnter(holy)
T.expect(f.tooltip[1] == "Paladin: Holy" and f.tooltip[2]:find("red cross", 1, true), "the tooltip explains the clicks")
widget:SetDisabled(true)
T.expect(holy.enabled == false and holy.alpha == 0.5, "disabled boxes cannot be clicked")
widget:OnRelease()
T.expect(not holy.shown and #widget.spare == 4 and next(widget.byKey) == nil, "a released list hides its boxes")
widget:SetList({ MAGE_FIRE = "Mage: Fire" })
T.expect(widget.shown[1].key == "MAGE_FIRE" and widget.shown[1].state == nil and #widget.spare == 3,
  "boxes are reused and start empty")

T.finish()
