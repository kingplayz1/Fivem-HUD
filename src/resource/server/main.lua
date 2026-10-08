-- Server entry point for bablo-hud

-- ─── Server info ──────────────────────────────────────────────────────────────

RegisterNetEvent("bablo-hud:requestServerInfo")
AddEventHandler("bablo-hud:requestServerInfo", function()
    local playerId = source
    TriggerClientEvent("bablo-hud:receiveServerInfo", playerId, {
        hostname = GetConvar("sv_hostname", "Unknown Server"),
        serverId = playerId,
    })
end)

-- ─── Server ID state bag ──────────────────────────────────────────────────────

function SetPlayerServerIdStateBag(playerId)
    local id = tonumber(playerId)
    if not id or id <= 0 then return end
    local playerState = Player(id)
    if playerState and playerState.state then
        playerState.state:set("bablo_sid", id, true)
    end
end

AddEventHandler("playerJoining", function()
    SetPlayerServerIdStateBag(source)
end)

-- Stamp all already-connected players on startup
CreateThread(function()
    Wait(0)
    for _, playerId in ipairs(GetPlayers()) do
        SetPlayerServerIdStateBag(playerId)
    end
end)

-- Periodic re-stamp (covers edge cases where state bag may have been lost)
CreateThread(function()
    while true do
        Wait(30000)
        for _, playerId in ipairs(GetPlayers()) do
            SetPlayerServerIdStateBag(playerId)
        end
    end
end)

-- ─── Callbacks ───────────────────────────────────────────────────────────────

if lib and lib.callback and lib.callback.register then
    lib.callback.register("bablo-hud:getServerId", function(source)
        SetPlayerServerIdStateBag(source)
        return source
    end)

    lib.callback.register("bablo-hud:getServerTime", function()
        local t = os.date("*t")
        return { h = t.hour, m = t.min, s = t.sec }
    end)
end

-- ─── Framework helper ─────────────────────────────────────────────────────────

local frameworkCore = nil

function GetFrameworkCore()
    if frameworkCore ~= nil then return frameworkCore end

    local fw = Config and Config.Framework

    if fw == "qbcore" or fw == "qbox" then
        local ok, core = pcall(function()
            return exports["qb-core"]:GetCoreObject()
        end)
        if ok and core then frameworkCore = core end

    elseif fw == "esx" then
        local ok, core = pcall(function()
            return exports.es_extended:getSharedObject()
        end)
        if ok and core then frameworkCore = core end
    end

    return frameworkCore
end

-- ─── Stress sync ─────────────────────────────────────────────────────────────

-- pendingStress: playerId → new stress value (to be flushed to framework)
-- syncedStress:  playerId → last value successfully written to framework
local pendingStress = {}
local syncedStress  = {}
local stressFlusherRunning = false

function SetStressOnFramework(playerId, stressValue)
    local fw   = Config and Config.Framework
    local core = GetFrameworkCore()
    if not core then return end

    if fw == "qbcore" or fw == "qbox" then
        local player = core.Functions and core.Functions.GetPlayer and core.Functions.GetPlayer(playerId)
        if player and player.Functions and player.Functions.SetMetaData then
            player.Functions.SetMetaData("stress", stressValue)
        end

    elseif fw == "esx" then
        local player = core.GetPlayerFromId and core.GetPlayerFromId(playerId)
        if not player then return end
        if player.setMeta then
            player.setMeta("stress", stressValue)
        elseif player.set then
            player.set("stress", stressValue)
        end
    end
end

function StartStressFlusher()
    if stressFlusherRunning then return end
    stressFlusherRunning = true

    CreateThread(function()
        while true do
            Wait(10000)
            for playerId, newValue in pairs(pendingStress) do
                pendingStress[playerId] = nil
                if syncedStress[playerId] ~= newValue then
                    syncedStress[playerId] = newValue
                    SetStressOnFramework(playerId, newValue)
                end
            end
        end
    end)
end

RegisterNetEvent("bablo-hud:server:setStress")
AddEventHandler("bablo-hud:server:setStress", function(rawValue)
    if not (Config and Config.Stress and Config.Stress.integrated == true) then return end

    local playerId   = source
    local stressValue = tonumber(rawValue) or 0
    stressValue = math.max(0, math.min(100, stressValue))

    pendingStress[playerId] = stressValue
    StartStressFlusher()
end)

AddEventHandler("playerDropped", function()
    local playerId = source
    local pending  = pendingStress[playerId]
    pendingStress[playerId] = nil

    if pending ~= nil and syncedStress[playerId] ~= pending then
        SetStressOnFramework(playerId, pending)
    end

    syncedStress[playerId] = nil
end)

-- ─── Seatbelt alarm relay ─────────────────────────────────────────────────────

function IsValidNetId(netId)
    return type(netId) == "number" and netId > 0
end

RegisterNetEvent("bablo-hud:server:startSeatbeltAlarm")
AddEventHandler("bablo-hud:server:startSeatbeltAlarm", function(vehicleNetId)
    if not IsValidNetId(vehicleNetId) then return end
    TriggerClientEvent("bablo-hud:client:startSeatbeltAlarm", -1, vehicleNetId)
end)

RegisterNetEvent("bablo-hud:server:stopSeatbeltAlarm")
AddEventHandler("bablo-hud:server:stopSeatbeltAlarm", function(vehicleNetId)
    if not IsValidNetId(vehicleNetId) then return end
    TriggerClientEvent("bablo-hud:client:stopSeatbeltAlarm", -1, vehicleNetId)
end)

RegisterNetEvent("bablo-hud:server:seatbeltSound")
AddEventHandler("bablo-hud:server:seatbeltSound", function(vehicleNetId, soundName)
    if not IsValidNetId(vehicleNetId) then return end
    if soundName ~= "buckle" and soundName ~= "unbuckle" then return end
    TriggerClientEvent("bablo-hud:client:seatbeltSound", -1, vehicleNetId, soundName)
end)
