Bablo = Bablo or {}

-- Ticker: runs registered callbacks every frame on a shared thread
-- ⚠️ Minimap is a global injected by an external resource — never assigned here
local tickerCallbacks = {}
local tickerRunning   = false
local nextTickerId    = 1
local currentFrame    = 0

function StartTickerThread()
    if tickerRunning then return end
    if next(tickerCallbacks) == nil then return end

    tickerRunning = true
    CreateThread(function()
        while next(tickerCallbacks) ~= nil do
            currentFrame = currentFrame + 1
            for _, callback in pairs(tickerCallbacks) do
                callback(currentFrame)
            end
            Wait(0)
        end
        tickerRunning = false
    end)
end

Bablo.Ticker = {
    frame = function()
        return currentFrame
    end,

    register = function(_, callback)
        if type(callback) ~= "function" then return nil end
        local id = nextTickerId
        nextTickerId = nextTickerId + 1
        tickerCallbacks[id] = callback
        StartTickerThread()
        return id
    end,

    unregister = function(_, id)
        if id then
            tickerCallbacks[id] = nil
        end
    end,
}

function NewEmptyMinimapAnchor()
    return {
        x        = 0, y        = 0,
        width    = 0, height   = 0,
        leftPx   = 0, topPx    = 0,
        widthPx  = 0, heightPx = 0,
        bottomPx = 0, rawX     = 0,
        rawY     = 0, deltaX   = 0,
        deltaY   = 0,
    }
end

function GetMinimapDelta()
    if Minimap then
        return Minimap:getOffset()
    end
    return 0.0, 0.0
end

function SetMinimapDelta(deltaX, deltaY)
    if Minimap then
        Minimap:setOffset(deltaX, deltaY)
    end
end

function GetMinimapAnchor()
    if not Minimap then
        return NewEmptyMinimapAnchor()
    end

    local anchor     = Minimap:getAnchor()
    local resX, resY = GetActualScreenResolution()

    return {
        x        = anchor.xPct,
        y        = anchor.yPct,
        width    = anchor.widthPct,
        height   = anchor.heightPct,
        leftPx   = anchor.leftPx,
        topPx    = anchor.topPx,
        widthPx  = anchor.widthPx,
        heightPx = anchor.heightPx,
        bottomPx = anchor.bottomPx,
        rawX     = anchor.rawX,
        rawY     = anchor.rawY,
        deltaX   = anchor.offsetX,
        deltaY   = anchor.offsetY,
        gameResX = resX,
        gameResY = resY,
    }
end

function ApplyMinimapPosition(refreshBigmap)
    if Minimap then
        Minimap:applyPosition(refreshBigmap)
    end
end

function RefreshMinimap()
    if Minimap then
        Minimap:refresh()
    end
end

function SendMinimapPosition(sendDefault)
    local anchor  = GetMinimapAnchor()
    local actions = (BabloHud and BabloHud.Constants and BabloHud.Constants.NUI_ACTIONS) or {}

    SendNUIMessage({
        action = actions.SET_MINIMAP_ANCHOR or "setMinimapAnchor",
        data   = anchor,
    })

    if sendDefault then
        SendNUIMessage({
            action = actions.SET_DEFAULT_MINIMAP_ANCHOR or "setDefaultMinimapAnchor",
            data   = anchor,
        })
    end
end

exports("getAnchor",       GetMinimapAnchor)
exports("setRadarVisible", SetRadarVisible)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(100) end
    Wait(1000)
    SendMinimapPosition(true)
    Info("Minimap utils initialized")
end)
