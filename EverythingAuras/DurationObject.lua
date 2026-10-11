if not EverythingAuras.IsLibsOK() then return end
---@type string
local AddonName = ...
---@class Private
local Private = select(2, ...)

function EverythingAuras.IsDurationObject(duration)
  if type(duration) == "userdata" and duration.GetRemainingDuration then
    return true
  end
  return false
end

local typeToFormatter = {
  elapsed = "FormatElapsedDuration",
  remaining = "FormatRemainingDuration",
  total = "FormatTotalDuration",
}

local typeToGetter = {
  elapsed = "GetElapsedDuration",
  remaining = "GetRemainingDuration",
  total = "GetTotalDuration",
}

function EverythingAuras.GetDurationObjectValue(duration, type, formatter)
  if formatter then
    return duration[typeToFormatter[type]](duration, formatter)
  else
    return duration[typeToGetter[type]](duration)
  end
end
-- Modified for Everything Auras by tools/ea_transform.py (identifiers renamed), see NOTICE.md
