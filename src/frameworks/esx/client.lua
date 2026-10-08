
Framework = Framework or {}

CreateThread(function()
    if Config.Framework ~= 'esx' then
        return
    end

    local ESX = exports['es_extended']:getSharedObject()

    function Framework:getCore()
        return ESX
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
        stressFromMetadata = nil,
        stressFromEsxStatus = nil,
        jobName = nil,
        jobLabel = nil,
        jobGrade = nil,
        cash = 0,
        bank = 0,
        dirty = 0,
        playerName = nil,
    }

    local function clamp100(n)
        local v = tonumber(n) or 0
        if v < 0 then return 0 end
        if v > 100 then return 100 end
        return v
    end

    local function scaleEsxStatus(val)
        local v = tonumber(val) or 0
        v = math.floor(v / 10000)
        if v < 0 then v = 0 end
        if v > 100 then v = 100 end
        return v
    end

    local function GetPlayerData()
        local ok, data = pcall(function()
            return ESX.GetPlayerData()
        end)
        if ok and type(data) == "table" then
            return data
        end
        return nil
    end

    local function recomputeStress()
        if cached.stressFromMetadata ~= nil then
            cached.stress = cached.stressFromMetadata
        elseif cached.stressFromEsxStatus ~= nil then
            cached.stress = cached.stressFromEsxStatus
        else
            cached.stress = 0
        end
    end

    local function applyJob(jobInfo)
        lazyFallbacks()
        if type(jobInfo) ~= "table" then
            cached.jobName = nil
            cached.jobLabel = jobFallbackLabel
            cached.jobGrade = jobFallbackGrade
            return
        end
        cached.jobName = jobInfo.name
        cached.jobLabel = jobInfo.label or jobInfo.name or jobFallbackLabel
        cached.jobGrade = jobInfo.grade_label or jobInfo.grade_name or jobFallbackGrade
    end

    local function applyAccounts(accounts)
        if type(accounts) ~= "table" then return end
        for _, account in ipairs(accounts) do
            if account and account.name == 'money' then
                cached.cash = tonumber(account.money) or 0
            elseif account and account.name == 'bank' then
                cached.bank = tonumber(account.money) or 0
            elseif account and account.name == 'black_money' then
                cached.dirty = tonumber(account.money) or 0
            end
        end
    end

    local function applyMetadata(metadata)
        if type(metadata) ~= "table" then return end
        if metadata.hunger ~= nil then cached.hunger = clamp100(metadata.hunger) end
        if metadata.thirst ~= nil then cached.thirst = clamp100(metadata.thirst) end
        if metadata.stress ~= nil then
            cached.stressFromMetadata = clamp100(metadata.stress)
            recomputeStress()
        end
    end

    local function applyName(data)
        if type(data) ~= "table" then return end
        local first = data.firstName or ""
        local last = data.lastName or ""
        if first == "" and last == "" then
            cached.playerName = nil
        else
            cached.playerName = string.format("%s %s", first, last)
        end
    end

    local function populateFromPlayerData(data)
        if type(data) ~= "table" then return false end
        applyMetadata(data.metadata)
        applyJob(data.job)
        applyAccounts(data.accounts)
        applyName(data)
        cached.loaded = data.job ~= nil or cached.loaded
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
        cached.stressFromMetadata = v
        recomputeStress()
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
        return cached.dirty or 0
    end

    function Framework:getGang()
        return false
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
        if ESX and type(ESX.ShowNotification) == "function" then
            ESX.ShowNotification(text, notificationType or "info", duration or 5000)
        else
            TriggerEvent('esx:showNotification', text)
        end
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

    AddEventHandler('esx_status:onTick', function(data)
        if type(data) ~= "table" then return end
        for _, entry in ipairs(data) do
            if entry and entry.name and entry.val ~= nil then
                local scaled = scaleEsxStatus(entry.val)
                if entry.name == 'hunger' then
                    cached.hunger = scaled
                elseif entry.name == 'thirst' then
                    cached.thirst = scaled
                elseif entry.name == 'stress' then
                    cached.stressFromEsxStatus = scaled
                    recomputeStress()
                end
            end
        end
    end)

    RegisterNetEvent('esx:setJob', function(job)
        applyJob(job)
    end)

    RegisterNetEvent('esx:setAccountMoney', function(account)
        if type(account) ~= "table" then return end
        if account.name == 'money' then
            cached.cash = tonumber(account.money) or cached.cash
        elseif account.name == 'bank' then
            cached.bank = tonumber(account.money) or cached.bank
        elseif account.name == 'black_money' then
            cached.dirty = tonumber(account.money) or cached.dirty
        end
    end)

    local function WaitForEsxDataThenFire()
        CreateThread(function()
            local tries = 0
            local data
            while tries < 50 do
                data = GetPlayerData()
                if data and data.job and data.accounts then break end
                Wait(100)
                tries = tries + 1
            end
            populateFromPlayerData(data)
            cached.loaded = true
            TriggerEvent('bablo-hud:playerLoaded')
        end)
    end

    RegisterNetEvent('esx:playerLoaded', function()
        WaitForEsxDataThenFire()
    end)

    RegisterNetEvent('esx:onPlayerLogout', function()
        cached.loaded = false
        cached.hunger = 100
        cached.thirst = 100
        cached.stress = 0
        cached.stressFromMetadata = nil
        cached.stressFromEsxStatus = nil
        cached.cash = 0
        cached.bank = 0
        cached.jobName = nil
        cached.jobLabel = nil
        cached.jobGrade = nil
        cached.playerName = nil
        TriggerEvent('bablo-hud:playerUnloaded')
    end)

    local data = GetPlayerData()
    if data and data.job then
        WaitForEsxDataThenFire()
    end
end)
