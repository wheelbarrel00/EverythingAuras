if not EverythingAuras.IsLibsOK() then return end

local OptionsPrivate = select(2, ...)
local L = EverythingAuras.L

local PositionOptions = OptionsPrivate.commonOptions.PositionOptions
OptionsPrivate.commonOptions.PositionOptions = function(id, data, ...)
  local options = PositionOptions(id, data, ...)
  if not data.controlledChildren then
    options.eaUnsureDisplay = {
      type = "select",
      width = EverythingAuras.normalWidth,
      name = L["When Unsure in Combat"],
      desc = L["In combat WoW Forever hides most auras from addons, so Everything Auras shows what it last knew. Dim fades it and adds a ~ marker. Sounds, glows, chat and custom actions never fire for it, whatever you pick."],
      order = 81.5,
      values = { dim = L["Dim"], hide = L["Hide"], show = L["Show Normally"] },
      get = function()
        return data.eaUnsureDisplay or "dim"
      end,
      set = function(_, value)
        data.eaUnsureDisplay = value ~= "dim" and value or nil
        EverythingAuras.Add(data)
      end,
    }
  end
  return options
end
