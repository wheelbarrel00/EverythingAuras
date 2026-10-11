if not EverythingAuras.IsLibsOK() then return end

local SHORT = { "/wa", "/ea" }

local function IsClaimed(command)
  if IsSecureCmd(command) or hash_SlashCmdList[command:upper()] then
    return true
  end
  -- SlashCmdList is a proxy: imported commands leave the raw table, so the hash check above covers those.
  for key in pairs(SlashCmdList) do
    local i, tag = 1, _G["SLASH_" .. key .. 1]
    while tag do
      if tag:lower() == command then
        return true
      end
      i = i + 1
      tag = _G["SLASH_" .. key .. i]
    end
  end
  return false
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  local count = 0
  for _, command in ipairs(SHORT) do
    if not IsClaimed(command) then
      count = count + 1
      _G["SLASH_EverythingAurasShort" .. count] = command
    end
  end
  -- A new key, because the chat frame imports each SlashCmdList key only once.
  if count > 0 then
    SlashCmdList.EverythingAurasShort = SlashCmdList.EverythingAuras
  end
end)
