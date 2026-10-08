local NUI_ACTIONS = (BabloHud and BabloHud.Constants and BabloHud.Constants.NUI_ACTIONS) or {}

-- ---------------------------------------------------------------------------
-- Config helpers
-- ---------------------------------------------------------------------------

function IsCinematicEnabled()
    return Config and Config.Cinematic and Config.Cinematic.enabled == true
end

-- Returns Config.Cinematic[key], or defaultValue if absent
function GetCinematicConfig(key, defaultValue)
    if Config and Config.Cinematic and Config.Cinematic[key] ~= nil then
        return Config.Cinematic[key]
    end
    return defaultValue
end

-- ---------------------------------------------------------------------------
-- Bablo.Cinematic state object
-- ---------------------------------------------------------------------------
Bablo = Bablo or {}

Bablo.Cinematic = {
    active = false,
}

-- Ticker handle for the per-frame HideHudAndRadarThisFrame call
local hideHudTickerId = nil

-- Sends the current cinematic state to the NUI layer
function SendCinematicState()
    SendNUIMessage({
        action = NUI_ACTIONS.SET_CINEMATIC or "setCinematic",
        data   = {
            active           = Bablo.Cinematic.active,
            barHeightPercent = GetCinematicConfig("barHeightPercent", 12),
            barColor         = GetCinematicConfig("barColor", "#000000"),
            transitionMs     = GetCinematicConfig("transitionMs", 700),
            hideHud          = GetCinematicConfig("hideHud", true) ~= false,
        },
    })
end

-- Starts or stops the per-frame HUD hide ticker based on cinematic state
function SyncCinematicHudHide()
    local shouldHide = Bablo.Cinematic.active and GetCinematicConfig("hideGameHud", true) ~= false

    if shouldHide then
        if not hideHudTickerId then
            if Bablo.Ticker then
                hideHudTickerId = Bablo.Ticker:register(function()
                    HideHudAndRadarThisFrame()
                end)
            end
        end
    else
        if hideHudTickerId then
            if Bablo.Ticker then
                Bablo.Ticker:unregister(hideHudTickerId)
            end
            hideHudTickerId = nil
        end
    end
end

-- Sets cinematic mode on or off. No-ops if state hasn't changed or if disabled in config.
function Bablo.Cinematic:Set(active)
    if not IsCinematicEnabled() then return end

    local newActive = active and true or false
    if newActive == self.active then return end

    self.active = newActive

    -- Update BabloHudCinematic global (controls minimap suppression)
    local hideMinimap = self.active and GetCinematicConfig("hideMinimap", true) ~= false
    _G.BabloHudCinematic = hideMinimap or nil

    SyncCinematicHudHide()

    if _G.BabloHudRecomputeRadar then
        _G.BabloHudRecomputeRadar()
    end

    SendCinematicState()
end

function Bablo.Cinematic:Toggle()
    self:Set(not self.active)
end

function Bablo.Cinematic:Get()
    return self.active
end

-- ---------------------------------------------------------------------------
-- Command registration
-- ---------------------------------------------------------------------------
if IsCinematicEnabled() then
    local command = GetCinematicConfig("command", "cinematic")
    RegisterCommand(command, function()
        Bablo.Cinematic:Toggle()
    end, false)
end

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------
exports("SetCinematic",      function(active) Bablo.Cinematic:Set(active) end)
exports("ToggleCinematic",   function()       Bablo.Cinematic:Toggle()    end)
exports("IsCinematicActive", function()       return Bablo.Cinematic:Get() end)
