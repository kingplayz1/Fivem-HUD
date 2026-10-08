-- Shared utility functions for bablo-hud

function IsResourceActive(resourceName)
    local state = GetResourceState(resourceName)
    return state == "started" or state == "starting"
end

function DetectFramework()
    -- Skip if Framework is already set to something other than "auto" or "standalone"
    if Config.Framework and Config.Framework ~= "auto" and Config.Framework ~= "standalone" then return end

    -- If explicitly set to standalone, skip detection and let fallback handle it
    if Config.Framework == "standalone" then
        Config.Framework = nil  -- Will trigger fallback below
        return
    end

    if IsResourceActive("qbx_core") then
        Config.Framework = "qbox"
    elseif IsResourceActive("nd-core") then
        Config.Framework = "nd"
    elseif IsResourceActive("vRP") then
        Config.Framework = "vrp"
    elseif IsResourceActive("qb-core") then
        Config.Framework = "qbcore"
    elseif IsResourceActive("es_extended") then
        Config.Framework = "esx"
    else
        Config.Framework = nil   -- no framework detected
    end
end

DetectFramework()

-- Set up a dummy Framework table if no framework was detected
-- This provides default values so the HUD can run without a specific framework
if Config.Framework == nil then
    Framework = Framework or {}

    -- Default values for when no framework is present
    Framework.getHunger = function(self) return 100 end
    Framework.getThirst = function(self) return 100 end
    Framework.getStress = function(self) return 0 end
    Framework.getJob = function(self) return "unemployed", "0" end
    Framework.getJobName = function(self) return nil end
    Framework.getMoney = function(self) return 0, 0 end
    Framework.getDirtyMoney = function(self) return 0 end
    Framework.getGang = function(self) return false end
    Framework.getPlayerName = function(self) return GetPlayerName(PlayerId()) end
    Framework.getPlayerId = function(self) return GetPlayerServerId(PlayerId()) end
    Framework.getFuel = function(self, vehicle) return GetVehicleFuelLevel(vehicle) end
    Framework.getVehicleMileage = function(self, vehicle, plate) return false end
    Framework.getNitro = function(self) return 0 end
    Framework.notify = function(self, title, description, notificationType, duration)
        -- Simple notification using the game's built-in notification
        SetNotificationTextEntry("STRING")
        AddTextComponentSubstringPlayerName(description or "")
        DrawNotification(false, false)
    end
    Framework.isPlayerLoaded = function(self) return true end
    Framework.isSeatbeltOn = function(self) return false end
    Framework.setStress = function(self, value) end
    Framework.applyEjectionPhysics = function(self, ped, vel)
        SetPedCanRagdoll(ped, true)
        SetPedToRagdoll(ped, 5511, 5511, 0, 0, 0, 0)
        SetEntityVelocity(ped, vel.x * 4, vel.y * 4, vel.z * 4)

        local ejectSpeed = math.ceil(GetEntitySpeed(ped) * 8)
        local hp = GetEntityHealth(ped)
        if hp - ejectSpeed > 0 then
            SetEntityHealth(ped, hp - ejectSpeed)
        elseif hp ~= 0 then
            SetEntityHealth(ped, 0)
        end
    end
    Framework.getCore = function(self) return {} end
end

-- Trigger player loaded event for standalone mode
CreateThread(function()
    Wait(1000)  -- Wait a bit for resources to initialize
    TriggerEvent('bablo-hud:playerLoaded')
end)

-- Handle player unload (though in standalone mode, this might not be perfectly accurate)
AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        TriggerEvent('bablo-hud:playerUnloaded')
    end
end)
