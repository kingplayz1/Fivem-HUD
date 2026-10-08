-- Server-side framework bindings for bablo-hud

Framework = Framework or {}

-- ESX: populate Framework.isAdmin
CreateThread(function()
    if Config.Framework ~= "esx" then return end

    local esxExports = exports.es_extended
    local ESX = esxExports:getSharedObject()

    Framework.isAdmin = function(_, playerId)
        local id = tonumber(playerId)
        if not id then return false end

        -- Check ESX group first
        if ESX and ESX.GetPlayerFromId then
            local player = ESX.GetPlayerFromId(id)
            if player and player.getGroup then
                local group = player.getGroup()
                if group == "admin" or group == "superadmin" or group == "god" then
                    return true
                end
            end
        end

        -- Fall back to ace permission
        return IsPlayerAceAllowed(id, "command") == true
    end
end)