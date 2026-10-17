-- Everything Auras step 5a: regions showing an unsure aura state stay silent, dim and carry a marker.
-- Step 7a: the marker is a corner triangle sized to the aura.
local testsDir = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = testsDir .. "/?.lua;" .. package.path
local T = require("helpers")

local performed, conditionsRun = {}, 0
local auraData = {}
local private = {
  PerformActions = function(data, when, region)
    local a = data.actions[when]
    performed[#performed + 1] = { when = when, sound = a.do_sound, message = a.do_message, custom = a.do_custom,
      glow = a.do_glow, stopSound = a.stop_sound }
  end,
  RunConditions = function() conditionsRun = conditionsRun + 1 end,
  regionPrototype = {
    create = function(region)
      region.calls = {}
      for _, name in ipairs({ "SoundPlay", "SendChat", "RunCode", "GlowExternal" }) do
        region[name] = function(self, options) self.calls[#self.calls + 1] = name .. (options and options.glow_action or "") end
      end
    end,
  },
}
local function newTexture()
  return { SetTexture = function(self, path) self.path = path end, SetPoint = function() end,
    SetSize = function(self, w, h) self.w, self.h = w, h end }
end
local env = setmetatable({
  EverythingAuras = { IsLibsOK = function() return true end, GetData = function(id) return auraData[id] end },
  issecretvalue = function() return false end,
  CreateFrame = function(_, _, parent)
    return { parent = parent, SetAllPoints = function() end, CreateTexture = newTexture,
      SetFrameLevel = function(self, level) self.level = level end,
      SetShown = function(self, shown) self.shown = shown end }
  end,
}, { __index = _G })
local chunk = assert(loadfile(T.repoRoot .. "/EverythingAuras/EA/Combat.lua"))
setfenv(chunk, env)("EverythingAuras", private)

local function newRegion(id)
  local region = {
    id = id, alpha = 1, shownAlpha = nil, width = 48, height = 48,
    SetAlpha = function(self, alpha) self.shownAlpha = alpha end,
    GetRegionAlpha = function(self) return self.alpha end,
    GetFrameLevel = function() return 5 end,
    GetWidth = function(self) return self.width end,
    GetHeight = function(self) return self.height end,
  }
  private.regionPrototype.create(region)
  return region
end

local function actionsData()
  return { actions = {
    start = { do_sound = true, sound = "x", do_message = true, message = "m", do_custom = true, do_glow = true, glow_action = "show" },
    finish = { do_sound = true, sound = "x", stop_sound = true, do_glow = true, glow_action = "hide" },
  } }
end

T.section("Actions")
local region = newRegion("Seal")
region.states = { [1] = { show = true } }
local data = actionsData()
private.PerformActions(data, "start", region)
T.expect(performed[1].sound and performed[1].message and performed[1].custom and performed[1].glow, "an exact show fires its actions")
region.states = { [1] = { show = true, eaUnsure = "lastKnown" } }
local start = data.actions.start
private.PerformActions(data, "start", region)
local p = performed[2]
T.expect(not p.sound and not p.message and not p.custom and not p.glow, "an unsure show fires nothing")
T.expect(data.actions.start == start and start.do_sound, "the aura's own actions are restored untouched")
region.states = { [1] = { show = false, changed = true, eaUnsure = "unknown" } }
private.PerformActions(data, "finish", region)
p = performed[3]
T.expect(not p.sound and p.stopSound and p.glow, "an unsure hide only cleans up: stops sounds and hides glows")
region.states = { [1] = { show = false, changed = false, eaUnsure = "unknown" }, [2] = { show = true } }
private.PerformActions(data, "start", region)
T.expect(performed[4].sound, "an old unsure mark on another hidden trigger does not silence an exact show")

T.section("Condition alerts")
region.states = { [1] = { show = true, eaUnsure = "lastKnown" } }
region:SoundPlay({})
region:SendChat({})
region:RunCode(function() end)
region:GlowExternal({ glow_action = "show" })
region:GlowExternal({ glow_action = "hide" })
T.expect(#region.calls == 1 and region.calls[1] == "GlowExternalhide", "while unsure only a glow hide goes through")
region.states = { [1] = { show = true } }
region:SoundPlay({})
T.expect(region.calls[2] == "SoundPlay", "an exact state plays its condition sound")

T.section("Look")
auraData.Seal = {}
region.states = { [1] = { show = true, eaUnsure = "lastKnown" } }
private.RunConditions(region, "uid")
T.expect(region.shownAlpha == 0.5 and region.eaMarker and region.eaMarker.shown, "unsure is dimmed with a marker by default")
local tex = region.eaMarkerTexture
T.expect(tex.path:find("Media\\EA\\marker.tga", 1, true) ~= nil, "the marker is the corner triangle texture")
T.expect(tex.w == 12 and tex.h == 12, "a 48 px icon gets a 12 px marker")
T.expect(region.eaMarker.level == 25, "the marker sits above the region's child frames")
T.expect(private.EAMarkerSize(24, 24) == 6 and private.EAMarkerSize(64, 64) == 14 and private.EAMarkerSize(200, 20) == 6
  and private.EAMarkerSize(0, 0) == 6 and private.EAMarkerSize(40, 40) == 10, "a quarter of the shorter side, 6 to 14 px")
region:SetAlpha(0.8)
T.expect(math.abs(region.shownAlpha - 0.4) < 1e-9, "later alpha changes keep the dim factor")
region.states = { [1] = { show = true } }
private.RunConditions(region, "uid")
T.expect(region.shownAlpha == 1 and not region.eaMarker.shown, "exact again restores alpha and hides the marker")
auraData.Seal.eaUnsureDisplay = "hide"
region.states = { [1] = { show = true, eaUnsure = "estimated" } }
private.RunConditions(region, "uid")
T.expect(region.shownAlpha == 0 and not region.eaMarker.shown, "Hide makes it invisible")
auraData.Seal.eaUnsureDisplay = "show"
private.RunConditions(region, "uid")
T.expect(region.shownAlpha == 1 and not region.eaMarker.shown, "Show Normally leaves it as is")
T.expect(conditionsRun == 4, "conditions still run every time")

T.section("Model regions store the alpha they are given")
auraData.Model = {}
local model = newRegion("Model")
-- RegionTypes/Model.lua writes its alpha into self.alpha, which GetRegionAlpha reads back.
model.SetAlpha = function(self, alpha) self.alpha = alpha; self.shownAlpha = alpha end
model.states = { [1] = { show = true, eaUnsure = "lastKnown" } }
private.RunConditions(model, "uid")
T.expect(model.shownAlpha == 0.5 and model.alpha == 1, "dimmed on screen, its own alpha kept")
model.states = { [1] = { show = true } }
private.RunConditions(model, "uid")
T.expect(model.shownAlpha == 1 and model.alpha == 1, "full alpha again after combat")
auraData.Model.eaUnsureDisplay = "hide"
model.states = { [1] = { show = true, eaUnsure = "estimated" } }
private.RunConditions(model, "uid")
model.states = { [1] = { show = true } }
private.RunConditions(model, "uid")
T.expect(model.shownAlpha == 1 and model.alpha == 1, "Hide comes back to full alpha too")

T.section("Icons Blizzard draws (0.3.0)")
auraData.Native = { eaUnsureDisplay = "show" }
local native = newRegion("Native")
native.eaNativeOn = true
native.states = { [1] = { show = true, eaUnsure = "estimated" } }
private.RunConditions(native, "uid")
T.expect(native.shownAlpha == 0 and not (native.eaMarker and native.eaMarker.shown),
  "while unsure its own parts hide, whatever When Unsure in Combat says")
private.EANativeSound = function(_, when) return when == "start" end
native.states = { [1] = { show = true } }
local nativeData = actionsData()
private.PerformActions(nativeData, "start", native)
p = performed[#performed]
T.expect(not p.sound and p.message and p.custom and p.glow, "Blizzard plays its On Show sound, the other actions still fire")
private.PerformActions(nativeData, "finish", native)
T.expect(performed[#performed].sound, "a sound Blizzard does not play stays Everything Auras' own")
T.expect(nativeData.actions.start.do_sound, "the aura's own actions are untouched")
private.EANativeSound = nil
T.finish()
