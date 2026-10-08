local NUI_ACTIONS     = (BabloHud and BabloHud.Constants and BabloHud.Constants.NUI_ACTIONS) or {}
local WAYPOINT_ACTION = NUI_ACTIONS.UPDATE_WAYPOINT or "updateWaypoint"
local POLL_INTERVAL   = 500   -- ms between waypoint distance checks

local waypointActive   = nil  -- last sent active state (nil = never sent)
local waypointDistance = nil  -- last sent distance

-- ---------------------------------------------------------------------------
-- Sends the current waypoint state to NUI
-- ---------------------------------------------------------------------------
function SendWaypointState(active, distance)
    SendNUIMessage({
        action = WAYPOINT_ACTION,
        data   = {
            active   = active and true or false,
            distance = distance,
        },
    })
end

-- ---------------------------------------------------------------------------
-- Calculates the 2D distance to the player's current waypoint blip (type 8).
-- Sends an update only when state changes.
-- ---------------------------------------------------------------------------
function UpdateWaypoint()
    local ped = cache and cache.ped
    if not ped or not DoesEntityExist(ped) then return end

    local waypointBlip = GetFirstBlipInfoId(8)

    if not DoesBlipExist(waypointBlip) then
        -- Waypoint was removed — send once
        if waypointActive ~= false then
            waypointActive   = false
            waypointDistance = nil
            SendWaypointState(false, nil)
        end
        return
    end

    local pedPos  = GetEntityCoords(ped)
    local blipPos = GetBlipInfoIdCoord(waypointBlip)
    local dx      = pedPos.x - blipPos.x
    local dy      = pedPos.y - blipPos.y
    local dist    = math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)

    -- Only send when active state or distance changes
    if waypointActive == true and waypointDistance == dist then return end

    waypointActive   = true
    waypointDistance = dist
    SendWaypointState(true, dist)
end

-- ---------------------------------------------------------------------------
-- Polling thread — waits for HUD to be active, then polls every POLL_INTERVAL
-- ---------------------------------------------------------------------------
CreateThread(function()
    while not _G.BabloHudActive do Wait(250) end

    while true do
        if _G.BabloHudActive then
            UpdateWaypoint()
        end
        Wait(POLL_INTERVAL)
    end
end)

AddEventHandler("bablo-hud:playerUnloaded", function()
    waypointActive   = nil
    waypointDistance = nil
    SendWaypointState(false, nil)
end)
