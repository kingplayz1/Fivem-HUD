-- Stress system for bablo-hud

Stress = {
    current = 0,
    loaded  = false,
    running = false,
}

local activeTickConfig  = nil  -- Current onTick tier being applied
local stressDirty       = false
local lastSyncedStress  = nil
local syncIntervalMs    = 5000

-- ─── Config helpers ──────────────────────────────────────────────────────────

function IsStressIntegrated()
    return Config and Config.Stress and Config.Stress.integrated == true
end

function ClampStress(value)
    local n = tonumber(value) or 0
    local minVal = (Config and Config.Stress and Config.Stress.minimumValue) or 0
    local maxVal = (Config and Config.Stress and Config.Stress.maximumValue) or 100
    if n < minVal then n = minVal end
    if n > maxVal then n = maxVal end
    return n
end

function IsEffectEnabled(effectKey)
    local effects = Config and Config.Stress and Config.Stress.effects
    if not effects then return true end
    return effects[effectKey] ~= false
end

-- Returns the highest-priority onTick tier that matches the given stress level
function GetActiveTier(stressLevel)
    local onTick = Config and Config.Stress and Config.Stress.onTick
    if not onTick then return nil end

    local best = nil
    for _, tier in ipairs(onTick) do
        local minVal = tier.minValue or 0
        if stressLevel >= minVal then
            if not best or minVal > (best.minValue or 0) then
                best = tier
            end
        end
    end
    return best
end

-- ─── Internal setter ─────────────────────────────────────────────────────────

function ApplyStressValue(rawValue)
    Stress.current = ClampStress(rawValue)
    stressDirty    = true

    -- Mirror into framework metadata if available
    if not Framework then return end
    if not Framework.getCore then return end

    local ok, core = pcall(function()
        return Framework.getCore(Framework)
    end)
    if not ok or not core then return end

    pcall(function()
        local playerData
        if core.Functions and core.Functions.GetPlayerData then
            playerData = core.Functions.GetPlayerData()
        elseif core.GetPlayerData then
            playerData = core.GetPlayerData()
        end
        if type(playerData) == "table" then
            playerData.metadata = playerData.metadata or {}
            playerData.metadata.stress = Stress.current
        end
    end)
end

-- ─── Public API (table methods) ──────────────────────────────────────────────

function Stress:Get()
    if IsStressIntegrated() then
        return self.current
    end
    if Framework and Framework.getStress then
        return Framework.getStress(Framework)
    end
    return 0
end

function Stress:Set(value)
    if not IsStressIntegrated() or not self.loaded then return end
    ApplyStressValue(value)
end

function Stress:Add(amount)
    if not IsStressIntegrated() or not self.loaded then return end
    ApplyStressValue(self.current + (tonumber(amount) or 0))
end

function Stress:Remove(amount)
    if not IsStressIntegrated() or not self.loaded then return end
    ApplyStressValue(self.current - (tonumber(amount) or 0))
end

-- ─── Effect application ──────────────────────────────────────────────────────

function ClearActiveTickEffects()
    if not activeTickConfig then return end
    local playerId = PlayerId()

    if activeTickConfig.healthRegenMultiplier then
        SetPlayerHealthRechargeMultiplier(playerId, 1.0)
    end
    if activeTickConfig.weaponDamageMultiplier then
        SetPlayerWeaponDamageModifier(playerId, 1.0)
    end
    activeTickConfig = nil
end

function ApplyTickEffects(tier)
    if not tier then ClearActiveTickEffects() return end
    if activeTickConfig == tier then return end

    if activeTickConfig and activeTickConfig ~= tier then
        ClearActiveTickEffects()
    end

    local playerId = PlayerId()

    if tier.healthRegenMultiplier and IsEffectEnabled("healthRegenMultiplier") then
        SetPlayerHealthRechargeMultiplier(playerId, tier.healthRegenMultiplier + 0.0)
    end
    if tier.weaponDamageMultiplier and IsEffectEnabled("weaponDamageMultiplier") then
        SetPlayerWeaponDamageModifier(playerId, tier.weaponDamageMultiplier + 0.0)
    end

    activeTickConfig = tier
end

-- ─── Steer impairment thread ─────────────────────────────────────────────────

function StartSteerImpairmentThread()
    CreateThread(function()
        local lastActionTime = 0
        while Stress.running do
            Citizen.Wait(100)
            if not activeTickConfig then goto continue end

            local impairment = tonumber(activeTickConfig.steerImpairment) or 0
            if impairment <= 0 then goto continue end
            if not IsEffectEnabled("steerImpairment") then goto continue end

            local ped     = PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) then goto continue end

            local vehicle = GetVehiclePedIsUsing(ped)
            if vehicle == 0 then goto continue end
            if GetPedInVehicleSeat(vehicle, -1) ~= ped then goto continue end

            local speedKmh = GetEntitySpeed(vehicle) * 3.6
            if speedKmh < 20 then goto continue end

            local now       = GetGameTimer()
            local baseDelay = math.max(150, math.floor(1000 - impairment * 2200))
            local jitter    = math.random(-80, 80)
            local interval  = baseDelay + jitter

            if now - lastActionTime >= interval then
                local action = math.random() < 0.5 and 7 or 8
                local duration = math.random(40, math.floor(40 + impairment * 250))
                TaskVehicleTempAction(ped, vehicle, action, duration)
                lastActionTime = now
            end

            ::continue::
        end
    end)
end

-- ─── Instant effects (blur, shake, vehicle swerve) ───────────────────────────

function TriggerInstantEffects(tier)
    if not tier then return end

    if tier.screenBlur and IsEffectEnabled("screenBlur") then
        TransitionToBlurred(100.0)
        Citizen.Wait(120)
        TransitionFromBlurred(500.0)
        Citizen.Wait(100)
        TransitionFromBlurred(0.0)
    end

    if tier.screenShake then
        local intensity = tonumber(tier.screenShake) or 0
        if intensity > 0 and IsEffectEnabled("screenShake") then
            ShakeGameplayCam("MEDIUM_EXPLOSION_SHAKE", intensity)
        end
    end

    if tier.vehicleAction and IsEffectEnabled("vehicleAction") then
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then return end
        local vehicle = GetVehiclePedIsUsing(ped)
        if not vehicle or vehicle == 0 then return end
        if GetPedInVehicleSeat(vehicle, -1) ~= ped then return end
        if GetEntitySpeed(vehicle) * 3.6 <= 30 then return end

        local duration = (type(tier.vehicleAction) == "number" and tier.vehicleAction) or 150
        TaskVehicleTempAction(ped, vehicle, 7, duration)
        Citizen.Wait(500)
        TaskVehicleTempAction(ped, vehicle, 8, duration)
    end
end

-- ─── Sync thread (push stress changes to framework) ──────────────────────────

function StartSyncThread()
    CreateThread(function()
        lastSyncedStress = math.floor(ClampStress(Stress.current) + 0.5)
        stressDirty      = false

        while Stress.running and Stress.loaded do
            Citizen.Wait(syncIntervalMs)
            if not stressDirty then goto continue end

            stressDirty = false
            local rounded = math.floor(ClampStress(Stress.current) + 0.5)

            if rounded ~= lastSyncedStress then
                if Framework and Framework.setStress then
                    lastSyncedStress = rounded
                    Framework.setStress(Framework, Stress.current)
                end
            end

            ::continue::
        end
    end)
end

-- ─── Decay + main tick thread ─────────────────────────────────────────────────

function StartDecayThread()
    CreateThread(function()
        local decayIntervalMs = 60000
        local lastDecayTime   = GetGameTimer()
        Citizen.Wait(decayIntervalMs)

        while Stress.running and Stress.loaded do
            local decayPerMinute = (Config and Config.Stress and Config.Stress.decayPerMinute) or 0
            local now            = GetGameTimer()

            if Stress.current > 0 and decayPerMinute > 0 then
                if now - lastDecayTime >= 60000 then
                    ApplyStressValue(Stress.current - decayPerMinute)
                    lastDecayTime = now
                end
            end

            local waitMs = decayIntervalMs
            local tier   = nil

            if Stress.current > 0 then
                tier = GetActiveTier(Stress.current)
            end

            if tier then
                ApplyTickEffects(tier)
                TriggerInstantEffects(tier)
                if tier.interval then waitMs = tier.interval end
            else
                ClearActiveTickEffects()
            end

            Citizen.Wait(waitMs)
        end
    end)
end

-- ─── Startup ─────────────────────────────────────────────────────────────────

function LoadStressFromFramework()
    if Framework and Framework.getStress then
        local val = Framework.getStress(Framework)
        Stress.current = ClampStress(val)
    end
    Stress.loaded = true
end

function StartStressSystem()
    if Stress.running then return end
    Stress.running = true
    StartSyncThread()
    StartDecayThread()
    StartSteerImpairmentThread()
end

-- ─── Events ──────────────────────────────────────────────────────────────────

AddEventHandler("bablo-hud:playerLoaded", function()
    if not IsStressIntegrated() then
        Stress.loaded = true
        return
    end
    LoadStressFromFramework()
    StartStressSystem()
end)

AddEventHandler("bablo-hud:playerUnloaded", function()
    Stress.running = false
    Stress.loaded  = false
    Stress.current = 0
    ClearActiveTickEffects()
end)

-- ─── Exports ─────────────────────────────────────────────────────────────────

exports("GetStress", function()
    return Stress:Get()
end)

exports("SetStress", function(value)
    Stress:Set(value)
end)

exports("AddStress", function(amount)
    Stress:Add(amount)
end)

exports("RemoveStress", function(amount)
    Stress:Remove(amount)
end)

-- ─── Global reference ────────────────────────────────────────────────────────

Bablo        = Bablo or {}
Bablo.Stress = Stress

-- ─── Debug commands (only registered when debug mode is on) ──────────────────

if IsDebugEnabled() then
    local function DebugPrint(msg)
        TriggerEvent("chat:addMessage", {
            color     = { 255, 120, 120 },
            multiline = true,
            args      = { "[bablo-hud:stress]", msg },
        })
    end

    RegisterCommand("stress", function()
        DebugPrint(("current = %s | integrated = %s | loaded = %s"):format(
            tostring(Stress.current),
            tostring(IsStressIntegrated()),
            tostring(Stress.loaded)
        ))
    end, false)

    RegisterCommand("setstress", function(_, args)
        if not IsStressIntegrated() then
            DebugPrint("integrated mode is OFF — set Config.Stress.integrated = true to use this")
            return
        end
        local val = tonumber(args[1])
        if not val then DebugPrint("usage: /setstress <0-100>") return end
        Stress:Set(val)
        DebugPrint(("set -> %s"):format(tostring(Stress.current)))
    end, false)

    RegisterCommand("addstress", function(_, args)
        if not IsStressIntegrated() then DebugPrint("integrated mode is OFF") return end
        local val = tonumber(args[1]) or 10
        Stress:Add(val)
        DebugPrint(("add %s -> %s"):format(tostring(val), tostring(Stress.current)))
    end, false)

    RegisterCommand("substress", function(_, args)
        if not IsStressIntegrated() then DebugPrint("integrated mode is OFF") return end
        local val = tonumber(args[1]) or 10
        Stress:Remove(val)
        DebugPrint(("remove %s -> %s"):format(tostring(val), tostring(Stress.current)))
    end, false)

    RegisterCommand("maxstress", function()
        if not IsStressIntegrated() then DebugPrint("integrated mode is OFF") return end
        Stress:Set(100)
        DebugPrint("set -> 100 (worst tier should fire on the next thread tick)")
    end, false)

    RegisterCommand("clearstress", function()
        if not IsStressIntegrated() then DebugPrint("integrated mode is OFF") return end
        Stress:Set(0)
        DebugPrint("cleared -> 0")
    end, false)

    RegisterCommand("stresstier", function(_, args)
        if not IsStressIntegrated() then DebugPrint("integrated mode is OFF") return end
        local val = tonumber(args[1]) or 50
        Stress:Set(val)
        local tier = GetActiveTier(Stress.current)
        if tier then
            DebugPrint(("jumped to %s — applying tier minValue=%s now"):format(
                tostring(val), tostring(tier.minValue)))
            TriggerInstantEffects(tier)
        else
            DebugPrint(("jumped to %s — no tier matches at this level"):format(tostring(val)))
        end
    end, false)

    RegisterCommand("stressmode", function()
        local tierCount = (Config and Config.Stress and Config.Stress.onTick and #Config.Stress.onTick) or 0
        DebugPrint(("integrated = %s | decay/min = %s | tiers = %s"):format(
            tostring(IsStressIntegrated()),
            tostring(Config and Config.Stress and Config.Stress.decayPerMinute),
            tostring(tierCount)
        ))
    end, false)
end
