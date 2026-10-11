---@type string
local AddonName = ...
---@class Private
local Private = select(2, ...)

local L = EverythingAuras.L

local optionsVersion = "@project-version@"
--@debug@
optionsVersion = "Dev"
--@end-debug@

if optionsVersion ~= EverythingAuras.versionString then
  local message = string.format(L["The EverythingAuras Options Addon version %s doesn't match the EverythingAuras version %s. If you updated the addon while the game was running, try restarting World of Warcraft. Otherwise try reinstalling EverythingAuras"],
                    optionsVersion, EverythingAuras.versionString)
  ---@diagnostic disable-next-line: duplicate-set-field
  EverythingAuras.IsLibsOk = function() return false end
  ---@diagnostic disable-next-line: duplicate-set-field
  EverythingAuras.ToggleOptions = function()
       EverythingAuras.prettyPrint(message)
  end

end
-- Modified for Everything Auras by tools/ea_transform.py (identifiers renamed), see NOTICE.md
