local NUI_ACTIONS = (BabloHud and BabloHud.Constants and BabloHud.Constants.NUI_ACTIONS) or {}

-- Health formula constants (GTA native: 0–200, where 100 = zero health for player)
local HEALTH_MIN = 100   -- native value at 0% health
local HEALTH_MAX = 200   -- native value at 100% health

-- ---------------------------------------------------------------------------
-- State
-- lastStatus  – last snapshot sent to NUI (used for change detection)
-- running     – guards against duplicate polling threads
-- ---------------------------------------------------------------------------
local lastStatus = {}
local running    = false

-- ---------------------------------------------------------------------------
-- Clamp and floor a number to [0, 100].
-- Used for every stat value to keep the NUI data clean.
-- ---------------------------------------------------------------------------
function ClampStat(value)
    return math.max(0, math.min(100, math.floor(value)))
end

-- ---------------------------------------------------------------------------
-- HasStatusChanged(newStatus, threshold)
-- Returns true when any numeric field differs by >= threshold from lastStatus,
-- or any boolean field has changed at all.
-- threshold defaults to 1.
-- ---------------------------------------------------------------------------
function HasStatusChanged(newStatus, threshold)
    threshold = threshold or 1
    for key, value in pairs(newStatus) do
        if type(value) == "number" then
            local prev = lastStatus[key] or -999
            if math.abs(value - prev) >= threshold then return true end
        elseif type(value) == "boolean" then
            if lastStatus[key] ~= value then return true end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- ReadNitro()
-- Returns the nitro level [0–100] from Framework.getNitro when configured,
-- or 0 if nitro is disabled / unavailable.
-- ---------------------------------------------------------------------------
function ReadNitro()
    if not (Config and Config.Nitro and Config.Nitro.enabled) then return 0 end
    if not (Framework and Framework.getNitro) then return 0 end
    local raw = tonumber(Framework:getNitro()) or 0
    return ClampStat(raw)
end

-- ---------------------------------------------------------------------------
-- ReadStress()
-- Priority:
--   1. Bablo.Stress:Get()  when Config.Stress.integrated == true
--   2. Framework:getStress() otherwise
-- Returns 0 when neither is available.
-- ---------------------------------------------------------------------------
function ReadStress()
    if Config and Config.Stress and Config.Stress.integrated then
        if Bablo and Bablo.Stress then
            return ClampStat(Bablo.Stress:Get())
        end
    elseif Framework and Framework.getStress then
        return ClampStat(tonumber(Framework:getStress()) or 0)
    end
    return 0
end

-- ---------------------------------------------------------------------------
-- ReadOxygen(ped, playerId)
-- Returns 100 when not underwater, or the remaining breath as a 0–100 value.
-- GetPlayerUnderwaterTimeRemaining returns seconds (max ~10); multiply by 10.
-- ---------------------------------------------------------------------------
function ReadOxygen(ped, playerId)
    if not IsPedSwimmingUnderWater(ped) then return 100 end
    local remaining = GetPlayerUnderwaterTimeRemaining(playerId) * 10
    return ClampStat(remaining)
end

-- ---------------------------------------------------------------------------
-- CollectStatus()
-- Reads all stat values and returns a snapshot table, or nil when the ped
-- doesn't exist.
-- ---------------------------------------------------------------------------
function CollectStatus()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return nil end

    local playerId = PlayerId()

    -- Health: convert from native 100–200 range to 0–100 percent
    local rawHealth = GetEntityHealth(ped)
    local health    = ClampStat((rawHealth - HEALTH_MIN) / (HEALTH_MAX - HEALTH_MIN) * 100)

    local armor   = GetPedArmour(ped)

    -- Stamina: native GetPlayerSprintStaminaRemaining returns how much is LEFT,
    -- so invert to get how much is SPENT (fatigue level sent to HUD)
    local stamina = ClampStat(100 - GetPlayerSprintStaminaRemaining(playerId))

    local oxygen     = ReadOxygen(ped, playerId)
    local inVehicle  = IsPedInAnyVehicle(ped, false) and true or false
    local isUnderwater = IsPedSwimmingUnderWater(ped)

    local hunger = 100
    local thirst = 100
    if Framework and Framework.getHunger then
        hunger = ClampStat(tonumber(Framework:getHunger()) or 100)
    end
    if Framework and Framework.getThirst then
        thirst = ClampStat(tonumber(Framework:getThirst()) or 100)
    end

    local stress = ReadStress()
    local nitro  = ReadNitro()

    return {
        health      = health,
        armor       = armor,
        stamina     = stamina,
        oxygen      = oxygen,
        hunger      = hunger,
        thirst      = thirst,
        stress      = stress,
        nitro       = nitro,
        isUnderwater = isUnderwater,
        inVehicle   = inVehicle,
    }
end

-- ---------------------------------------------------------------------------
-- SendStatus(status)
-- Sends a status snapshot to the NUI layer.
-- ---------------------------------------------------------------------------
function SendStatus(status)
    if not status then return end
    SendNUIMessage({
        action = NUI_ACTIONS.UPDATE_STATUS or "updateStatus",
        data   = status,
    })
end

-- ---------------------------------------------------------------------------
-- StartStatusModule()
-- Launches the polling thread if not already running.
--
-- Poll interval:
--   • 250 ms when stamina < 95 (regenerating fast — need smooth updates)
--   • 500 ms otherwise
--
-- Warm-up: the first 10 frames always send regardless of change detection,
-- to ensure the NUI is populated immediately after load.
-- ---------------------------------------------------------------------------
function StartStatusModule()
    if running then return end
    running = true
    Info("Status module started")

    CreateThread(function()
        local warmupFrames = 10

        while running do
            local status = CollectStatus()

            if status then
                if warmupFrames > 0 then
                    SendStatus(status)
                    lastStatus   = status
                    warmupFrames = warmupFrames - 1
                elseif HasStatusChanged(status, 1) then
                    SendStatus(status)
                    lastStatus = status
                end
            end

            -- Faster polling while stamina is actively changing
            local fastPoll = status and status.stamina < 95
            Wait(fastPoll and 250 or 500)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- ForceRefresh()
-- Reads and sends the current status immediately (used by the refresh event).
-- ---------------------------------------------------------------------------
function ForceRefresh()
    if not running then return end
    local status = CollectStatus()
    if not status then return end
    SendStatus(status)
    lastStatus = status
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
AddEventHandler("bablo-hud:status:refresh", ForceRefresh)

AddEventHandler("bablo-hud:playerLoaded", function()
    StartStatusModule()
end)

AddEventHandler("bablo-hud:playerUnloaded", function()
    running    = false
    lastStatus = {}
end)