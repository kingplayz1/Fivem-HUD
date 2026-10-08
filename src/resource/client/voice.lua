function IsTalking()
    return NetworkIsPlayerTalking(PlayerId())
end

function GetProximityDistance()
    local state = LocalPlayer.state["proximity"]
    return state and state.distance or 0
end

local mockRadioActive = false
local radioActive     = false
local radioChannel    = 0

local lastTalking, lastDistance, lastRadio = nil, nil, nil

function PushVoiceState()
    local proxTalking       = IsTalking()
    local proximityDistance = GetProximityDistance()
    local isRadioActive     = mockRadioActive or (radioActive and radioChannel ~= 0)
    local isTalking         = proxTalking or radioActive or mockRadioActive

    if isTalking == lastTalking
        and proximityDistance == lastDistance
        and isRadioActive == lastRadio then
        return
    end

    lastTalking, lastDistance, lastRadio = isTalking, proximityDistance, isRadioActive

    SendNUIMessage({
        action = "updateVoice",
        data   = {
            isTalking         = isTalking,
            proximityDistance = proximityDistance,
            isRadioActive     = isRadioActive,
        },
    })
end

-- Use Bablo.Ticker if available (shared thread), otherwise fall back to a plain loop
CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(100) end

    if Bablo and Bablo.Ticker then
        Bablo.Ticker:register(function(frame)
            if frame % 15 == 0 then
                PushVoiceState()
            end
        end)
    else
        while true do
            PushVoiceState()
            Wait(150)
        end
    end
end)

AddEventHandler("pma-voice:radioActive", function(isActive)
    radioActive = isActive and true or false
    PushVoiceState()
end)

AddEventHandler("pma-voice:setTalkingMode", function()
    PushVoiceState()
end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(100) end

    local bagName = ("player:%s"):format(GetPlayerServerId(PlayerId()))
    AddStateBagChangeHandler("radioChannel", bagName, function(_, _, value)
        radioChannel = tonumber(value) or 0
        PushVoiceState()
    end)

    if LocalPlayer and LocalPlayer.state and LocalPlayer.state.radioChannel then
        radioChannel = tonumber(LocalPlayer.state.radioChannel) or 0
    end

    PushVoiceState()
end)

RegisterCommand("mockradio", function()
    mockRadioActive = not mockRadioActive
    Info(("[bablo-hud] Mock radio %s"):format(mockRadioActive and "on" or "off"))
    PushVoiceState()
end, false)
