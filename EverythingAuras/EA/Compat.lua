if not EverythingAuras.IsLibsOK() then return end

local Private = select(2, ...)

-- Same returns as Blizzard's GetWeaponEnchantInfo shim, which exists only while loadDeprecationFallbacks is on.
function Private.GetWeaponEnchantInfo()
  local values = {}
  local offset = 1
  for _, slot in ipairs({ INVSLOT_MAINHAND, INVSLOT_OFFHAND, INVSLOT_RANGED }) do
    local info = C_PaperDollInfo.GetTemporaryEnchantmentInfo(slot)
    if info then
      values[offset] = true
      values[offset + 1] = info.remainingTimeMs
      values[offset + 2] = info.chargesRemaining
      values[offset + 3] = info.enchantID
    else
      values[offset] = false
    end
    offset = offset + 4
  end
  return unpack(values, 1, offset - 1)
end
