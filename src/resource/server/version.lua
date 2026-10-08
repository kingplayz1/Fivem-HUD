-- Version checker for bablo-hud

CreateThread(function()
    local resourceName  = GetCurrentResourceName()
    local currentVersion = GetResourceMetadata(resourceName, "version", 0) or "0.0.0"

    Wait(5000)
    Info("^6[CHECKING UPDATES]^0 ^7" .. resourceName .. "^0")

    -- Convert "1.2.3" → 123 for numeric comparison
    local function versionToNumber(versionStr)
        local stripped = (versionStr or "0"):gsub("%.", "")
        return tonumber(stripped) or 0
    end

    -- Word-wrap a string to fit within maxWidth visible characters (strips color codes for measurement)
    local function wordWrap(text, maxWidth)
        local words = {}
        for word in text:gmatch("%S+") do
            table.insert(words, word)
        end

        local lines   = {}
        local current = ""

        for _, word in ipairs(words) do
            local candidate = current == "" and word or (current .. " " .. word)
            local visibleLen = candidate:gsub("%^%d", ""):len()

            if visibleLen <= maxWidth then
                current = candidate
            else
                if current ~= "" then
                    table.insert(lines, current)
                end
                current = word
            end
        end

        if current ~= "" then
            table.insert(lines, current)
        end

        return lines
    end

    local url = "https://raw.githubusercontent.com/TheRealBablo/version/master/" .. resourceName .. ".json"

    PerformHttpRequest(url, function(statusCode, responseBody)
        if not responseBody or responseBody == "" then
            Info("^1[VERSION CHECK] No response (status " .. tostring(statusCode) .. ").^0")
            return
        end

        local ok, data = pcall(json.decode, responseBody)
        if not (ok and data and data.version) then
            Info("^1[VERSION CHECK] Invalid version data received.^0")
            return
        end

        local remoteNum  = versionToNumber(data.version)
        local currentNum = versionToNumber(currentVersion)

        if remoteNum > currentNum then
            local divider = "^3" .. string.rep("-", 50) .. "^0"

            Info("")
            Info("^1[UPDATE AVAILABLE]^0 ^7" .. resourceName .. "^0")
            Info(divider)
            Info("^7Current Version: ^5" .. currentVersion .. "^0")
            Info("^7New Version:     ^2" .. data.version .. "^0")
            Info("")
            Info("^6Patch Notes:^0")

            if data.descriptions and #data.descriptions > 0 then
                for _, description in ipairs(data.descriptions) do
                    local lines = wordWrap(description, 75)
                    for i, line in ipairs(lines) do
                        if i == 1 then
                            Info("^6  \226\128\162 ^5" .. line .. "^0")
                        else
                            Info("^5    " .. line .. "^0")
                        end
                    end
                end
            else
                Info("^6  \226\128\162 ^5No patch notes available^0")
            end

            Info("")
            Info("^4Download: ^7portal.cfx.re/assets/granted-assets^0")
            Info(divider)
            Info("")
        else
            Info("")
            Info("^2[UP TO DATE]^0 ^7" .. resourceName .. " - Version " .. currentVersion .. "^0")
            Info("")
        end
    end, "GET")
end)
