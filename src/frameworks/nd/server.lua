-- Server-side framework bindings for bablo-hud (NDCore)

Framework = Framework or {}

-- NDCore: populate Framework.isAdmin
CreateThread(function()
    if Config.Framework ~= "nd" then return end

    local ndExports = exports["nd-core"]
    local NDCore

    -- Check if nd-core is available and get its module
    if type(ndExports) == "table" and type(ndExports.getModule) == "function" then
        NDCore = ndExports:getModule('NDCore')
    end

    Framework.isAdmin = function(_, playerId)
        local id = tonumber(playerId)
        if not id then return false end

        -- Check if NDCore has a permission function
        if NDCore and NDCore.Functions and NDCore.Functions.HasPermission then
            if NDCore.Functions.HasPermission(id, "admin")
            or NDCore.Functions.HasPermission(id, "god") then
                return true
            end
        end

        -- Fall back to ace permission
        return IsPlayerAceAllowed(id, "command") == true
    end
end)