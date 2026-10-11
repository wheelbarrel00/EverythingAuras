if not EverythingAuras.IsLibsOK() then return end

local L = EverythingAuras.L



-- Make missing translations available
setmetatable(EverythingAuras.L, {__index = function(self, key)
  self[key] = (key or "")
  return key
end})
-- Modified for Everything Auras by tools/ea_transform.py (identifiers renamed), see NOTICE.md
