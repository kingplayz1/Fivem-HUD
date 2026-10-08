-- Settings system for bablo-hud

local constants    = (BabloHud and BabloHud.Constants) or {}
local kvpKeys      = constants.KVP     or {}
local nuiActions   = constants.NUI_ACTIONS or {}
local settingsKey  = kvpKeys.SETTINGS or "bablo_hud_settings"

-- Minimap / map state
local minimapState = {
    showMapOnFoot    = true,
    minimapTransition = true,
    mapStyle         = "square",
}

-- Global config mode state
local globalConfigActive = false
local globalConfigData   = nil
local isAdmin            = false
local canEditGlobal      = false

-- Per-player reset-in-progress guard
local resetInProgress = false

-- Ticker registration handle (set when player is loaded)
local tickerHandle = nil

-- Last known radar visibility state
local lastRadarState = nil

-- Component enabled flags (populated by LoadSettings)
local componentEnabled = {}

-- ─── BabloHud.GlobalConfig API ───────────────────────────────────────────────

_G.BabloHud       = _G.BabloHud or {}
BabloHud.GlobalConfig = {
    isGated  = function() return globalConfigActive and not isAdmin end,
    isModeOn = function() return globalConfigActive end,
    isAdmin  = function() return isAdmin end,
    canEdit  = function() return globalConfigActive and canEditGlobal end,
}

BabloHud.Settings = BabloHud.Settings or {}
BabloHud.Settings.isComponentEnabled = function(name)
    return componentEnabled[name]
end

-- ─── Helpers ─────────────────────────────────────────────────────────────────

-- Safe deep-read of Config.DefaultSettings.<section>.<field>
local function cfgDefault(section, field)
    local ds = Config and Config.DefaultSettings
    if not ds then return nil end
    local sec = ds[section]
    if not sec then return nil end
    return field and sec[field] or sec
end

-- Resolve NUI action name with fallback
local function nuiAction(key, fallback)
    return nuiActions[key] or fallback
end

-- ─── Build default settings from Config.DefaultSettings ──────────────────────

local STATUS_ORDER = { health=1, hunger=2, thirst=3, armor=4, stress=5, stamina=6, oxygen=7, nitro=8 }
local STATUS_TYPES = { "health", "hunger", "thirst", "armor", "stress", "stamina", "oxygen", "nitro" }

function BuildDefaultSettings()
    local ds = Config and Config.DefaultSettings
    if not ds then return {} end

    local out = {}

    -- Minimap
    if ds.minimap then
        out.showMapOnFoot  = ds.minimap.showOnFoot
        out.mapStyle       = ds.minimap.style
        out.minimapSize    = ds.minimap.size
    end

    -- Status bars
    if ds.status then
        out.design = ds.status.design

        local hasColors     = ds.status.colors     ~= nil
        local hasVisibility = ds.status.visibility ~= nil
        local hasAutoHide   = ds.status.autoHide   ~= nil

        if hasColors or hasVisibility or hasAutoHide then
            out.statuses = {}
            for _, statusType in ipairs(STATUS_TYPES) do
                local visible = true
                if ds.status.visibility and ds.status.visibility[statusType] == false then
                    visible = false
                end

                local hideThreshold = 0
                local autoHideVal = ds.status.autoHide and ds.status.autoHide[statusType]
                if autoHideVal ~= nil then
                    if autoHideVal == false then
                        hideThreshold = -1
                    elseif type(autoHideVal) == "number" and autoHideVal >= 1 then
                        hideThreshold = math.floor(math.max(1, math.min(100, autoHideVal)))
                    end
                end

                local color = ds.status.colors and ds.status.colors[statusType] or nil

                out.statuses[statusType] = {
                    type          = statusType,
                    visible       = visible,
                    hideThreshold = hideThreshold,
                    order         = STATUS_ORDER[statusType],
                    color         = color,
                }
            end
        end
    end

    -- Notifications
    if ds.notification then
        out.notificationStyle  = ds.notification.style
        out.notificationTheme  = ds.notification.theme
        out.notificationSound  = ds.notification.sound
        out.notificationVolume = ds.notification.volume
        out.notificationOpacity = ds.notification.opacity
    end

    -- Voice
    if ds.voice then
        local loc = ds.voice.location
        if loc == "standalone" or loc == "status" then
            out.voiceLocation = loc
        end
        if type(ds.voice.color) == "string" and ds.voice.color ~= "" then
            out.voiceColor = ds.voice.color
        end
    end

    -- Player info
    if ds.playerInfo then
        local pi = ds.playerInfo
        out.playerInfoEnabled       = pi.enabled
        out.playerInfoOpacity       = pi.opacity
        out.playerInfoShowJob       = pi.showJob
        out.playerInfoShowId        = pi.showId
        out.playerInfoShowTime      = pi.showTime
        out.playerInfoShowBank      = pi.showBank
        out.playerInfoShowCash      = pi.showCash
        out.playerInfoShowDirtyMoney = pi.showDirtyMoney
        out.playerInfoShowGang      = pi.showGang
        out.playerInfoShowWeapon    = pi.showWeapon
        if pi.colors then
            out.playerInfoElementColors = pi.colors
        end
    end

    -- Compass
    if ds.compass then
        local c = ds.compass
        out.compassEnabled       = c.enabled
        out.compassShowOnFoot    = c.showOnFoot
        out.compassStyle         = c.style
        out.compassOpacity       = c.opacity
        out.compassShowDirection = c.showDirection
        out.compassShowStreet    = c.showStreet
        out.compassShowZone      = c.showZone
    end

    return out
end

-- ─── Build locked-fields table from Config.DefaultSettings ───────────────────

function BuildLockedFields()
    local ds = Config and Config.DefaultSettings
    if not ds then return {} end

    local out = {}

    local sections = { "minimap", "status", "notification", "playerInfo", "compass", "progressBar", "speedometer" }
    for _, sec in ipairs(sections) do
        if ds[sec] and ds[sec].locked then
            out[sec] = true
        end
        if ds[sec] and ds[sec].lockedPosition then
            out[sec .. "Position"] = true
        end
    end

    -- Component enabled overrides
    out.components = {}
    local componentSections = { "status", "notification", "playerInfo", "progressBar", "speedometer", "compass" }
    for _, sec in ipairs(componentSections) do
        if ds[sec] and ds[sec].enabled == false then
            out.components[sec] = false
        end
    end

    return out
end

-- ─── Merge settings, respecting server locks ─────────────────────────────────

local LOCKED_MINIMAP_KEYS       = { showMapOnFoot=true, mapStyle=true, minimapSize=true }
local LOCKED_STATUS_KEYS        = { design=true, statuses=true, containerPosition=true }
local LOCKED_NOTIFICATION_KEYS  = { notificationStyle=true, notificationTheme=true, notificationSound=true, notificationVolume=true, notificationOpacity=true }
local LOCKED_PLAYER_INFO_KEYS   = { playerInfoEnabled=true, playerInfoOpacity=true, playerInfoAccentColor=true, playerInfoShowJob=true, playerInfoShowId=true, playerInfoShowTime=true, playerInfoShowBank=true, playerInfoShowCash=true, playerInfoShowDirtyMoney=true, playerInfoShowGang=true, playerInfoShowWeapon=true }
local LOCKED_COMPASS_KEYS       = { compassEnabled=true, compassShowOnFoot=true, compassStyle=true, compassOpacity=true, compassShowDirection=true, compassShowStreet=true, compassShowZone=true }

function MergeSettings(base, overrides, locks)
    if not overrides then return base end

    local result = {}
    for k, v in pairs(base) do result[k] = v end

    for k, v in pairs(overrides) do
        local blocked = false
        if locks then
            if locks.minimap       and LOCKED_MINIMAP_KEYS[k]       then blocked = true
            elseif locks.status    and LOCKED_STATUS_KEYS[k]        then blocked = true
            elseif locks.notification and LOCKED_NOTIFICATION_KEYS[k] then blocked = true
            elseif locks.playerInfo and LOCKED_PLAYER_INFO_KEYS[k]  then blocked = true
            elseif locks.compass   and LOCKED_COMPASS_KEYS[k]       then blocked = true
            end
        end
        if not blocked then
            result[k] = v
        end
    end

    return result
end

-- ─── Load and apply all settings ─────────────────────────────────────────────

function LoadSettings()
    local kvpKey = BabloHud.GetKvpKey(settingsKey)

    local defaultSettings = BuildDefaultSettings()
    local locks           = BuildLockedFields()

    -- Resolve saved settings (KVP or global config data)
    local savedSettings = nil
    if globalConfigActive then
        savedSettings = globalConfigData
    else
        local raw = GetResourceKvpString(kvpKey)
        if raw and raw ~= "" then
            savedSettings = json.decode(raw)
        end
    end

    local effectiveLocks = globalConfigActive and {} or locks

    local merged = MergeSettings(defaultSettings, savedSettings, effectiveLocks)

    -- Fix status hideThreshold when locked to default server values
    local statusCfg = cfgDefault("status")
    if locks.status and merged.statuses then
        for statusType, statusData in pairs(merged.statuses) do
            if type(statusData) == "table" then
                local autoHide = statusCfg and statusCfg.autoHide and statusCfg.autoHide[statusType]
                local locked   = (autoHide == nil) or (autoHide == true)
                statusData.hideThreshold = locked and 0 or -1
            end
        end
    end

    -- Apply component enables
    local dsComponents = (Config and Config.DefaultSettings) or {}
    componentEnabled.playerInfo    = merged.playerInfoEnabled ~= false
    componentEnabled.compass       = merged.compassEnabled ~= false
    componentEnabled.status        = not (dsComponents.status and dsComponents.status.enabled == false)
    componentEnabled.speedometer   = not (dsComponents.speedometer and dsComponents.speedometer.enabled == false)
    componentEnabled.progressBar   = not (dsComponents.progressBar and dsComponents.progressBar.enabled == false)
    componentEnabled.notifications = not (dsComponents.notification and dsComponents.notification.enabled == false)

    -- Apply minimap state
    if merged.showMapOnFoot ~= nil then
        minimapState.showMapOnFoot = merged.showMapOnFoot
    end
    if merged.minimapTransition ~= nil then
        minimapState.minimapTransition = merged.minimapTransition
    end
    if merged.mapStyle ~= nil then
        minimapState.mapStyle = merged.mapStyle
    end

    _G.BabloHudMapStyle = minimapState.mapStyle or "square"

    -- Apply minimap size
    if merged.minimapSize ~= nil then
        local sizeNum = tonumber(merged.minimapSize) or 1.0
        _G.BabloHudMinimapSize = sizeNum
        if Minimap and Minimap.isInitialized then
            Minimap:refresh()
            if SendMinimapPosition then SendMinimapPosition(true) end
        end
    end

    -- Apply minimap position delta
    if type(merged.minimapPosition) == "table" then
        local dx = tonumber(merged.minimapPosition.deltaX)
        local dy = tonumber(merged.minimapPosition.deltaY)
        if dx and dy then
            SetMinimapDelta(dx, dy)
            if Minimap and Minimap.isInitialized then
                ApplyMinimapPosition(true)
                if SendMinimapPosition then SendMinimapPosition(true) end
            end
        end
    end

    _G.BabloHudCompassShowOnFoot = merged.compassShowOnFoot == true

    Trace("LoadSettings: mode=%s showMapOnFoot=%s active=%s",
        globalConfigActive and "GLOBAL" or "KVP",
        tostring(minimapState.showMapOnFoot),
        tostring(_G.BabloHudActive)
    )

    if _G.BabloHudRecomputeRadar then
        _G.BabloHudRecomputeRadar()
    end

    -- Send user settings to NUI
    SendNUIMessage({
        action = nuiAction("LOAD_SETTINGS", "loadSettings"),
        data   = merged,
    })

    -- Build and send server config
    local speedometerConfig = cfgDefault("speedometer") or {}
    local progressBarConfig = cfgDefault("progressBar") or {}

    local controlHints = Config.ControlHints
    if not controlHints then
        controlHints = { enabled = true, hints = {} }
    end

    local notificationConfig = cfgDefault("notification") or { enabled = true }

    local scaleFor = function(section, default)
        return tonumber(cfgDefault(section, "scale")) or default or 1.0
    end

    local serverConfig = {
        locks         = locks,
        speedometer   = speedometerConfig,
        progressBar   = progressBarConfig,
        controlHints  = controlHints,
        notification  = notificationConfig,
        voiceIcon     = Config.VoiceIcon or "lines",
        themeHighlightColor          = Config.HighlightColor,
        currency      = Config.Currency or "$_",
        themeHighlightSecondaryColor = Config.HighlightSecondaryColor,
        font          = Config.Font,
        seatbeltEnabled = not Config.Seatbelt,
        debug         = Config.DEBUG == true,
        globalConfigMode = globalConfigActive,
        isAdmin       = isAdmin,
        allowEdit     = canEditGlobal,
        componentScales = {
            playerInfo  = scaleFor("playerInfo", 1.0),
            status      = scaleFor("status"),
            speedometer = scaleFor("speedometer", 1.0),
            compass     = scaleFor("compass", 1.0),
            progressBar = scaleFor("progressBar", 1.0),
        },
        serverLogo = Config.ServerLogo or { enabled = true, scale = 1.0, opacity = 1.0 },
        minimapTransition = Config.MinimapTransition or { enabled = true, showLogo = true, duration = 400 },
        minimap = {
            maxSize = tonumber(cfgDefault("minimap", "maxSize")) or 1.25,
        },
    }

    SendNUIMessage({ action = "loadServerConfig", data = serverConfig })
    Info("Settings loaded (mode=%s)", globalConfigActive and "GLOBAL" or "KVP")
end

-- ─── Reset settings ───────────────────────────────────────────────────────────

function ResetSettings()
    resetInProgress = true
    SetResourceKvp(BabloHud.GetKvpKey(settingsKey), "")

    local speedometerDesign = cfgDefault("speedometer", "style") or "round-modern"
    local statusDesign      = cfgDefault("status", "design") or "v1"

    SendNUIMessage({
        action = "resetAllBrowserSettings",
        data   = { speedometerDesign = speedometerDesign, statusDesign = statusDesign },
    })

    LoadSettings()

    SetTimeout(1500, function()
        SetResourceKvp(BabloHud.GetKvpKey(settingsKey), "")
        resetInProgress = false
    end)

    Info("Settings reset")
end

-- ─── Commands ─────────────────────────────────────────────────────────────────

RegisterCommand("resetkvp", ResetSettings, false)

RegisterCommand("getsettings", function()
    local kvpKey = BabloHud.GetKvpKey(settingsKey)
    local raw    = GetResourceKvpString(kvpKey)
    Trace("Settings (%s): %s", kvpKey, raw)
end, false)

-- ─── NUI Callbacks ───────────────────────────────────────────────────────────

RegisterNUICallback("resetSettings", function(_, cb)
    ResetSettings()
    cb({ success = true })
end)

RegisterNUICallback("saveSettings", function(data, cb)
    if type(data) ~= "table" then
        cb({ success = false, error = "Invalid payload" })
        return
    end
    if resetInProgress then
        cb({ success = true, skipped = "resetInProgress" })
        return
    end

    -- Apply locally-relevant fields
    if data.showMapOnFoot ~= nil then
        minimapState.showMapOnFoot = data.showMapOnFoot
    end
    if data.minimapTransition ~= nil then
        minimapState.minimapTransition = data.minimapTransition ~= false
    end
    if data.mapStyle ~= nil then
        minimapState.mapStyle = data.mapStyle
        _G.BabloHudMapStyle   = data.mapStyle
    end

    if _G.BabloHudRecomputeRadar then _G.BabloHudRecomputeRadar() end

    if data.playerInfoEnabled ~= nil then
        componentEnabled.playerInfo = data.playerInfoEnabled ~= false
    end
    if data.compassEnabled ~= nil then
        componentEnabled.compass = data.compassEnabled ~= false
    end

    -- If global config + admin: buffer, don't save to KVP
    if globalConfigActive and isAdmin then
        cb({ success = true, buffered = true })
        return
    end

    local encoded = json.encode(data)
    SetResourceKvp(BabloHud.GetKvpKey(settingsKey), encoded)
    Info("Settings saved to KVP")
    cb({ success = true })
end)

RegisterNUICallback("publishGlobalConfig", function(data, cb)
    if not globalConfigActive then
        cb({ success = false, error = "Global Config mode is not enabled" })
        return
    end
    if not isAdmin then
        cb({ success = false, error = "Not an admin" })
        return
    end
    if type(data) ~= "table" then
        cb({ success = false, error = "Invalid payload" })
        return
    end

    data.minimapSize     = tonumber(_G.BabloHudMinimapSize) or data.minimapSize
    local dx, dy         = GetMinimapDelta()
    data.minimapPosition = { deltaX = dx, deltaY = dy }

    TriggerServerEvent("bablo-hud:globalConfig:publish", data)
    cb({ success = true })
end)

RegisterNUICallback("closeEditMode", function(_, cb)
    SetNuiFocus(false, false)
    cb({ success = true })
end)

RegisterNUICallback("setMapStyle", function(data, cb)
    if type(data) == "table" and data.style then
        minimapState.mapStyle = data.style
        _G.BabloHudMapStyle   = data.style
        if Minimap and Minimap.SwitchMap then
            Minimap:SwitchMap(data.style)
        end
        if SendMinimapPosition then SendMinimapPosition(true) end
    end
    cb({ success = true })
end)

RegisterNUICallback("setMinimapSize", function(data, cb)
    if type(data) == "table" and data.size then
        local sizeNum = tonumber(data.size) or 1.0
        _G.BabloHudMinimapSize = sizeNum
        if Minimap and Minimap.isInitialized then
            Minimap:applyPosition(data.final == true)
        end
        if SendMinimapPosition then SendMinimapPosition(false) end
    end
    cb({ success = true })
end)

RegisterNUICallback("setCompassShowOnFoot", function(data, cb)
    _G.BabloHudCompassShowOnFoot = data and data.value == true
    cb({ success = true })
end)

-- ─── Global config events ─────────────────────────────────────────────────────

AddEventHandler("bablo-hud:hostnameReady", function()
    LoadSettings()
    TriggerServerEvent("bablo-hud:globalConfig:request")
end)

RegisterNetEvent("bablo-hud:globalConfig:push")
AddEventHandler("bablo-hud:globalConfig:push", function(payload)
    if type(payload) ~= "table" then
        globalConfigActive = false
        globalConfigData   = nil
        isAdmin            = false
        canEditGlobal      = false
    else
        globalConfigActive = payload.enabled == true
        globalConfigData   = (type(payload.config) == "table" and payload.config) or nil
        isAdmin            = payload.isAdmin == true
        canEditGlobal      = payload.allowEdit == true
    end
    LoadSettings()
end)

RegisterNetEvent("bablo-hud:globalConfig:broadcast")
AddEventHandler("bablo-hud:globalConfig:broadcast", function(payload)
    if type(payload) ~= "table" then return end
    globalConfigActive = payload.enabled == true
    globalConfigData   = (type(payload.config) == "table" and payload.config) or nil
    canEditGlobal      = payload.allowEdit == true
    LoadSettings()
end)

-- ─── Radar / minimap visibility ───────────────────────────────────────────────

-- Minimap transition state
local transitionCounter  = 0
local pendingRadarState  = nil

function SetRadarVisibility(shouldShow, useTransition)
    local transitionCfg = Config.MinimapTransition
    local transitionEnabled = transitionCfg
        and transitionCfg.enabled ~= false
        and minimapState.minimapTransition

    if useTransition and transitionEnabled then
        local duration = 360
        if transitionCfg and transitionCfg.timing and tonumber(transitionCfg.timing.open) then
            duration = tonumber(transitionCfg.timing.open)
        elseif transitionCfg and tonumber(transitionCfg.duration) then
            duration = tonumber(transitionCfg.duration)
        end
        duration = duration + 40

        transitionCounter = transitionCounter + 1
        local myCount = transitionCounter
        pendingRadarState = shouldShow

        SendNUIMessage({
            action = nuiAction("MINIMAP_TRANSITION", "minimapTransition"),
            data   = { state = shouldShow },
        })

        CreateThread(function()
            Wait(duration)
            if myCount ~= transitionCounter then return end
            pendingRadarState = nil
            DisplayRadar(shouldShow)
        end)
        return
    end

    -- No transition: skip if already at the target state
    if pendingRadarState ~= nil then
        if pendingRadarState == shouldShow then return end
    end

    transitionCounter = transitionCounter + 1
    pendingRadarState = nil
    DisplayRadar(shouldShow)
end

function RecomputeRadar(vehicleOverride)
    if not _G.BabloHudActive then return end

    local vehicle
    if select("#", vehicleOverride) > 0 then
        vehicle = vehicleOverride
    else
        vehicle = cache and cache.vehicle
    end

    local inVehicle = vehicle ~= nil and vehicle ~= false

    local isDead = false
    if Framework and Framework.isPlayerDead then
        local ok, result = pcall(Framework.isPlayerDead, Framework)
        isDead = ok and result == true
    else
        isDead = IsPedDeadOrDying(PlayerPedId(), true)
    end

    local shouldShow = inVehicle or minimapState.showMapOnFoot

    -- ⚠️ The original logic here is complex: it checks BabloHudCinematic, BabloHudSuppressed,
    -- and BabloHudMinimapHidden but the flow is partially redundant/confusing after deobfuscation.
    -- The `shouldShow` branch below preserves the original behavior as closely as possible.
    if shouldShow or inVehicle then
        local cinematic  = _G.BabloHudCinematic
        local suppressed = _G.BabloHudSuppressed
        local hidden     = _G.BabloHudMinimapHidden
        shouldShow = not hidden and shouldShow
        -- Note: cinematic/suppressed flags override but original code path was unclear
    end

    Trace("recomputeRadar: showMapOnFoot=%s inVehicle=%s shouldShow=%s last=%s",
        tostring(minimapState.showMapOnFoot), tostring(inVehicle),
        tostring(shouldShow), tostring(lastRadarState)
    )

    local useTransition = (not _G.BabloHudCinematic and not _G.BabloHudSuppressed)
        and (lastRadarState ~= shouldShow)

    lastRadarState = shouldShow
    SetRadarVisibility(shouldShow, useTransition)
end

_G.BabloHudRecomputeRadar = RecomputeRadar

-- ─── Curtain command (debug/admin hold) ──────────────────────────────────────

local curtainHeld = false

RegisterCommand("hudcurtain", function(_, args)
    curtainHeld = not curtainHeld
    local ghost = args and args[1] == "ghost"

    local data
    if curtainHeld then
        data = { state = true, hold = true, ghost = ghost }
    else
        data = { release = true }
    end

    SendNUIMessage({
        action = nuiAction("MINIMAP_TRANSITION", "minimapTransition"),
        data   = data,
    })

    print(("[bablo-hud] curtain %s"):format(
        curtainHeld and "held open (run again to release)" or "released"
    ))
end, false)

-- ─── HUD component hiding (zone / street name suppression during load) ────────

local HIDE_DURATION_MS  = 300
local zoneHideUntil     = 0
local vehicleHideUntil  = 0
local streetHideUntil   = 0
local lastZoneName      = nil
local lastStreetHash    = nil

AddEventHandler("gameEventTriggered", function(eventName)
    if eventName ~= "CEventNetworkPlayerEnteredVehicle" then return end
    local frame = (Bablo and Bablo.Ticker and Bablo.Ticker.frame and Bablo.Ticker.frame()) or 0
    zoneHideUntil = frame + HIDE_DURATION_MS
end)

-- ─── Player load / unload lifecycle ──────────────────────────────────────────

AddEventHandler("bablo-hud:playerLoaded", function()
    if tickerHandle then return end
    if not (Bablo and Bablo.Ticker) then return end

    RecomputeRadar()

    -- After 4s, reset last radar state to force re-evaluation
    CreateThread(function()
        Wait(4000)
        lastRadarState = nil
        RecomputeRadar()
    end)

    local ticker = Bablo.Ticker
    tickerHandle = ticker:register(ticker, function(frame)
        if not _G.BabloHudActive then return end

        if frame < zoneHideUntil    then HideHudComponentThisFrame(6) end
        if frame < vehicleHideUntil then HideHudComponentThisFrame(7) end
        if frame < streetHideUntil  then HideHudComponentThisFrame(9) end

        if frame % 60 == 0 then
            local ped = cache and cache.ped
            if ped then
                local coords = GetEntityCoords(ped)
                local zone   = GetNameOfZone(coords.x, coords.y, coords.z)
                if zone ~= lastZoneName then
                    lastZoneName    = zone
                    vehicleHideUntil = frame + HIDE_DURATION_MS
                end

                if cache.vehicle then
                    local streetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
                    if streetHash ~= lastStreetHash then
                        lastStreetHash = streetHash
                        streetHideUntil = frame + HIDE_DURATION_MS
                    end
                end
            end

            if IsBigmapActive() then
                SetRadarBigmapEnabled(false, false)
            end
        end
    end)
end)

if lib and lib.onCache then
    lib.onCache("vehicle", function(vehicle)
        RecomputeRadar(vehicle)
    end)
end

AddEventHandler("bablo-hud:playerUnloaded", function()
    if tickerHandle and Bablo and Bablo.Ticker then
        Bablo.Ticker:unregister(Bablo.Ticker, tickerHandle)
        tickerHandle = nil
    end
    lastRadarState = nil
    DisplayRadar(false)
end)
