Framework = Framework or {}

CreateThread(function()
    if Config.Framework ~= 'vrp' then
        return
    end

    local vRP = exports['vRP']:getvRP() -- or maybe getvRP? Some use getvRP
    -- If the above doesn't work, try alternative
    if not vRP then
        vRP = exports['vRP']
    end

    function Framework:getCore()
        return vRP
    end

    local jobFallbackLabel = nil
    local jobFallbackGrade = nil
    local playerNameFallback = nil
    local function lazyFallbacks()
        if jobFallbackLabel == nil then
            jobFallbackLabel = Locale.t("framework.fallbacks.jobLabel")
            jobFallbackGrade = Locale.t("framework.fallbacks.jobGrade")
            playerNameFallback = Locale.t("framework.fallbacks.playerName")
        end
    end

    local cached = {
        loaded = false,
        hunger = 100,
        thirst = 100,
        stress = 0,
        jobName = nil,
        jobLabel = nil,
        jobGrade = nil,
        cash = 0,
        bank = 0,
        playerName = nil,
        gangName = nil,
        gangLabel = nil,
        gangGrade = nil,
    }

    local function clamp100(n)
        local v = tonumber(n) or 0
        if v < 0 then return 0 end
        if v > 100 then return 100 end
        return v
    end

    -- Helper to get user data from vRP
    local function GetUserData()
        local user_id = vRP.getUserId({source})
        if user_id then
            local user = vRP.getUserData({user_id})
            return user
        end
        return nil
    end

    local function applyJob(jobInfo)
        lazyFallbacks()
        if type(jobInfo) ~= "table" then
            cached.jobName = nil
            cached.jobLabel = jobFallbackLabel
            cached.jobGrade = jobFallbackGrade
            return
        end
        cached.jobName = jobInfo.name or jobInfo.job or "unemployed"
        cached.jobLabel = jobInfo.label or jobInfo.name or jobInfo.job or jobFallbackLabel
        cached.jobGrade = (jobInfo.grade and jobInfo.grade.name) or jobInfo.grade or jobFallbackGrade
    end

    local function applyMoney(moneyTable)
        if type(moneyTable) ~= "table" then return end
        if moneyTable.cash ~= nil then cached.cash = tonumber(moneyTable.cash) or 0 end
        if moneyTable.bank ~= nil then cached.bank = tonumber(moneyTable.bank) or 0 end
    end

    local function applyGang(gangInfo)
        if type(gangInfo) ~= "table" or not gangInfo.name or gangInfo.name == "none" then
            cached.gangName = nil
            cached.gangLabel = nil
            cached.gangGrade = nil
            return
        end
        cached.gangName = gangInfo.name
        cached.gangLabel = gangInfo.label or gangInfo.name
        cached.gangGrade = gangInfo.grade and (gangInfo.grade.name or gangInfo.grade.label) or nil
    end

    local function applyCharinfo(charinfo)
        if type(charinfo) ~= "table" then return end
        local first = charinfo.firstname or ""
        local last = charinfo.lastname or ""
        if first == "" and last == "" then
            cached.playerName = nil
        else
            cached.playerName = string.format("%s %s", first, last)
        end
    end

    local function applyMetadata(metadata)
        if type(metadata) ~= "table" then return end
        if metadata.hunger ~= nil then cached.hunger = clamp100(metadata.hunger) end
        if metadata.thirst ~= nil then cached.thirst = clamp100(metadata.thirst) end
        if metadata.stress ~= nil then cached.stress = clamp100(metadata.stress) end
    end

    local function populateFromPlayerData(data)
        if type(data) ~= "table" then return false end
        applyMetadata(data)
        applyJob(data.job or {})
        applyGang(data.gang or {})
        applyMoney(data.wallet or data.money or {})
        applyCharinfo(data)
        cached.loaded = true
        return true
    end

    function Framework:isPlayerLoaded()
        return cached.loaded == true
    end

    function Framework:getHunger() return cached.hunger end
    function Framework:getThirst() return cached.thirst end
    function Framework:getStress() return cached.stress end

    function Framework:setStress(value)
        local v = clamp100(value)
        cached.stress = v
        TriggerServerEvent('bablo-hud:server:setStress', v)
    end

    function Framework:getNitro()
        return 0
    end

    function Framework:getJob()
        lazyFallbacks()
        return cached.jobLabel or jobFallbackLabel, cached.jobGrade or jobFallbackGrade
    end

    function Framework:getJobName()
        return cached.jobName
    end

    function Framework:getMoney()
        return cached.cash, cached.bank
    end

    function Framework:getDirtyMoney()
        -- vRP might have black money
        local user_id = vRP.getUserId({source})
        if user_id then
            local amount = vRP.getInventoryItemAmount({user_id, "dirty_money"}) or 0
            return amount
        end
        return 0
    end

    function Framework:getGang()
        if not cached.gangName then return false end
        return { name = cached.gangName, label = cached.gangLabel, grade = cached.gangGrade }
    end

    function Framework:getVehicleMileage(vehicle, plate)
        return false
    end

    function Framework:getFuel(vehicle)
        return GetVehicleFuelLevel(vehicle)
    end

    function Framework:getPlayerName()
        if cached.playerName and cached.playerName ~= "" then
            return cached.playerName
        end
        lazyFallbacks()
        return GetPlayerName(PlayerId()) or playerNameFallback
    end

    local cachedServerId = 0
    function Framework:getPlayerId()
        if cachedServerId > 0 then return cachedServerId end
        local bag = LocalPlayer and LocalPlayer.state and LocalPlayer.state.bablo_sid
        if type(bag) == "number" and bag > 0 then
            cachedServerId = bag
            return cachedServerId
        end
        if type(_G.BabloHudServerId) == "number" and _G.BabloHudServerId > 0 then
            cachedServerId = _G.BabloHudServerId
            return cachedServerId
        end
        local id = GetPlayerServerId(PlayerId())
        if type(id) == "number" and id > 0 then
            cachedServerId = id
        end
        return cachedServerId
    end

    function Framework:isSeatbeltOn()
        return false
    end

    function Framework:notify(title, description, notificationType, duration)
        local text
        if description and description ~= "" then
            text = string.format("%s: %s", title or "", description)
        else
            text = title or description or ""
        end
        -- vRP notification
        vRP.notify({source, text})
    end

    function Framework:applyEjectionPhysics(ped, vel)
        SetPedCanRagdoll(ped, true)
        SetPedToRagdoll(ped, 5511, 5511, 0, 0, 0, 0)
        SetEntityVelocity(ped, vel.x * 4, vel.y * 4, vel.z * 4)

        local ejectSpeed = math.ceil(GetEntitySpeed(ped) * 8)
        local hp = GetEntityHealth(ped)
        if hp - ejectSpeed > 0 then
            SetEntityHealth(ped, hp - ejectSpeed)
        elseif hp ~= 0 then
            SetEntityHealth(ped, 0)
        end
    end

    RegisterNetEvent('hud:client:UpdateNeeds', function(newHunger, newThirst)
        if newHunger ~= nil then cached.hunger = clamp100(newHunger) end
        if newThirst ~= nil then cached.thirst = clamp100(newThirst) end
    end)

    RegisterNetEvent('hud:client:OnMoneyChange', function()
        -- Trigger vRP update? We'll just refresh data
        local user_id = vRP.getUserId({source})
        if user_id then
            local user = vRP.getUserData({user_id})
            if user then
                populateFromPlayerData(user)
                TriggerEvent('bablo-hud:playerLoaded')
            end
        end
    end)

    -- We need to listen for vRP events if any, but for simplicity we'll rely on the above.
    -- Also, we need to initialize data on player loaded.
    CreateThread(function()
        -- Wait for vRP to be ready
        Wait(1000)
        local user_id = vRP.getUserId({source})
        if user_id then
            local user = vRP.getUserData({user_id})
            if user then
                populateFromPlayerData(user)
                cached.loaded = true
                TriggerEvent('bablo-hud:playerLoaded')
            end
        end
    end)

    -- Handle player unload (if vRP provides an event)
    -- Not all vRP versions have client unload event; we'll rely on server trigger.
end)