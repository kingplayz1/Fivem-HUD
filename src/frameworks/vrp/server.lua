-- Server-side framework bindings for bablo-hud (vRP)

Framework = Framework or {}

-- vRP: populate Framework.isAdmin
CreateThread(function()
    if Config.Framework ~= "vrp" then return end

    local vRP = exports['vRP']

    Framework.isAdmin = function(_, playerId)
        local id = tonumber(playerId)
        if not id then return false end

        -- Check if vRP has a way to check admin permissions
        -- This varies by vRP version, but common approaches:
        if vRP and vRP.hasGroup and vRP.hasPermission then
            local user_id = vRP.getUserId({id})
            if user_id then
                -- Check if user is in admin group or has god permission
                if vRP.hasGroup({user_id, "admin"}) or vRP.hasGroup({user_id, "god"}) or
                   vRP.hasPermission({user_id, "admin.command"}) or vRP.hasPermission({user_id, "god.command"}) then
                    return true
                end
            end
        end

        -- Fall back to ace permission
        return IsPlayerAceAllowed(id, "command") == true
    end
end)