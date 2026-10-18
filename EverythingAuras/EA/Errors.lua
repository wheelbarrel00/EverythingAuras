if not EverythingAuras.IsLibsOK() then return end

local Private = select(2, ...)
local L = EverythingAuras.L

local ERROR_LIMIT = 10

-- Session only, never saved: [uid] = Lua errors since login, and [aura id or uid] = uid with custom code off.
local errorCounts = {}
local codeOff = {}

local function SwitchOff(data)
  codeOff[data.id] = data.uid
  codeOff[data.uid] = data.uid
  Private.AuraWarnings.UpdateWarning(data.uid, "EACustomCodeOff", "error",
    L["Everything Auras switched off this aura's custom code after %d Lua errors this session. Fix the code, then use Turn Custom Code Back On in the Information tab, or /reload."]:format(errorCounts[data.uid]))
  if EverythingAuras.ClearAndUpdateOptions then
    EverythingAuras.ClearAndUpdateOptions(data.id)
  end
end

function Private.EACustomCodeOff(uid)
  return codeOff[uid] ~= nil
end

function Private.EATurnCustomCodeOn(data)
  errorCounts[data.uid] = nil
  for key, uid in pairs(codeOff) do
    if uid == data.uid then
      codeOff[key] = nil
    end
  end
  Private.AuraWarnings.UpdateWarning(data.uid, "EACustomCodeOff")
end

local currentId, currentUid, handler
local function CountingHandler(message)
  local data
  if currentId then
    data = EverythingAuras.GetData(currentId)
  elseif currentUid then
    data = Private.GetDataByUID(currentUid)
  end
  -- Half-typed code errors constantly while the options are open, so nothing counts then.
  if data and not EverythingAuras.IsOptionsOpen() and not codeOff[data.uid] then
    errorCounts[data.uid] = (errorCounts[data.uid] or 0) + 1
    if errorCounts[data.uid] >= ERROR_LIMIT then
      SwitchOff(data)
    end
  end
  return handler(message)
end

local GetErrorHandlerId, GetErrorHandlerUid = Private.GetErrorHandlerId, Private.GetErrorHandlerUid
function Private.GetErrorHandlerId(id, context)
  handler = GetErrorHandlerId(id, context)
  currentId, currentUid = id, nil
  return CountingHandler
end
function Private.GetErrorHandlerUid(uid, context)
  handler = GetErrorHandlerUid(uid, context)
  currentId, currentUid = nil, uid
  return CountingHandler
end

-- Every piece of custom code loads here with its aura's id (animations pass the uid), so this one gate stops it.
local LoadFunction = EverythingAuras.LoadFunction
function EverythingAuras.LoadFunction(code, id, ...)
  local func, err = LoadFunction(code, id, ...)
  if type(func) ~= "function" or id == nil then
    return func, err
  end
  -- Animations pass their start values from the second argument on and use the results outside xpcall.
  local animation = Private.UIDtoID(id) ~= nil
  return function(...)
    if not codeOff[id] then
      return func(...)
    elseif animation then
      return select(2, ...)
    end
  end
end

Private.callbacks:RegisterCallback("Rename", function(_, _, oldId, newId)
  if codeOff[oldId] then
    codeOff[newId], codeOff[oldId] = codeOff[oldId], nil
  end
end)

Private.callbacks:RegisterCallback("Delete", function(_, uid, id)
  codeOff[id], codeOff[uid], errorCounts[uid] = nil, nil, nil
end)
