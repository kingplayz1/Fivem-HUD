local isCarControlOpen = false

function GetVehicleData(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then
        return nil
    end

    local playerPed    = PlayerPedId()
    local model        = GetEntityModel(vehicle)
    local engineOn     = GetIsVehicleEngineRunning(vehicle)
    local _, lowBeams, highBeams = GetVehicleLightsState(vehicle)
    local headlights   = 1 == lowBeams or 1 == highBeams
    local interiorLight = IsVehicleInteriorLightOn(vehicle)
    local lockStatus   = GetVehicleDoorLockStatus(vehicle)

    local indicatorRaw = GetVehicleIndicatorLights(vehicle)
    local signalType   = "off"
    if     indicatorRaw == 1 then signalType = "left"
    elseif indicatorRaw == 2 then signalType = "right"
    elseif indicatorRaw == 3 then signalType = "hazard"
    end

    local seatCount = GetVehicleModelNumberOfSeats(model)
    if not seatCount or seatCount <= 0 then seatCount = 2 end

    local seats = {}
    for i = 0, seatCount - 1 do
        local seatPed = GetPedInVehicleSeat(vehicle, i - 1)
        seats[i] = {
            isOccupied      = 0 ~= seatPed and DoesEntityExist(seatPed),
            isCurrentPlayer = seatPed == playerPed,
            exists          = true,
        }
    end

    -- Doors
    local function doorEntry(doorIndex)
        return { isOpen = GetVehicleDoorAngleRatio(vehicle, doorIndex) > 0.05, exists = true }
    end

    local doors = {}
    doors[0] = doorEntry(0)
    doors[1] = doorEntry(1)

    if seatCount > 2 then
        if DoesVehicleHaveDoor(vehicle, 2) then doors[2] = doorEntry(2) end
        if DoesVehicleHaveDoor(vehicle, 3) then doors[3] = doorEntry(3) end
    end

    local hasHood = DoesVehicleHaveDoor(vehicle, 4)
        or GetEntityBoneIndexByName(vehicle, "bonnet") ~= -1
    if hasHood then doors[4] = doorEntry(4) end

    local hasTrunk = DoesVehicleHaveDoor(vehicle, 5)
        or DoesVehicleHaveDoor(vehicle, 6)
        or GetEntityBoneIndexByName(vehicle, "boot") ~= -1
    if hasTrunk then
        local trunkAngle = math.max(
            GetVehicleDoorAngleRatio(vehicle, 5),
            GetVehicleDoorAngleRatio(vehicle, 6)
        )
        doors[5] = { isOpen = trunkAngle > 0.05, exists = true }
    end

    -- Windows
    local windowCount = 4
    if seatCount > 4 then
        windowCount = math.min(8, seatCount)
    elseif seatCount > 2 and doors[2] and doors[2].exists then
        windowCount = 4
    else
        windowCount = 2
    end

    local windows = {}
    for i = 0, windowCount - 1 do
        windows[i] = { isOpen = not IsVehicleWindowIntact(vehicle, i), exists = true }
    end

    local engineHealth = math.floor(math.max(0, GetVehicleEngineHealth(vehicle)))
    local bodyHealth   = math.floor(math.max(0, GetVehicleBodyHealth(vehicle)))
    local fuel         = math.floor(GetVehicleFuelLevel(vehicle) or 100)

    local modelDisplayKey = GetDisplayNameFromVehicleModel(model)
    local vehicleName = GetLabelText(modelDisplayKey)
    if not vehicleName or vehicleName == "NULL" then vehicleName = modelDisplayKey end

    local plate = GetVehicleNumberPlateText(vehicle) or "BABLO"

    return {
        plate        = plate,
        name         = vehicleName,
        isEngineOn   = engineOn,
        headlights   = headlights,
        highbeams    = 1 == highBeams,
        interiorLight = interiorLight,
        lockStatus   = lockStatus,
        engineHealth = engineHealth,
        bodyHealth   = bodyHealth,
        fuel         = fuel,
        doors        = doors,
        windows      = windows,
        seats        = seats,
        signalType   = signalType,
    }
end

-- Cached vehicle data table, keyed by vehicle handle
local vehicleDataCache = {}

function GetCachedVehicleData(vehicle)
    return vehicleDataCache[vehicle]
end

function OpenCarControl()
    if Config and Config.VehicleControl and Config.VehicleControl.enabled == false then
        return false
    end

    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    local allowOnFoot = Config and Config.VehicleControl and Config.VehicleControl.allowOnFoot

    if not allowOnFoot and (not vehicle or vehicle == 0) then
        local msg = (Locale and type(Locale.t) == "function" and Locale.t("notifications.mustBeInVehicle"))
            or "You must be inside a vehicle to access vehicle controls."
        exports["bablo-hud"]:Notify(msg, "warning")
        return false
    end

    local data = GetVehicleData(vehicle)
    vehicleDataCache[vehicle] = data

    isCarControlOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = "openCarControl", data = data })
    return true
end

function CloseCarControl()
    if not isCarControlOpen then return false end
    isCarControlOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "closeCarControl" })
    return true
end

function ToggleCarControl()
    if isCarControlOpen then
        return CloseCarControl()
    end
    return OpenCarControl()
end

-- Exports
exports("OpenVehicleControl", function()
    if not _G.BabloHudActive then return false end
    return OpenCarControl()
end)

exports("CloseVehicleControl", CloseCarControl)

exports("ToggleVehicleControl", function()
    if not _G.BabloHudActive then return false end
    return ToggleCarControl()
end)

exports("IsVehicleControlOpen", function()
    return isCarControlOpen == true
end)

-- Net events
RegisterNetEvent("bablo-hud:vehiclecontrol:open")
AddEventHandler("bablo-hud:vehiclecontrol:open", function()
    if not _G.BabloHudActive then return end
    OpenCarControl()
end)

RegisterNetEvent("bablo-hud:vehiclecontrol:close")
AddEventHandler("bablo-hud:vehiclecontrol:close", function()
    CloseCarControl()
end)

RegisterNetEvent("bablo-hud:vehiclecontrol:toggle")
AddEventHandler("bablo-hud:vehiclecontrol:toggle", function()
    if not _G.BabloHudActive then return end
    ToggleCarControl()
end)

-- Command registration
local commandName = "carcontrol"
if Config and Config.VehicleControl and Config.VehicleControl.command then
    local cmdCfg = Config.VehicleControl.command
    if type(cmdCfg.name) == "string" and cmdCfg.name ~= "" then
        commandName = cmdCfg.name
    end
end

local commandEnabled = not (
    Config and Config.VehicleControl
    and Config.VehicleControl.command
    and Config.VehicleControl.command.enabled == false
)

if commandEnabled then
    RegisterCommand(commandName, function()
        if not _G.BabloHudActive then return end
        OpenCarControl()
    end, false)
end

-- Keybind registration
local keybindEnabled = not (
    Config and Config.VehicleControl
    and Config.VehicleControl.keybind
    and Config.VehicleControl.keybind.enabled == false
)

if keybindEnabled then
    local defaultKey = (Config and Config.VehicleControl and Config.VehicleControl.keybind
        and Config.VehicleControl.keybind.defaultKey) or "M"

    local keybindLabel = (Locale and type(Locale.t) == "function"
        and Locale.t("keymapping.openCarControl"))
        or "Open Vehicle Control Menu"

    RegisterKeyMapping(commandName, keybindLabel, "keyboard", defaultKey)
end

-- Returns the vehicle the player is driving, or nil
function GetDrivenVehicle()
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then return nil end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return nil end
    return vehicle
end

-- Indicator / blinker helpers
local binds = Config and Config.VehicleControl and Config.VehicleControl.binds
local bindsEnabled = not (binds and binds.enabled == false)

function SetIndicators(vehicle, leftOn, rightOn)
    SetVehicleIndicatorLights(vehicle, 1, leftOn)
    SetVehicleIndicatorLights(vehicle, 0, rightOn)
end

function GetLocaleOrDefault(key, default)
    if Locale and type(Locale.t) == "function" then
        local val = Locale.t("keymapping." .. key)
        if val then return val end
    end
    return default
end

if bindsEnabled then
    RegisterCommand("hud_indicator_left", function()
        if not _G.BabloHudActive then return end
        local vehicle = GetDrivenVehicle()
        if not vehicle then return end
        if GetVehicleIndicatorLights(vehicle) == 1 then
            SetIndicators(vehicle, false, false)
        else
            SetIndicators(vehicle, true, false)
        end
    end, false)

    RegisterCommand("hud_indicator_right", function()
        if not _G.BabloHudActive then return end
        local vehicle = GetDrivenVehicle()
        if not vehicle then return end
        if GetVehicleIndicatorLights(vehicle) == 2 then
            SetIndicators(vehicle, false, false)
        else
            SetIndicators(vehicle, false, true)
        end
    end, false)

    RegisterCommand("hud_hazards", function()
        if not _G.BabloHudActive then return end
        local vehicle = GetDrivenVehicle()
        if not vehicle then return end
        if GetVehicleIndicatorLights(vehicle) == 3 then
            SetIndicators(vehicle, false, false)
        else
            SetIndicators(vehicle, true, true)
        end
    end, false)

    local leftKey   = (binds and binds.indicatorLeft)  or "LEFT"
    local rightKey  = (binds and binds.indicatorRight) or "RIGHT"
    local hazardKey = (binds and binds.hazards)        or "DOWN"

    RegisterKeyMapping("hud_indicator_left",  GetLocaleOrDefault("indicatorLeft",  "Toggle Left Blinker"),  "keyboard", leftKey)
    RegisterKeyMapping("hud_indicator_right", GetLocaleOrDefault("indicatorRight", "Toggle Right Blinker"), "keyboard", rightKey)
    RegisterKeyMapping("hud_hazards",         GetLocaleOrDefault("hazards",        "Toggle Hazard Lights"), "keyboard", hazardKey)
end

-- NUI Callbacks
RegisterNUICallback("closeCarControl", function(_, cb)
    isCarControlOpen = false
    SetNuiFocus(false, false)
    cb("ok")
end)

RegisterNUICallback("toggleCarEngine", function(_, cb)
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then cb(nil) return end

    local newState = not GetIsVehicleEngineRunning(vehicle)
    SetVehicleEngineOn(vehicle, newState, false, true)

    local cached = vehicleDataCache[vehicle]
    if cached then cached.isEngineOn = newState end
    cb(cached)
end)

RegisterNUICallback("toggleCarLights", function(_, cb)
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then cb(nil) return end

    local _, lowBeams, highBeams = GetVehicleLightsState(vehicle)
    local lightsOff = 1 ~= lowBeams and 1 ~= highBeams
    SetVehicleLights(vehicle, lightsOff and 3 or 1)

    local cached = vehicleDataCache[vehicle]
    if cached then cached.headlights = lightsOff end
    cb(cached)
end)

RegisterNUICallback("toggleCarLock", function(_, cb)
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then cb(nil) return end

    local lockStatus = GetVehicleDoorLockStatus(vehicle)
    local newLock    = lockStatus == 1 and 2 or 1
    SetVehicleDoorsLocked(vehicle, newLock)

    local cached = vehicleDataCache[vehicle]
    if cached then cached.lockStatus = newLock end
    cb(cached)
end)

RegisterNUICallback("toggleCarDoor", function(data, cb)
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then cb(nil) return end

    if type(data) ~= "table" or type(data.doorIndex) ~= "number" then return end

    local doorIndex = data.doorIndex
    local angle5    = GetVehicleDoorAngleRatio(vehicle, 5)
    local angle6    = GetVehicleDoorAngleRatio(vehicle, 6)
    local angle     = GetVehicleDoorAngleRatio(vehicle, doorIndex)

    if doorIndex == 5 then
        angle = math.max(angle, angle5, angle6)
    end

    local shouldClose = angle > 0.05

    if doorIndex == 5 then
        if not shouldClose then
            SetVehicleDoorOpen(vehicle, 5, false, false)
            if DoesVehicleHaveDoor(vehicle, 6) then
                SetVehicleDoorOpen(vehicle, 6, false, false)
            end
        else
            SetVehicleDoorShut(vehicle, 5, false)
            if DoesVehicleHaveDoor(vehicle, 6) then
                SetVehicleDoorShut(vehicle, 6, false)
            end
        end
    elseif not shouldClose then
        SetVehicleDoorOpen(vehicle, doorIndex, false, false)
    else
        SetVehicleDoorShut(vehicle, doorIndex, false)
    end

    local cached = vehicleDataCache[vehicle]
    if cached and cached.doors and cached.doors[doorIndex] then
        cached.doors[doorIndex].isOpen = not shouldClose
    end
    cb(cached)
end)

RegisterNUICallback("toggleAllDoors", function(_, cb)
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then cb(nil) return end

    local anyOpen = false
    for i = 0, 6 do
        if GetVehicleDoorAngleRatio(vehicle, i) > 0.05 then
            anyOpen = true
            break
        end
    end

    local shouldOpen = not anyOpen

    CreateThread(function()
        for _, doorIndex in ipairs({ 0, 1, 2, 3, 4, 5, 6 }) do
            if DoesVehicleHaveDoor(vehicle, doorIndex) or doorIndex == 4 or doorIndex == 5 then
                if shouldOpen then
                    SetVehicleDoorOpen(vehicle, doorIndex, false, false)
                else
                    SetVehicleDoorShut(vehicle, doorIndex, false)
                end
                Wait(40)
            end
        end
    end)

    local cached = vehicleDataCache[vehicle]
    if cached and cached.doors then
        for _, doorData in pairs(cached.doors) do
            doorData.isOpen = shouldOpen
        end
    end
    cb(cached)
end)

RegisterNUICallback("toggleCarWindow", function(data, cb)
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then cb(nil) return end

    if type(data) ~= "table" or type(data.windowIndex) ~= "number" then return end

    local windowIndex = data.windowIndex
    local isIntact    = IsVehicleWindowIntact(vehicle, windowIndex)
    if isIntact then
        RollDownWindow(vehicle, windowIndex)
    else
        RollUpWindow(vehicle, windowIndex)
    end

    local cached = vehicleDataCache[vehicle]
    if cached and cached.windows and cached.windows[windowIndex] then
        cached.windows[windowIndex].isOpen = isIntact
    end
    cb(cached)
end)

RegisterNUICallback("toggleAllWindows", function(_, cb)
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then cb(nil) return end

    local model      = GetEntityModel(vehicle)
    local seatCount  = GetVehicleModelNumberOfSeats(model)
    local windowCount = 4
    if seatCount > 4 then
        windowCount = math.min(8, seatCount)
    elseif seatCount <= 2 or not DoesVehicleHaveDoor(vehicle, 2) then
        windowCount = 2
    end

    local anyOpen = false
    for i = 0, windowCount - 1 do
        if not IsVehicleWindowIntact(vehicle, i) then
            anyOpen = true
            break
        end
    end

    local shouldOpen = not anyOpen

    CreateThread(function()
        for i = 0, windowCount - 1 do
            if shouldOpen then
                RollDownWindow(vehicle, i)
            else
                RollUpWindow(vehicle, i)
            end
            Wait(30)
        end
    end)

    local cached = vehicleDataCache[vehicle]
    if cached and cached.windows then
        for _, winData in pairs(cached.windows) do
            winData.isOpen = shouldOpen
        end
    end
    cb(cached)
end)

RegisterNUICallback("switchCarSeat", function(data, cb)
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then cb(nil) return end

    if type(data) ~= "table" or type(data.seatIndex) ~= "number" then return end

    local targetSeat = data.seatIndex - 1
    if IsVehicleSeatFree(vehicle, targetSeat) then
        TaskWarpPedIntoVehicle(ped, vehicle, targetSeat)
    end

    Wait(100)
    cb(GetVehicleData(vehicle))
end)

RegisterNUICallback("toggleCarSignal", function(data, cb)
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then cb(nil) return end

    if type(data) ~= "table" or not data.signalType then return end

    local sig = data.signalType
    if sig == "left" then
        SetVehicleIndicatorLights(vehicle, 1, true)
        SetVehicleIndicatorLights(vehicle, 0, false)
    elseif sig == "right" then
        SetVehicleIndicatorLights(vehicle, 0, true)
        SetVehicleIndicatorLights(vehicle, 1, false)
    elseif sig == "hazard" then
        SetVehicleIndicatorLights(vehicle, 0, true)
        SetVehicleIndicatorLights(vehicle, 1, true)
    else
        SetVehicleIndicatorLights(vehicle, 0, false)
        SetVehicleIndicatorLights(vehicle, 1, false)
    end

    local cached = vehicleDataCache[vehicle]
    if cached then cached.signalType = sig end
    cb(cached)
end)

RegisterNUICallback("toggleCarInteriorLight", function(_, cb)
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then cb(nil) return end

    local newState = not IsVehicleInteriorLightOn(vehicle)
    SetVehicleInteriorlight(vehicle, newState)

    local cached = vehicleDataCache[vehicle]
    if cached then cached.interiorLight = newState end
    cb(cached)
end)
