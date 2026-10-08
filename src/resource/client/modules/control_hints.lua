local NUI_ACTIONS = (BabloHud and BabloHud.Constants and BabloHud.Constants.NUI_ACTIONS) or {}

-- Map of hint id → generation counter (used to cancel auto-hide if the hint was replaced)
local activeHints    = {}
local hintGeneration = 0

-- Returns true when Config is absent (hints fall back to no-op in that case)
function IsControlHintsDisabled()
    return not Config
end

-- Returns true when a value is a table
function IsTable(value)
    return type(value) == "table"
end

-- ---------------------------------------------------------------------------
-- ShowSingleHint(id, label, key, duration)
-- Sends a controlHint:show message. If duration > 0 starts an auto-hide timer.
-- Returns false on invalid input.
-- ---------------------------------------------------------------------------
function ShowSingleHint(id, label, key, duration)
    if IsControlHintsDisabled() then return false end
    if type(id) ~= "string" or id == "" then return false end
    if type(label) ~= "string" or type(key) ~= "string" then return false end

    hintGeneration = hintGeneration + 1
    local generation = hintGeneration
    activeHints[id]  = generation

    SendNUIMessage({
        action = NUI_ACTIONS.CONTROL_HINT_SHOW or "controlHint:show",
        data   = { id = id, label = label, key = key },
    })

    duration = tonumber(duration)
    if duration and duration > 0 then
        CreateThread(function()
            Wait(math.floor(duration))
            -- Only hide if this hint hasn't been replaced since
            if activeHints[id] == generation then
                activeHints[id] = nil
                SendNUIMessage({
                    action = NUI_ACTIONS.CONTROL_HINT_HIDE or "controlHint:hide",
                    data   = { id = id },
                })
            end
        end)
    end

    return true
end

-- ---------------------------------------------------------------------------
-- HideSingleHint(id)
-- ---------------------------------------------------------------------------
function HideSingleHint(id)
    if type(id) ~= "string" or id == "" then return false end
    activeHints[id] = nil
    SendNUIMessage({
        action = NUI_ACTIONS.CONTROL_HINT_HIDE or "controlHint:hide",
        data   = { id = id },
    })
    return true
end

-- ---------------------------------------------------------------------------
-- ClearAllHints()
-- ---------------------------------------------------------------------------
function ClearAllHints()
    activeHints = {}
    SendNUIMessage({ action = NUI_ACTIONS.CONTROL_HINT_CLEAR or "controlHint:clear" })
    return true
end

-- ---------------------------------------------------------------------------
-- ShowControlHint(idOrTable, label, key, duration)
-- Accepts a single hint (string id) or a table / array of hint tables.
-- ---------------------------------------------------------------------------
function ShowControlHint(idOrTable, label, key, duration)
    if type(idOrTable) == "string" then
        return ShowSingleHint(idOrTable, label, key, duration)
    end

    if type(idOrTable) ~= "table" then return false end

    local defaultDuration = tonumber(label)  -- second arg used as default duration for arrays

    -- Single hint object: { id, label, key, duration }
    if IsTable(idOrTable) and idOrTable.id then
        return ShowSingleHint(
            idOrTable.id,
            idOrTable.label,
            idOrTable.key,
            idOrTable.duration or defaultDuration
        )
    end

    -- Array of hint objects
    local allOk = true
    for _, hint in ipairs(idOrTable) do
        if IsTable(hint) then
            local ok = ShowSingleHint(
                hint.id,
                hint.label,
                hint.key,
                hint.duration or defaultDuration
            )
            if not ok then allOk = false end
        end
    end
    return allOk
end

-- ---------------------------------------------------------------------------
-- HideControlHint(idOrTable)
-- Accepts a string id, a hint object, or an array of either.
-- ---------------------------------------------------------------------------
function HideControlHint(idOrTable)
    if type(idOrTable) == "string" then
        return HideSingleHint(idOrTable)
    end

    if type(idOrTable) ~= "table" then return false end

    if IsTable(idOrTable) and idOrTable.id then
        return HideSingleHint(idOrTable.id)
    end

    for _, entry in ipairs(idOrTable) do
        if type(entry) == "string" then
            HideSingleHint(entry)
        elseif IsTable(entry) and entry.id then
            HideSingleHint(entry.id)
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------
exports("ShowControlHint",  ShowControlHint)
exports("ShowControlHints", ShowControlHint)
exports("HideControlHint",  HideControlHint)
exports("HideControlHints", HideControlHint)
exports("ClearControlHints", ClearAllHints)

-- ---------------------------------------------------------------------------
-- Net events (server-side triggers)
-- ---------------------------------------------------------------------------
RegisterNetEvent("bablo-hud:controlhint:show")
AddEventHandler("bablo-hud:controlhint:show", function(id, label, key, duration)
    ShowControlHint(id, label, key, duration)
end)

RegisterNetEvent("bablo-hud:controlhint:hide")
AddEventHandler("bablo-hud:controlhint:hide", function(idOrTable)
    HideControlHint(idOrTable)
end)

RegisterNetEvent("bablo-hud:controlhint:clear")
AddEventHandler("bablo-hud:controlhint:clear", function()
    ClearAllHints()
end)
