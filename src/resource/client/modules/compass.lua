local NUI_ACTIONS        = (BabloHud and BabloHud.Constants and BabloHud.Constants.NUI_ACTIONS) or {}
local ACTION_COMPASS     = NUI_ACTIONS.UPDATE_COMPASS       or "updateCompass"
local ACTION_IN_VEHICLE  = NUI_ACTIONS.SET_COMPASS_IN_VEHICLE or "setCompassInVehicle"

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local compassInVehicle  = false   -- true while the vehicle compass is active
local compassThreadActive = false -- guards against duplicate polling threads

local lastHeading  = nil  -- last heading sent to NUI (prevents redundant sends)
local lastStreet   = nil
local lastZone     = nil
local lastStreetCached = nil  -- last non-empty street name (used when native returns "")

-- ---------------------------------------------------------------------------
-- Cardinal direction lookup (N / NE / E / SE / S / SW / W / NW)
-- ---------------------------------------------------------------------------
local CARDINAL_DIRECTIONS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

function GetCardinalDirection(heading)
    local normalised = heading % 360
    if normalised < 0 then normalised = normalised + 360 end
    local index = math.floor((normalised + 22.5) % 360 / 45) % 8
    return CARDINAL_DIRECTIONS[index + 1]
end

-- ---------------------------------------------------------------------------
-- NUI helpers
-- ---------------------------------------------------------------------------

function SendCompassInVehicle(inVehicle)
    SendNUIMessage({
        action = ACTION_IN_VEHICLE,
        data   = inVehicle and true or false,
    })
end

function SendCompassUpdate(heading, street, zone)
    SendNUIMessage({
        action = ACTION_COMPASS,
        data   = { heading = heading, street = street, zone = zone },
    })
end

-- ---------------------------------------------------------------------------
-- Street / zone resolution
-- Returns: streetName (string or nil), zoneName (string or "")
-- Uses lastStreetCached as fallback when the native returns an empty string.
-- ---------------------------------------------------------------------------
function ResolveLocationStrings(pos)
    local streetHash = GetStreetNameAtCoord(pos.x, pos.y, pos.z)
    local street     = GetStreetNameFromHashKey(streetHash) or ""

    if street == "" then
        street = lastStreetCached
    else
        lastStreetCached = street
    end

    local zoneId = GetNameOfZone(pos.x, pos.y, pos.z)
    local zone   = (zoneId and GetLabelText(zoneId)) or ""

    -- Normalise empty / falsy street to nil for the NUI
    if not street or street == "" then street = nil end

    return street, zone
end

-- ---------------------------------------------------------------------------
-- Returns true when the on-foot compass should be shown.
-- Controlled by compassInVehicle flag OR the BabloHudCompassShowOnFoot global.
-- ---------------------------------------------------------------------------
function ShouldShowCompass()
    return compassInVehicle or (_G.BabloHudCompassShowOnFoot == true)
end

-- ---------------------------------------------------------------------------
-- Main compass polling thread
-- Runs at ~60 fps for smooth heading updates.
-- Street / zone are refreshed at most every 400 ms to avoid native overhead.
-- ---------------------------------------------------------------------------
function StartCompassThread()
    if compassThreadActive then return end
    compassThreadActive = true

    CreateThread(function()
        local lastStreetRefreshTime = 0

        while compassThreadActive and _G.BabloHudActive do
            local ped = cache and cache.ped
            if ped and ShouldShowCompass() then
                local camRot  = GetGameplayCamRot(0)
                local heading = math.floor((360 - camRot.z % 360) % 360)

                -- Refresh street/zone at most every 400 ms
                local now = GetGameTimer()
                if now - lastStreetRefreshTime > 400 or lastStreet == nil then
                    lastStreetRefreshTime = now
                    local pos            = GetEntityCoords(ped)
                    lastStreet, lastZone = ResolveLocationStrings(pos)
                end

                -- Only send when heading changed
                if heading ~= lastHeading then
                    lastHeading = heading
                    SendCompassUpdate(heading, lastStreet, lastZone)
                end
            end

            Wait(16)
        end

        compassThreadActive = false
    end)
end

-- ---------------------------------------------------------------------------
-- Enter / leave vehicle compass mode
-- ---------------------------------------------------------------------------
function EnterVehicleCompass()
    if compassInVehicle then return end
    compassInVehicle = true
    lastHeading = nil
    lastStreet  = nil
    lastZone    = nil
    SendCompassInVehicle(true)
    StartCompassThread()
end

function LeaveVehicleCompass()
    if not compassInVehicle then return end
    compassInVehicle = false
    lastHeading = nil
    lastStreet  = nil
    lastZone    = nil
    SendCompassInVehicle(false)
    StartCompassThread()
end

-- ---------------------------------------------------------------------------
-- Custom street / zone name injection (Config.CustomStreetNames / CustomZoneNames)
-- ---------------------------------------------------------------------------
function RegisterCustomLocationNames()
    if Config and Config.CustomStreetNames then
        for hash, name in pairs(Config.CustomStreetNames) do
            AddTextEntryByHash(hash, name)
        end
    end

    if Config and Config.CustomZoneNames then
        for zoneName, label in pairs(Config.CustomZoneNames) do
            AddTextEntryByHash(GetHashKey(zoneName), label)
        end
    end
end

-- Register custom names once the player is active
CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(200) end
    RegisterCustomLocationNames()
end)

-- Re-register on player load (in case the resource restarted mid-session)
AddEventHandler("bablo-hud:playerLoaded", RegisterCustomLocationNames)

-- ---------------------------------------------------------------------------
-- Player loaded — determine initial compass mode after a short settle delay
-- ---------------------------------------------------------------------------
AddEventHandler("bablo-hud:playerLoaded", function()
    CreateThread(function()
        Wait(600)
        if cache and cache.vehicle then
            EnterVehicleCompass()
        else
            SendCompassInVehicle(false)
        end
        StartCompassThread()
    end)
end)

-- ---------------------------------------------------------------------------
-- Vehicle cache change (ox_lib) — switch compass mode on enter/exit vehicle
-- ---------------------------------------------------------------------------
lib.onCache("vehicle", function(vehicle)
    if not _G.BabloHudActive then return end
    if vehicle then
        EnterVehicleCompass()
    else
        LeaveVehicleCompass()
    end
end)

-- ---------------------------------------------------------------------------
-- Player unloaded — reset all state
-- ---------------------------------------------------------------------------
AddEventHandler("bablo-hud:playerUnloaded", function()
    compassInVehicle    = false
    compassThreadActive = false
    SendCompassInVehicle(false)
end)

-- ---------------------------------------------------------------------------
-- Resource stop — restore native compass if we were in vehicle mode
-- ---------------------------------------------------------------------------
AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if compassInVehicle then
        SendCompassInVehicle(false)
    end
end)
