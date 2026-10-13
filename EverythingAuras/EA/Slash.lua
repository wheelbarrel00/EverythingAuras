if not EverythingAuras.IsLibsOK() then return end
---@class Private
local Private = select(2, ...)

local L = EverythingAuras.L

local SHORT = { "/wa", "/ea" }
Private.EAShortCommands = {}

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

local HELP = {
  L["/wa help - Show this message"],
  L["/wa minimap - Toggle the minimap icon"],
  L["/wa pstart - Start profiling. Optionally include a duration in seconds after which profiling automatically stops. To profile the next combat/encounter, pass a \"combat\" or \"encounter\" argument."],
  L["/wa pstop - Finish profiling"],
  L["/wa pprint - Show the results from the most recent profiling"],
  L["/wa repair - Repair tool"],
  L["/wa trackprint - Toggle the display of a hyperlink in the chat frame when an aura prints a message."],
}

function Private.PrintHelp()
  print(L["Usage:"])
  print(L["/eauras settings - Open the Everything Auras window"])
  for _, line in ipairs(HELP) do
    print((line:gsub("^/wa ", "/eauras ")))
  end
  local ours = {}
  for _, command in ipairs(SHORT) do
    if Private.EAShortCommands[command] then ours[#ours + 1] = command end
  end
  if #ours > 0 then
    print(L["Also available as %s."]:format(table.concat(ours, L[" and "])))
  end
  print(L["If you require additional assistance, please open a ticket on GitHub."])
end

local slash = SlashCmdList.EverythingAuras
SlashCmdList.EverythingAuras = function(input)
  local msg = (input or ""):match("^%s*(%S*)"):lower()
  if msg == "settings" then
    Private.EAOpenSettings()
    return
  end
  return slash(input)
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
      Private.EAShortCommands[command] = true
    end
  end
  -- A new key, because the chat frame imports each SlashCmdList key only once.
  if count > 0 then
    SlashCmdList.EverythingAurasShort = SlashCmdList.EverythingAuras
  end
end)
