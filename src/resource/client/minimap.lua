-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local ASPECT_RATIO_16_9  = 1.7777777910233   -- canonical 16:9 threshold for superwide detection
local MINIMAP_OFFSET_X   = -7.0              -- default X offset (resolution pixels)
local MINIMAP_OFFSET_Y   = 21.0             -- default Y offset (resolution pixels)

-- ---------------------------------------------------------------------------
-- math.round extension
-- ---------------------------------------------------------------------------
function math.round(value, decimals)
    if decimals then
        local factor = 10 ^ decimals
        return math.floor(value * factor + 0.5) / factor
    end
    return math.floor(value + 0.5)
end

-- ---------------------------------------------------------------------------
-- Coordinate conversion utilities
-- All functions convert between four coordinate spaces:
--   Resolution  = raw pixel coords from GetActualScreenResolution / GetActiveScreenResolution
--   Screen      = normalised 0–1 coords used by GTA natives
--   Scaleform   = 1280×720 virtual canvas used by scaleform movies
-- ---------------------------------------------------------------------------

-- Resolution pixels (active) → Scaleform 1280×720
function ConvertResolutionCoordsToScaleformCoords(x, y)
    local w, h = GetActiveScreenResolution()
    return vector2(x / w * 1280, y / h * 720)
end

-- Scaleform 1280×720 → Resolution pixels (active)
function ConvertScaleformCoordsToResolutionCoords(x, y)
    local w, h = GetActiveScreenResolution()
    return vector2(x / 1280 * w, y / 720 * h)
end

-- Screen 0–1 → Scaleform 1280×720
function ConvertScreenCoordsToScaleformCoords(x, y)
    return vector2(x * 1280, y * 720)
end

-- Scaleform 1280×720 → Screen 0–1
function ConvertScaleformCoordsToScreenCoords(x, y)
    return vector2(x / 1280, y / 720)
end

-- Resolution pixels (actual/physical) → Screen 0–1
function ConvertResolutionCoordsToScreenCoords(x, y)
    local w, h = GetActualScreenResolution()
    return vector2(x / w, y / h)
end

-- Screen 0–1 → Resolution pixels (actual/physical), rounded
function ConvertScreenCoordsToResolutionCoords(x, y)
    local w, h = GetActualScreenResolution()
    return vector2(math.floor(x * w + 0.5), math.floor(y * h + 0.5))
end

-- Resolution pixels (active) → Scaleform size  (same math as Coords variant; kept as separate global for clarity)
function ConvertResolutionSizeToScaleformSize(w, h)
    local sw, sh = GetActiveScreenResolution()
    return vector2(w / sw * 1280, h / sh * 720)
end

-- Scaleform size → Resolution pixels (active)
function ConvertScaleformSizeToResolutionSize(w, h)
    local sw, sh = GetActiveScreenResolution()
    return vector2(w / 1280 * sw, h / 720 * sh)
end

-- Screen 0–1 size → Scaleform size
function ConvertScreenSizeToScaleformSize(w, h)
    return vector2(w * 1280, h * 720)
end

-- Resolution pixels (actual) → Screen 0–1 size
function ConvertScaleformSizeToScreenSize(w, h)
    local sw, sh = GetActualScreenResolution()
    return vector2(w / sw, h / sh)
end

-- Resolution pixels (actual) → Screen 0–1 size  (same as above; separate global kept for API surface)
function ConvertResolutionSizeToScreenSize(w, h)
    local sw, sh = GetActualScreenResolution()
    return vector2(w / sw, h / sh)
end

-- ---------------------------------------------------------------------------
-- Screen geometry helpers
-- ---------------------------------------------------------------------------

-- Returns true when the physical aspect ratio exceeds 16:9
function IsSuperWideScreen()
    return GetAspectRatio(true) > ASPECT_RATIO_16_9
end

-- Returns true when the display is wider than 3:2 but not driven by physical
-- resolution alone (i.e. the active/render aspect is wide, not just the monitor)
function GetWideScreen()
    local minRatio  = 1.5
    local activeAspect = GetAspectRatio(false)
    local physW, physH = GetActualScreenResolution()
    if physW / physH <= minRatio then return false end
    return minRatio < activeAspect
end

-- Adjusts normalised screen-space x/y for superwide monitors so elements
-- stay centred within the 16:9 pillarbox area.
function AdjustForSuperWidescreen(x, width)
    if not IsSuperWideScreen() then return x, width end
    local ratio   = ASPECT_RATIO_16_9 / GetAspectRatio(false)
    local offsetX = (0.5 - x) * ratio
    return 0.5 - offsetX, width * ratio
end

-- Returns the safe-zone boundary in screen-space (left, top, right, bottom).
-- When adjustSuperWide is true, horizontal bounds are narrowed for superwide.
function GetMinSafeZone(safeZoneOverride, adjustSuperWide)
    local safe   = GetSafeZoneSize()
    local safeSz = GetSafeZoneSize()

    if safeZoneOverride < 1.0 then
        safe = 1.0 - ((1.0 - safe) + (1.0 - safeZoneOverride))
    end

    local physW, physH = GetActualScreenResolution()
    local marginW = physW * safe
    local marginH = physH * safeSz
    local padX    = (physW - marginW) * 0.5
    local padY    = (physH - marginH) * 0.5

    local left   = math.ceil(padX)  / physW
    local top    = math.ceil(padY)  / physH
    local right  = math.floor(physW - padX) / physW
    local bottom = math.floor(physH - padY) / physH

    if adjustSuperWide and IsSuperWideScreen() then
        local ratio       = ASPECT_RATIO_16_9 / GetAspectRatio(true)
        local pillarWidth = physW * ratio
        local pillarPadX  = (physW - pillarWidth) * 0.5 / physW
        left  = left  + pillarPadX
        right = right - pillarPadX
    end

    return left, top, right, bottom
end

-- Same as GetMinSafeZone but applies an additional horizontal correction to
-- account for the difference between the current aspect ratio and 16:9 when
-- used with scaleform movies.
function GetMinSafeZoneForScaleformMovies(safeZoneOverride)
    local left, top, right, bottom = GetMinSafeZone(safeZoneOverride)
    local diff = GetDifferenceFrom_16_9_ToCurrentAspectRatio()
    return left + diff, top, right - diff, bottom
end

-- Returns how much extra horizontal space exists between 16:9 and the current
-- aspect ratio (accounting for safe zone), expressed in screen-space units.
-- Returns 0 for superwide screens (where the minimap is already letterboxed).
function GetDifferenceFrom_16_9_ToCurrentAspectRatio()
    if IsSuperWideScreen() then return 0.0 end

    local physW, physH = GetActualScreenResolution()
    local physAspect   = physW / physH
    local safeMargin   = (1.0 - GetSafeZoneSize()) * 0.5

    local targetWidth  = safeMargin * ASPECT_RATIO_16_9 - physAspect
    local normalised   = 1.0 - (physAspect / ASPECT_RATIO_16_9)
    return normalised - targetWidth * 0.5
end

-- Normalises a horizontal-alignment string to "L", "R", or "C" (defaults to "L").
function GetFormatFromString(align)
    local s = align and align:upper() or ""
    if s == "C" then return "C"
    elseif s == "R" then return "R"
    else return "L" end
end

-- Adjusts a 16:9-normalised position + size for the current aspect ratio.
-- align: "L", "R", or "C"  (horizontal anchor)
-- x, y: position; w, h: size (all in screen 0–1 normalised to 16:9)
-- Returns two vector2: adjusted position, adjusted size.
function AdjustNormalized16_9ValuesForCurrentAspectRatio(align, x, y, w, h)
    local activeAspect = GetAspectRatio(false)
    if IsSuperWideScreen() then activeAspect = ASPECT_RATIO_16_9 end

    local ratio = ASPECT_RATIO_16_9 / activeAspect
    local delta = 1.0 - ratio
    if math.abs(delta) < 0.001 then delta = 0.0 end

    w = w * ratio

    if align == "C" then
        x = x * ratio + delta * 0.5
    elseif align == "R" then
        x = x * ratio + delta
    else -- "L"
        x = x * ratio
    end

    x, h = AdjustForSuperWidescreen(x, h)
    return vector2(x, y), vector2(w, h)
end

-- Calculates the top-left position for a HUD element given its size and
-- horizontal/vertical anchor strings ("L"/"R"/"C" and "T"/"B"/"C").
function CalculateHudPosition(offset, size, alignH, alignV)
    local left, top, right, bottom = GetMinSafeZone(1.0)
    local safeMin = vector2(left,  top)
    local safeMax = vector2(right, bottom)
    local pos     = vector2(0.0, 0.0)

    if alignH == "L" then
        pos = vector2(safeMin.x, pos.y)
    elseif alignH == "R" then
        pos = vector2(safeMax.x - size.x, pos.y)
    elseif alignH == "C" then
        pos = vector2((safeMin.x + safeMax.x - size.x) * 0.5, pos.y)
    end

    if alignV == "T" then
        pos = vector2(pos.x, safeMin.y)
    elseif alignV == "B" then
        pos = vector2(pos.x, safeMax.y - size.y)
    elseif alignV == "C" then
        pos = vector2(pos.x, (safeMin.y + safeMax.y - size.y) * 0.5)
    end

    return pos + offset
end

-- Returns a rect table with all computed positions for a HUD element anchor.
-- alignH/alignV: "L"/"R"/"C" and "T"/"B"/"C"
-- x, y, w, h: 16:9-normalised values
function GetAnchorScreenCoords(alignH, alignV, x, y, w, h)
    local pos, size = AdjustNormalized16_9ValuesForCurrentAspectRatio(alignH, x, y, w, h)
    local topLeft   = CalculateHudPosition(pos, size, alignH, alignV)

    local rect = {
        Width   = size.x,
        Height  = size.y,
        LeftX   = topLeft.x,
        TopY    = topLeft.y,
        RightX  = topLeft.x + size.x,
        BottomY = topLeft.y + size.y,
        CenterX = topLeft.x + size.x * 0.5,
        CenterY = topLeft.y + size.y * 0.5,
        x       = topLeft.x,
        y       = topLeft.y,
    }
    return rect
end

-- Same as GetAnchorScreenCoords but accepts resolution-pixel inputs instead
-- of screen-normalised ones.
function GetAnchorResolutionCoords(alignH, alignV, xPx, yPx, wPx, hPx)
    local screenPos  = ConvertResolutionCoordsToScreenCoords(xPx, yPx)
    local screenSize = ConvertResolutionSizeToScreenSize(wPx, hPx)
    return GetAnchorScreenCoords(alignH, alignV, screenPos.x, screenPos.y, screenSize.x, screenSize.y)
end

-- Simplified CalculateHudPosition variant that skips the 16:9 normalisation
-- step; used internally when coords are already in screen space.
function CalculateRawHudRect(alignH, alignV, xScreen, yScreen, wScreen, hScreen)
    local size    = vector2(wScreen, hScreen)
    local pos     = CalculateHudPosition(vector2(xScreen, yScreen), size, alignH, alignV)
    return {
        LeftX   = pos.x,
        TopY    = pos.y,
        Width   = wScreen,
        Height  = hScreen,
        RightX  = pos.x + wScreen,
        BottomY = pos.y + hScreen,
    }
end

-- ---------------------------------------------------------------------------
-- Minimap style shape data
-- Each style has three layers: main, mask, blur.
-- Values are screen-space offsets/sizes relative to the anchor.
-- ---------------------------------------------------------------------------
local MINIMAP_STYLES = {
    square = {
        main = { x = 0.0,   y = -0.047, w = 0.1638, h = 0.183 },
        mask = { x = 0.0,   y =  0.0,   w = 0.128,  h = 0.2   },
        blur = { x = -0.01, y =  0.025, w = 0.262,  h = 0.3   },
    },
    circle = {
        main = { x = 0.0,   y = -0.047, w = 0.1638, h = 0.183 },
        mask = { x = 0.0,   y = -0.047, w = 0.1638, h = 0.183 },
        blur = { x = -0.01, y =  0.025, w = 0.262,  h = 0.3   },
    },
    -- ⚠️ This third style (wider map) has no explicit name in the source.
    --    It is referenced via the bigmap component only (L6_1 in the original).
    --    Named "wide" here for clarity — verify against config if needed.
    wide = {
        main = { x = 0.0,   y = -0.047, w = 0.364,  h = 0.460416666 },
        mask = { x = 0.0,   y =  0.0,   w = 0.176,  h = 0.395       },
        blur = { x = -0.01, y =  0.025, w = 0.262,  h = 0.464       },
    },
}

-- Texture dict name lookup for each style
local STYLE_TEXTURE_DICT = {
    circle = "circlemap",
    square = "squaremap",
}

-- ---------------------------------------------------------------------------
-- Minimap object
-- ---------------------------------------------------------------------------
Minimap = {
    offsetX             = MINIMAP_OFFSET_X,
    offsetY             = MINIMAP_OFFSET_Y,
    isInitialized       = false,
    overlayHideLockStarted = false,
    currentStyle        = "square",
    reapplyPending      = false,
    scaleform           = nil,
}

-- Returns the style data table for a given style name (falls back to "square")
function GetMinimapStyleData(styleName)
    return MINIMAP_STYLES[styleName or "square"] or MINIMAP_STYLES.square
end

-- Returns the texture dict name for the given style (falls back to squaremap)
function GetStyleTextureName(styleName)
    return STYLE_TEXTURE_DICT[styleName or "square"] or STYLE_TEXTURE_DICT.square
end

-- Computes an X-axis correction for screens wider than 16:9 that use an
-- active resolution ratio rather than physical (used for component placement).
function GetWidescreenMinimapXCorrection()
    local RATIO_16_9 = 1.7777777777777777
    local activeAspect = GetAspectRatio(false)
    if RATIO_16_9 >= activeAspect then return 0.0 end

    local w, h = GetActiveScreenResolution()
    local physAspect = w / h
    if RATIO_16_9 < physAspect then
        return (RATIO_16_9 - physAspect) / 3.6 - 0.008
    end
    return 0.0
end

-- Returns Config.DefaultSettings.minimap (or nil)
function GetMinimapConfig()
    return Config and Config.DefaultSettings and Config.DefaultSettings.minimap or nil
end

-- Returns the effective minimap scale factor.
-- Priority: BabloHudMinimapSize global > Config.DefaultSettings.minimap.size > 1.0
function GetMinimapScale()
    if type(_G.BabloHudMinimapSize) == "number" and _G.BabloHudMinimapSize > 0 then
        return _G.BabloHudMinimapSize
    end
    local cfg = GetMinimapConfig()
    if cfg then
        local size = tonumber(cfg.size)
        if size and size > 0 then return size end
    end
    return 1.0
end

-- Sets the north blip alpha based on whether the minimap config shows it
function ApplyNorthIndicatorVisibility()
    local blip = GetNorthRadarBlip()
    if not blip or not DoesBlipExist(blip) then return end

    local cfg   = GetMinimapConfig()
    local alpha = (cfg and cfg.showNorthIndicator) and 255 or 0
    SetBlipAlpha(blip, alpha)
end

-- ---------------------------------------------------------------------------
-- Blip hide/restore (used while edit mode is active)
-- ---------------------------------------------------------------------------
local savedBlipAlphas = {}

function HideAllBlips()
    for blipType = 0, 826 do
        local blip = GetFirstBlipInfoId(blipType)
        while DoesBlipExist(blip) do
            if savedBlipAlphas[blip] == nil then
                savedBlipAlphas[blip] = GetBlipAlpha(blip)
            end
            SetBlipAlpha(blip, 0)
            blip = GetNextBlipInfoId(blipType)
        end
    end

    local playerBlip = GetMainPlayerBlipId()
    if playerBlip and DoesBlipExist(playerBlip) then
        SetBlipAlpha(playerBlip, 0)
    end

    local northBlip = GetNorthRadarBlip()
    if northBlip and DoesBlipExist(northBlip) then
        SetBlipAlpha(northBlip, 0)
    end
end

function RestoreAllBlips()
    for blipType = 0, 826 do
        local blip = GetFirstBlipInfoId(blipType)
        while DoesBlipExist(blip) do
            local saved = savedBlipAlphas[blip]
            SetBlipAlpha(blip, saved ~= nil and saved or 255)
            blip = GetNextBlipInfoId(blipType)
        end
    end

    local playerBlip = GetMainPlayerBlipId()
    if playerBlip and DoesBlipExist(playerBlip) then
        SetBlipAlpha(playerBlip, 255)
    end

    savedBlipAlphas = {}
end

-- ---------------------------------------------------------------------------
-- Edit mode (NUI callback)
-- Hides all blips while the edit panel is open, restores when closed.
-- ---------------------------------------------------------------------------
local editModeActive = false

RegisterNUICallback("setEditMode", function(data, cb)
    local requestedActive = (data and data.active == true)

    if requestedActive == editModeActive then
        cb({ success = true })
        return
    end

    editModeActive = requestedActive

    if editModeActive then
        CreateThread(function()
            while editModeActive do
                HideAllBlips()
                Wait(400)
            end
            RestoreAllBlips()
            ApplyNorthIndicatorVisibility()
        end)
    end

    cb({ success = true })
end)

-- ---------------------------------------------------------------------------
-- Minimap:setOffset / resetOffset / getOffset
-- ---------------------------------------------------------------------------
function Minimap:setOffset(x, y)
    self.offsetX = x or 0.0
    self.offsetY = y or 0.0
end

function Minimap:resetOffset()
    self.offsetX = MINIMAP_OFFSET_X
    self.offsetY = MINIMAP_OFFSET_Y
end

function Minimap:getOffset()
    return self.offsetX, self.offsetY
end

-- ---------------------------------------------------------------------------
-- Minimap:getAnchor
-- Returns a rich table describing the minimap's current screen position in
-- multiple coordinate spaces (used by utils.lua → GetMinimapAnchor).
-- ---------------------------------------------------------------------------
function Minimap:getAnchor()
    local style      = GetMinimapStyleData(self.currentStyle)
    local main       = style.main
    local widthScale = (GetMinimapConfig() and GetMinimapConfig().widthScale) or 0.88
    local offsetPx   = ConvertResolutionCoordsToScreenCoords(self.offsetX, self.offsetY)
    local xCorrect   = GetWidescreenMinimapXCorrection()
    local scale      = GetMinimapScale()

    local x = (main.x + xCorrect + offsetPx.x) * scale
    local y = (main.y - offsetPx.y) * scale
    local w = main.w * scale * widthScale
    local h = main.h * scale

    local rect     = GetAnchorScreenCoords("L", "B", x, y, w, h)
    local topLeft  = ConvertScreenCoordsToResolutionCoords(rect.x, rect.y)
    local botRight = ConvertScreenCoordsToResolutionCoords(rect.RightX, rect.BottomY)

    local widthPx  = math.max(0, botRight.x - topLeft.x)
    local heightPx = math.max(0, botRight.y - topLeft.y)
    local leftPx   = math.max(0, topLeft.x)
    local topPx    = math.max(0, topLeft.y)

    return {
        x         = rect.x,
        y         = rect.y,
        width     = rect.Width,
        height    = rect.Height,
        xPct      = rect.x       * 100,
        yPct      = rect.y       * 100,
        widthPct  = rect.Width   * 100,
        heightPct = rect.Height  * 100,
        leftPx    = leftPx,
        topPx     = topPx,
        widthPx   = widthPx,
        heightPx  = heightPx,
        bottomPx  = topPx + heightPx,
        rawX      = rect.x,
        rawY      = rect.y,
        offsetX   = self.offsetX,
        offsetY   = self.offsetY,
    }
end

-- ---------------------------------------------------------------------------
-- Minimap:applyClipType
-- Sets the native clip mask to circle (1) or square (0).
-- ---------------------------------------------------------------------------
function Minimap:applyClipType()
    SetMinimapClipType(self.currentStyle == "circle" and 1 or 0)
end

-- ---------------------------------------------------------------------------
-- Minimap:enforceHiddenOverlays
-- Hides health/armour bars and the satnav arrow via scaleform calls.
-- ---------------------------------------------------------------------------
function Minimap:enforceHiddenOverlays()
    if not self.scaleform or not HasScaleformMovieLoaded(self.scaleform) then return end

    BeginScaleformMovieMethod(self.scaleform, "SETUP_HEALTH_ARMOUR")
    ScaleformMovieMethodAddParamInt(3)
    EndScaleformMovieMethod()

    BeginScaleformMovieMethod(self.scaleform, "HIDE_SATNAV")
    EndScaleformMovieMethod()
end

-- ---------------------------------------------------------------------------
-- MoveMinimapComponent
-- Positions the six native minimap/bigmap scaleform layers.
-- align / valign: "L"/"B" etc.  deltaX/deltaY: offset  scale: size multiplier
-- refreshBigmap: when true, pulses SetBigmapActive and hides long-range blips.
-- ---------------------------------------------------------------------------
function MoveMinimapComponent(alignH, alignV, deltaX, deltaY, scale, refreshBigmap)
    local miniStyle  = GetMinimapStyleData(Minimap.currentStyle)
    local wideStyle  = MINIMAP_STYLES.wide
    local xCorrect   = GetWidescreenMinimapXCorrection()
    local widthScale = (GetMinimapConfig() and GetMinimapConfig().widthScale) or 0.88

    -- Helper: call SetMinimapComponentPosition for one layer
    local function PlaceLayer(component, layer, xOff)
        local cx = (layer.x + xOff + deltaX) * scale
        local cy = (layer.y + deltaY) * scale
        local cw = layer.w * scale * (widthScale or 1.0)
        local ch = layer.h * scale
        -- bigmap layers don't use widthScale
        if component == "bigmap" or component == "bigmap_mask" or component == "bigmap_blur" then
            cw = layer.w * scale
        end
        SetMinimapComponentPosition(component, alignH, alignV, cx, cy, cw, ch)
    end

    PlaceLayer("minimap",      miniStyle.main, xCorrect)
    PlaceLayer("minimap_mask", miniStyle.mask, xCorrect)
    PlaceLayer("minimap_blur", miniStyle.blur, xCorrect)
    PlaceLayer("bigmap",      wideStyle.main, xCorrect)
    PlaceLayer("bigmap_mask", wideStyle.mask, xCorrect)
    PlaceLayer("bigmap_blur", wideStyle.blur, xCorrect)

    if refreshBigmap then
        SetBigmapActive(true,  false)
        Wait(50)
        SetBigmapActive(false, false)

        local cfg = GetMinimapConfig()
        if not (cfg and cfg.showLongRangeBlips) then
            -- Suppress long-range blips for a brief window (8 × 50 ms)
            CreateThread(function()
                for _ = 1, 8 do
                    SetMinimapComponent(2, false, 0)
                    Wait(50)
                end
            end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Minimap:applyPosition
-- Full position update: resets scaleform align, converts offset, moves all
-- components, optionally refreshes bigmap and enforces hidden overlays.
-- ---------------------------------------------------------------------------
function Minimap:applyPosition(refreshBigmap)
    ResetScriptGfxAlign()
    local offsetScreen = ConvertResolutionCoordsToScreenCoords(self.offsetX, self.offsetY)
    self:applyClipType()
    MoveMinimapComponent("L", "B", offsetScreen.x, -offsetScreen.y, GetMinimapScale(), refreshBigmap)
    if refreshBigmap then self:applyClipType() end
    self:enforceHiddenOverlays()
end

-- Minimap:refresh — shorthand for applyPosition with bigmap refresh
function Minimap:refresh()
    self:applyPosition(true)
end

-- ---------------------------------------------------------------------------
-- SetRadarVisible — thin wrapper kept as a named global
-- ---------------------------------------------------------------------------
function SetRadarVisible(visible)
    DisplayRadar(visible)
end

-- ---------------------------------------------------------------------------
-- Texture loading helpers
-- ---------------------------------------------------------------------------

-- Loads a texture dict, retrying every 50 ms up to ~8 seconds (160 attempts).
-- Re-requests every 40 attempts. Returns true if loaded, false if timed out.
function LoadTextureDictWithTimeout(dictName)
    if HasStreamedTextureDictLoaded(dictName) then return true end

    RequestStreamedTextureDict(dictName, false)
    for attempt = 0, 159 do
        if HasStreamedTextureDictLoaded(dictName) then return true end
        if attempt % 40 == 0 then
            RequestStreamedTextureDict(dictName, false)
        end
        Wait(50)
    end
    return HasStreamedTextureDictLoaded(dictName)
end

-- Ensures "circlemap" is loaded, with a 250 ms initial wait if needed.
function EnsureCirclemapLoaded()
    if HasStreamedTextureDictLoaded("circlemap") then return true end
    Wait(250)
    RequestStreamedTextureDict("circlemap", false)
    return LoadTextureDictWithTimeout("circlemap")
end

-- Applies the custom radar mask texture for circle/other styles.
-- Respects Config.DefaultSettings.minimap.useCustomMask (skips if false).
-- ⚠️ CirclemapTextureName is an optional global set by an external resource.
function ApplyMinimapMask(textureDictName)
    local cfg = GetMinimapConfig()
    if cfg and cfg.useCustomMask == false then return end

    local maskTexture = "radarmasksm"
    if textureDictName == "circlemap" and CirclemapTextureName then
        maskTexture = CirclemapTextureName
    end

    RemoveReplaceTexture("platform:/textures/graphics", "radarmasksm")
    RemoveReplaceTexture("platform:/textures/graphics", "radarmask1g")
    AddReplaceTexture("platform:/textures/graphics", "radarmasksm", textureDictName, maskTexture)
    AddReplaceTexture("platform:/textures/graphics", "radarmask1g",  textureDictName, maskTexture)

    if textureDictName == "circlemap" then
        Trace("Circlemap mask applied (texture: %s)", maskTexture)
    end
end

-- ---------------------------------------------------------------------------
-- Internal: shared texture loading logic for LoadMap / SwitchMap / reapply
-- Loads the texture dict for the requested style, falls back to square on
-- failure. Returns the resolved texture dict name, or nil on total failure.
-- ---------------------------------------------------------------------------
function LoadStyleTexture(self, requestedStyle, failureMessageFormat)
    local texDict = GetStyleTextureName(requestedStyle)
    local loaded  = false

    if texDict == "circlemap" then
        loaded = EnsureCirclemapLoaded()
    else
        loaded = LoadTextureDictWithTimeout(texDict)
    end

    if not loaded then
        if texDict == "circlemap" then
            Info("Circlemap texture dict 'circlemap' did not load in time; using square. Check stream/circlemap.ytd and that the resource has started.")
        else
            Info(failureMessageFormat, texDict)
        end

        self.currentStyle = "square"
        local fallbackDict = STYLE_TEXTURE_DICT.square
        if not LoadTextureDictWithTimeout(fallbackDict) then
            Info("Failed to load square minimap texture '%s'", fallbackDict)
            return nil
        end
        return fallbackDict
    end

    return texDict
end

-- ---------------------------------------------------------------------------
-- Minimap:LoadMap  — initial texture + position setup (called once on init)
-- ---------------------------------------------------------------------------
function Minimap:LoadMap(styleName)
    self.currentStyle = (styleName == "default") and "square" or (styleName or "square")

    local texDict = LoadStyleTexture(self, self.currentStyle,
        "Failed to load minimap texture '%s', falling back to square")
    if not texDict then return end

    self:applyClipType()
    ApplyMinimapMask(texDict)
    self:applyPosition(true)
    self:applyClipType()
    ApplyNorthIndicatorVisibility()
end

-- ---------------------------------------------------------------------------
-- Minimap:SwitchMap  — hot-switch to a different style at runtime
-- ---------------------------------------------------------------------------
function Minimap:SwitchMap(styleName)
    self.currentStyle = (styleName == "default") and "square" or (styleName or "square")

    local texDict = LoadStyleTexture(self, self.currentStyle,
        "Failed to switch minimap texture '%s', falling back to square")
    if not texDict then return end

    self:applyClipType()
    ApplyMinimapMask(texDict)
    self:applyPosition(true)
    self:applyClipType()
    ApplyNorthIndicatorVisibility()
end

-- ---------------------------------------------------------------------------
-- Minimap:reapply  — re-applies the current style (e.g. after pause menu close)
-- Sets reapplyPending = true if the texture dict isn't ready yet.
-- ---------------------------------------------------------------------------
function Minimap:reapply()
    if not self.isInitialized then return false end

    local styleName = self.currentStyle or "square"
    local texDict   = GetStyleTextureName(styleName)
    local loaded    = (texDict == "circlemap") and EnsureCirclemapLoaded()
                                               or LoadTextureDictWithTimeout(texDict)

    if not loaded then
        self.reapplyPending = true
        Info("Minimap reapply: texture dict '%s' not ready, watchdog will retry", texDict)
        return false
    end

    self.reapplyPending = false
    self:applyClipType()
    ApplyMinimapMask(texDict)
    self:applyPosition(true)
    self:applyClipType()
    ApplyNorthIndicatorVisibility()
    return true
end

-- ---------------------------------------------------------------------------
-- Minimap:init  — full initialisation (called once after player is active)
-- ---------------------------------------------------------------------------
function Minimap:init()
    Info("starting minimap init")
    self:LoadMap("square")

    -- Pre-request circlemap in background so it's ready for a quick switch
    RequestStreamedTextureDict("circlemap", false)

    local requestedStyle = _G.BabloHudMapStyle or "square"
    if requestedStyle == "default" then requestedStyle = "square" end
    Trace("loaded startup minimap style: square, requested: %s", requestedStyle)

    ApplyNorthIndicatorVisibility()

    self.scaleform = RequestScaleformMovie("minimap")
    while not HasScaleformMovieLoaded(self.scaleform) do Wait(0) end

    SetRadarBigmapEnabled(false, false)
    DisplayRadar(false)
    self:applyPosition(true)
    self.isInitialized = true

    -- ⚠️ "denna skiten" is Swedish for "this thing/crap" — a developer note left in the original
    Trace("starting denna skiten")

    self:enforceHiddenOverlays()

    if IsPauseMenuActive() then
        SetMinimapClipType(0)
    end

    local cfg = GetMinimapConfig()
    if not (cfg and cfg.showLongRangeBlips) then
        SetMinimapComponent(2, false, 0)
    end

    if IsBigmapActive() then
        SetRadarBigmapEnabled(false, false)
    end

    -- Deferred position re-apply after 300 ms (lets the game settle)
    CreateThread(function()
        Wait(300)
        Minimap:applyPosition(true)
    end)

    -- If a non-square style was requested, switch after 600 ms
    if requestedStyle ~= "square" then
        CreateThread(function()
            Wait(600)
            Minimap:SwitchMap(requestedStyle)
            if SendMinimapPosition then SendMinimapPosition(true) end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Startup thread — waits for the player to be active, then initialises
-- ---------------------------------------------------------------------------
CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(100) end
    Wait(500)
    Minimap:init()

    local watchdogCfg     = (Config and Config.MinimapWatchdog) or {}
    local enforceInterval = watchdogCfg.enforceFrameInterval or 300

    -- If continuous mode is NOT configured, use Bablo.Ticker instead
    if not watchdogCfg.continuous then
        if Bablo and Bablo.Ticker then
            Bablo.Ticker:register(function(frame)
                if frame % enforceInterval == 17 then
                    Minimap:enforceHiddenOverlays()
                end
            end)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Video-mode watcher — re-sends minimap position when resolution/aspect/
-- safe-zone changes are detected (checked every 1 s, acts after 250 ms).
-- ---------------------------------------------------------------------------
CreateThread(function()
    while not (Minimap and Minimap.isInitialized) do Wait(500) end

    local prevW, prevH      = GetActualScreenResolution()
    local prevAspect        = GetAspectRatio(false)
    local prevSafeZone      = GetSafeZoneSize()

    while true do
        Wait(1000)
        local w, h       = GetActualScreenResolution()
        local aspect     = GetAspectRatio(false)
        local safeZone   = GetSafeZoneSize()

        local resChanged  = (w ~= prevW or h ~= prevH)
        local aspectDiff  = math.abs((aspect or 0) - (prevAspect or 0))
        local safeZoneDiff= math.abs((safeZone or 0) - (prevSafeZone or 0))

        if resChanged or aspectDiff > 0.001 or safeZoneDiff > 0.001 then
            prevW, prevH, prevAspect, prevSafeZone = w, h, aspect, safeZone
            Wait(250)
            Minimap:applyPosition(true)
            if SendMinimapPosition then SendMinimapPosition(true) end
            Trace("video mode changed (%dx%d aspect %.3f safezone %.3f) - minimap anchor resent",
                w, h, aspect or 0, safeZone or 0)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- MinimapWatchdog — periodically reapplies the minimap after the pause menu
-- closes, and triggers BabloHudRecomputeRadar when set.
-- ---------------------------------------------------------------------------
CreateThread(function()
    local watchdogCfg = (Config and Config.MinimapWatchdog) or {}
    if watchdogCfg.enabled == false then return end

    local interval   = watchdogCfg.intervalMs or 1000
    local wasInPause = false
    local lastReapplyTime = 0

    while true do
        Wait(interval)
        if Minimap.isInitialized then
            local inPause = IsPauseMenuActive()

            -- Reapply once when returning from the pause menu
            if wasInPause and not inPause then
                Minimap:reapply()
                lastReapplyTime = GetGameTimer()
            end
            wasInPause = inPause

            -- Periodic texture watchdog (every 3 s)
            if GetGameTimer() - lastReapplyTime > 3000 then
                local texDict = GetStyleTextureName(Minimap.currentStyle)
                if Minimap.reapplyPending or not HasStreamedTextureDictLoaded(texDict) then
                    Minimap:reapply()
                    lastReapplyTime = GetGameTimer()
                end
            end

            -- Call BabloHudRecomputeRadar global if set
            if _G.BabloHudRecomputeRadar and not IsPauseMenuActive() then
                _G.BabloHudRecomputeRadar()
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Continuous-mode watchdog — applies position every frame when configured
-- ---------------------------------------------------------------------------
CreateThread(function()
    local watchdogCfg = (Config and Config.MinimapWatchdog) or {}
    if not watchdogCfg.continuous then return end

    while true do
        Wait(0)
        if Minimap.isInitialized then
            Minimap:applyPosition(false)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Custom radar zoom loop (Config.DefaultSettings.minimap.customMap)
-- ---------------------------------------------------------------------------
CreateThread(function()
    local cfg = GetMinimapConfig()
    if not (cfg and cfg.customMap and cfg.customMap.enabled) then return end

    local customMap = cfg.customMap
    while customMap.enabled do
        SetRadarZoom(customMap.radarZoom or 1100)
        Wait(customMap.refreshRate or 500)
    end
end)

-- ---------------------------------------------------------------------------
-- HUD resource compatibility — reapply minimap when a known HUD resource
-- starts or stops (e.g. qb-hud replaces radar components on load)
-- ---------------------------------------------------------------------------
local COMPATIBLE_HUD_RESOURCES = {
    ["qb-hud"]  = true,
    qbx_hud     = true,
    ["qbx-hud"] = true,
}

AddEventHandler("onClientResourceStop", function(resourceName)
    if not COMPATIBLE_HUD_RESOURCES[resourceName] then return end
    CreateThread(function()
        Wait(300)
        Minimap:reapply()
    end)
end)

AddEventHandler("onClientResourceStart", function(resourceName)
    if not COMPATIBLE_HUD_RESOURCES[resourceName] then return end
    CreateThread(function()
        Wait(1500)
        Minimap:reapply()
    end)
end)