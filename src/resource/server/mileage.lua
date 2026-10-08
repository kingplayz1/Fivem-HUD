-- Server-side mileage tracking for bablo-hud

local migrations = {
    [[
        CREATE TABLE IF NOT EXISTS bablo_hud_mileage
        (
            plate VARCHAR(16) NOT NULL,
            mileage DOUBLE NOT NULL DEFAULT 0,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (plate)
        );
    ]],
}

local persistentEnabled = Config and Config.Mileage and Config.Mileage.persistent ~= false
local dbReady           = false

-- In-memory mileage cache: plate → total distance (km or miles)
local mileageCache = {}

-- Dirty set: plates that need to be flushed to DB
local dirtyPlates  = {}

-- ─── Plate normalisation ──────────────────────────────────────────────────────

function NormalisePlate(raw)
    if type(raw) ~= "string" then return nil end
    local trimmed = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then return nil end
    return trimmed:upper()
end

-- ─── DB flush ────────────────────────────────────────────────────────────────

function FlushDirtyMileage()
    if not persistentEnabled or not dbReady then return end

    for plate in pairs(dirtyPlates) do
        dirtyPlates[plate] = nil
        local mileage = mileageCache[plate]
        if mileage then
            local ok, err = pcall(function()
                MySQL.query.await(
                    "INSERT INTO bablo_hud_mileage (plate, mileage) VALUES (?, ?) ON DUPLICATE KEY UPDATE mileage = ?",
                    { plate, mileage, mileage }
                )
            end)
            if not ok then
                print(("[bablo-hud] mileage save failed for %s: %s"):format(plate, tostring(err)))
            end
        end
    end
end

-- ─── DB init & periodic save ─────────────────────────────────────────────────

if persistentEnabled then
    MySQL.ready(function()
        for _, sql in ipairs(migrations) do
            local ok, err = pcall(function()
                MySQL.query.await(sql)
            end)
            if not ok then
                print(("[bablo-hud] mileage migration failed: %s"):format(tostring(err)))
                return
            end
        end
        dbReady = true
    end)

    CreateThread(function()
        local intervalSec = tonumber(Config.Mileage and Config.Mileage.saveInterval) or 60
        local intervalMs  = intervalSec * 1000
        while true do
            Wait(intervalMs)
            FlushDirtyMileage()
        end
    end)

    AddEventHandler("onResourceStop", function(resourceName)
        if GetCurrentResourceName() == resourceName then
            FlushDirtyMileage()
        end
    end)
end

-- ─── Callback: get mileage for a plate ───────────────────────────────────────

if lib and lib.callback and lib.callback.register then
    lib.callback.register("bablo-hud:mileage:get", function(_, rawPlate)
        local plate = NormalisePlate(rawPlate)
        if not plate then return 0.0 end

        -- Return from cache if already loaded
        if mileageCache[plate] ~= nil then
            return mileageCache[plate]
        end

        -- Without DB, return 0
        if not persistentEnabled or not dbReady then return 0.0 end

        -- Fetch from DB and cache
        local ok, result = pcall(function()
            return MySQL.scalar.await(
                "SELECT mileage FROM bablo_hud_mileage WHERE plate = ?",
                { plate }
            )
        end)

        local value = (ok and tonumber(result)) or 0.0
        mileageCache[plate] = value
        return value
    end)
end

-- ─── Net event: add mileage increment ────────────────────────────────────────

RegisterNetEvent("bablo-hud:mileage:add")
AddEventHandler("bablo-hud:mileage:add", function(rawPlate, rawDelta)
    local plate = NormalisePlate(rawPlate)
    local delta = tonumber(rawDelta)

    if not plate or not delta then return end
    if delta <= 0 or delta > 2.0 then return end  -- sanity: max 2 km per tick

    mileageCache[plate] = (mileageCache[plate] or 0.0) + delta
    dirtyPlates[plate]  = true
end)
