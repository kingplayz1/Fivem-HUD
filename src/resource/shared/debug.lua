-- Logging / debug utilities for bablo-hud

local resourcePrefix = ("[%s]"):format(GetCurrentResourceName())

-- Returns true if Config.DEBUG == true
function IsDebugEnabled()
    local config = rawget(_G, "Config")
    if type(config) == "table" and config.DEBUG ~= nil then
        return config.DEBUG == true
    end
    return false
end

-- Serialise any value to a printable string.
-- Tables are pretty-printed as JSON; everything else uses tostring.
function Serialise(value)
    if type(value) == "table" then
        local ok, encoded = pcall(json.encode, value, { indent = true })
        if ok and encoded then return encoded end
    end
    return tostring(value)
end

-- Build a formatted message string from a format string + varargs,
-- serialising any table arguments automatically.
-- When the first argument is not a string, all arguments are serialised
-- and concatenated with spaces.
function FormatMessage(fmt, ...)
    local argCount = select("#", ...)

    -- No extra args: just serialise the single value
    if argCount == 0 then
        return Serialise(fmt)
    end

    -- First arg is not a string: serialise everything and join
    if type(fmt) ~= "string" then
        local parts = { Serialise(fmt) }
        for i = 1, argCount do
            parts[#parts + 1] = Serialise(select(i, ...))
        end
        return table.concat(parts, " ")
    end

    -- Format string path: serialise any table args, then string.format
    local args = { ... }
    for i = 1, #args do
        if type(args[i]) == "table" then
            args[i] = Serialise(args[i])
        end
    end

    local ok, result = pcall(string.format, fmt, table.unpack(args))
    if ok then return result end

    -- string.format failed (wrong arg count/type): fall back to concat
    local parts = { fmt }
    for i = 1, #args do
        parts[#parts + 1] = Serialise(args[i])
    end
    return table.concat(parts, " ")
end

-- Core log emitter: prints "[resource][LEVEL] message".
-- When debugOnly is true, skips output if debug mode is off.
function EmitLog(level, debugOnly, fmt, ...)
    if debugOnly and not IsDebugEnabled() then return end
    local message = FormatMessage(fmt, ...)
    print(("%s[%s] %s"):format(resourcePrefix, level, message))
end

-- Public log functions (all debug-gated except where noted)
function Trace(fmt, ...)  EmitLog("TRACE", true,  fmt, ...) end
function Info(fmt, ...)   EmitLog("INFO",  true,  fmt, ...) end
function Warn(fmt, ...)   EmitLog("WARN",  true,  fmt, ...) end
function Error(fmt, ...)  EmitLog("ERROR", true,  fmt, ...) end
function DebugPrint(fmt, ...) Trace(fmt, ...) end
