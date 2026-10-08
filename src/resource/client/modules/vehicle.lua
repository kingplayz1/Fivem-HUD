-- Vehicle HUD data provider for bablo-hud

local constants   = (BabloHud and BabloHud.Constants) or {}
local nuiActions  = constants.NUI_ACTIONS or {}

-- ─── State ───────────────────────────────────────────────────────────────────

local inVehicle       = false  -- Whether the local player is currently in a tracked vehicle
local currentVehicle  = 0      -- Entity handle of the current vehicle
local seatbeltOn      = false  -- Internal seatbelt state (used when no framework)
local lastVehicleData = nil    -- Most recently sent vehicle data snapshot

local landingGearState = -1    -- Last known landing gear state (for heli/plane)
local vehicleDataRunning = false  -- Guard: is the per-vehicle update thread running?
local alarmRunning    = false  -- Is the seatbelt alarm thread running?

-- Sound: netId → soundId mapping for active seatbelt alarms
local activeSeatbeltAlarms = {}

-- ─── Mileage tracker ─────────────────────────────────────────────────────────

local mileage = {
    veh     = nil,
    plate   = nil,
    base    = 0.0,
    session = 0.0,
    pending = 0.0,
    lastT   = nil,
    lastSync = 0,
}

lib.onCache("vehicle", function(vehicle)
    -- Flush pending mileage when leaving a vehicle
    if mileage.veh and vehicle ~= mileage.veh then
        if mileage.pending > 0.001 and mileage.plate then
            TriggerServerEvent("bablo-hud:mileage:add", mileage.plate, mileage.pending)
            mileage.pending = 0.0
        end
    end
    if not vehicle then
        mileage.veh   = nil
        mileage.plate = nil
    end
end)

-- ─── Audio bank ──────────────────────────────────────────────────────────────

local seatbeltAudioMode = (Config and Config.Seatbelt and Config.Seatbelt.audioMode) or "native"
local nativeSoundReady  = false

if not Config and seatbeltAudioMode == "native" then
    CreateThread(function()
        local deadline = GetGameTimer() + 10000
        while true do
            local loaded = RequestScriptAudioBank("audiodirectory/bablo_custom_sounds", false)
            if loaded then nativeSoundReady = true break end
            if GetGameTimer() > deadline then return end
            Wait(250)
        end
    end)
end

-- ─── Ejection config ─────────────────────────────────────────────────────────

local ejectionMinSpeed = 100
local ejectionChance   = 50

local ejectionCfg = Config and Config.Seatbelt and Config.Seatbelt.ejection
if type(ejectionCfg) == "table" then
    if type(ejectionCfg.minSpeed) == "number" and ejectionCfg.minSpeed >= 0 then
        ejectionMinSpeed = ejectionCfg.minSpeed
    end
    if type(ejectionCfg.chance) == "number" then
        ejectionChance = math.max(0, math.min(100, ejectionCfg.chance))
    end
end

-- ─── Speed units ─────────────────────────────────────────────────────────────

local SPEED_MULTIPLIERS = { kmh = 3.6, mph = 2.236936 }

function GetSpeedMultiplier()
    local unit = Config and Config.SpeedUnit
    return SPEED_MULTIPLIERS[unit] or SPEED_MULTIPLIERS.kmh
end

-- ─── Utility ─────────────────────────────────────────────────────────────────

function IsMotorcycleOrBike(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return false end
    local class = GetVehicleClass(vehicle)
    return class == 8 or class == 13
end

function VehicleHasAnyDoorOpen(vehicle)
    if not DoesEntityExist(vehicle) then return false end
    for i = 0, 5 do
        if GetVehicleDoorAngleRatio(vehicle, i) > 0.0 then return true end
    end
    return false
end

-- Resolve network entity handle from net ID, or 0 if unavailable
function EntityFromNetId(netId)
    if not netId or netId == 0 then return 0 end
    if not NetworkDoesEntityExistWithNetworkId(netId) then return 0 end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity ~= 0 and DoesEntityExist(entity) then return entity end
    return 0
end

-- Stop and release a sound by its slot key
function ReleaseAlarmSound(slotKey)
    local soundId = activeSeatbeltAlarms[slotKey]
    if not soundId then return end
    activeSeatbeltAlarms[slotKey] = nil
    StopSound(soundId)
    ReleaseSoundId(soundId)
end

-- ─── Vehicle state snapshot ──────────────────────────────────────────────────

function GetVehicleSnapshot(vehicle)
    if not DoesEntityExist(vehicle) then return nil end

    local speed       = GetEntitySpeed(vehicle)
    local speedScaled = speed * GetSpeedMultiplier()

    -- RPM (0-1 range, remapped to display range)
    local rawRpm = GetVehicleCurrentRpm(vehicle)
    local rpmMin  = 0.2
    local rpm = math.max((rawRpm - rpmMin) / (1.0 - rpmMin), 0.0)
    if rpm < 0.05 then rpm = 0.0 end
    if speed < 1.0 and rawRpm <= 0.55 then rpm = 0.0 end

    -- Gear / direction
    local currentGear = GetVehicleCurrentGear(vehicle)
    local velocityY   = GetEntitySpeedVector(vehicle, true).y
    local gear
    if speed < 0.5 then
        if math.abs(velocityY) < 0.3 then gear = "N"
        end
    else
        if velocityY < -0.5 then gear = "R"
        elseif currentGear > 0 then gear = currentGear
        else gear = 1
        end
    end

    -- Fuel
    local fuel = nil
    if Framework and Framework.getFuel then
        local ok, result = pcall(Framework.getFuel, Framework, vehicle)
        if ok and type(result) == "number" then fuel = result end
    end
    if fuel == nil then fuel = GetVehicleFuelLevel(vehicle) end

    -- Seatbelt (internal state or framework)
    local hasSeatbelt = not Config or Config.Seatbelt ~= false
    local seatbeltState = seatbeltOn
    if not hasSeatbelt then
        if Framework and Framework.isSeatbeltOn then
            local ok, result = pcall(Framework.isSeatbeltOn, Framework)
            seatbeltState = ok and result == true
        end
    end

    local engineHealth  = GetVehicleEngineHealth(vehicle)
    local engineRunning = GetIsVehicleEngineRunning(vehicle)
    local doorOpen      = VehicleHasAnyDoorOpen(vehicle)

    local model    = GetEntityModel(vehicle)
    local isHeli   = IsThisModelAHeli(model)
    local isPlane  = IsThisModelAPlane(model)
    local isAircraft = isHeli or isPlane
    local isBoat   = IsThisModelABoat(model) or GetVehicleClass(vehicle) == 14
    local isBike   = IsThisModelABicycle(model) or GetVehicleClass(vehicle) == 13

    -- Heading: convert GTA heading (inverted) to compass bearing
    local gtaHeading = GetEntityHeading(vehicle)
    local heading = math.floor((360 - gtaHeading % 360) % 360)

    -- Aircraft-specific data
    local pitch, roll, verticalSpeed = 0, 0, 0
    local isGearDown    = false
    local mainRotorHealth = 1000
    local tailRotorHealth = 1000
    local stallWarning  = false
    local altitude      = 0

    if isAircraft then
        altitude = math.floor(GetEntityHeightAboveGround(vehicle))

        local rotZ = GetEntityRotation(vehicle).z
        if rotZ < 0 then rotZ = rotZ + 360 end
        heading = math.floor((360 - rotZ % 360) % 360)

        pitch = GetEntityPitch(vehicle)
        roll  = GetEntityRoll(vehicle)

        local gearState = GetLandingGearState(vehicle)
        if gearState == -1 or gearState == 0 then isGearDown = true
        elseif gearState == 4 then isGearDown = false
        else isGearDown = 2
        end

        if GetEntityHeightAboveGround(vehicle) > 2.0 then
            engineRunning = true
        end

        local vz = GetEntityVelocity(vehicle).z
        verticalSpeed = math.floor(vz * 10 + 0.5) / 10

        if isHeli then
            mainRotorHealth = math.floor(GetHeliMainRotorHealth(vehicle) or 1000)
            tailRotorHealth = math.floor(GetHeliTailRotorHealth(vehicle) or 1000)
        end

        if isPlane then
            stallWarning = engineRunning == true
        end
    end

    -- Boat-specific
    local isAnchored = false
    local waterDepth = 0

    if isBoat then
        if type(IsBoatAnchoredAndFrozen) == "function" then
            isAnchored = IsBoatAnchoredAndFrozen(vehicle) == true
        end
        local coords = GetEntityCoords(vehicle)
        local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z, true)
        if found and groundZ and groundZ < coords.z then
            waterDepth = math.floor((coords.z - groundZ) * 10 + 0.5) / 10
        end
    end

    -- Bike stamina / BPM
    local stamina = 100
    local bpm     = 75

    if isBike then
        local playerId = PlayerId()
        local staminaRemaining = GetPlayerSprintStaminaRemaining and GetPlayerSprintStaminaRemaining(playerId)
        if staminaRemaining and staminaRemaining <= 100.0 then
            stamina = math.floor(100.0 - staminaRemaining)
        else
            local raw = GetPlayerStamina and GetPlayerStamina(playerId) or 100
            stamina = math.floor(raw)
        end
        stamina = math.max(0, math.min(100, stamina))

        bpm = math.floor(72 + (speedScaled / 40.0) * 55 + (100 - stamina) * 0.45)
        if bpm > 185 then bpm = 185 end
    end

    -- Indicators
    local indicatorRaw = GetVehicleIndicatorLights(vehicle)
    local signalType   = "off"
    if indicatorRaw == 1 then signalType = "left"
    elseif indicatorRaw == 2 then signalType = "right"
    elseif indicatorRaw == 3 then signalType = "hazard"
    end

    -- Lights
    local _, lowBeams, highBeams = GetVehicleLightsState(vehicle)
    local headlightState = "off"
    if highBeams == 1 then headlightState = "high"
    elseif lowBeams == 1 then headlightState = "normal"
    end

    -- Lock
    local lockStatus = GetVehicleDoorLockStatus(vehicle)
    local isLocked   = lockStatus == 2 or lockStatus == 4 or lockStatus == 7

    -- Odometer
    local odometer = GetOdometerValue(vehicle)

    local speedUnit = (Config and Config.SpeedUnit) or "kmh"

    return {
        speed           = math.floor(speedScaled),
        rpm             = rpm,
        gear            = gear,
        fuel            = fuel,
        engineHealth    = engineHealth,
        isEngineRunning = engineRunning,
        isDoorOpen      = doorOpen,
        isSeatbeltOn    = seatbeltState,
        signalType      = signalType,
        headlightState  = headlightState,
        isLocked        = isLocked,
        odometer        = odometer,
        speedUnit       = speedUnit,
        isHelicopter    = isHeli,
        isBoat          = isBoat,
        isBicycle       = isBike,
        isPlane         = isPlane,
        stamina         = stamina,
        bpm             = bpm,
        altitude        = altitude,
        heading         = heading,
        pitch           = pitch,
        roll            = roll,
        isGearDown      = isGearDown,
        verticalSpeed   = verticalSpeed,
        mainRotorHealth = mainRotorHealth,
        tailRotorHealth = tailRotorHealth,
        stallWarning    = stallWarning,
        isAnchored      = isAnchored,
        waterDepth      = waterDepth,
    }
end

-- ─── Odometer logic ───────────────────────────────────────────────────────────

function GetOdometerValue(vehicle)
    local mileageProvider = (Config and Config.Mileage and Config.Mileage.provider) or "builtin"

    if mileageProvider == "framework" then
        if Framework and Framework.getVehicleMileage then
            local plate = GetVehicleNumberPlateText(vehicle)
            local ok, result = pcall(Framework.getVehicleMileage, Framework, vehicle, plate)
            if ok and type(result) == "number" then return result end
        end
        return nil
    end

    -- builtin provider
    local mileagePersistent = not (Config and Config.Mileage and Config.Mileage.persistent == false)

    if not mileagePersistent then
        -- Non-persistent: use entity state bag, increment in real-time
        local odo = Entity(vehicle).state.odometer or 0.0
        if GetEntitySpeed(vehicle) > 0.5 then
            odo = odo + GetEntitySpeed(vehicle) * 0.1 / 1000.0
            Entity(vehicle).state.odometer = odo
        end
        return odo
    end

    -- Persistent: server-synced KVP-based odometer
    local plate = GetVehicleNumberPlateText(vehicle)

    if mileage.veh ~= vehicle then
        mileage.veh     = vehicle
        mileage.plate   = plate
        mileage.base    = 0.0
        mileage.session = 0.0
        mileage.pending = 0.0
        local t = GetGameTimer()
        mileage.lastT    = t
        mileage.lastSync = t

        -- Async fetch of saved base mileage
        local capturedVehicle = vehicle
        CreateThread(function()
            local ok, savedBase = pcall(function()
                return lib.callback.await("bablo-hud:mileage:get", false, plate)
            end)
            if ok and mileage.veh == capturedVehicle then
                mileage.base = tonumber(savedBase) or 0.0
            end
        end)
    end

    local now = GetGameTimer()
    local dt  = now - (mileage.lastT or now)
    dt = dt / 1000.0
    mileage.lastT = now

    local speed = GetEntitySpeed(vehicle)
    local isDriver = cache and cache.seat == -1

    if isDriver and speed > 0.5 and dt > 0 and dt < 2.0 then
        local delta = speed * dt / 1000.0
        mileage.session = mileage.session + delta
        mileage.pending = mileage.pending + delta
    end

    -- Periodic server sync
    if isDriver and mileage.pending > 0.001 then
        local elapsed = now - (mileage.lastSync or 0)
        if elapsed > 10000 then
            TriggerServerEvent("bablo-hud:mileage:add", mileage.plate, mileage.pending)
            mileage.pending  = 0.0
            mileage.lastSync = now
        end
    end

    local total = mileage.base + mileage.session

    -- Write to entity state (driver only), or read from it (passenger)
    if isDriver then
        pcall(function()
            Entity(vehicle).state:set("odometer", total, true)
        end)
    else
        local stateOdo = Entity(vehicle).state.odometer
        total = stateOdo or total
    end

    -- Convert to display units
    if Config and Config.SpeedUnit == "mph" then
        total = total * 0.621371
    end
    return math.floor(total * 10) / 10
end

-- ─── NUI helpers ─────────────────────────────────────────────────────────────

function SendVehicleState(isInVehicle)
    SendNUIMessage({
        action = nuiActions.SET_VEHICLE_STATE or "setVehicleState",
        data   = { isInVehicle = isInVehicle },
    })
    Info("Vehicle state: %s", isInVehicle and "ENTERED" or "EXITED")
end

function HasVehicleDataChanged(newData, oldData)
    if not oldData then return true end

    local thresholds = {
        rpm           = 0.01,
        pitch         = 0.25,
        roll          = 0.25,
        verticalSpeed = 0.3,
        waterDepth    = 0.5,
    }

    for k, newVal in pairs(newData) do
        local oldVal = oldData[k]
        if type(newVal) == "number" then
            if type(oldVal) == "number" then
                local threshold = thresholds[k] or 1
                if math.abs(newVal - oldVal) >= threshold then return true end
            else
                return true
            end
        elseif newVal ~= oldVal then
            return true
        end
    end
    return false
end

function SendVehicleUpdate(data)
    if not data then return end
    if not HasVehicleDataChanged(data, lastVehicleData) then return end

    SendNUIMessage({
        action = nuiActions.UPDATE_VEHICLE_DATA or "updateVehicleData",
        data   = data,
    })
    lastVehicleData = data
end

-- ─── Engine toggle ────────────────────────────────────────────────────────────

function ToggleEngine()
    local ped     = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if not DoesEntityExist(vehicle) then return end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return end

    local wasRunning = GetIsVehicleEngineRunning(vehicle)
    SetVehicleEngineOn(vehicle, not wasRunning, false, true)

    local notify = exports["bablo-hud"]
    if wasRunning then
        notify:Notify(Locale.t("notifications.engine.disabledTitle"), Locale.t("notifications.engine.disabledBody"), "error", 2000)
    else
        notify:Notify(Locale.t("notifications.engine.enabledTitle"), Locale.t("notifications.engine.enabledBody"), "success", 2000)
    end

    Info("Engine toggled: %s", wasRunning and "OFF" or "ON")
end

if not Config then
    RegisterCommand("+_toggleengine", ToggleEngine, false)
    RegisterCommand("-_toggleengine", function() end, false)
    RegisterCommand("_toggleengine",  ToggleEngine, false)
    RegisterKeyMapping("+_toggleengine", Locale.t("keymapping.toggleEngine"), "keyboard", Config.EngineToggleKey)
end

-- ─── Seatbelt animation ───────────────────────────────────────────────────────

local SEATBELT_ANIM_DICT     = "bablo@belt"
local SEATBELT_ANIM_DURATION = 3500

function PlaySeatbeltAnimation(clip)
    local ped = PlayerPedId()
    RequestAnimDict(SEATBELT_ANIM_DICT)
    local attempts = 0
    while not HasAnimDictLoaded(SEATBELT_ANIM_DICT) and attempts < 1000 do
        Wait(0)
        attempts = attempts + 1
    end
    if HasAnimDictLoaded(SEATBELT_ANIM_DICT) then
        TaskPlayAnim(ped, SEATBELT_ANIM_DICT, clip, 8.0, -8.0, SEATBELT_ANIM_DURATION, 48, 0, false, false, false)
    end
end

-- ─── Seatbelt windscreen ejection params ─────────────────────────────────────

function SetEjectionProtection(protected)
    if Config then return end  -- Only active when no config (ejection enabled)
    SetPedConfigFlag(PlayerPedId(), 32, protected)
    if protected then
        SetFlyThroughWindscreenParams(10000.0, 10000.0, 1000.0, 500.0)
    else
        SetFlyThroughWindscreenParams(7.8, 1.0, 12.0, 8.0)
    end
end

-- ─── Seatbelt sound ───────────────────────────────────────────────────────────

function PlaySeatbeltNetworkSound(soundName)
    if not inVehicle or not DoesEntityExist(currentVehicle) then return end
    local netId = NetworkGetNetworkIdFromEntity(currentVehicle)
    if netId and netId ~= 0 then
        TriggerServerEvent("bablo-hud:server:seatbeltSound", netId, soundName)
    else
        PlaySoundFrontend(-1, soundName, "bablo_special_soundset", true)
    end
end

function PlaySeatbeltSound(soundName)
    if seatbeltAudioMode == "nui" then
        SendNUIMessage({
            action = nuiActions.PLAY_ALERT_SOUND or "playAlertSound",
            data   = { file = soundName .. ".ogg", volume = 0.2 },
        })
    else
        PlaySeatbeltNetworkSound(soundName)
    end
end

-- ─── Seatbelt toggle ─────────────────────────────────────────────────────────

function ToggleSeatbelt()
    local hasSeatbelt = not Config or Config.Seatbelt ~= false
    if not hasSeatbelt then return end
    if not inVehicle then return end
    if IsMotorcycleOrBike(currentVehicle) then return end

    seatbeltOn = not seatbeltOn
    Info("Seatbelt: %s", seatbeltOn and "ON" or "OFF")

    local notify = exports["bablo-hud"]

    if seatbeltOn then
        PlaySeatbeltSound("buckle")

        -- Determine seat side for correct buckle animation
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local seatIndex = -1
        for i = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
            if GetPedInVehicleSeat(vehicle, i) == ped then
                seatIndex = i
                break
            end
        end

        local clip = (seatIndex == -1 or seatIndex == 1) and "clip_l" or "clip_r"
        PlaySeatbeltAnimation(clip)
        SetEjectionProtection(true)

        notify:Notify(
            Locale.t("notifications.seatbelt.enabledTitle"),
            Locale.t("notifications.seatbelt.enabledBody"),
            "success", 2000
        )
    else
        PlaySeatbeltSound("unbuckle")
        SetEjectionProtection(false)
        notify:Notify(
            Locale.t("notifications.seatbelt.disabledTitle"),
            Locale.t("notifications.seatbelt.disabledBody"),
            "error", 2000
        )
    end
end

exports("ToggleSeatbelt", ToggleSeatbelt)

exports("IsSeatbeltOn", function()
    local hasSeatbelt = not Config or Config.Seatbelt ~= false
    if hasSeatbelt then return seatbeltOn end
    if Framework and Framework.isSeatbeltOn then
        local ok, result = pcall(Framework.isSeatbeltOn, Framework)
        return ok and result == true
    end
    return false
end)

if not Config or Config.Seatbelt ~= false then
    RegisterCommand("+_toggleseatbelt", ToggleSeatbelt, false)
    RegisterCommand("-_toggleseatbelt", function() end, false)
    RegisterCommand("_toggleseatbelt",  ToggleSeatbelt, false)
    RegisterKeyMapping("+_toggleseatbelt", Locale.t("keymapping.toggleSeatbelt"), "keyboard", Config and Config.SeatbeltToggleKey)
end

-- ─── Seatbelt alarm: stop ────────────────────────────────────────────────────

local seatbeltAlarmVehicleNetId = nil
local seatbeltAlarmStartTime    = nil
local SEATBELT_ALARM_DELAY_MS   = 5000

function StopSeatbeltAlarm()
    if seatbeltAlarmVehicleNetId then
        if seatbeltAudioMode == "nui" then
            SendNUIMessage({ action = nuiActions.STOP_ALARM_SOUND or "stopAlarmSound" })
        else
            TriggerServerEvent("bablo-hud:server:stopSeatbeltAlarm", seatbeltAlarmVehicleNetId)
        end
        seatbeltAlarmVehicleNetId = nil
    end
    seatbeltAlarmStartTime = nil
end

-- ─── Seatbelt alarm: monitoring thread ───────────────────────────────────────

function StartSeatbeltMonitor()
    local hasSeatbelt = not Config or Config.Seatbelt ~= false
    if not hasSeatbelt then return end
    if alarmRunning then return end
    alarmRunning = true

    CreateThread(function()
        while alarmRunning do
            if not _G.BabloHudActive or not inVehicle or not DoesEntityExist(currentVehicle) then
                break
            end

            local ped = PlayerPedId()
            local isDriver = GetPedInVehicleSeat(currentVehicle, -1) == ped
            local speedKmh = GetEntitySpeed(currentVehicle) * 3.6
            local isBike   = IsMotorcycleOrBike(currentVehicle)

            if not isBike and isDriver then
                local seatbeltState = seatbeltOn
                if not seatbeltState then
                    if speedKmh >= ejectionMinSpeed then
                        seatbeltAlarmStartTime = seatbeltAlarmStartTime or GetGameTimer()

                        if not seatbeltAlarmVehicleNetId then
                            local elapsed = GetGameTimer() - seatbeltAlarmStartTime
                            if elapsed >= SEATBELT_ALARM_DELAY_MS then
                                local netId = NetworkGetNetworkIdFromEntity(currentVehicle)
                                if netId and netId ~= 0 then
                                    seatbeltAlarmVehicleNetId = netId
                                    if seatbeltAudioMode == "nui" then
                                        SendNUIMessage({
                                            action = nuiActions.START_ALARM_SOUND or "startAlarmSound",
                                            data   = { file = "seatbelt-alarm.ogg", volume = 0.5 },
                                        })
                                    else
                                        TriggerServerEvent("bablo-hud:server:startSeatbeltAlarm", netId)
                                    end
                                end
                            end
                        end
                    else
                        StopSeatbeltAlarm()
                    end
                else
                    StopSeatbeltAlarm()
                end
            else
                StopSeatbeltAlarm()
            end

            Wait(500)
        end

        alarmRunning = false
        StopSeatbeltAlarm()
    end)
end

-- ─── Disable exit-vehicle control when seatbelt is on ─────────────────────────

CreateThread(function()
    while true do
        if _G.BabloHudActive and inVehicle and IsSeatbeltActiveForFrame() then
            DisableControlAction(0, 75, true)
            Wait(0)
        else
            Wait(500)
        end
    end
end)

function IsSeatbeltActiveForFrame()
    if not Config or Config.Seatbelt ~= false then
        return seatbeltOn
    end
    if Framework and Framework.isSeatbeltOn then
        local ok, result = pcall(Framework.isSeatbeltOn, Framework)
        return ok and result == true
    end
    return false
end

-- ─── Per-vehicle data update thread ──────────────────────────────────────────

function StartVehicleUpdateThread()
    if vehicleDataRunning then return end
    if not inVehicle or not DoesEntityExist(currentVehicle) then return end

    vehicleDataRunning = true

    CreateThread(function()
        while vehicleDataRunning and _G.BabloHudActive and inVehicle and DoesEntityExist(currentVehicle) do
            local snapshot = GetVehicleSnapshot(currentVehicle)

            -- Track landing gear changes (reset cached data on change to force NUI update)
            if snapshot and snapshot.isHelicopter then
                local gear = GetLandingGearState(currentVehicle)
                if gear ~= landingGearState then
                    landingGearState = gear
                    lastVehicleData  = nil
                end
            end

            SendVehicleUpdate(snapshot)
            Wait(100)
        end
        vehicleDataRunning = false
    end)
end

-- ─── Enter / exit vehicle ────────────────────────────────────────────────────

function OnEnterVehicle(vehicle)
    if inVehicle and vehicle == currentVehicle then return end

    if inVehicle then
        StopSeatbeltAlarm()
        SendVehicleState(false)
        Wait(50)
    end

    inVehicle        = true
    currentVehicle   = vehicle
    seatbeltOn       = false
    landingGearState = -1
    lastVehicleData  = nil

    SetEjectionProtection(false)
    SendVehicleState(true)
    StartVehicleUpdateThread()
    StartSeatbeltMonitor()
end

function OnExitVehicle()
    if not inVehicle then return end
    StopSeatbeltAlarm()
    inVehicle         = false
    currentVehicle    = 0
    seatbeltOn        = false
    lastVehicleData   = nil
    landingGearState  = -1
    vehicleDataRunning = false
    alarmRunning      = false

    SetEjectionProtection(false)
    SendVehicleState(false)
end

-- ─── Net events: seatbelt sounds (played on other clients via server relay) ───

RegisterNetEvent("bablo-hud:client:startSeatbeltAlarm")
AddEventHandler("bablo-hud:client:startSeatbeltAlarm", function(vehicleNetId)
    local hasSeatbelt = not Config or Config.Seatbelt ~= false
    if not hasSeatbelt then return end
    if seatbeltAudioMode ~= "native" then return end
    if not nativeSoundReady then return end
    if type(vehicleNetId) ~= "number" or vehicleNetId <= 0 then return end
    if activeSeatbeltAlarms[vehicleNetId] then return end

    local soundId = GetSoundId()
    if soundId == -1 then return end

    activeSeatbeltAlarms[vehicleNetId] = soundId

    CreateThread(function()
        while activeSeatbeltAlarms[vehicleNetId] == soundId do
            local vehicleEntity = EntityFromNetId(vehicleNetId)
            if vehicleEntity == 0 then break end

            PlaySoundFromEntity(soundId, "seatbelt-alarm", vehicleEntity, "bablo_special_soundset", false, 0)
            Wait(200)

            -- Wait for the sound to finish
            while activeSeatbeltAlarms[vehicleNetId] == soundId do
                if HasSoundFinished(soundId) then break end
                Wait(100)
            end
        end

        if activeSeatbeltAlarms[vehicleNetId] == soundId then
            activeSeatbeltAlarms[vehicleNetId] = nil
        end
        StopSound(soundId)
        ReleaseSoundId(soundId)
    end)
end)

RegisterNetEvent("bablo-hud:client:stopSeatbeltAlarm")
AddEventHandler("bablo-hud:client:stopSeatbeltAlarm", function(vehicleNetId)
    if type(vehicleNetId) ~= "number" then return end
    ReleaseAlarmSound(vehicleNetId)
end)

RegisterNetEvent("bablo-hud:client:seatbeltSound")
AddEventHandler("bablo-hud:client:seatbeltSound", function(vehicleNetId, soundName)
    local hasSeatbelt = not Config or Config.Seatbelt ~= false
    if not hasSeatbelt then return end
    if seatbeltAudioMode ~= "native" then return end
    if not nativeSoundReady then return end
    if soundName ~= "buckle" and soundName ~= "unbuckle" then return end

    local vehicleEntity = EntityFromNetId(vehicleNetId)
    if vehicleEntity == 0 then return end

    local soundId = GetSoundId()
    if soundId == -1 then return end

    PlaySoundFromEntity(soundId, soundName, vehicleEntity, "bablo_special_soundset", false, 0)

    CreateThread(function()
        while not HasSoundFinished(soundId) do Wait(100) end
        ReleaseSoundId(soundId)
    end)
end)

-- ─── Lifecycle events ─────────────────────────────────────────────────────────

AddEventHandler("bablo-hud:playerLoaded", function()
    CreateThread(function()
        Wait(600)
        local vehicle = cache and cache.vehicle
        if vehicle then OnEnterVehicle(vehicle) end
    end)
end)

lib.onCache("vehicle", function(vehicle)
    if not _G.BabloHudActive then return end
    if vehicle then
        OnEnterVehicle(vehicle)
    else
        OnExitVehicle()
    end
end)

AddEventHandler("bablo-hud:playerUnloaded", function()
    StopSeatbeltAlarm()
    if inVehicle then
        inVehicle         = false
        currentVehicle    = 0
        vehicleDataRunning = false
        alarmRunning      = false
        SendVehicleState(false)
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    StopSeatbeltAlarm()
    alarmRunning = false

    for netId, soundId in pairs(activeSeatbeltAlarms) do
        StopSound(soundId)
        ReleaseSoundId(soundId)
        activeSeatbeltAlarms[netId] = nil
    end

    if inVehicle then SendVehicleState(false) end
end)

-- ─── Exports ─────────────────────────────────────────────────────────────────

exports("GetOdometer", function(vehicle)
    if not vehicle then
        local ped = PlayerPedId()
        vehicle = GetVehiclePedIsIn(ped, false)
    end
    if not vehicle or vehicle == 0 then return 0.0 end
    return Entity(vehicle).state.odometer or 0.0
end)

exports("SetOdometer", function(vehicle, value)
    if not vehicle then
        local ped = PlayerPedId()
        vehicle = GetVehiclePedIsIn(ped, false)
    end
    if not vehicle or vehicle == 0 then return end
    Entity(vehicle).state.odometer = tonumber(value) or 0.0
end)
