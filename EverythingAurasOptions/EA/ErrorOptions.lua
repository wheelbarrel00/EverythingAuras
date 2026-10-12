if not EverythingAuras.IsLibsOK() then return end

local OptionsPrivate = select(2, ...)
local L = EverythingAuras.L

local GetInformationOptions = OptionsPrivate.GetInformationOptions
function OptionsPrivate.GetInformationOptions(data)
  local options = GetInformationOptions(data)
  if type(data.id) ~= "table" then
    options.args.eaCustomCodeOn = {
      type = "execute",
      name = L["Turn Custom Code Back On"],
      desc = L["Everything Auras switched this aura's custom code off after repeated Lua errors. Turn it back on once the code is fixed. A /reload turns it back on too."],
      width = EverythingAuras.doubleWidth,
      order = 0.5,
      hidden = function()
        return not OptionsPrivate.Private.EACustomCodeOff(data.uid)
      end,
      func = function()
        OptionsPrivate.Private.EATurnCustomCodeOn(data)
        EverythingAuras.ClearAndUpdateOptions(data.id)
      end,
    }
  end
  return options
end
