local NUI_ACTIONS = (BabloHud and BabloHud.Constants and BabloHud.Constants.NUI_ACTIONS) or {}

-- ---------------------------------------------------------------------------
-- Active bar state (nil when no bar is running)
-- ---------------------------------------------------------------------------
local currentBar = nil   -- { active, canCancel, manual, completed }

-- ---------------------------------------------------------------------------
-- Cancel keybind: "bablohud:cancelProgress" / default key X
-- Only cancels when the current bar has canCancel = true.
-- ---------------------------------------------------------------------------
RegisterCommand("bablohud:cancelProgress", function()
    if currentBar and currentBar.canCancel then
        currentBar.active = false
    end
end, false)

RegisterKeyMapping("bablohud:cancelProgress", "Cancel progress bar", "keyboard", "x")

-- ---------------------------------------------------------------------------
-- NUI helpers
-- ---------------------------------------------------------------------------

function SendProgressStart(data)
    SendNUIMessage({
        action = NUI_ACTIONS.PROGRESS_START or "progressBar:start",
        data   = data,
    })
end

function SendProgressStop()
    SendNUIMessage({ action = NUI_ACTIONS.PROGRESS_STOP or "progressBar:stop" })
end

function SendProgressUpdate(value, label)
    SendNUIMessage({
        action = NUI_ACTIONS.PROGRESS_UPDATE or "progressBar:update",
        data   = { value = value, label = label },
    })
end

-- ---------------------------------------------------------------------------
-- SpawnProp(ped, propConfig)
-- Loads a model, creates an object, attaches it to a ped bone, and releases
-- the model. Returns the entity handle, or nil on failure / timeout (5 s).
-- propConfig fields: model, bone (default 60309), coords {x,y,z}, rotation {x,y,z}
-- ---------------------------------------------------------------------------
function SpawnProp(ped, propConfig)
    if not propConfig or not propConfig.model then return nil end

    local modelHash = GetHashKey(propConfig.model)
    RequestModel(modelHash)

    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(modelHash) do
        if GetGameTimer() > deadline then return nil end
        Citizen.Wait(0)
    end

    local pos    = GetEntityCoords(ped)
    local prop   = CreateObject(modelHash, pos.x, pos.y, pos.z, true, true, false)
    local bone   = GetPedBoneIndex(ped, propConfig.bone or 60309)

    local coords   = propConfig.coords   or {}
    local rotation = propConfig.rotation or {}

    AttachEntityToEntity(
        prop, ped, bone,
        coords.x   or 0.0, coords.y   or 0.0, coords.z   or 0.0,
        rotation.x or 0.0, rotation.y or 0.0, rotation.z or 0.0,
        true, true, false, true, 1, true
    )

    SetModelAsNoLongerNeeded(modelHash)
    return prop
end

-- ---------------------------------------------------------------------------
-- PlayAnimation(ped, animConfig)
-- Plays a bablo-animations animation or a raw anim dict/clip.
-- animConfig fields: babloAnim | { animDict, anim, flags }
-- ---------------------------------------------------------------------------
function PlayAnimation(ped, animConfig)
    if not animConfig then return end

    if animConfig.babloAnim then
        if GetResourceState("bablo-animations") == "started" then
            pcall(function()
                exports["bablo-animations"]:playAnimation(ped, animConfig.babloAnim)
            end)
        else
            print("[bablo-hud] bablo-animations is not started — babloAnim will not play")
        end
        return
    end

    if not (animConfig.animDict and animConfig.anim) then return end

    RequestAnimDict(animConfig.animDict)
    local deadline = GetGameTimer() + 5000
    while not HasAnimDictLoaded(animConfig.animDict) do
        if GetGameTimer() > deadline then return end
        Citizen.Wait(0)
    end

    TaskPlayAnim(
        ped,
        animConfig.animDict,
        animConfig.anim,
        8.0, -8.0, -1,
        animConfig.flags or 1,
        0, false, false, false
    )
    RemoveAnimDict(animConfig.animDict)
end

-- ---------------------------------------------------------------------------
-- StopAnimation(ped, animConfig)
-- Cancels a bablo-animations animation or clears ped tasks.
-- ---------------------------------------------------------------------------
function StopAnimation(ped, animConfig)
    if not animConfig then return end

    if animConfig.babloAnim then
        if GetResourceState("bablo-animations") == "started" then
            pcall(function()
                exports["bablo-animations"]:cancelAnimation()
            end)
        end
        return
    end

    if animConfig.animDict and animConfig.anim then
        ClearPedTasks(ped)
    end
end

-- ---------------------------------------------------------------------------
-- ApplyControlDisables(controlDisables)
-- Disables GTA control groups every frame while the bar is active.
-- controlDisables fields (all boolean): disableMovement, disableCarMovement,
--   disableMouse, disableCombat
-- ---------------------------------------------------------------------------
function ApplyControlDisables(controlDisables)
    if not controlDisables then return end

    if controlDisables.disableMovement then
        DisableControlAction(0, 30, true)   -- move left/right
        DisableControlAction(0, 31, true)   -- move up/down
        DisableControlAction(0, 21, true)   -- sprint
        DisableControlAction(0, 22, true)   -- jump
        DisableControlAction(0, 44, true)   -- cover
        DisableControlAction(0, 36, true)   -- duck
    end

    if controlDisables.disableCarMovement then
        DisableControlAction(27, 59, true)  -- accelerate
        DisableControlAction(27, 60, true)  -- brake/reverse
        DisableControlAction(27, 71, true)  -- steer left
        DisableControlAction(27, 72, true)  -- steer right
    end

    if controlDisables.disableMouse then
        DisableControlAction(0, 1, true)    -- look left/right
        DisableControlAction(0, 2, true)    -- look up/down
    end

    if controlDisables.disableCombat then
        DisableControlAction(0, 24, true)   -- attack
        DisableControlAction(0, 25, true)   -- aim
        DisableControlAction(0, 37, true)   -- select weapon
        DisableControlAction(0, 47, true)   -- detonate
        DisableControlAction(0, 58, true)   -- sniper zoom
    end
end

-- ---------------------------------------------------------------------------
-- ProgressBar(options, callback)
-- Main entry point. Starts a progress bar, running the loop until:
--   • duration elapsed (non-manual mode), or
--   • bar.active set to false (cancel / stop), or
--   • player dies (unless useWhileDead = true), or
--   • manual mode bar.completed = true (via UpdateProgressBar reaching 100)
--
-- options fields:
--   duration      number  ms (required unless manual = true)
--   manual        bool    bar is driven by UpdateProgressBar calls
--   canCancel     bool    allow cancel via keybind
--   label         string  bar label (default "Processing...")
--   color         string  bar colour
--   control       string  cancel key hint (default "X" when canCancel)
--   animation     table   { babloAnim | animDict + anim + flags }
--   prop_left     table   prop config for left hand
--   prop_right    table   prop config for right hand
--   controlDisables table { disableMovement, disableCarMovement, disableMouse, disableCombat }
--   useWhileDead  bool    don't cancel bar on player death
--
-- callback(cancelled) called when the bar ends (cancelled = true if not completed)
-- ---------------------------------------------------------------------------
function ProgressBar(options, callback)
    if not options then
        error("[bablo-hud] ProgressBar export requires a data table")
        return
    end

    local isManual = options.manual == true
    if not isManual and not options.duration then
        error("[bablo-hud] ProgressBar export requires 'duration' (or manual = true)")
        return
    end

    -- Cancel any existing bar before starting a new one
    if currentBar then currentBar.active = false end

    local canCancel = options.canCancel ~= false

    SendProgressStart({
        duration = isManual and 0 or options.duration,
        manual   = isManual,
        label    = options.label or "Processing...",
        color    = options.color,
        control  = options.control or (canCancel and "X" or nil),
    })

    local bar = {
        active    = true,
        canCancel = canCancel,
        manual    = isManual,
        completed = false,
    }
    currentBar = bar

    Citizen.CreateThread(function()
        local ped       = PlayerPedId()
        local startTime = GetGameTimer()
        local props     = {}

        PlayAnimation(ped, options.animation)

        if options.prop_left  then props[1] = SpawnProp(ped, options.prop_left)  end
        if options.prop_right then props[2] = SpawnProp(ped, options.prop_right) end

        while bar.active do
            local elapsed = GetGameTimer() - startTime

            -- Time-based completion (non-manual only)
            if not isManual and elapsed >= options.duration then break end

            ApplyControlDisables(options.controlDisables)

            -- Cancel on death (unless useWhileDead)
            if not options.useWhileDead and IsEntityDead(PlayerPedId()) then
                bar.active = false
                break
            end

            Citizen.Wait(0)
        end

        -- Determine whether the bar was cancelled or completed
        local elapsed   = GetGameTimer() - startTime
        local cancelled = isManual and not bar.completed
                       or (not isManual and elapsed < options.duration)

        -- Clean up props
        for _, prop in ipairs(props) do
            if prop and DoesEntityExist(prop) then
                DeleteObject(prop)
            end
        end

        StopAnimation(PlayerPedId(), options.animation)

        -- Send stop message when cancelled or in manual mode
        if cancelled or isManual then
            SendProgressStop()
        end

        -- Clear the global bar reference if it's still ours
        if currentBar == bar then currentBar = nil end

        if callback then callback(cancelled) end
    end)
end

-- ---------------------------------------------------------------------------
-- UpdateProgressBar(valueOrTable, label)
-- Updates a running manual bar's value and/or label.
-- Accepts: number, or table { value/progress/percent, label }
-- Returns false when no bar is active.
-- Auto-completes the bar when value reaches 100 in manual mode.
-- ---------------------------------------------------------------------------
function UpdateProgressBar(valueOrTable, label)
    if not currentBar then return false end

    local value, newLabel

    if type(valueOrTable) == "table" then
        value    = tonumber(valueOrTable.value or valueOrTable.progress or valueOrTable.percent)
        newLabel = valueOrTable.label
    else
        value    = tonumber(valueOrTable)
        newLabel = label
    end

    if value == nil and newLabel == nil then return false end

    if value ~= nil then
        value = math.max(0, math.min(100, value))
    end

    SendProgressUpdate(value, newLabel)

    -- Auto-complete manual bar when it reaches 100
    if value ~= nil and value >= 100 and currentBar.manual then
        currentBar.completed = true
        currentBar.active    = false
    end

    return true
end

-- ---------------------------------------------------------------------------
-- CompleteProgressBar()
-- Immediately completes a manual bar at 100% and ends it.
-- ---------------------------------------------------------------------------
function CompleteProgressBar()
    if not currentBar then return false end
    SendProgressUpdate(100, nil)
    currentBar.completed = true
    currentBar.active    = false
    return true
end

-- ---------------------------------------------------------------------------
-- StopProgressBar()
-- Force-stops any active bar immediately.
-- ---------------------------------------------------------------------------
function StopProgressBar()
    if currentBar then currentBar.active = false end
    SendProgressStop()
end

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------
exports("ProgressBar",        ProgressBar)
exports("UpdateProgressBar",  UpdateProgressBar)
exports("CompleteProgressBar", CompleteProgressBar)
exports("StopProgressBar",    StopProgressBar)

-- ---------------------------------------------------------------------------
-- Net events (server-side triggers)
-- ---------------------------------------------------------------------------
RegisterNetEvent("bablo-hud:progressbar:start")
AddEventHandler("bablo-hud:progressbar:start", function(duration, label, color, control)
    SendProgressStart({
        duration = duration,
        label    = label,
        color    = color,
        control  = control,
    })
end)

RegisterNetEvent("bablo-hud:progressbar:stop")
AddEventHandler("bablo-hud:progressbar:stop", function()
    SendProgressStop()
end)

RegisterNetEvent("bablo-hud:progressbar:update")
AddEventHandler("bablo-hud:progressbar:update", function(valueOrTable, label)
    UpdateProgressBar(valueOrTable, label)
end)

RegisterNetEvent("bablo-hud:progressbar:complete")
AddEventHandler("bablo-hud:progressbar:complete", function()
    CompleteProgressBar()
end)