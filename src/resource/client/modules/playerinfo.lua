local NUI_ACTIONS      = (BabloHud and BabloHud.Constants and BabloHud.Constants.NUI_ACTIONS) or {}
local ACTION_UPDATE    = NUI_ACTIONS.UPDATE_PLAYER_INFO or "updatePlayerInfo"

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local running         = false       -- true while the module polling threads are live
local lastSnapshot    = nil         -- last playerInfo table sent to NUI
local weaponCardVisible = false     -- true when the NUI weapon card overlay is visible
local hasWeaponEquipped = cache and cache.weapon and true or false

-- Ticker handle for HideHudComponentThisFrame (component 2 = weapon info)
local hideWeaponHudTickerId = nil

-- Cache of weapon labels: hash → display name (built lazily from Framework.getCore)
local weaponLabelCache = nil

-- ---------------------------------------------------------------------------
-- Known GTA weapon hashes (hash → internal name string)
-- Used for image path resolution when Framework labels are unavailable.
-- ---------------------------------------------------------------------------
local WEAPON_HASH_TO_NAME = {}

local KNOWN_WEAPON_NAMES = {
    -- Pistols
    "weapon_pistol", "weapon_pistolmkii", "weapon_combatpistol", "weapon_appistol",
    "weapon_stungun", "weapon_pistol50", "weapon_snspistol", "weapon_snspistolmkii",
    "weapon_heavypistol", "weapon_vintagepistol", "weapon_flaregun", "weapon_marksmanpistol",
    "weapon_revolver", "weapon_revolvermkii", "weapon_doubleaction", "weapon_raypistol",
    "weapon_ceramicpistol", "weapon_navyrevolver", "weapon_gadgetpistol", "weapon_pistolxm3",
    -- SMGs
    "weapon_microsmg", "weapon_smg", "weapon_smgmkii", "weapon_assaultsmg",
    "weapon_combatpdw", "weapon_machinepistol", "weapon_minismg", "weapon_tacticalsmg",
    -- Shotguns
    "weapon_pumpshotgun", "weapon_pumpshotgunmkii", "weapon_sawnoffshotgun",
    "weapon_assaultshotgun", "weapon_bullpupshotgun", "weapon_heavyshotgun",
    "weapon_doublebarrelshotgun", "weapon_sweeper", "weapon_combatshotgun",
    -- Assault rifles
    "weapon_assaultrifle", "weapon_assaultriflemkii", "weapon_carbinerifle",
    "weapon_carbineriflemkii", "weapon_advancedrifle", "weapon_specialcarbine",
    "weapon_specialcarbinemkii", "weapon_bullpuprifle", "weapon_bullpupriflomkii",
    "weapon_compactrifle", "weapon_militaryrifle", "weapon_heavyrifle", "weapon_tacticalrifle",
    -- MGs
    "weapon_mg", "weapon_combatmg", "weapon_combatmgmkii", "weapon_gusenberg",
    -- Snipers
    "weapon_sniperrifle", "weapon_heavysniper", "weapon_heavysnipermkii",
    "weapon_marksmanrifle", "weapon_marksmanriflomkii", "weapon_precisionrifle",
    -- Launchers / heavy
    "weapon_musket", "weapon_rpg", "weapon_grenadelauncher", "weapon_smokelauncher",
    "weapon_minigun", "weapon_firework", "weapon_railgun", "weapon_hominglauncher",
    "weapon_compactlauncher", "weapon_widowmaker", "weapon_emplauncher",
    -- Melee
    "weapon_knife", "weapon_bat", "weapon_hammer", "weapon_crowbar", "weapon_machete",
    "weapon_switchblade", "weapon_nightstick", "weapon_hatchet", "weapon_wrench",
    "weapon_poolcue", "weapon_battleaxe", "weapon_stone_hatchet",
}

for _, name in ipairs(KNOWN_WEAPON_NAMES) do
    local hash = GetHashKey(name)
    if hash and hash ~= 0 then
        WEAPON_HASH_TO_NAME[hash] = name
    end
end

-- ---------------------------------------------------------------------------
-- GetWeaponInternalName(weaponHash)
-- Returns the lowercase internal name string for a hash, or "" if unknown.
-- ---------------------------------------------------------------------------
function GetWeaponInternalName(weaponHash)
    if not weaponHash or weaponHash == 0 then return "" end
    return WEAPON_HASH_TO_NAME[weaponHash] or ""
end

-- ---------------------------------------------------------------------------
-- HashToHex(hash)
-- Converts a signed 32-bit weapon hash to "0xXXXXXXXX" string form.
-- Returns nil for nil input.
-- ---------------------------------------------------------------------------
function HashToHex(hash)
    if not hash then return nil end
    if hash < 0 then hash = hash + 4294967296 end
    return string.format("0x%08X", hash)
end

-- ---------------------------------------------------------------------------
-- GetWeaponLabelMap()
-- Returns a hash → label table sourced from Framework.getCore().Shared.Weapons.
-- Result is cached after first call.
-- ---------------------------------------------------------------------------
function GetWeaponLabelMap()
    if weaponLabelCache then return weaponLabelCache end

    local labels = {}

    if Framework and Framework.getCore then
        local core = Framework:getCore()
        if core and core.Shared and core.Shared.Weapons then
            for weaponName, weaponData in pairs(core.Shared.Weapons) do
                if type(weaponName) == "string" then
                    local hash = GetHashKey(string.upper(weaponName))
                    if hash and hash ~= 0 then
                        local label = (type(weaponData) == "table" and weaponData.label)
                            or labels[hash]
                            or weaponName
                        labels[hash] = label
                    end
                end
            end
        end
    end

    weaponLabelCache = labels
    return labels
end

-- ---------------------------------------------------------------------------
-- GetWeaponDisplayName(weaponHash)
-- Priority: unarmed locale key → framework label map → locale key by hex →
--           GetWeaponDisplayNameFromHash native → fallback locale key
-- ---------------------------------------------------------------------------
local UNARMED_HASH = GetHashKey("WEAPON_UNARMED")

function GetWeaponDisplayName(weaponHash)
    -- Unarmed / no weapon
    if not weaponHash or weaponHash == 0 or weaponHash == UNARMED_HASH then
        return Locale.t("framework.fallbacks.unarmed")
    end

    -- Framework label map
    local labels = GetWeaponLabelMap()
    local label  = labels[weaponHash]
    if label and label ~= "" then return label end

    -- Locale key via hex hash ("weapons.0xXXXXXXXX")
    local hex = HashToHex(weaponHash)
    if hex then
        local localeKey    = "weapons." .. hex
        local localeResult = Locale.t(localeKey)
        if localeResult ~= localeKey then return localeResult end
    end

    -- Native GTA function
    if type(GetWeaponDisplayNameFromHash) == "function" then
        local ok, displayKey = pcall(GetWeaponDisplayNameFromHash, weaponHash)
        if ok and displayKey and displayKey ~= "NULL" then
            local text = GetLabelText(displayKey)
            if text and text ~= "NULL" then return text end
            return displayKey
        end
    end

    return Locale.t("framework.fallbacks.weaponName")
end

-- ---------------------------------------------------------------------------
-- GetVoiceProximity()
-- Returns voiceLevel, voiceMax from LocalPlayer.state.proximity.
-- Falls back to level=3, max=5.
-- ---------------------------------------------------------------------------
function GetVoiceProximity()
    local proximity = LocalPlayer and LocalPlayer.state and LocalPlayer.state.proximity
    if proximity then
        local index = tonumber(proximity.index) or tonumber(proximity.mode)
        if index then
            return math.max(1, math.floor(index + 1)), 5
        end
    end
    return 3, 5
end

-- ---------------------------------------------------------------------------
-- GetRadioFrequency()
-- Returns the player's radio channel as a "%.1f" string, or "0.0".
-- ---------------------------------------------------------------------------
function GetRadioFrequency()
    local channel = LocalPlayer and LocalPlayer.state and LocalPlayer.state.radioChannel
    local n = channel and tonumber(channel)
    if n and n > 0 then return string.format("%.1f", n) end
    return "0.0"
end

-- ---------------------------------------------------------------------------
-- GetAmmoData(ped, weaponHash)
-- Returns ammoClip, ammoTotal for the given weapon.
-- ammoTotal excludes the clip count (total reserve only).
-- ---------------------------------------------------------------------------
function GetAmmoData(ped, weaponHash)
    local _, clipAmmo   = GetAmmoInClip(ped, weaponHash)
    local totalAmmo     = GetAmmoInPedWeapon(ped, weaponHash)
    clipAmmo  = clipAmmo  or 0
    totalAmmo = totalAmmo or 0
    return clipAmmo, math.max(0, totalAmmo - clipAmmo)
end

-- ---------------------------------------------------------------------------
-- GetServerPlayerId()
-- Returns the server-side player ID from Framework.getPlayerId or
-- GetPlayerServerId, or nil when unavailable / invalid.
-- ---------------------------------------------------------------------------
function GetServerPlayerId()
    local id = nil
    if Framework and Framework.getPlayerId then
        id = Framework:getPlayerId()
    end
    if not id then
        id = GetPlayerServerId(PlayerId())
    end
    if type(id) ~= "number" or id <= 0 then return nil end
    return id
end

-- ---------------------------------------------------------------------------
-- CollectPlayerInfo()
-- Reads all player info fields and returns a snapshot table,
-- or nil when the ped does not exist.
-- ---------------------------------------------------------------------------
function CollectPlayerInfo()
    local ped = cache and cache.ped
    if not ped or not DoesEntityExist(ped) then return nil end

    local playerId   = PlayerId()
    local playerName = GetPlayerName(playerId) or "Player"
    local jobName    = "Unemployed"
    local jobGrade   = "Worker"
    local wallet     = 0
    local bank       = 0
    local dirtyMoney = nil
    local gangName   = nil
    local gangGrade  = nil

    if Framework then
        if Framework.getPlayerName then playerName = Framework:getPlayerName() end

        if Framework.getJob then
            jobName, jobGrade = Framework:getJob()
        end

        if Framework.getMoney then
            wallet, bank = Framework:getMoney()
        end

        if Framework.getDirtyMoney then
            local ok, dirty = pcall(function() return Framework:getDirtyMoney() end)
            if ok and type(dirty) == "number" and dirty > 0 then
                dirtyMoney = dirty
            end
        end

        if Framework.getGang then
            local ok, gang = pcall(function() return Framework:getGang() end)
            if ok and type(gang) == "table" then
                gangName  = gang.label or gang.name
                gangGrade = gang.grade
            end
        end
    end

    local currentWeapon = GetSelectedPedWeapon(ped)
    local hasWeapon     = currentWeapon and currentWeapon ~= 0 and currentWeapon ~= UNARMED_HASH

    local ammoClip, ammoTotal = 0, 0
    if hasWeapon then
        ammoClip, ammoTotal = GetAmmoData(ped, currentWeapon)
    end

    local voiceLevel, voiceMax = GetVoiceProximity()

    return {
        playerName    = playerName,
        playerId      = GetServerPlayerId(),
        activePlayers = #GetActivePlayers(),
        voiceLevel    = voiceLevel,
        voiceMax      = voiceMax,
        radioFrequency = GetRadioFrequency(),
        bank          = bank,
        wallet        = wallet,
        dirtyMoney    = dirtyMoney,
        gang          = gangName,
        gangGrade     = gangGrade,
        job           = jobName,
        jobGrade      = jobGrade,
        gameHour      = GetClockHours(),
        gameMinute    = GetClockMinutes(),
        weapon        = GetWeaponDisplayName(currentWeapon),
        weaponImage   = GetWeaponInternalName(currentWeapon),
        hasWeapon     = hasWeapon and true or false,
        ammoClip      = ammoClip,
        ammoTotal     = ammoTotal,
    }
end

-- ---------------------------------------------------------------------------
-- PlayerInfoChanged(prev, next)
-- Returns true when the player name differs (used to gate full NUI sends).
-- Simple check — the NUI handles fine-grained change detection internally.
-- ---------------------------------------------------------------------------
function PlayerInfoChanged(prev, next)
    if not prev or not next then return true end
    return prev.playerName ~= next.playerName
end

-- ---------------------------------------------------------------------------
-- PushPlayerInfoSnapshot()
-- Forces an immediate send of player info to the NUI, bypassing change check.
-- Assigned to BabloHud.PushPlayerInfoSnapshot for external callers.
-- ---------------------------------------------------------------------------
BabloHud = BabloHud or {}

function BabloHud.PushPlayerInfoSnapshot()
    local info = CollectPlayerInfo()
    if not info then return end
    lastSnapshot = nil   -- clear so change check always passes
    SendNUIMessage({ action = ACTION_UPDATE, data = info })
    lastSnapshot = info
end

-- ---------------------------------------------------------------------------
-- SendPlayerInfo(info)
-- Sends a player info snapshot only when playerName has changed.
-- ---------------------------------------------------------------------------
function SendPlayerInfo(info)
    if not info then return end
    if not PlayerInfoChanged(lastSnapshot, info) then return end
    SendNUIMessage({ action = ACTION_UPDATE, data = info })
    lastSnapshot = info
end

-- ---------------------------------------------------------------------------
-- SyncWeaponHudHide()
-- Registers or unregisters the per-frame ticker that hides GTA's native
-- weapon HUD component (component 2) while the weapon card is visible
-- and a weapon is equipped.
-- ---------------------------------------------------------------------------
function SyncWeaponHudHide()
    local shouldHide = weaponCardVisible and hasWeaponEquipped

    if shouldHide then
        if not hideWeaponHudTickerId and Bablo and Bablo.Ticker then
            hideWeaponHudTickerId = Bablo.Ticker:register(function()
                HideHudComponentThisFrame(2)
            end)
        end
    else
        if hideWeaponHudTickerId and Bablo and Bablo.Ticker then
            Bablo.Ticker:unregister(hideWeaponHudTickerId)
            hideWeaponHudTickerId = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- NUI callbacks
-- ---------------------------------------------------------------------------

-- NUI tells us whether the weapon card overlay is currently visible
RegisterNUICallback("setWeaponCardVisible", function(data, cb)
    if type(data) == "table" and data.visible ~= nil then
        weaponCardVisible = data.visible == true
        SyncWeaponHudHide()
    end
    cb({ success = true })
end)

-- NUI requests a fresh player info push (e.g. on mount / reconnect)
RegisterNUICallback("requestPlayerInfoSnapshot", function(_, cb)
    if BabloHud and BabloHud.PushPlayerInfoSnapshot then
        BabloHud.PushPlayerInfoSnapshot()
    end
    cb({ success = true })
end)

-- NUI requests the current server time via ox_lib callback
RegisterNUICallback("requestServerTime", function(_, cb)
    local ok, result = pcall(function()
        return lib.callback.await("bablo-hud:getServerTime", false)
    end)
    if ok and type(result) == "table" and type(result.h) == "number" then
        cb(result)
    else
        cb(false)
    end
end)

-- ---------------------------------------------------------------------------
-- Weapon cache change (ox_lib) — update hasWeaponEquipped and push weapon info
-- ---------------------------------------------------------------------------
lib.onCache("weapon", function(weaponHash)
    hasWeaponEquipped = weaponHash and true or false
    SyncWeaponHudHide()

    if not running then return end

    -- Immediately push updated weapon state to NUI on weapon switch
    local isArmed    = weaponHash and weaponHash ~= 0 and weaponHash ~= UNARMED_HASH
    local ammoClip, ammoTotal = 0, 0
    if isArmed then
        local ped = cache and cache.ped
        if ped then ammoClip, ammoTotal = GetAmmoData(ped, weaponHash) end
    end

    local serverId = GetServerPlayerId()

    SendNUIMessage({
        action = ACTION_UPDATE,
        data   = {
            weapon      = GetWeaponDisplayName(weaponHash),
            weaponImage = GetWeaponInternalName(weaponHash),
            hasWeapon   = isArmed and true or false,
            ammoClip    = ammoClip,
            ammoTotal   = ammoTotal,
            playerId    = serverId,
        },
    })
end)

-- ---------------------------------------------------------------------------
-- StartPlayerInfoModule()
-- Launches two polling threads:
--   1. Ammo thread: updates clip/total ammo at 50–250 ms while armed
--   2. Slow info thread: pushes full player snapshot every 5 s
-- ---------------------------------------------------------------------------
function StartPlayerInfoModule()
    if running then return end
    running = true
    Info("Player info module started")

    -- Thread 1: ammo polling (fast when shooting, slow when armed, idle when unarmed)
    CreateThread(function()
        local lastClipAmmo = nil

        while running do
            local weaponHash = cache and cache.weapon

            if weaponHash and weaponHash ~= 0 and weaponHash ~= UNARMED_HASH then
                local ped     = cache and cache.ped
                local clipAmmo, totalAmmo = GetAmmoData(ped, weaponHash)

                if clipAmmo ~= lastClipAmmo then
                    lastClipAmmo = clipAmmo
                    SendNUIMessage({
                        action = ACTION_UPDATE,
                        data   = {
                            weapon      = GetWeaponDisplayName(weaponHash),
                            weaponImage = GetWeaponInternalName(weaponHash),
                            hasWeapon   = true,
                            ammoClip    = clipAmmo,
                            ammoTotal   = totalAmmo,
                        },
                    })
                end

                -- Poll faster while the player is actively shooting
                Wait(IsPedShooting(ped) and 50 or 250)
            else
                lastClipAmmo = nil
                Wait(1000)
            end
        end
    end)

    -- Thread 2: slow full-snapshot poll (every 5 s, with a 300 ms initial delay)
    CreateThread(function()
        Wait(300)
        while running do
            local info = CollectPlayerInfo()
            if info then SendPlayerInfo(info) end
            Wait(5000)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------
exports("RefreshPlayerInfo", function()
    if not _G.BabloHudActive then return false end
    BabloHud.PushPlayerInfoSnapshot()
    return true
end)

-- ---------------------------------------------------------------------------
-- Net event: server-triggered player info refresh
-- ---------------------------------------------------------------------------
RegisterNetEvent("bablo-hud:playerinfo:refresh")
AddEventHandler("bablo-hud:playerinfo:refresh", function()
    if not _G.BabloHudActive then return end
    BabloHud.PushPlayerInfoSnapshot()
end)

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
AddEventHandler("bablo-hud:playerLoaded", function()
    StartPlayerInfoModule()

    -- Deferred initial snapshot (3 s) so Framework data is fully loaded
    CreateThread(function()
        Wait(3000)
        if BabloHud and BabloHud.PushPlayerInfoSnapshot then
            BabloHud.PushPlayerInfoSnapshot()
        end
    end)
end)

AddEventHandler("bablo-hud:playerUnloaded", function()
    running = false
end)