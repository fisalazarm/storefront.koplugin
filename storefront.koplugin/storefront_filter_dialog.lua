local CheckButton = require("ui/widget/checkbutton")
local ButtonDialog = require("ui/widget/buttondialog")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")
local util = require("util")
local _ = require("gettext")

local StorefrontFilterDialog = {}

function StorefrontFilterDialog:show(Storefront)
    Storefront:ensureBrowserState()
    local filters = Storefront.browser_state
    local dialog
    local check_readme

    dialog = MultiInputDialog:new{
        title = _("Search & filters"),
        fields = {
            {
                description = _("Search text"),
                text = filters.search_text or "",
                hint = _("Name, description, topic"),
            },
            {
                description = _("Owner"),
                text = filters.owner or "",
                hint = _("anyone"),
            },
            {
                description = _("Minimum stars"),
                input_type = "number",
                text = (filters.min_stars and filters.min_stars > 0) and tostring(filters.min_stars) or "",
                hint = "0",
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Clear filters"),
                    callback = function()
                        Storefront.browser_state.search_text = ""
                        Storefront.browser_state.owner = ""
                        Storefront.browser_state.min_stars = 0
                        Storefront.browser_state.page = 1
                        Storefront.browser_state.scroll_offset = nil
                        Storefront.browser_state.search_in_readme = false
                        Storefront.readme_filter = nil
                        Storefront:saveBrowserState()
                        UIManager:close(dialog)
                        Storefront:reopenBrowser()
                    end,
                },
                {
                    text = _("Apply"),
                    is_enter_default = true,
                    callback = function()
                        local values = dialog:getFields()
                        Storefront.browser_state.search_text = util.trim(values[1] or "")
                        Storefront.browser_state.owner = util.trim(values[2] or "")
                        local stars = tonumber(values[3]) or 0
                        if stars < 0 then
                            stars = 0
                        end
                        Storefront.browser_state.min_stars = math.floor(stars)
                        local enable_readme = false
                        if check_readme then
                            enable_readme = check_readme.checked and true or false
                            Storefront.browser_state.search_in_readme = enable_readme
                        end
                        Storefront.readme_filter = nil
                        Storefront.browser_state.page = 1
                        Storefront.browser_state.scroll_offset = nil
                        Storefront:saveBrowserState()
                        UIManager:close(dialog)
                        Storefront:reopenBrowser()
                    end,
                },
            },
        },
    }

    check_readme = CheckButton:new{
        text = _("Search in README"),
        checked = filters.search_in_readme == true,
        parent = dialog,
    }
    dialog:addWidget(check_readme)
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

return StorefrontFilterDialog
