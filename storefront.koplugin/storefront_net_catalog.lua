local http = require("socket.http")
local json = require("json")
local logger = require("logger")
local Cache = require("storefront_cache")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local ok_cfg, StorefrontConfig = pcall(require, "storefront_config")
if not ok_cfg then
    ok_cfg, StorefrontConfig = pcall(require, "storefront_configuration")
end
if not ok_cfg then
    StorefrontConfig = {}
end

local CatalogClient = {}

local DEFAULT_CATALOG_URL = "https://jpautz.github.io/storefront.koplugin/catalog.json"
local USER_AGENT = "KOReader-Storefront"

local SETTINGS_PATH = DataStorage:getSettingsDir() .. "/Storefront.lua"
local StorefrontSettings = LuaSettings:open(SETTINGS_PATH)
local CATALOG_URL_KEY = "catalog_url"

function CatalogClient.getCatalogUrl()
    local saved = StorefrontSettings:readSetting(CATALOG_URL_KEY)
    if type(saved) == "string" and saved ~= "" then
        return saved
    end
    if StorefrontConfig.catalog_url and StorefrontConfig.catalog_url ~= "" then
        return StorefrontConfig.catalog_url
    end
    return DEFAULT_CATALOG_URL
end

function CatalogClient.setCatalogUrl(url)
    url = url and url:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if url == "" or url == DEFAULT_CATALOG_URL then
        StorefrontSettings:delSetting(CATALOG_URL_KEY)
    else
        StorefrontSettings:saveSetting(CATALOG_URL_KEY, url)
    end
    StorefrontSettings:flush()
end

local function newTableSink(target)
    return function(chunk, err)
        if chunk then
            target[#target + 1] = chunk
        end
        return 1, err
    end
end

function CatalogClient.fetchCatalog(url_to_fetch)
    local target_url = url_to_fetch or CatalogClient.getCatalogUrl()
    logger.info("Storefront: fetching static catalog from", target_url)
    
    local response_body = {}
    local headers = {
        ["Accept"] = "application/json",
        ["User-Agent"] = USER_AGENT,
    }
    
    local _, code = http.request{
        url = target_url,
        headers = headers,
        sink = newTableSink(response_body),
    }
    
    code = tonumber(code) or 0
    if code ~= 200 then
        logger.warn("Storefront catalog fetch error", target_url, code)
        return nil, { code = code, body = "HTTP " .. tostring(code) }
    end
    
    local body = table.concat(response_body)
    local ok, parsed = pcall(json.decode, body)
    if not ok or type(parsed) ~= "table" then
        logger.warn("Storefront catalog decode error", parsed)
        return nil, { code = 0, body = "JSON decode error" }
    end
    
    return parsed, nil
end

function CatalogClient.updateCacheFromCatalog(catalog_data)
    if not catalog_data or type(catalog_data) ~= "table" then
        return false, "invalid catalog format"
    end
    
    local plugins = catalog_data.plugins or {}
    local patches = catalog_data.patches or {}
    
    logger.info("Storefront: updating cache from static catalog", "plugins:", #plugins, "patches:", #patches)
    
    -- Store plugin repositories
    Cache.storeRepos("plugin", plugins)
    
    -- Store patch repositories
    Cache.storeRepos("patch", patches)
    
    -- Store patch file metadata for patch repositories
    for _, repo in ipairs(patches) do
        local repo_id = tonumber(repo.repo_id or repo.id)
        if repo_id and repo.patch_files and type(repo.patch_files) == "table" then
            local pushed_at = repo.pushed_at or repo.updated_at or ""
            Cache.storePatchFiles(repo_id, repo.patch_files, pushed_at)
        end
    end
    
    return true, nil
end

function CatalogClient.fetchAndUpdateCache(url_to_fetch)
    local catalog, err = CatalogClient.fetchCatalog(url_to_fetch)
    if not catalog then
        return false, err
    end
    local ok, update_err = CatalogClient.updateCacheFromCatalog(catalog)
    if not ok then
        return false, update_err
    end
    return true, nil
end

return CatalogClient
