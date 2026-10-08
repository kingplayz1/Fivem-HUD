-- ---------------------------------------------------------------------------
-- Stressors: driving speed and shooting stress integrations for Bablo.Stress
-- ⚠️ Bablo.Stress is defined externally — this file only calls Add() on it.
-- ⚠️ Framework.getJobName is expected from an external Framework global.
-- ---------------------------------------------------------------------------

local stressors = { started = false }

-- ---------------------------------------------------------------------------
-- Config helpers
-- ---------------------------------------------------------------------------

function IsStressIntegrated()
    return Config and Config.Stress and Config.Stress.integrated == true
end

function GetStressModule()
    return Bablo and Bablo.Stress
end

-- Returns true when the given weapon hash is in Config.Stress.shooting.weaponBlacklist
function IsWeaponBlacklisted(weaponHash)
    local blacklist = Config.Stress
        and Config.Stress.shooting
        and Config.Stress.shooting.weaponBlacklist

    if not blacklist or #blacklist == 0 then return false end

    for _, weaponName in ipairs(blacklist) do
        if GetHashKey(weaponName) == weaponHash then return true end
    end
    return false
end

-- Returns true when the player's current job is in Config.Stress.jobWhitelist
-- (whitelisted jobs are exempt from stress gain)
function IsJobWhitelisted()
    local whitelist = Config.Stress and Config.Stress.jobWhitelist
    if not whitelist or #whitelist == 0 then return false end

    if not (Framework and Framework.getJobName) then return false end

    local jobName = Framework:getJobName()
    if not jobName then return false end

    for _, name in ipairs(whitelist) do
        if name == jobName then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Finds the best matching speed threshold for the given speed value.
-- Returns the threshold table with the highest minSpeed that the speed exceeds.
-- ---------------------------------------------------------------------------
function GetMatchingSpeedThreshold(speed, thresholds)
    if not thresholds then return nil end

    local best = nil
    for _, threshold in ipairs(thresholds) do
        local minSpeed = threshold.minSpeed or 0
        if speed >= minSpeed then
            if not best or minSpeed > (best.minSpeed or 0) then
                best = threshold
            end
        end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- Returns the player's vehicle speed in the given unit ("mph" or "kmh").
-- Returns 0 if the player is not the driver of any vehicle.
-- ---------------------------------------------------------------------------
function GetDriverSpeed(unit)
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return 0 end

    local vehicle = GetVehiclePedIsUsing(ped)
    if vehicle == 0 then return 0 end

    -- Only count stress if the player is in the driver seat
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return 0 end

    local rawSpeed = GetEntitySpeed(vehicle)
    if unit == "mph" then
        return rawSpeed * 2.23694
    end
    return rawSpeed * 3.6
end

-- ---------------------------------------------------------------------------
-- Driving stressor loop
-- Adds stress per tick when the player exceeds a speed threshold while driving
-- ---------------------------------------------------------------------------
function StartDrivingStressor()
    local drivingCfg = Config.Stress and Config.Stress.driving
    if not drivingCfg or drivingCfg.enabled == false then return end

    local interval = drivingCfg.tickIntervalMs or 10000

    CreateThread(function()
        while stressors.started do
            Citizen.Wait(interval)

            local stress = GetStressModule()
            if stress and not IsJobWhitelisted() then
                local unit  = drivingCfg.speedUnit or "kmh"
                local speed = GetDriverSpeed(unit)
                if speed > 0 then
                    local threshold = GetMatchingSpeedThreshold(speed, drivingCfg.thresholds)
                    if threshold and threshold.perTick and threshold.perTick > 0 then
                        stress:Add(threshold.perTick)
                    end
                end
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Shooting stressor loop
-- Adds stress per shot fired (detected via ammo delta), excluding blacklisted
-- weapons and job-whitelisted players.
-- ---------------------------------------------------------------------------
function StartShootingStressor()
    local shootingCfg = Config.Stress and Config.Stress.shooting
    if not shootingCfg or shootingCfg.enabled == false then return end

    local perShot      = tonumber(shootingCfg.perShot) or 0
    local unarmedHash  = GetHashKey("WEAPON_UNARMED")

    CreateThread(function()
        local lastAmmo       = nil
        local lastWeaponHash = nil

        while stressors.started do
            Citizen.Wait(50)

            if perShot <= 0 then goto continue end

            local ped        = PlayerPedId()
            local weaponHash = GetSelectedPedWeapon(ped)

            -- Reset tracking when unarmed or no weapon
            if not weaponHash or weaponHash == 0 or weaponHash == unarmedHash then
                lastAmmo       = nil
                lastWeaponHash = nil
                goto continue
            end

            local currentAmmo = GetAmmoInPedWeapon(ped, weaponHash)

            if weaponHash == lastWeaponHash and lastAmmo and lastAmmo > currentAmmo then
                local shotsFired = lastAmmo - currentAmmo
                if not IsJobWhitelisted() and not IsWeaponBlacklisted(weaponHash) then
                    local stress = GetStressModule()
                    if stress then
                        stress:Add(perShot * shotsFired)
                    end
                end
            end

            lastAmmo       = currentAmmo
            lastWeaponHash = weaponHash

            ::continue::
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
AddEventHandler("bablo-hud:playerLoaded", function()
    if not IsStressIntegrated() then return end
    if stressors.started then return end

    stressors.started = true
    StartDrivingStressor()
    StartShootingStressor()
end)

AddEventHandler("bablo-hud:playerUnloaded", function()
    stressors.started = false
end)
