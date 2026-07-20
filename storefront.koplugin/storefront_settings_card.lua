local Screen = require("device").screen
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local TextWidget = require("ui/widget/textwidget")
local GestureRange = require("ui/gesturerange")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalSpan = require("ui/widget/horizontalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local LineWidget = require("ui/widget/linewidget")
local _ = require("gettext")
local Cache = require("storefront_cache")
local storefront_theme = require("storefront_theme")

local StorefrontSettingsCard = {}

local function sc(val)
    return Screen:scaleBySize(val)
end

function StorefrontSettingsCard.show(Storefront)
    local current_kind = (Storefront.browser_state and Storefront.browser_state.kind) or "plugin"
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local dialog_w = math.min(sw - sc(20), sc(380))

    local ui_font_size = 16
    local title_font_size = 18

    local overlay
    local refresh

    refresh = function()
        if overlay then
            UIManager:close(overlay, "ui")
        end

        local function span()
            return VerticalSpan:new{ width = storefront_theme.gap }
        end

        -- Title Widget
        local title_label = TextWidget:new{
            text = _("Settings"),
            face = Font:getFace("cfont", title_font_size),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }

        local title_container = FrameContainer:new{
            padding = sc(10),
            bordersize = 0,
            title_label,
        }

        local content_vg = VerticalGroup:new{
            align = "left",
            title_container,
            LineWidget:new{
                dimen = Geom:new{ w = dialog_w - sc(4), h = sc(1) },
                background = Blitbuffer.COLOR_BLACK,
            }
        }

        -- Helper to create setting row
        local function create_setting_row(icon_text, left_text, right_widget, callback)
            local row_elements = {}

            -- Icon (represented as text/unicode character or emoji-like indicator)
            if icon_text then
                local icon = TextWidget:new{
                    text = icon_text,
                    face = Font:getFace("cfont", ui_font_size),
                    fgcolor = callback and Blitbuffer.COLOR_BLACK or storefront_theme.color_label_dim,
                }
                table.insert(row_elements, icon)
                table.insert(row_elements, HorizontalSpan:new{ width = sc(8) })
            end

            -- Left Text
            local txt = TextBoxWidget:new{
                text = left_text,
                face = Font:getFace("cfont", ui_font_size),
                fgcolor = callback and Blitbuffer.COLOR_BLACK or storefront_theme.color_label_dim,
                width = dialog_w - sc(150),
                alignment = "left",
            }
            table.insert(row_elements, txt)

            -- Spacer to push right widget
            table.insert(row_elements, HorizontalSpan:new{ width = sc(8) })

            -- Right Widget (optional)
            if right_widget then
                table.insert(row_elements, right_widget)
            end

            local row_content = HorizontalGroup:new(row_elements)

            local frame = FrameContainer:new{
                bordersize = 0,
                padding = sc(10),
                width = dialog_w - sc(4),
                row_content,
            }

            if not callback then
                return frame
            end

            local item = InputContainer:new{ frame }
            item.ges_events = {
                Tap = {
                    GestureRange:new{
                        ges = "tap",
                        range = function()
                            local dim = item.dimen or { x = 0, y = 0, w = 0, h = 0 }
                            return Geom:new{
                                x = dim.x or 0,
                                y = dim.y or 0,
                                w = dialog_w - sc(4),
                                h = dim.h or 0
                            }
                        end
                    }
                }
            }
            item.onTap = function()
                callback()
                return true
            end
            return item
        end

        -- 1. Refresh Cache Row
        local ts = Cache.getLastFetched(current_kind)
        local time_str = ts and ts > 0 and os.date("%H:%M", ts) or "Never"
        local total_repos = #Cache.listRepos(current_kind)
        local meta_text = string.format("%d · %s", total_repos, time_str)
        local meta_widget = TextWidget:new{
            text = meta_text,
            face = Font:getFace("cfont", ui_font_size - 2),
            fgcolor = storefront_theme.color_label_dim,
        }
        table.insert(content_vg, create_setting_row("↻", _("Refresh cache"), meta_widget, function()
            UIManager:close(overlay, "ui")
            Storefront:browserRefresh()
        end))

        -- Divider line
        table.insert(content_vg, LineWidget:new{
            dimen = Geom:new{ w = dialog_w - sc(4), h = sc(1) },
            background = Blitbuffer.COLOR_DARK_GRAY,
        })

        -- 2. Include 0-star forks Row
        local include_zero = Storefront.browser_state.include_zero_star_forks == true
        local fork_indicator = include_zero and "☑" or "☐"
        table.insert(content_vg, create_setting_row(fork_indicator, _("Include 0-star forks"), nil, function()
            Storefront.browser_state.include_zero_star_forks = not include_zero
            Storefront:saveBrowserState()
            refresh()
        end))

        -- Divider line
        table.insert(content_vg, LineWidget:new{
            dimen = Geom:new{ w = dialog_w - sc(4), h = sc(1) },
            background = Blitbuffer.COLOR_DARK_GRAY,
        })

        -- 3. GitHub Token Row
        local ok_cfg, StorefrontConfig = pcall(require, "storefront_configuration")
        local github_configured = false
        if ok_cfg and StorefrontConfig and StorefrontConfig.auth and StorefrontConfig.auth.github then
            local token = StorefrontConfig.auth.github.token
            if token and token ~= "" and token ~= "your_github_token" then
                github_configured = true
            end
        end

        local token_status_text = github_configured and _("Configured ✓") or _("Not Found")
        local token_widget = TextWidget:new{
            text = token_status_text,
            face = Font:getFace("cfont", ui_font_size - 1),
            fgcolor = storefront_theme.color_label_dim,
        }
        table.insert(content_vg, create_setting_row(nil, _("GitHub token"), token_widget, nil))

        -- Divider line
        table.insert(content_vg, LineWidget:new{
            dimen = Geom:new{ w = dialog_w - sc(4), h = sc(1) },
            background = Blitbuffer.COLOR_DARK_GRAY,
        })

        -- 4. Close Button Row
        local close_text_widget = TextWidget:new{
            text = _("Close"),
            face = Font:getFace("cfont", ui_font_size),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
        local close_row_content = HorizontalGroup:new{
            HorizontalSpan:new{ width = (dialog_w - close_text_widget:getSize().w) / 2 - sc(10) },
            close_text_widget,
        }
        local close_frame = FrameContainer:new{
            bordersize = 0,
            padding = sc(10),
            width = dialog_w - sc(4),
            close_row_content,
        }
        local close_btn = InputContainer:new{ close_frame }
        close_btn.ges_events = {
            Tap = {
                GestureRange:new{
                    ges = "tap",
                    range = function()
                        local dim = close_btn.dimen or { x = 0, y = 0, w = 0, h = 0 }
                        return Geom:new{
                            x = dim.x or 0,
                            y = dim.y or 0,
                            w = dialog_w - sc(4),
                            h = dim.h or 0
                        }
                    end
                }
            }
        }
        close_btn.onTap = function()
            UIManager:close(overlay, "ui")
            return true
        end
        table.insert(content_vg, close_btn)

        -- Build modal frame
        local card = FrameContainer:new{
            padding = 0,
            radius = sc(12),
            bordersize = sc(2),
            color = Blitbuffer.COLOR_BLACK,
            background = storefront_theme.color_bg,
            width = dialog_w - sc(2),
            content_vg
        }

        local card_outer = FrameContainer:new{
            bordersize = sc(1),
            color = Blitbuffer.Color8(180),
            padding = 0,
            background = storefront_theme.color_bg,
            radius = sc(12),
            width = dialog_w,
            card
        }

        overlay = InputContainer:new{
            align = "center",
            vertical_align = "center",
            dimen = Geom:new{ w = sw, h = sh },
            key_events = {
                Close = { { "Back" } }
            },
            ges_events = {
                Tap = {
                    GestureRange:new{
                        ges = "tap",
                        range = function()
                            return Geom:new{ x = 0, y = 0, w = sw, h = sh }
                        end
                    }
                }
            },
            card_outer
        }

        overlay.onTap = function()
            UIManager:close(overlay, "ui")
            return true
        end

        overlay.onClose = function()
            UIManager:close(overlay, "ui")
            return true
        end

        UIManager:show(overlay, "ui")
    end

    refresh()
end

return StorefrontSettingsCard
