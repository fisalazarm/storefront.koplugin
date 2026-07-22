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

-- Maps a Content-Type to the file extension MuPDF's image decoders expect.
-- Needed because plenty of image URLs carry no usable extension of their own
-- (e.g. camo.githubusercontent.com's proxy hashes), and the URL's apparent
-- extension can't be trusted anyway (e.g. a shields.io badge proxied through
-- camo keeps whatever extension we guessed even though camo actually served
-- SVG).
local CONTENT_TYPE_EXT = {
    ["image/png"] = "png",
    ["image/jpeg"] = "jpg",
    ["image/jpg"] = "jpg",
    ["image/gif"] = "gif",
    ["image/webp"] = "webp",
    ["image/bmp"] = "bmp",
}

-- Downloads `url` to `dest`. Returns `ok, final_path`: `final_path` may
-- differ from `dest` when the server's Content-Type reveals a different
-- (correct) extension than the one we guessed from the URL. Images that
-- turn out to be SVG (MuPDF's HTML box can't render them, whatever the
-- extension) are rejected -- this is the only reliable way to catch SVGs
-- served through camo, whose proxy URLs never contain ".svg".
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
        local content_type = (headers and (headers["content-type"] or headers["Content-Type"]) or ""):lower()
        if content_type:find("svg", 1, true) then
            os.remove(dest)
            return false
        end
        local mapped_ext = CONTENT_TYPE_EXT[content_type:match("^[^;%s]+") or ""]
        if mapped_ext then
            local current_ext = dest:match("%.([%w]+)$")
            if current_ext and current_ext:lower() ~= mapped_ext then
                local new_dest = dest:gsub("%.[%w]+$", "." .. mapped_ext)
                os.remove(new_dest)
                if os.rename(dest, new_dest) then
                    return true, new_dest
                end
            end
        end
        return true, dest
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

-- Resolves a possibly-relative image src against the repo's default branch
-- on raw.githubusercontent.com. GitHub's rendered README HTML leaves
-- relative paths (e.g. "./data/screenshots/x.png") exactly as authored --
-- it does not rewrite them to absolute URLs the way the github.com web UI
-- does -- so left alone they'd resolve against our local cache directory
-- instead of the repo, and MuPDF would find nothing there.
local function resolveImageUrl(raw_url, owner, repo)
    if raw_url:match("^https?://") or raw_url:match("^//") or raw_url:match("^data:") then
        return raw_url
    end
    local rel = raw_url:gsub("^%./", ""):gsub("^/+", "")
    return string.format("https://raw.githubusercontent.com/%s/%s/HEAD/%s", owner, repo, rel)
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
    local dir = getCacheDir()
    local safe_owner = owner:gsub("[^%w_-]", "_")
    local safe_repo = repo:gsub("[^%w_-]", "_")
    local path = string.format("%s/%s_%s_README.html", dir, safe_owner, safe_repo)

    -- 1. Check disk cache first for instant opening
    if lfs.attributes(path, "mode") == "file" then
        local cached_content = util.readFromFile(path)
        if cached_content and cached_content ~= "" then
            if cached_content:find("<img") then
                cached_content = cached_content:gsub("(<img[^>]+style=[\"'][^\"']*[%s\"';])width:%s*[^;\"]+;?", "%1")
                if not cached_content:find("storefront%-img:") then
                    cached_content = cached_content:gsub('(<img[^>]+src=["\'])([^"\']+)(["\'][^>]*>)', function(prefix, filename, suffix)
                        local full_img_path = dir .. "/" .. filename
                        if lfs.attributes(full_img_path, "mode") == "file" then
                            return string.format('<a href="storefront-img:%s">%s%s%s</a>', full_img_path, prefix, filename, suffix)
                        end
                        return prefix .. filename .. suffix
                    end)
                end
                cached_content = cached_content:gsub('<a[^>]+href=["\'][^"\']+["\'][^>]*>%s*(<a%s+href=["\']storefront%-img:[^"\']+["\'][^>]*>.-</a>)%s*</a>', "%1")
                util.writeToFile(cached_content, path)
            end
            return true, path
        end
    end

    -- 2. Fetch HTML content
    local body, err = GitHubClient.fetchReadmeHtml(owner, repo)
    if not body then
        return false, err or "fetch error"
    end
    
    -- Strip explicit width and height attributes so images expand to full width
    body = body:gsub("(<img[^>]+)%s+width=[\"'][^\"']*[\"']", "%1")
    body = body:gsub("(<img[^>]+)%s+height=[\"'][^\"']*[\"']", "%1")
    body = body:gsub("(<img[^>]+style=[\"'][^\"']*[%s\"';])width:%s*[^;\"]+;?", "%1")

    -- Download inline images locally for MuPDF HTML viewer widget
    body = body:gsub('(<img[^>]+src=["\'])([^"\']+)(["\'][^>]*>)', function(prefix, raw_url, suffix)
        local url = raw_url:gsub("&amp;", "&")
        if url:lower():match("%.svg") ~= nil then
            return ""
        end
        url = resolveImageUrl(url, owner, repo)

        local clean_url = url:gsub("[^%w]", "_")
        if #clean_url > 40 then
            clean_url = clean_url:sub(-40)
        end
        local ext = url:match("%.([%w]+)$") or "png"
        ext = ext:lower()
        if ext == "svg" then return "" end

        local img_filename = string.format("%s_%s_img_%s.%s", safe_owner, safe_repo, clean_url, ext)
        local img_dest = dir .. "/" .. img_filename

        if lfs.attributes(img_dest, "mode") == "file" then
            local img_html = prefix .. img_filename .. suffix
            return string.format('<a href="storefront-img:%s">%s</a>', img_dest, img_html)
        end

        local ok_img, final_path = downloadImage(url, img_dest)
        if ok_img and final_path then
            local final_filename = final_path:match("[^/]+$") or img_filename
            local img_html = prefix .. final_filename .. suffix
            return string.format('<a href="storefront-img:%s">%s</a>', final_path, img_html)
        end

        return ""
    end)

    -- Clean up double-nested <a> tags so storefront-img links take precedence
    body = body:gsub('<a[^>]+href=["\'][^"\']+["\'][^>]*>%s*(<a%s+href=["\']storefront%-img:[^"\']+["\'][^>]*>.-</a>)%s*</a>', "%1")

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

