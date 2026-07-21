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

function Logger.log(msg)
    local path = getLogFilePath()
    local f = io.open(path, "a")
    if f then
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        f:write(string.format("[%s] %s\n", timestamp, tostring(msg)))
        f:close()
    end
    local ok, logger = pcall(require, "logger")
    if ok and logger and logger.info then
        logger.info("[Storefront]", tostring(msg))
    end
end

function Logger.clear()
    local path = getLogFilePath()
    local f = io.open(path, "w")
    if f then
        f:close()
    end
end

return Logger
