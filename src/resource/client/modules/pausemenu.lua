local NUI_ACTIONS = (BabloHud and BabloHud.Constants and BabloHud.Constants.NUI_ACTIONS) or {}

local pauseMenuActive = false

function SendPauseMenuState(active)
    SendNUIMessage({
        action = NUI_ACTIONS.SET_PAUSE_MENU_ACTIVE or "setPauseMenuActive",
        data   = active,
    })
end

-- Poll pause menu state and notify NUI on change.
-- Uses a shorter interval (100 ms) while in the pause menu for responsiveness.
CreateThread(function()
    while true do
        local active = IsPauseMenuActive()
        if active ~= pauseMenuActive then
            pauseMenuActive = active
            SendPauseMenuState(active)
        end
        Wait(active and 100 or 250)
    end
end)
