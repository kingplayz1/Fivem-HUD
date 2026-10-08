local Constants   = (BabloHud and BabloHud.Constants) or {}
local KVP         = Constants.KVP        or {}
local NUI_ACTIONS = Constants.NUI_ACTIONS or {}

local MINIMAP_KVP_KEY = KVP.MINIMAP_POSITION or "bablo_hud_minimap_position"

function GetMinimapKvpKey()
    return BabloHud.GetKvpKey(MINIMAP_KVP_KEY)
end

-- Restore saved minimap position from KVP after hostname is ready
AddEventHandler("bablo-hud:hostnameReady", function()
    local kvpKey  = GetMinimapKvpKey()
    local rawJson = GetResourceKvpString(kvpKey)

    if not rawJson or rawJson == "" then return end

    local data = json.decode(rawJson)
    if not data then return end

    if data.deltaX == nil or data.deltaY == nil then return end

    SetMinimapDelta(data.deltaX, data.deltaY)
    ApplyMinimapPosition(true)
    SendMinimapPosition(true)
    Info("Loaded minimap position from KVP (" .. kvpKey .. ")")
end)

RegisterNUICallback("closeSettings", function(_, cb)
    SendNUIMessage({
        action = NUI_ACTIONS.TOGGLE_SETTINGS or "toggleSettings",
        data   = false,
    })
    SetNuiFocus(false, false)
    cb({ success = true })
end)

RegisterNUICallback("setMinimapPosition", function(data, cb)
    if data.deltaX == nil or data.deltaY == nil then
        cb({ success = true })
        return
    end

    local refreshBigmap = data.refreshBigmap ~= false

    SetMinimapDelta(data.deltaX, data.deltaY)
    ApplyMinimapPosition(refreshBigmap)
    SendMinimapPosition()

    if refreshBigmap then
        SetResourceKvp(GetMinimapKvpKey(), json.encode({
            deltaX = data.deltaX,
            deltaY = data.deltaY,
        }))
    end

    Trace("Minimap position: deltaX=%.4f deltaY=%.4f", data.deltaX, data.deltaY)
    cb({ success = true })
end)

RegisterNUICallback("resetMinimapPosition", function(_, cb)
    if Minimap then
        Minimap:resetOffset()
    else
        SetMinimapDelta(0.0, 0.0)
    end

    ApplyMinimapPosition(true)
    SendMinimapPosition(true)
    SetResourceKvp(GetMinimapKvpKey(), "")
    Info("Minimap position reset")
    cb({ success = true })
end)

RegisterNUICallback("getMinimapPosition", function(_, cb)
    SendMinimapPosition(true)
    cb({ success = true })
end)
