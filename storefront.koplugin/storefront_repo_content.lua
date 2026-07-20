local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local FileManager = require("apps/filemanager/filemanager")
local _ = require("gettext")
local http = require("socket.http")
local ltn12 = require("ltn12")
local util = require("util")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local GitHubClient = require("storefront_net_github")

local RepoContent = {}

local function getCacheDir()
    local dir = DataStorage:getDataDir() .. "/cache/Storefront/readme"
    local ok, err = util.makePath(dir)
    if not ok then
        logger.warn("Storefront README cache dir failure", err)
    end
    return dir
end

local function buildRawUrl(owner, repo)
    return string.format("https://raw.githubusercontent.com/%s/%s/HEAD/README.md", owner, repo)
end

local function download(url)
    local response = {}
    local _, code = http.request{
        url = url,
        sink = ltn12.sink.table(response),
        headers = {
            ["Accept"] = "text/plain",
            ["User-Agent"] = "KOReader-Storefront",
        },
    }
    return tonumber(code), table.concat(response)
end

local function downloadImage(url, dest, max_redirects)
    max_redirects = max_redirects or 5
    if max_redirects <= 0 then return false end
    local f, err = io.open(dest, "wb")
    if not f then return false end
    local _, code, headers = http.request{
        url = url,
        sink = ltn12.sink.file(f),
        headers = {
            ["User-Agent"] = "KOReader-Storefront",
        },
        redirect = false,
    }
    code = tonumber(code)
    if code == 200 then
        return true
    elseif (code == 301 or code == 302 or code == 303 or code == 307 or code == 308) and headers and headers.location then
        os.remove(dest)
        local new_url = headers.location
        if not new_url:match("^https?://") then
            local host = url:match("^(https?://[^/]+)")
            if host then
                if new_url:sub(1,1) == "/" then
                    new_url = host .. new_url
                else
                    new_url = host .. "/" .. new_url
                end
            end
        end
        return downloadImage(new_url, dest, max_redirects - 1)
    else
        os.remove(dest)
        return false
    end
end

function RepoContent.stripMarkdown(text)
    if not text then return "" end
    -- Remove HTML comments
    text = text:gsub("<!%-%-.-%-%->", "")
    -- Strip HTML tags completely
    text = text:gsub("<[^>]+>", "")
    -- Remove markdown images: ![alt](url)
    text = text:gsub("!%[[^%]]*%]%([^%)]*%)", "")
    -- Remove inline code fences: `code`
    text = text:gsub("`([^`]+)`", "%1")
    -- Remove blocks of code fences: ```
    text = text:gsub("```", "")
    -- Remove reference definitions: [label]: url
    text = text:gsub("%[%S+%]:%s*%S+", "")
    -- Replace ATX headings: # Header -> HEADER
    text = text:gsub("([^\n]*)\n([#]+)%s*([^\n]+)", function(before, level, title)
        return before .. "\n" .. title:upper()
    end)
    text = text:gsub("^([#]+)%s*([^\n]+)", function(level, title)
        return title:upper()
    end)
    -- Remove link styling while keeping text: [link text](url) -> link text
    text = text:gsub("%[([^%]]+)%]%([^%)]*%)", "%1")
    -- Remove reference style link: [link text][ref] -> link text
    text = text:gsub("%[([^%]]+)%]%[[^%]]*%]", "%1")
    -- Remove bold/italic markers: **bold**, __bold__
    text = text:gsub("%*%*([^*]+)%*%*", "%1")
    text = text:gsub("__([^_]+)__", "%1")
    text = text:gsub("%*([^*]+)%*", "%1")
    text = text:gsub("_([^_]+)_", "%1")
    -- Remove horizontal rules
    text = text:gsub("\n[-*#]%s*[-*#]%s*[-*#]%s*\n", "\n")
    return text
end

function RepoContent.fetchReadme(owner, repo)
    if not owner or not repo then
        return false, "missing owner/repo"
    end
    local url = buildRawUrl(owner, repo)
    local code, body = download(url)
    if code ~= 200 then
        return false, string.format("HTTP %s", tostring(code))
    end
    if not body or body == "" then
        return false, "empty body"
    end
    local dir = getCacheDir()
    local safe_owner = owner:gsub("[^%w_-]", "_")
    local safe_repo = repo:gsub("[^%w_-]", "_")
    local path = string.format("%s/%s_%s_README.md", dir, safe_owner, safe_repo)
    local ok, err = util.writeToFile(body, path)
    if not ok then
        return false, err or "write error"
    end
    return true, path
end

function RepoContent.fetchReadmeHtml(owner, repo)
    if not owner or not repo then
        return false, "missing owner/repo"
    end
    local body, err = GitHubClient.fetchReadmeHtml(owner, repo)
    if not body then
        return false, err or "fetch error"
    end
    local dir = getCacheDir()
    local safe_owner = owner:gsub("[^%w_-]", "_")
    local safe_repo = repo:gsub("[^%w_-]", "_")
    
    -- Strip explicit width and height attributes so images expand to full width
    body = body:gsub("(<img[^>]+)%s+width=[\"'][^\"']*[\"']", "%1")
    body = body:gsub("(<img[^>]+)%s+height=[\"'][^\"']*[\"']", "%1")
    body = body:gsub("(<img[^>]+style=[\"'][^\"']*)width:%s*[^;\"]+;?", "%1")

    local image_idx = 1
    body = body:gsub('(<img[^>]+src=["\'])([^"\']+)(["\'][^>]*>)', function(prefix, raw_url, suffix)
        -- Decode HTML entity query parameters (&amp; -> &) for signed S3 / GitHub user asset URLs
        local url = raw_url:gsub("&amp;", "&")

        -- SVG images (e.g. shields.io badges) cannot be rendered by MuPDF HTML box; strip them to prevent [image] text links
        local is_svg = url:lower():match("%.svg") ~= nil
        if is_svg then
            return ""
        end

        local ext = url:match("%.(%w+)") or "png"
        ext = ext:gsub("%?.*", ""):lower()
        if #ext > 4 or ext == "" then ext = "png" end

        local img_filename = string.format("%s_%s_img%d.%s", safe_owner, safe_repo, image_idx, ext)
        local img_path = dir .. "/" .. img_filename
        if downloadImage(url, img_path) then
            image_idx = image_idx + 1
            return prefix .. img_filename .. suffix
        end
        return ""
    end)

    local path = string.format("%s/%s_%s_README.html", dir, safe_owner, safe_repo)
    local ok, write_err = util.writeToFile(body, path)
    if not ok then
        return false, write_err or "write error"
    end
    return true, path
end

-- Remove every cached README markdown file generated by RepoContent.fetchReadme.
-- Returns a table with `removed` count and `errors` list (failed file paths).
function RepoContent.clearReadmeCache()
    local dir = DataStorage:getDataDir() .. "/cache/Storefront/readme"
    local removed = 0
    local errors = {}
    if lfs.attributes(dir, "mode") ~= "directory" then
        return { removed = 0, errors = errors }
    end
    for entry in lfs.dir(dir) do
        if entry ~= "." and entry ~= ".." then
            local full_path = dir .. "/" .. entry
            local mode = lfs.attributes(full_path, "mode")
            if mode == "file" then
                local ok = os.remove(full_path)
                if ok then
                    removed = removed + 1
                else
                    table.insert(errors, full_path)
                end
            end
        end
    end
    return { removed = removed, errors = errors }
end

function RepoContent.openReadme(path)
    if not path then
        UIManager:show(InfoMessage:new{ text = _("Missing README path"), timeout = 4 })
        return
    end
    local text, err = util.readFromFile(path)
    if not text or text == "" then
        UIManager:show(InfoMessage:new{ text = _("Unable to read README file"), timeout = 4 })
        return
    end
    local TextViewer = require("ui/widget/textviewer")
    UIManager:show(TextViewer:new{
        text = text,
        title = _("README"),
    })
end

return RepoContent

