-- Global config manager for bablo-hud (server-side)

local resourceName  = GetCurrentResourceName()
local globalConfig  = {}  -- In-memory config table (loaded from JSON file)

-- ─── Config helpers ───────────────────────────────────────────────────────────

function GetConfigFilename()
    local gc = Config and Config.GlobalConfig
    return (gc and gc.filename) or "global-config.json"
end

function IsGlobalConfigEnabled()
    local gc = Config and Config.GlobalConfig
    return gc and gc.enabled == true
end

function IsGlobalConfigEditAllowed()
    local gc = Config and Config.GlobalConfig
    return gc and gc.allowEdit == true
end

-- ─── File I/O ─────────────────────────────────────────────────────────────────

function LoadGlobalConfig()
    local filename = GetConfigFilename()
    local raw      = LoadResourceFile(resourceName, filename)

    if not raw or raw == "" then
        globalConfig = {}
        return
    end

    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == "table" then
        globalConfig = decoded
    else
        globalConfig = {}
    end
end

function SaveGlobalConfig()
    local filename = GetConfigFilename()
    local encoded  = json.encode(globalConfig) or "{}"
    return SaveResourceFile(resourceName, filename, encoded, -1)
end

-- ─── Push helpers ─────────────────────────────────────────────────────────────

-- Push config state to a single player
function PushGlobalConfigToPlayer(playerId)
    local isAdmin = false
    if IsGlobalConfigEnabled() and Framework and Framework.isAdmin then
        isAdmin = Framework.isAdmin(Framework, playerId) == true
    end

    TriggerClientEvent("bablo-hud:globalConfig:push", playerId, {
        enabled   = IsGlobalConfigEnabled(),
        config    = globalConfig,
        isAdmin   = isAdmin,
        allowEdit = IsGlobalConfigEditAllowed(),
    })
end

-- Broadcast config state to all players
function BroadcastGlobalConfig()
    TriggerClientEvent("bablo-hud:globalConfig:broadcast", -1, {
        enabled   = IsGlobalConfigEnabled(),
        config    = globalConfig,
        allowEdit = IsGlobalConfigEditAllowed(),
    })
end

-- ─── Events ──────────────────────────────────────────────────────────────────

AddEventHandler("onResourceStart", function(startedResource)
    if startedResource ~= resourceName then return end
    LoadGlobalConfig()
end)

RegisterNetEvent("bablo-hud:globalConfig:request")
AddEventHandler("bablo-hud:globalConfig:request", function()
    PushGlobalConfigToPlayer(source)
end)

RegisterNetEvent("bablo-hud:globalConfig:publish")
AddEventHandler("bablo-hud:globalConfig:publish", function(newData)
    local playerId = source

    if not IsGlobalConfigEnabled() then return end

    -- Verify admin
    if not (Framework and Framework.isAdmin and Framework.isAdmin(Framework, playerId)) then
        return
    end

    if type(newData) ~= "table" then return end

    -- Merge or replace the stored config
    if type(globalConfig) == "table" then
        for k, v in pairs(newData) do
            globalConfig[k] = v
        end
    else
        globalConfig = newData
    end

    SaveGlobalConfig()
    BroadcastGlobalConfig()
end)
