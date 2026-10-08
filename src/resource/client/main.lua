local Constants   = (BabloHud and BabloHud.Constants) or {}
local NUI_ACTIONS = Constants.NUI_ACTIONS or {}
local KVP         = Constants.KVP        or {}

-- Helper to check if a resource is active
function IsResourceActive(resourceName)
    local state = GetResourceState(resourceName)
    return state == "started" or state == "starting"
end

_G.BabloHudActive = false

-- ---------------------------------------------------------------------------
-- Settings command name (falls back to "settings" if not configured)
-- ---------------------------------------------------------------------------
local settingsCommand = "settings"
if Config and Config.Settings and type(Config.Settings.command) == "string" and Config.Settings.command ~= "" then
    settingsCommand = Config.Settings.command
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Returns a localised string by key, or the given fallback if Locale is absent
function GetLocaleString(key, fallback)
    if Locale and type(Locale.t) == "function" then
        local result = Locale.t(key)
        if result then return result end
    end
    return fallback
end

-- Shows a locked-settings notification via the bablo-hud export
function NotifySettingsLocked()
    local msg = GetLocaleString(
        "notifications.settingsLocked",
        "HUD customization is managed by the server. Settings aren't editable on this server."
    )
    exports["bablo-hud"]:Notify(msg)
end

-- Returns true when the settings panel should be blocked from opening
function AreSettingsLocked()
    if Config and Config.Settings and Config.Settings.enabled == false then
        return true
    end
    if BabloHud and BabloHud.GlobalConfig and BabloHud.GlobalConfig.isGated() then
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- /settings  –  open HUD settings panel
-- ---------------------------------------------------------------------------
RegisterCommand(settingsCommand, function()
    if not _G.BabloHudActive then return end

    if AreSettingsLocked() then
        NotifySettingsLocked()
        return
    end

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = NUI_ACTIONS.TOGGLE_SETTINGS or "toggleSettings",
        data   = true,
    })
end, false)

-- Keybind for opening settings (optional, driven by config)
if Config and Config.Settings and Config.Settings.keybind and Config.Settings.keybind.enabled == true then
    local defaultKey = Config.Settings.keybind.defaultKey or "I"
    local label      = GetLocaleString("keymapping.openSettings", "Open HUD Settings Menu")
    RegisterKeyMapping(settingsCommand, label, "keyboard", defaultKey)
end

-- ---------------------------------------------------------------------------
-- /edithud  –  open HUD edit mode (GlobalConfig only)
-- ---------------------------------------------------------------------------
if Config and Config.GlobalConfig and Config.GlobalConfig.enabled == true and Config.GlobalConfig.allowEdit == true then
    RegisterCommand("edithud", function()
        if not _G.BabloHudActive then return end
        SetNuiFocus(true, true)
        SendNUIMessage({ action = "openEditMode", data = true })
    end, false)
end

-- ---------------------------------------------------------------------------
-- NUI z-index
-- ---------------------------------------------------------------------------
SetNuiZindex(9999999)

-- ---------------------------------------------------------------------------
-- Weapon image template resolution
-- ---------------------------------------------------------------------------

-- Known inventory resource → weapon image URL templates
local WEAPON_IMAGE_TEMPLATES = {
    ["bablo-hud"]       = "nui://bablo-hud/weapons/{weapon}.png",
    ox_inventory        = "nui://ox_inventory/web/images/{weapon}.png",
    ["qb-inventory"]    = "nui://qb-inventory/html/images/{weapon}.png",
    ["qs-inventory"]    = "nui://qs-inventory/html/images/{weapon}.png",
    ["ps-inventory"]    = "nui://ps-inventory/html/images/{weapon}.png",
    origen_inventory    = "nui://origen_inventory/html/images/{weapon}.png",
    core_inventory      = "nui://core_inventory/html/images/{weapon}.png",
    ["codem-inventory"] = "nui://codem-inventory/html/itemimages/{weapon}.png",
    ["tgiann-inventory"]= "nui://inventory_images/images/{weapon}.png",
}

-- Resolves the weapon image URL template from Config.WeaponImageInventory.
-- Supports a literal template string (must contain "{weapon}") or an
-- inventory resource name (looked up in WEAPON_IMAGE_TEMPLATES, with a
-- fallback to bablo-hud's own weapons if inventory resource is not active).
function ResolveWeaponImageTemplate()
    local inventorySetting = (Config and Config.WeaponImageInventory) or "ox_inventory"
    local template = nil

    -- Handle explicit "none" or empty setting for no inventory
    if inventorySetting == "" or inventorySetting == "none" or inventorySetting == false then
        return "nui://bablo-hud/weapons/{weapon}.png"
    end

    if type(inventorySetting) == "string" then
        if inventorySetting:find("{weapon}", 1, true) then
            -- Already a full template URL
            template = inventorySetting
        else
            -- Resource name — check if inventory resource is active
            if IsResourceActive(inventorySetting) then
                -- Resource name — look up or build a generic fallback
                template = WEAPON_IMAGE_TEMPLATES[inventorySetting]
                    or ("nui://" .. inventorySetting .. "/html/images/{weapon}.png")
            else
                -- Inventory resource not active, fall back to bablo-hud's own weapons
                template = "nui://bablo-hud/weapons/{weapon}.png"
            end
        end
    end

    return template
end

-- Builds a normalised table of per-weapon image overrides from Config.WeaponImages
function BuildWeaponImageOverrides()
    local overrides = {}
    if type(Config) == "table" and type(Config.WeaponImages) == "table" then
        for weaponName, url in pairs(Config.WeaponImages) do
            if type(weaponName) == "string" and type(url) == "string" and url ~= "" then
                overrides[string.lower(weaponName)] = url
            end
        end
    end
    return overrides
end

-- ---------------------------------------------------------------------------
-- BuildModuleConfig  –  assembles the full config payload sent to the NUI
-- ---------------------------------------------------------------------------
function BuildModuleConfig()
    local playerInfo = nil

    if Config and Config.DefaultSettings and Config.DefaultSettings.playerInfo then
        local src = Config.DefaultSettings.playerInfo

        local timeSource = src.timeSource
        if timeSource ~= "local" and timeSource ~= "server" then
            timeSource = "ingame"
        end

        playerInfo = {
            job   = { enabled = src.showJob   ~= false },
            id    = { enabled = src.showId    ~= false },
            time  = { enabled = src.showTime  ~= false, source = timeSource },
            bank  = { enabled = src.showBank  ~= false },
            cash  = { enabled = src.showCash  ~= false },
            dirty = { enabled = src.showDirtyMoney ~= false },
            gang  = { enabled = src.showGang  ~= false },
            weapon= { enabled = src.showWeapon ~= false },
        }
    end

    return {
        PlayerInfo = playerInfo,
        weaponImageTemplate  = ResolveWeaponImageTemplate(),
        weaponImageOverrides = BuildWeaponImageOverrides(),
    }
end

RegisterNUICallback("requestModuleConfig", function(_, cb)
    cb(BuildModuleConfig())
end)

-- ---------------------------------------------------------------------------
-- Player loaded / unloaded lifecycle
-- ---------------------------------------------------------------------------
AddEventHandler("bablo-hud:playerLoaded", function()
    if _G.BabloHudActive then return end
    _G.BabloHudActive = true

    Wait(500)

    -- Send locale dictionary to NUI
    local dict     = Locale.getDictionary()
    local fallback = Locale.getFallback()
    local code     = Locale.getCode()
    SendNUIMessage({
        action = NUI_ACTIONS.LOAD_LOCALE or "loadLocale",
        data   = {
            code     = code,
            dict     = dict,
            fallback = (dict ~= fallback and fallback) or nil,
        },
    })

    -- Show HUD
    SendNUIMessage({ action = NUI_ACTIONS.SET_HUD_VISIBLE or "setHudVisible", data = true })
    DisplayRadar(true)

    -- Send module config
    SendNUIMessage({ action = "moduleConfig", data = BuildModuleConfig() })

    -- Sync minimap position
    if SendMinimapPosition then
        SendMinimapPosition(true)
    end

    TriggerServerEvent("bablo-hud:requestServerInfo")

    -- Fetch server ID via ox_lib callback if available
    if lib and lib.callback and lib.callback.await then
        CreateThread(function()
            local serverId = lib.callback.await("bablo-hud:getServerId", false)
            if type(serverId) == "number" and serverId > 0 then
                _G.BabloHudServerId = serverId
            end
        end)
    end

    Info("HUD activated (player loaded)")
end)

-- Receive server info (hostname + serverId) from the server side
RegisterNetEvent("bablo-hud:receiveServerInfo")
AddEventHandler("bablo-hud:receiveServerInfo", function(info)
    if type(info) ~= "table" then return end

    -- Sanitise hostname: strip colour codes, replace non-alphanumeric/dash/underscore
    -- with underscores, collapse runs, and trim leading/trailing underscores
    local hostname = (info.hostname or "")
        :gsub("%^%d",    "")
        :gsub("[^%w%-_]","_")
        :gsub("_+",      "_")
        :gsub("^_+",     "")
        :gsub("_+$",     "")

    _G.BabloHudHostname = hostname

    if type(info.serverId) == "number" and info.serverId > 0 then
        _G.BabloHudServerId = info.serverId
    end

    TriggerEvent("bablo-hud:hostnameReady")
    Info("Server hostname for KVP: " .. hostname)
end)

AddEventHandler("bablo-hud:playerUnloaded", function()
    _G.BabloHudActive = false
    SendNUIMessage({ action = NUI_ACTIONS.SET_HUD_VISIBLE or "setHudVisible", data = false })
    DisplayRadar(false)
    Info("HUD deactivated (player unloaded)")
end)

-- ---------------------------------------------------------------------------
-- Debug commands
-- ---------------------------------------------------------------------------

-- /removekvp  –  deletes the minimap KVP entry (debug only)
RegisterCommand("removekvp", function()
    if not IsDebugEnabled() then
        Warn("removekvp is debug-only")
        return
    end
    local key = BabloHud.GetKvpKey(KVP.MINIMAP_POSITION or "bablo_hud_minimap_position")
    DeleteResourceKvp(key)
    Info("Minimap KVP removed (" .. key .. ")")
end, false)

-- /hudinfo  –  prints KVP contents and screen resolution diagnostics
RegisterCommand("hudinfo", function()
    local settingsKey = BabloHud.GetKvpKey(KVP.SETTINGS        or "bablo_hud_settings")
    local minimapKey  = BabloHud.GetKvpKey(KVP.MINIMAP_POSITION or "bablo_hud_minimap_position")

    Info("^3=== bablo-hud KVP Data ===^0")
    Info("^3Hostname: " .. (_G.BabloHudHostname or "(not set)") .. "^0")

    local settingsVal = GetResourceKvpString(settingsKey)
    if settingsVal and settingsVal ~= "" then
        Info("^2[Settings]^0 (" .. settingsKey .. ") " .. settingsVal)
    else
        Info("^1[Settings]^0 (" .. settingsKey .. ") (empty)")
    end

    local minimapVal = GetResourceKvpString(minimapKey)
    if minimapVal and minimapVal ~= "" then
        Info("^2[Minimap Position]^0 (" .. minimapKey .. ") " .. minimapVal)
    else
        Info("^1[Minimap Position]^0 (" .. minimapKey .. ") (empty)")
    end

    -- Screen resolution and aspect ratio diagnostics
    local physW, physH   = GetActualScreenResolution()
    local activeW, activeH = GetActiveScreenResolution()
    local physAspect     = (physW and physH and physH > 0) and (physW / physH) or 0
    local aspectTrue     = GetAspectRatio(true)  or 0
    local aspectFalse    = GetAspectRatio(false) or 0
    local screenAspect   = GetScreenAspectRatio and GetScreenAspectRatio() or 0
    local safeZone       = GetSafeZoneSize() or 0

    print(string.format(
        "[bablo-hud] aspect: physical=%sx%s (%.4f) active=%sx%s GetAspectRatio(true)=%.4f GetAspectRatio(false)=%.4f screen=%.4f safezone=%.3f",
        tostring(physW), tostring(physH), physAspect,
        tostring(activeW), tostring(activeH),
        aspectTrue, aspectFalse, screenAspect, safeZone
    ))

    -- Log minimap anchor if available
    if Minimap and Minimap.getAnchor then
        local ok, anchor = pcall(function() return Minimap:getAnchor() end)
        if ok and anchor then
            print(string.format(
                "[bablo-hud] minimap anchor: left=%.1f top=%.1f width=%.1f height=%.1f",
                anchor.leftPx  or 0,
                anchor.topPx   or 0,
                anchor.widthPx or 0,
                anchor.heightPx or 0
            ))
        end
    end

    SendNUIMessage({ action = "dumpPositions", data = true })
    Info("^3(NUI positions returned via callback)^0")
end, false)

-- NUI callback: receives and prints the full NUI debug state in 900-char chunks
RegisterNUICallback("dumpDebug", function(data, cb)
    print("=== bablo-hud NUI DEBUG DUMP ===")
    local ok, encoded = pcall(json.encode, data)
    if ok and encoded then
        for i = 1, #encoded, 900 do
            print(encoded:sub(i, i + 899))
        end
    end
    print("=== END DEBUG DUMP ===")
    cb({ success = true })
end)

-- NUI callback: logs each element's x/y position from the NUI layer
RegisterNUICallback("dumpPositions", function(data, cb)
    Info("^3=== NUI Element Positions ===^0")
    if type(data) == "table" then
        for elementName, pos in pairs(data) do
            if type(pos) == "table" then
                local scaleStr = pos.scale and string.format("  scale=%.2f", pos.scale) or ""
                Info(string.format("  ^2%s^0: x=%.1f  y=%.1f%s",
                    elementName, pos.x or 0, pos.y or 0, scaleStr))
            end
        end
    end
    cb({ success = true })
end)

-- ---------------------------------------------------------------------------
-- Hide native GTA HUD text components (optional, driven by config)
-- ---------------------------------------------------------------------------
if Config and Config.HideNativeTexts then
    local hide = Config.HideNativeTexts
    local hideVehicleName  = hide.vehicleName  == true
    local hideVehicleClass = hide.vehicleClass == true
    local hideAreaName     = hide.areaName     == true
    local hideStreetName   = hide.streetName   == true

    -- Only spin up the thread if at least one flag is set
    if hideVehicleName or hideVehicleClass or hideAreaName or hideStreetName then
        CreateThread(function()
            while true do
                -- HUD component IDs: 6=vehicleName, 7=areaName, 8=vehicleClass, 9=streetName
                if hideVehicleName  then HideHudComponentThisFrame(6) end
                if hideAreaName     then HideHudComponentThisFrame(7) end
                if hideVehicleClass then HideHudComponentThisFrame(8) end
                if hideStreetName   then HideHudComponentThisFrame(9) end
                Wait(0)
            end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Safe-zone change watcher  –  notifies the NUI when GTA safe zone is adjusted
-- ---------------------------------------------------------------------------
local lastSafeZoneSize = nil

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(100) end
    Wait(1000)

    while true do
        local size = GetSafeZoneSize()
        if size ~= lastSafeZoneSize then
            lastSafeZoneSize = size
            SendNUIMessage({
                action = NUI_ACTIONS.SAFEZONE_UPDATE or "safeZone:update",
                data   = { size = size },
            })
        end
        Wait(10000)
    end
end)

-- ---------------------------------------------------------------------------
-- /testaudio  –  plays each custom audio cue in sequence (debug helper)
-- ---------------------------------------------------------------------------
RegisterCommand("testaudio", function()
    -- Wait up to 5 s for the audio bank to load
    local deadline = GetGameTimer() + 5000
    while true do
        if RequestScriptAudioBank("audiodirectory/bablo_custom_sounds", false) then break end
        if GetGameTimer() > deadline then
            Info("[bablo-hud] RequestScriptAudioBank failed after 5s - bank limit or missing file")
            return
        end
        Wait(100)
    end

    local sounds = { "bomb-ticking", "unbuckle", "buckle" }
    for _, soundName in ipairs(sounds) do
        Info("[bablo-hud] Playing sound " .. soundName)
        local soundId = GetSoundId()
        PlaySoundFromEntity(soundId, soundName, PlayerPedId(), "bablo_special_soundset", 0, 0)
        while not HasSoundFinished(soundId) do Wait(0) end
        ReleaseSoundId(soundId)
    end
end, false)
