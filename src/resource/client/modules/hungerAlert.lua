local NUI_ACTIONS = (BabloHud and BabloHud.Constants and BabloHud.Constants.NUI_ACTIONS) or {}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local alertActive       = false   -- true while the polling thread is running
local lastAlertTime     = 0       -- GetGameTimer() value of the last fired alert
local firedThresholds   = {       -- tracks which thresholds have already fired
    hunger = {},
    thirst = {},
}

-- ---------------------------------------------------------------------------
-- Config helpers
-- ---------------------------------------------------------------------------

-- Returns Config.HungerThirstAlert or nil
function GetAlertConfig()
    return Config and Config.HungerThirstAlert or nil
end

-- Returns true when the alert should be suppressed:
--   • HUD is suppressed
--   • Cinematic mode is active
--   • Player ped is dead or doesn't exist
function IsAlertSuppressed()
    if Bablo and Bablo.Hud and Bablo.Hud.suppressed then return true end
    if Bablo and Bablo.Cinematic and Bablo.Cinematic:Get() then return true end

    local ped = PlayerPedId()
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return true end

    return false
end

-- ---------------------------------------------------------------------------
-- PlayAlertSound(alertCfg)
-- Sends a playAlertSound NUI message if sound is enabled in config.
-- ---------------------------------------------------------------------------
function PlayAlertSound(alertCfg)
    local sound = alertCfg and alertCfg.sound
    if not sound or sound.enabled == false then return end

    SendNUIMessage({
        action = NUI_ACTIONS.PLAY_ALERT_SOUND or "playAlertSound",
        data   = {
            file   = sound.file   or "hungry.ogg",
            volume = sound.volume or 0.05,
        },
    })
end

-- ---------------------------------------------------------------------------
-- SendAlertNotification(localeKey, stat)
-- Fires a warning notification using localised strings for the given tier/stat.
-- localeKey: e.g. "critical", "low"
-- stat:      "hunger" or "thirst"
-- ---------------------------------------------------------------------------
function SendAlertNotification(localeKey, stat)
    if type(localeKey) ~= "string" or localeKey == "" then return end

    local base  = "notifications.hungerAlert." .. localeKey .. "." .. stat
    local title = Locale.t(base .. ".title")
    local body  = Locale.t(base .. ".body")

    exports["bablo-hud"]:Notify(title, body, "warning", 7500)
end

-- ---------------------------------------------------------------------------
-- BuildTierList(alertCfg)
-- Normalises Config.HungerThirstAlert.tiers into a sorted list of:
--   { threshold = number, localeKey = string }
-- Accepts both plain numbers and table entries in the tiers array.
-- Returns the list sorted ascending by threshold.
-- ---------------------------------------------------------------------------
function BuildTierList(alertCfg)
    local tiers = alertCfg and alertCfg.tiers
    if type(tiers) ~= "table" then return {} end

    local result = {}

    for _, entry in ipairs(tiers) do
        if type(entry) == "number" then
            result[#result + 1] = {
                threshold = entry,
                localeKey = "tier" .. tostring(entry),
            }
        elseif type(entry) == "table" then
            local threshold = tonumber(entry.threshold)
            if threshold then
                local key = entry.localeKey
                if not key then
                    key = "tier" .. tostring(threshold)
                end
                result[#result + 1] = {
                    threshold = threshold,
                    localeKey = tostring(key),
                }
            end
        end
    end

    table.sort(result, function(a, b) return a.threshold < b.threshold end)
    return result
end

-- ---------------------------------------------------------------------------
-- CheckStatThresholds(stat, value, tiers, alertCfg, now)
-- For each tier:
--   • If value is ABOVE the threshold → clear the fired flag (allow re-trigger
--     when the player drops below again).
--   • If value is AT OR BELOW the threshold and not yet fired → fire the alert
--     (notify + sound) provided the minInterval has elapsed.
-- ---------------------------------------------------------------------------
function CheckStatThresholds(stat, value, tiers, alertCfg, now)
    local fired = firedThresholds[stat]

    -- First pass: clear thresholds the player has recovered above
    for _, tier in ipairs(tiers) do
        if value > tier.threshold then
            fired[tier.threshold] = nil
        end
    end

    -- Second pass: fire alerts for thresholds the player is at or below
    for _, tier in ipairs(tiers) do
        if value <= tier.threshold then
            if not fired[tier.threshold] then
                fired[tier.threshold] = true

                local minInterval = tonumber(alertCfg.minInterval) or 2000
                if now - lastAlertTime >= minInterval then
                    SendAlertNotification(tier.localeKey, stat)
                    PlayAlertSound(alertCfg)
                    lastAlertTime = now
                end
            end
            return  -- only process the first matching (lowest active) tier
        end
    end
end

-- ---------------------------------------------------------------------------
-- RunAlertCheck()
-- Single poll cycle: reads hunger/thirst from Framework, checks all tiers.
-- ---------------------------------------------------------------------------
function RunAlertCheck()
    local alertCfg = GetAlertConfig()
    if not alertCfg or alertCfg.enabled == false then return end

    if not (Framework and type(Framework.getHunger) == "function"
                      and type(Framework.getThirst) == "function") then
        return
    end

    if IsAlertSuppressed() then return end

    local tiers = BuildTierList(alertCfg)
    if #tiers == 0 then return end

    local hunger = tonumber(Framework:getHunger()) or 100
    local thirst = tonumber(Framework:getThirst()) or 100
    local now    = GetGameTimer()

    CheckStatThresholds("hunger", hunger, tiers, alertCfg, now)
    CheckStatThresholds("thirst", thirst, tiers, alertCfg, now)
end

-- ---------------------------------------------------------------------------
-- ResetAlertState()
-- Called on player load and unload to clear all fired flags and the timer.
-- ---------------------------------------------------------------------------
function ResetAlertState()
    firedThresholds = { hunger = {}, thirst = {} }
    lastAlertTime   = 0
end

-- ---------------------------------------------------------------------------
-- StartAlertModule()
-- Starts the polling thread if not already running and config allows it.
-- ---------------------------------------------------------------------------
function StartAlertModule()
    if alertActive then return end

    local alertCfg = GetAlertConfig()
    if not alertCfg or alertCfg.enabled == false then return end

    alertActive = true
    Info("HungerThirstAlert module started")

    CreateThread(function()
        while alertActive do
            RunAlertCheck()

            local interval = tonumber(GetAlertConfig() and GetAlertConfig().checkInterval) or 5000
            interval = math.max(interval, 1000)
            Wait(interval)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
AddEventHandler("bablo-hud:playerLoaded", function()
    ResetAlertState()
    StartAlertModule()
end)

AddEventHandler("bablo-hud:playerUnloaded", function()
    alertActive = false
    ResetAlertState()
end)

-- ---------------------------------------------------------------------------
-- /testhungeralert [tier] [stat]
-- Fires a specific alert tier for testing without waiting for real stat values.
-- Usage: /testhungeralert critical hunger
-- ---------------------------------------------------------------------------
RegisterCommand("testhungeralert", function(source, args)
    local alertCfg = GetAlertConfig()
    if not alertCfg then
        Info("[hungerAlert] Config.HungerThirstAlert missing")
        return
    end

    local tierArg = (args[1] or "critical"):lower()
    local statArg = (args[2] or "hunger"):lower()

    if statArg ~= "hunger" and statArg ~= "thirst" then
        Info("[hungerAlert] unknown stat '" .. tostring(args[2]) .. "' (use hunger or thirst)")
        return
    end

    -- Build list of valid locale keys from config tiers
    local availableKeys = {}
    local matchedTier   = nil

    if type(alertCfg.tiers) == "table" then
        for _, entry in ipairs(alertCfg.tiers) do
            if type(entry) == "table" and type(entry.localeKey) == "string" then
                availableKeys[#availableKeys + 1] = entry.localeKey
                if entry.localeKey:lower() == tierArg then
                    matchedTier = entry
                end
            end
        end
    end

    if not matchedTier then
        Info(string.format("[hungerAlert] unknown tier '%s' (available: %s)",
            tierArg, table.concat(availableKeys, ", ")))
        return
    end

    Info(string.format("[hungerAlert] test fire: tier=%s stat=%s", matchedTier.localeKey, statArg))
    SendAlertNotification(matchedTier.localeKey, statArg)
    PlayAlertSound(alertCfg)
end, false)

TriggerEvent("chat:addSuggestion", "/testhungeralert",
    "Fire a hunger/thirst alert for testing (sound + notify).", {
        { name = "tier", help = "low | medium | critical (default: critical)" },
        { name = "stat", help = "hunger | thirst (default: hunger)" },
    }
)