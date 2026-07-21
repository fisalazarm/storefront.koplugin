-- storefront_readme_test.lua
-- Unit tests for Storefront README Markdown-to-HTML converter
package.path = "plugins/storefront.koplugin/?.lua;" .. package.path

local failures = 0
local function check(label, condition)
    if condition then
        print("PASS", label)
    else
        failures = failures + 1
        print("FAIL", label)
    end
end

-- Mock dependencies for storefront_net_github loading headlessly
package.loaded["socket.http"] = {}
package.loaded["json"] = {}
package.loaded["socket.url"] = {}
package.loaded["logger"] = { dbg = function() end, info = function() end, warn = function() end, err = function() end }
package.loaded["datastorage"] = { getSettingsDir = function() return "/tmp" end }
package.loaded["luasettings"] = { open = function() return { readSetting = function() end, saveSetting = function() end, delSetting = function() end, flush = function() end } end }

local GitHubClient = require("storefront_net_github")

print("=== Running README Markdown-to-HTML Unit Tests ===")

-- Test 1: Heading conversion
local html_h1 = GitHubClient.markdownToHtml("# My Plugin Header")
check("H1 header converted to <h1>", html_h1:find("<h1>My Plugin Header</h1>") ~= nil)
check("H1 header does NOT contain raw markdown '#'", html_h1:find("# My Plugin Header") == nil)

-- Test 2: Sub-headings H2 and H3
local html_h2_h3 = GitHubClient.markdownToHtml("## Installation\n### Requirements")
check("H2 header converted to <h2>", html_h2_h3:find("<h2>Installation</h2>") ~= nil)
check("H3 header converted to <h3>", html_h2_h3:find("<h3>Requirements</h3>") ~= nil)

-- Test 3: Unordered List conversion
local html_list = GitHubClient.markdownToHtml("- Feature 1\n- Feature 2")
check("Unordered list contains <ul>", html_list:find("<ul>") ~= nil)
check("Unordered list contains <li>Feature 1</li>", html_list:find("<li>Feature 1</li>") ~= nil)
check("Unordered list contains <li>Feature 2</li>", html_list:find("<li>Feature 2</li>") ~= nil)

-- Test 4: Bold and Italic formatting
local html_inline = GitHubClient.markdownToHtml("**Bold text** and *Italic text*")
check("Bold text converted to <b>Bold text</b>", html_inline:find("<b>Bold text</b>") ~= nil)
check("Italic text converted to <i>Italic text</i>", html_inline:find("<i>Italic text</i>") ~= nil)

-- Test 5: Links conversion
local html_link = GitHubClient.markdownToHtml("[GitHub Page](https://github.com)")
check("Markdown link converted to <a href=...>", html_link:find('<a href="https://github.com">GitHub Page</a>') ~= nil)

-- Test 6: Code blocks
local html_code = GitHubClient.markdownToHtml("```lua\nlocal x = 1\n```")
check("Code block converted to <pre><code>", html_code:find("<pre><code>") ~= nil)
check("Code block content preserved", html_code:find("local x = 1") ~= nil)

-- Test 7: Ensure output is wrapped in markdown-body container
check("Output wrapped in <div class=\"markdown-body\">", html_h1:find("<div class=\"markdown%-body\">") ~= nil)

if failures > 0 then
    print(string.format("README TESTS FAILED: %d errors", failures))
    os.exit(1)
else
    print("ALL README TESTS PASSED")
end
