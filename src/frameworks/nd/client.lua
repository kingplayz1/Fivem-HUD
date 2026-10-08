Framework = Framework or {}

CreateThread(function()
    if Config.Framework ~= 'nd' then
        return
    end

    local NDCore = exports['nd-core']:getModule('NDCore')

    function Framework:getCore()
        return NDCore
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

    local function GetPlayerData()
        local ok, data = pcall(function()
            return NDCore.Functions.GetPlayerData()
        end)
        if ok and type(data) == "table" then
            return data
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
        cached.jobName = jobInfo.name
        cached.jobLabel = jobInfo.label or jobInfo.name or jobFallbackLabel
        cached.jobGrade = (jobInfo.grade and jobInfo.grade.name) or jobFallbackGrade
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
        applyMetadata(data.metadata)
        applyJob(data.job)
        applyGang(data.gang)
        applyMoney(data.money)
        applyCharinfo(data.charinfo)
        cached.loaded = data.citizenid ~= nil or cached.loaded
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
        return false
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
        NDCore.Functions.Notify(text, notificationType or "primary", duration or 5000)
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
        local data = GetPlayerData()
        if data and data.money then applyMoney(data.money) end
    end)

    RegisterNetEvent('NDCore:Client:OnJobUpdate', function(jobInfo)
        applyJob(jobInfo)
    end)

    RegisterNetEvent('NDCore:Client:OnGangUpdate', function(gangInfo)
        applyGang(gangInfo)
    end)

    RegisterNetEvent('NDCore:Player:SetPlayerData', function(data)
        populateFromPlayerData(data)
    end)

    local function WaitForNDDataThenFire()
        CreateThread(function()
            local tries = 0
            local data
            while tries < 50 do
                data = GetPlayerData()
                if data and data.job and data.money and data.charinfo then break end
                Wait(100)
                tries = tries + 1
            end
            populateFromPlayerData(data)
            cached.loaded = true
            TriggerEvent('bablo-hud:playerLoaded')
        end)
    end

    RegisterNetEvent('NDCore:Client:OnPlayerLoaded', function()
        WaitForNDDataThenFire()
    end)

    RegisterNetEvent('NDCore:Client:OnPlayerUnload', function()
        cached.loaded = false
        cached.hunger = 100
        cached.thirst = 100
        cached.stress = 0
        cached.cash = 0
        cached.bank = 0
        cached.jobName = nil
        cached.jobLabel = nil
        cached.jobGrade = nil
        cached.playerName = nil
        TriggerEvent('bablo-hud:playerUnloaded')
    end)

    local data = GetPlayerData()
    if data and data.citizenid then
        WaitForNDDataThenFire()
    end
end)