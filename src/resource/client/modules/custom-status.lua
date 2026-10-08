-- ---------------------------------------------------------------------------
-- Custom statuses: configurable HUD status bars driven by fetch functions,
-- events, or direct SetCustomStatus export calls.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Value clamping helpers
-- ---------------------------------------------------------------------------

-- Clamps a value to [0, 100]. Returns nil if not a number.
function ClampStatusValue(raw)
    local n = tonumber(raw)
    if not n then return nil end
    if n < 0   then return 0   end
    if n > 100 then return 100 end
    return n
end

-- Converts an autoHide config value to a hide threshold integer.
--   false / nil  → -1  (never hide)
--   true         →  0  (hide when value is 0)
--   number       →  floor(clamp(0,100))
function ResolveHideThreshold(raw)
    if raw == nil or raw == false then return -1 end
    if raw == true               then return 0  end
    local n = tonumber(raw)
    if not n  then return -1 end
    if n < 0  then return 0  end
    if n > 100 then return 100 end
    return math.floor(n)
end

-- ---------------------------------------------------------------------------
-- BuildStatusDefinitions()
-- Normalises Config.CustomStatuses into a clean list for the NUI.
-- ---------------------------------------------------------------------------
function BuildStatusDefinitions()
    local defs = {}
    if not Config.CustomStatuses then return defs end

    for _, status in ipairs(Config.CustomStatuses) do
        if status.id then
            defs[#defs + 1] = {
                id            = tostring(status.id),
                label         = status.label or tostring(status.id),
                icon          = status.icon,
                image         = status.image,
                color         = status.color or "200 90% 60%",
                order         = tonumber(status.order) or 50,
                hideThreshold = ResolveHideThreshold(status.autoHide),
                default       = ClampStatusValue(status.default) or 0,
            }
        end
    end
    return defs
end

-- ---------------------------------------------------------------------------
-- Per-status state
-- sentValues   – last value acknowledged by NUI (to skip redundant sends)
-- pendingValues – latest value from fetch/event (sent on next NUI request)
-- ---------------------------------------------------------------------------
local sentValues   = {}
local pendingValues = {}

-- Sends a single status value to NUI when it differs from the last sent value.
function SendStatusValue(id, value)
    local key          = tostring(id)
    local clampedValue = (value ~= nil) and ClampStatusValue(value) or nil

    pendingValues[key] = clampedValue

    if sentValues[key] == clampedValue then return end
    sentValues[key] = clampedValue

    SendNUIMessage({
        action = "setCustomStatus",
        data   = { id = key, value = clampedValue },
    })
end

-- Sends the status definition list to NUI
function LoadStatusDefinitions()
    sentValues = {}
    local defs = BuildStatusDefinitions()
    if #defs == 0 then return end
    SendNUIMessage({ action = "loadCustomStatuses", data = defs })
end

-- ---------------------------------------------------------------------------
-- Fetch loop
-- ---------------------------------------------------------------------------
local fetchActive = false

function StartStatusFetchLoop(status)
    local interval = tonumber(status.fetchInterval) or 1000

    CreateThread(function()
        while fetchActive do
            local ok, result = pcall(status.fetch)
            if ok then
                SendStatusValue(status.id, result)
            end
            Citizen.Wait(interval)
        end
    end)
end

function StartAllStatusFetchLoops()
    if not Config.CustomStatuses or #Config.CustomStatuses == 0 then return end
    fetchActive = true
    for _, status in ipairs(Config.CustomStatuses) do
        if status.id and type(status.fetch) == "function" then
            StartStatusFetchLoop(status)
        end
    end
end

function StopAllStatusFetchLoops()
    fetchActive = false
    sentValues  = {}
    if not Config.CustomStatuses then return end
    for _, status in ipairs(Config.CustomStatuses) do
        if status.id then
            SendStatusValue(status.id, ClampStatusValue(status.default) or 0)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Event-driven status updates (Config.CustomStatuses[n].event)
-- Registered once at script load.
-- ---------------------------------------------------------------------------
function RegisterStatusEventHandlers()
    if not Config.CustomStatuses then return end
    for _, status in ipairs(Config.CustomStatuses) do
        if status.id and type(status.event) == "string" and status.event ~= "" then
            local statusId = status.id
            AddEventHandler(status.event, function(value)
                SendStatusValue(statusId, value)
            end)
        end
    end
end

RegisterStatusEventHandlers()

-- ---------------------------------------------------------------------------
-- NUI callback: NUI requests a full resync on mount / reconnect
-- ---------------------------------------------------------------------------
RegisterNUICallback("requestCustomStatuses", function(_, cb)
    LoadStatusDefinitions()
    -- Replay all pending values so NUI is up to date
    for id, value in pairs(pendingValues) do
        SendStatusValue(id, value)
    end
    cb("ok")
end)

-- ---------------------------------------------------------------------------
-- Export
-- ---------------------------------------------------------------------------
exports("SetCustomStatus", function(id, value)
    if id == nil then return end
    SendStatusValue(id, value)
end)

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
AddEventHandler("bablo-hud:playerLoaded", function()
    LoadStatusDefinitions()
    StartAllStatusFetchLoops()
end)

AddEventHandler("bablo-hud:playerUnloaded", function()
    StopAllStatusFetchLoops()
end)
