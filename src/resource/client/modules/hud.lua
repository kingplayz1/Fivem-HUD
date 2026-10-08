local NUI_ACTIONS = (BabloHud and BabloHud.Constants and BabloHud.Constants.NUI_ACTIONS) or {}

-- Known component names — used to validate SetComponentVisible / IsComponentVisible calls
local VALID_COMPONENTS = {
    status        = true,
    speedometer   = true,
    playerInfo    = true,
    minimap       = true,
    voice         = true,
    notifications = true,
    progressBar   = true,
    controlHints  = true,
}

-- ---------------------------------------------------------------------------
-- Bablo.Hud state object
-- ---------------------------------------------------------------------------
Bablo = Bablo or {}

Bablo.Hud = {
    suppressed        = false,
    hiddenComponents  = {},
}

-- ---------------------------------------------------------------------------
-- Internal: sync minimap suppression globals after any visibility change
-- ---------------------------------------------------------------------------
function SyncMinimapHiddenGlobal()
    local hidden = Bablo.Hud.suppressed or (Bablo.Hud.hiddenComponents.minimap == true)
    _G.BabloHudMinimapHidden = hidden or nil

    if _G.BabloHudRecomputeRadar then
        _G.BabloHudRecomputeRadar()
    end
end

-- Internal: tells NUI the current suppression state
function SendHudSuppressedState()
    SendNUIMessage({
        action = NUI_ACTIONS.SET_HUD_SUPPRESSED or "setHudSuppressed",
        data   = Bablo.Hud.suppressed,
    })
end

-- Internal: tells NUI a component's visibility
function SendComponentVisibility(component, visible)
    SendNUIMessage({
        action = NUI_ACTIONS.SET_COMPONENT_VISIBLE or "setComponentVisible",
        data   = { component = component, visible = visible and true or false },
    })
end

-- ---------------------------------------------------------------------------
-- Bablo.Hud:SetVisible(visible)
-- No-ops when state is unchanged.
-- ---------------------------------------------------------------------------
function Bablo.Hud:SetVisible(visible)
    local newSuppressed = not visible
    if newSuppressed == self.suppressed then return end

    self.suppressed            = newSuppressed
    _G.BabloHudSuppressed      = self.suppressed

    SendHudSuppressedState()
    SyncMinimapHiddenGlobal()
end

function Bablo.Hud:Toggle()
    self:SetVisible(self.suppressed)   -- suppressed=true means hidden, so toggling: show when suppressed
end

function Bablo.Hud:IsVisible()
    return not self.suppressed
end

-- ---------------------------------------------------------------------------
-- Bablo.Hud:SetComponentVisible(component, visible)
-- ---------------------------------------------------------------------------
function Bablo.Hud:SetComponentVisible(component, visible)
    if type(component) ~= "string" or not VALID_COMPONENTS[component] then
        return false
    end

    self.hiddenComponents[component] = (not visible) or nil
    SendComponentVisibility(component, visible)

    if component == "minimap" then
        SyncMinimapHiddenGlobal()
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Bablo.Hud:IsComponentVisible(component)
-- Checks: not force-hidden, then defers to BabloHud.Settings.isComponentEnabled
-- ---------------------------------------------------------------------------
function Bablo.Hud:IsComponentVisible(component)
    if type(component) ~= "string" or not VALID_COMPONENTS[component] then
        return false
    end

    if self.hiddenComponents[component] == true then return false end

    if BabloHud and BabloHud.Settings and type(BabloHud.Settings.isComponentEnabled) == "function" then
        if BabloHud.Settings.isComponentEnabled(component) == false then
            return false
        end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------
exports("ShowHud", function()
    Bablo.Hud:SetVisible(true)
end)

exports("HideHud", function()
    Bablo.Hud:SetVisible(false)
end)

exports("ToggleHud", function()
    Bablo.Hud:Toggle()
end)

exports("IsHudVisible", function()
    return Bablo.Hud:IsVisible()
end)

exports("SetComponentVisible", function(component, visible)
    return Bablo.Hud:SetComponentVisible(component, visible)
end)

exports("IsComponentVisible", function(component)
    return Bablo.Hud:IsComponentVisible(component)
end)
