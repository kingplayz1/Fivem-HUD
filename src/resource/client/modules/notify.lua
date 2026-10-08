local NUI_ACTIONS = (BabloHud and BabloHud.Constants and BabloHud.Constants.NUI_ACTIONS) or {}

-- ---------------------------------------------------------------------------
-- Returns true when notifications should be redirected to the framework
-- instead of being shown in the bablo-hud NUI.
-- This happens when:
--   • Config.DefaultSettings.notification.enabled == false, OR
--   • Bablo.Hud.hiddenComponents.notifications == true
-- ---------------------------------------------------------------------------
function AreNotificationsRedirected()
    local notifCfg = Config and Config.DefaultSettings and Config.DefaultSettings.notification
    if notifCfg and notifCfg.enabled == false then return true end

    if Bablo and Bablo.Hud and Bablo.Hud.hiddenComponents
        and Bablo.Hud.hiddenComponents.notifications == true then
        return true
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Notify(titleOrTable, description, notifType, duration)
--
-- Accepts multiple calling conventions:
--   Notify({ title, description, type, duration })   — table
--   Notify("message")                                — string, uses default title
--   Notify("message", 5000)                          — string + duration
--   Notify("Title", "message", "success", 5000)      — full positional args
-- ---------------------------------------------------------------------------
function Notify(titleOrTable, description, notifType, duration)
    local payload = {}

    if type(titleOrTable) == "table" then
        payload = titleOrTable

    elseif type(titleOrTable) == "string" then
        if type(description) == "number" or description == nil then
            -- Notify("message") or Notify("message", 5000)
            payload.title       = Locale.t("notifications.defaultTitle")
            payload.description = titleOrTable
            payload.type        = "info"
            payload.duration    = description or 5000
        elseif type(description) == "string" then
            -- Notify("Title", "body", "type", duration)
            payload.title       = titleOrTable
            payload.description = description
            payload.type        = notifType or "info"
            payload.duration    = duration  or 5000
        end
    end

    -- Fill in missing fields
    if not payload.title    then payload.title    = Locale.t("notifications.defaultTitle") end
    if not payload.type     then payload.type     = "info" end
    if not payload.duration then payload.duration = 5000   end

    -- Route to framework when notifications are redirected
    if AreNotificationsRedirected() then
        if Framework and type(Framework.notify) == "function" then
            Framework:notify(payload.title, payload.description, payload.type, payload.duration)
        end
        return
    end

    SendNUIMessage({
        action = NUI_ACTIONS.NOTIFY or "notify",
        data   = payload,
    })
end

-- ---------------------------------------------------------------------------
-- Net event, export, and test command
-- ---------------------------------------------------------------------------
RegisterNetEvent("bablo-hud:client:Notify")
AddEventHandler("bablo-hud:client:Notify", Notify)

exports("Notify", Notify)

RegisterCommand("testnotify", function(source, args)
    local notifType = args[1] or "success"
    Notify(
        Locale.t("notifications.test.title"),
        Locale.t("notifications.test.body"),
        notifType,
        5000
    )
end, false)
