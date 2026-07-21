-- storefront_logger.lua
-- Dedicated logging utility for Storefront plugin troubleshooting

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")

local Logger = {}

local function getLogFilePath()
    local dir = DataStorage:getDataDir() .. "/plugins/storefront.koplugin"
    local attr = lfs.attributes(dir, "mode")
    if attr ~= "directory" then
        dir = DataStorage:getSettingsDir()
    end
    return dir .. "/storefront.log"
end

local function writeLog(level, msg)
    -- Logging disabled per user request
end

function Logger.log(msg)
    writeLog("INFO", msg)
end

function Logger.info(msg)
    writeLog("INFO", msg)
end

function Logger.action(msg)
    writeLog("ACTION", msg)
end

function Logger.warn(msg)
    writeLog("WARN", msg)
end

function Logger.err(msg)
    writeLog("ERROR", msg)
end

function Logger.clear()
    local path = getLogFilePath()
    local f = io.open(path, "w")
    if f then
        f:close()
    end
end

Logger.reset = Logger.clear

return Logger
