-- Server-side framework bindings for bablo-hud (QBCore)

Framework = Framework or {}

-- QBCore: populate Framework.isAdmin
CreateThread(function()
    if Config.Framework ~= "qbcore" then return end

    local qbExports = exports["qb-core"]
    local QBCore = qbExports:GetCoreObject()

    Framework.isAdmin = function(_, playerId)
        local id = tonumber(playerId)
        if not id then return false end

        -- Check QBCore permission groups
        if QBCore and QBCore.Functions and QBCore.Functions.HasPermission then
            if QBCore.Functions.HasPermission(id, "admin")
            or QBCore.Functions.HasPermission(id, "god") then
                return true
            end
        end

        -- Fall back to ace permission
        return IsPlayerAceAllowed(id, "command") == true
    end
end)