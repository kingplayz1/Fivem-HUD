
Config                         = Config or {}

Config.Framework               = "standalone" -- "auto", "standalone", "qbcore", "esx", "qbox", "nd", or "vrp"
Config.Locale                  = "en-US" -- Locale code; must match a file in /locales/<code>.json
-- Weapon image source: "bablo-hud" (own /weapons folder, weapon_pistol.png/.webp), "ox_inventory",
-- "qb-inventory", "qs-inventory", "ps-inventory", "origen_inventory", "core_inventory",
-- "codem-inventory", "tgiann-inventory", "none" (use bablo-hud weapons only), or a URL template containing "{weapon}".
Config.WeaponImageInventory    = "ox_inventory"

-- Per-weapon image overrides (checked before WeaponImageInventory). Key = lowercase weapon name, value = any URL.
Config.WeaponImages            = {
    -- ["weapon_pistol"]       = "nui://my-images/weapons/pistol.png",
    -- ["weapon_assaultrifle"] = "https://example.com/images/ar.png",
}

Config.DEBUG                   = false     -- Master debug flag: enables Trace/Info logs, debug-only commands, and the in-game Collision Debug button

Config.HighlightColor          = "#7aadff" -- Default light blue

-- Money format for Player Info pills: "_" is replaced by the amount, e.g. "$_", "_ kr", "€_", "_ $".
Config.Currency = "$_"

Config.HighlightSecondaryColor = "#3C83F6" -- Default blue

-- Force one font for all HUD text (e.g. Arabic/RTL). url = optional stylesheet that loads it.
Config.Font                    = {
    enabled = false,
    family  = "Cairo",
    url     = "https://fonts.googleapis.com/css2?family=Cairo:wght@400;500;600;700&display=swap",
}

-- Hide GTA's native text popups (vehicle name/class, area and street names).
Config.HideNativeTexts         = {
    vehicleName  = true, -- e.g. "Truffade Adder" when entering a vehicle
    vehicleClass = true, -- the class label, e.g. "Super"
    areaName     = true, -- district/area name popup
    streetName   = true, -- street name popup
}

-- Logo box in the Player Info stack. `logo` = asset path, nui:// or https:// URL.
Config.ServerLogo              = {
    enabled = true,              -- Set to false to hide the logo box entirely
    logo    = "assets/logo.png", -- Image shown in the logo box
    opacity = 1.0,
}

-- Minimap Transition: a branded panel that covers the minimap while the radar shows/hides.
-- `color` = any CSS color/gradient (nil = dial gradient); `timing` = open/hold/close in ms.
Config.MinimapTransition       = {
    enabled   = true,
    showLogo  = true,                                               -- Draw a logo centered in the curtain
    logo      = "bablo-curtain.png",                                -- File in web/public (shipped in web/dist), or nui:// / https:// URL; nil = Config.ServerLogo.logo
    logoScale = 0.5,                                                -- Logo size as a fraction of the curtain's shorter side
    color     = "linear-gradient(180deg, #131417 0%, #25282D 100%)", -- e.g. "#e11d48" or Config.HighlightColor
    style     = "slide",                                            -- "slide" (panel slides in/out) or "shutter" (opens from the center line, closes sideways)
    timing    = { open = 320, hold = 260, close = 480 },
    -- Fit tuning (fractions of map size per edge, negative = grow). Use /hudcurtain to compare in-game.
    inset     = { top = 0.012, right = 0.016, bottom = 0.004, left = -0.008 },
    -- Circle style: visible disc center/radii as fractions of the map rect.
    circle    = { cx = 0.460, cy = 0.500, rx = 0.489, ry = 0.558 },
}

-- Odometer source. provider = "builtin": the HUD tracks mileage itself (persistent = true saves per plate via
-- oxmysql, table auto-created; false = session-only). provider = "framework": the built-in tracker is off and the
-- info bar shows whatever Framework:getVehicleMileage(vehicle, plate) returns from your bridge file
-- (src/frameworks/<qb|qbox|esx>/client.lua), e.g. return exports["jg-vehiclemileage"]:getMileage() (km, or false to hide).
Config.Mileage                 = {
    provider     = "builtin",
    persistent   = false,
    saveInterval = 60, -- Seconds between database writes for changed plates
}

-- Mic icon: "lines" (default), "classic", "lucide", "headset", "keyboard", or any Lucide icon name (e.g. "MicVocal").
Config.VoiceIcon               = "lines"

-- Voice backend: "pma-voice" (default), "saltychat" or "yaca".
Config.VoiceScript             = "pma-voice"

-- Vehicle Settings
Config.SpeedUnit               = "kmh" -- "kmh" or "mph"
Config.EngineToggleKey         = "L" -- Key to toggle engine on/off
Config.SeatbeltToggleKey       = "B" -- Key to toggle seatbelt

-- Engine toggle keybind. Set enabled = false if another resource owns engine control.
Config.Engine                  = {
    enabled = true,
}

-- Nitro status icon (vehicle only). Renders Framework:getNitro() (0-100); wire that bridge function
-- in src/frameworks/<qb|qbox|esx>/client.lua to your nitro script.
Config.Nitro                   = {
    enabled = false,
}

-- Integrated seatbelt module (keybind, animation, ejection). enabled = false → read state via Framework:isSeatbeltOn().
Config.Seatbelt                = {
    enabled = true,

    showIndicator = true,   -- Show the seatbelt icon in speedometer designs
    preventEjection = true, -- Buckled players are never thrown through the windshield
    audioMode = "native",   -- "native" (GTA audio bank, spatial) or "nui" (local .ogg files)
    alarm = true,           -- Alarm sound when driving unbuckled above the speed threshold
    -- Unbuckled crash ejection: each hard impact rolls `chance`. chance = 0 → GTA default.
    ejection = {
        minSpeed = 100, -- km/h the vehicle must reach before an impact can eject you
        chance   = 50,  -- % probability per qualifying impact (0-100)
    },
}

-- HUD settings panel access. enabled = false disables the command for everyone.
Config.Settings                = {
    enabled = true,

    command = "hudsettings", -- Chat command that opens the panel
    keybind = {              -- Optional keybind (players can rebind in FiveM Key Bindings)
        enabled = true,
        defaultKey = "I",
    },
}

-- Vehicle control panel (engine, lights, signals, doors, windows...). Keybind "M" or /carcontrol.
-- Other scripts: exports['bablo-hud']:OpenVehicleControl() / CloseVehicleControl() / ToggleVehicleControl() /
-- IsVehicleControlOpen(), or events bablo-hud:vehiclecontrol:open / :close / :toggle.
Config.VehicleControl          = {
    enabled = true, -- Master toggle for the entire Vehicle Control system

    command = {
        enabled = true,      -- Enable chat command to open vehicle control panel
        name = "carcontrol", -- Command name (e.g. /carcontrol)
    },

    keybind = {
        enabled = true,   -- Enable keybind to open vehicle control panel
        defaultKey = "M", -- Default keybind (rebindable in FiveM Key Bindings)
    },

    -- Direct keybinds (rebindable per player). enabled = false skips registering them.
    binds = {
        enabled        = true,
        indicatorLeft  = "LEFT",  -- Toggle left blinker
        indicatorRight = "RIGHT", -- Toggle right blinker
        hazards        = "DOWN",  -- Toggle hazard lights (warning triangle)
    },

    allowOnFoot = false, -- If false, panel only opens when sitting inside a vehicle
}

-- Progress bar API: exports['bablo-hud']:ProgressBar({duration=ms | manual=true, label, color, control, canCancel,
--   animation, prop_left, prop_right, controlDisables, useWhileDead}, cb(cancelled)); UpdateProgressBar(value0-100, label?)
--   or UpdateProgressBar({value=, label=}); CompleteProgressBar(); StopProgressBar(). Manual bars finish at 100 or on Complete.
--   Events: bablo-hud:progressbar:start/update/complete/stop.

-- Server-wide defaults for every HUD component. Players can override in settings unless `locked = true`.
Config.DefaultSettings         = {
    -- Minimap Settings
    minimap = {
        showOnFoot = true,          -- Show minimap while on foot
        style = "square",           -- "square" or "circle"
        size = 1.0,                 -- Server default minimap size (1.0 = 100%; try ~0.75–1.5). Players can still resize in HUD edit mode.
        widthScale = 0.88,          -- Width aspect scale (default ~0.88 creates a perfect 1:1 un-stretched square minimap; 1.0 = native default)
        maxSize = 1.25,             -- Max size a player can drag the minimap to in edit mode (min is fixed at 0.75).
        showNorthIndicator = true,  -- Keep the native GTA north "N" compass blip on the minimap
        showLongRangeBlips = false, -- Show edge-of-minimap arrows for long-range blips (blips not SetBlipAsShortRange)
        useCustomMask = true,       -- Apply the built-in square/circle masks; false if another resource streams a minimap skin
        -- Re-assert radar zoom on a timer (needed for streamed satellite/HD maps that go blank).
        customMap = {
            enabled     = false, -- Enable/Disable custom map radar zoom
            radarZoom   = 1100,  -- radar zoom level (default 1100; higher zooms out)
            refreshRate = 500,   -- how often to re-assert the zoom (in ms)
        },

        locked = false,         -- Lock minimap settings (visibility/style)
        lockedPosition = false, -- Prevent players from moving the minimap in edit mode
    },

    -- Status Icons
    status = {
        enabled = true,         -- Enable status icons entirely
        design = "v3",          -- Default design: v1, v2, v3, v4
        scale = nil,            -- Element scale; nil auto-selects (1.35 for bar designs, 1.5 otherwise)
        locked = false,         -- Lock status design/color settings
        lockedPosition = false, -- Prevent players from moving the status group in edit mode

        -- Per-status configuration (Supports HEX like "#FF4D4D" or HSL like "354 87% 66%")
        colors = {
            health  = "#F64843",
            hunger  = "#FFC548",
            thirst  = "#7AADFF",
            armor   = "#A0A0A0",
            stress  = "#FF6DC6",
            stamina = "#C4FF48",
            oxygen  = "#85FF7A",
            nitro   = "#BA65FF",
        },
        visibility = {
            health  = true,
            hunger  = true,
            thirst  = true,
            armor   = true,
            stress  = true,
            stamina = true,
            oxygen  = true,
            nitro   = true,
        },
        -- autoHide: false = always show, true/0 = hide at 0, 1-100 = hide when value >= threshold.
        autoHide = {
            health  = false,
            hunger  = false,
            thirst  = false,
            armor   = true,
            stress  = false,
            stamina = true,
            oxygen  = true,
            nitro   = true,
        },
    },

    -- Notification Settings
    notification = {
        enabled = true,         -- Enable notifications
        style = "linear",       -- "linear", "circular", or "overlay"
        theme = "colored",      -- "primary" or "colored"
        sound = true,           -- Enable notification sounds
        volume = 50,            -- Sound volume (0-100)
        opacity = 100,          -- Notification opacity (20-100)
        locked = false,         -- Lock notification settings
        lockedPosition = false, -- Prevent players from moving the notification area in edit mode
    },

    -- Player Info Panel
    playerInfo = {
        enabled = true,               -- Enable the player info panel
        opacity = 100,                -- Panel opacity (20-100)
        accentColor = "217 100% 74%", -- HSL accent color for info pill icons (#7aadff)
        colors = {
            id = "#000000",           -- Color for Player ID pill (#HEX or HSL)
            time = "#000000",         -- Color for In-game / Real time pill (#HEX or HSL)
            cash = "#FFFFFF",         -- Color for Cash money pill (#HEX or HSL)
            bank = "#26D090",         -- Color for Bank balance pill (#HEX or HSL)
            job = "#000000",          -- Color for Job / Grade pill (#HEX or HSL)
            dirty = "#B23B3B",        -- Color for Dirty money pill (#HEX or HSL)
            gang = "#000000",         -- Color for Gang pill (#HEX or HSL)
        },
        showJob = true,               -- Show job/grade pill
        showId = true,                -- Show player ID pill
        showTime = true,              -- Show in-game time pill
        timeSource = "ingame",        -- Clock shown in the time pill: "ingame" (GTA world clock), "local" (player's own PC clock), "server" (clock of the machine hosting the server)
        showBank = true,              -- Show bank balance
        showCash = true,              -- Show cash on hand
        showDirtyMoney = true,        -- Dirty money pill (only shown when Framework:getDirtyMoney() > 0; false hides it for everyone)
        showGang = true,              -- Gang pill (only shown when Framework:getGang() returns a gang; false hides it for everyone)
        showWeapon = true,            -- Show equipped weapon card
        scale = 1.0,                  -- Default element scale in edit mode (design-canvas units; the runtime multiplies by globalScale for your actual resolution)
        locked = false,               -- Lock player info settings
        lockedPosition = false,       -- Prevent players from moving the player info panel in edit mode
    },

    -- Compass (vehicle-only, top-center HUD)
    compass = {
        enabled = true,         -- Enable the compass module entirely
        showOnFoot = false,     -- Show the compass on foot too (when the minimap is visible), not just in a vehicle
        style = "default",      -- Reserved for future compass styles; leave as "default"
        opacity = 100,          -- Panel opacity (20-100)
        showDirection = true,   -- Show the direction pill (N/NE/E/...)
        showStreet = true,      -- Show the current street pill
        showZone = true,        -- Show the current zone/area pill
        scale = 1.0,            -- Default element scale in edit mode
        locked = false,         -- Lock compass settings in /settings
        lockedPosition = false, -- Prevent players from moving the compass in edit mode
    },

    -- Voice / Microphone
    voice = {
        location = "status", -- "standalone" (own movable voice element) or "status" (mic icon inside the status bar)
        color = "",          -- Mic color ("#hex" or "H S% L%"); "" = server theme color
    },

    -- Progress Bar
    progressBar = {
        enabled = true,         -- Enable progress bars
        style = "linear-slim",  -- "linear-slim", "linear-icon", or "circular"
        color = "primary",      -- "primary", "success", "error", "info", "warning"
        borderRadius = "full",  -- "full", "md", or "none"
        scale = 1.0,            -- Default element scale in edit mode
        locked = false,         -- Lock progress bar settings
        lockedPosition = false, -- Prevent players from moving the progress bar in edit mode
    },

    -- Speedometer
    speedometer = {
        enabled = true,                 -- Enable speedometer
        style = "round-modern",         -- "round-basic", "round-modern", "round-arc", "digital-bar", or "racing-angle"
        highlight = true,               -- Show highlight glow
        highlightColor = "217 91% 60%", -- HSL color for highlight
        scale = 1.0,                    -- Default element scale in edit mode
        locked = false,                 -- Lock speedometer settings
        lockedPosition = false,         -- Prevent players from moving the speedometer in edit mode
    },
}

-- Control hints (key + label prompts). enabled = false removes the feature and its settings tab.
-- Runtime API: exports['bablo-hud']:ShowControlHints({ {id=,label=,key=,duration=?}, ... }, sharedDurationMs?)
--   also accepts a single hint table or (id, label, key, durationMs); HideControlHints(id | {ids}) ; ClearControlHints().
--   Events bablo-hud:controlhint:show / :hide / :clear take the same arguments.
Config.ControlHints            = {
    enabled = false,
    position = "center-right", -- "center-left" or "center-right"
    hints = {
        { label = "Open Phone", key = "F1" },
        { label = "Inventory",  key = "TAB" },
    },
}

-- Stress: integrated = true runs the built-in system (decay, blur, shake, exports);
-- false only displays Framework:getStress() from your own stress script.
Config.Stress                  = {
    integrated = true,   -- Toggle: use the integrated stress module
    decayPerMinute = 10, -- How much stress is removed per minute when above 0
    minimumValue = 0,    -- Floor stress can fall to via decay
    maximumValue = 100,  -- Ceiling stress can rise to

    -- Job names exempt from driving/shooting stress.
    jobWhitelist = { 'police', 'sheriff', 'ambulance', 'doctor' },

    -- Speed-based stress; highest matching threshold adds perTick every tickIntervalMs.
    driving = {
        enabled = true,
        speedUnit = 'kmh', -- 'kmh' | 'mph'
        thresholds = {
            { minSpeed = 80,  perTick = 2 },
            { minSpeed = 120, perTick = 5 },
            { minSpeed = 180, perTick = 10 },
        },
        tickIntervalMs = 10000,
    },

    -- Stress per shot; blacklisted weapons never add stress.
    shooting = {
        enabled = true,
        perShot = 5,
        weaponBlacklist = {
            'weapon_petrolcan',
            'weapon_fireextinguisher',
            'weapon_flashlight',
        },
    },

    -- Master switches per side-effect (apply across all tiers below).
    effects = {
        screenBlur             = true, -- short blur burst per tier tick
        screenShake            = true, -- gameplay cam shake per tier tick
        vehicleAction          = true, -- big random swerve per tier tick
        steerImpairment        = true, -- continuous drunk-wheel jitter
        healthRegenMultiplier  = true, -- slowed passive regen
        weaponDamageMultiplier = true, -- shaky hands lower damage
    },

    -- Tiers by minValue (highest wins). Per tick: screenBlur (bool), screenShake (0-1), vehicleAction (true=150ms or ms).
    -- Persistent: healthRegenMultiplier / weaponDamageMultiplier (0-1), steerImpairment (0-0.5).
    onTick = {
        {
            minValue = 50,
            interval = 60000,
            screenBlur = true,
            screenShake = nil,
            vehicleAction = false,
            healthRegenMultiplier = 0.5, -- regen at half speed
        },
        {
            minValue = 75,
            interval = 12000, -- vehicle effects fire ~every 12s
            screenBlur = true,
            screenShake = 0.07,
            vehicleAction = 80,            -- mild swerve (ms) while driving > 30 km/h
            steerImpairment = 0.15,        -- wheel jitters mildly on its own
            healthRegenMultiplier = 0.25,
            weaponDamageMultiplier = 0.85, -- shaky aim hits weaker
        },
        {
            minValue = 90,
            interval = 8000, -- vehicle effects fire ~every 8s
            screenBlur = true,
            screenShake = 0.10,
            vehicleAction = true,        -- full swerve while driving > 30 km/h
            steerImpairment = 0.30,      -- wheel actively fights you
            healthRegenMultiplier = 0.0, -- no passive regen at all
            weaponDamageMultiplier = 0.7,
        },
    },
}

-- Player Info Tick Intervals (all values in ms)
Config.PlayerInfo              = {
    tickInterval         = 5000,
    ammoTickInterval     = 250,
    ammoShootingInterval = 50,
    unarmedTickInterval  = 1000,
}

Config.HungerThirstAlert       = {
    enabled       = true,
    tiers         = {
        { threshold = 20, localeKey = "low" },
        { threshold = 10, localeKey = "medium" },
        { threshold = 5,  localeKey = "critical" },
    },
    minInterval   = 2000,
    checkInterval = 5000,
    sound         = {
        enabled = true,
        file    = "hungry.ogg",
        volume  = 0.1,
    },
}

-- Cinematic mode: letterbox bars + optional HUD/radar hide. Exports: ToggleCinematic(), SetCinematic(bool), IsCinematicActive().
Config.Cinematic               = {
    enabled = true,        -- Master toggle for the whole module
    command = "cinematic", -- Chat command name (no slash)
    barHeightPercent = 12, -- Height of EACH bar as % of viewport height
    barColor = "#000000",  -- Bar color (any CSS color)
    transitionMs = 700,    -- Slide-in / slide-out duration in ms
    hideHud = true,        -- Hide bablo-hud components while active
    hideMinimap = true,    -- Hide the minimap while active
    hideGameHud = true,    -- Hide the native GTA V HUD + radar while active
}

-- Global Config: only admins edit settings; "Publish Globally" writes global-config.json and pushes it to everyone.
-- Player KVP is ignored (not wiped) while enabled.
Config.GlobalConfig            = {
    enabled = false,                 -- Master toggle. Set true to enable Global Config mode.
    filename = "global-config.json", -- Path (relative to resource root) where published config is stored.
    allowEdit = false,               -- Let players still reposition elements (per-player) while global mode is on
}

-- Minimap watchdog: re-asserts minimap position/mask/overlays against other scripts.
-- continuous = per-frame enforcement (small cost); otherwise every enforceFrameInterval frames.
Config.MinimapWatchdog         = {
    enabled              = false, -- master toggle for all watchdog behaviour
    intervalMs           = 1000,  -- timed thread interval in ms
    continuous           = false, -- enforce overlays every frame (see above)
    enforceFrameInterval = 300,   -- frame interval for overlay enforcement (continuous=false only)
}

-- Custom map radar zoom: re-asserts zoom on a timer so streamed satellite/HD maps never go blank.
Config.CustomMap               = {
    enabled     = true, -- Enable/Disable custom map radar zoom
    radarZoom   = 1100, -- radar zoom level (default 1100; higher values zoom out)
    refreshRate = 500,  -- how often to re-assert the radar zoom (in ms)
}

--[[
    Custom Pills — extra pills in the Player Info stack.
    Fields: id, label ("" for value-only), icon (Lucide name), defaultValue (nil = hidden until updated),
    plus event (client event fired with the value; nil hides) and/or fetch (function returning the value)
    with fetchInterval (ms, default 1000).
    Example:
        { id = "duty", label = "Duty", icon = "Shield",
          fetch = function() return exports['my-resource']:IsOnDuty() and "On Duty" or nil end, fetchInterval = 5000 },
]]
Config.CustomPills = {
}

--[[
    Custom Status Gauges — extra 0-100 gauges rendered like the built-ins.
    Fields: id, label, icon (curated: radiation, biohazard, heartbeat, brain, lungs, virus, skull, fire, snowflake,
    bolt, droplet, shield, gas, gauge, gauge-high, temperature, battery, signal, wifi, star, crown, coins, money, key,
    wrench, gear, eye, bone, pills, syringe, bandage, wind, running, food, heart) or image (nui:// path),
    color (HSL triplet), order (built-ins are 1-8), autoHide (false | 0 | 1-100), default (0-100),
    plus event and/or fetch + fetchInterval like custom pills. Push values: exports['bablo-hud']:SetCustomStatus(id, value).
    Example:
        { id = "radiation", label = "Radiation", icon = "radiation", color = "120 90% 55%",
          order = 9, autoHide = false, default = 50, fetch = function() return 50 end, fetchInterval = 1000 },
]]
Config.CustomStatuses = {
}

-- Rename GTA streets (by hash) and zones (by short code) everywhere they show.
-- Reference: https://github.com/TheRealBablo/fivem-street-and-zone-names
Config.CustomStreetNames = {
    -- [0x7999837] = "Route 66",
}

Config.CustomZoneNames = {
    -- ["AIRP"] = "LAX Airport",
}
