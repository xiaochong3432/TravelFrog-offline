-------------------------------------------------------------------------------
-- 工具栏配置 https://yuque.antfin.com/ejoy-platform/ejoy-platform/gio111
--
-- Created Date: 2022.04.11
-- Author: 四境
--
-- Copyright (c) 2022 灵犀互娱
-------------------------------------------------------------------------------

local E = require 'ejoysdk_lua.ejoysdk'
local Lang = require 'ejoysdk_lua.lang.util'
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'

-- ======================== 1. Config ========================

local M = {}
local TAG = "ejoysdk_webview_toolbar"

local TOOLBAR_DEFAUTL_ICON_SIZE = 24
local TOOLBAR_DEFAUTL_ICON_PADDING = 16
local TOOLBAR_DEFAUTL_ICON_FONT_SIZE = 13
local TOOLBAR_DEFAUTL_TITLE_FONT_SIZE = 18

M.align = {
    left = "left",
    right = "right",
    center = "center",
    top = "top",
    bottom = "bottom"
}

M.theme = {
    light = "light",
    dark = "dark",
    light_bottom = "light_bottom",
    dark_bottom = "dark_bottom",
}

-- more、share、custom等native实现后再定义
M.type = {
    backward = "backward",
    forward = "forward",
    reload = "reload",
    close = "close",
    title = "title",
    space = "space",
}

-- ======================== 2. Generator ========================

-- 图标样式
local function general_item_icon(src, height, width, color)
    local icon = {
        src = src, 
        height = height,
        width = width,
        color = color
    }
    return icon
end

-- 图标文字样式或标题样式
local function general_item_title(text, color, bold, font_size, align)
    local title = {
        text = text,
        color = color,
        bold = bold,
        font_size = font_size,
        align = align,
    }
    return title
end

-- 按钮样式
local function general_button(_type, src, color, align, align_padding, ext)
    local item = {
        type = _type,
        icon = general_item_icon(src, TOOLBAR_DEFAUTL_ICON_SIZE, TOOLBAR_DEFAUTL_ICON_SIZE, color),
        visible = true,
        align = align,
        align_padding = align_padding,
        ext = ext
    }
    return item
end

-- 标题样式
local function general_title(align, align_padding, use_h5_title, ext)
    local item = {
        type = "title",
        align = align,
        visible = true,
        align_padding = align_padding,
        use_h5_title = use_h5_title,
        ext = ext
    }
    return item
end

-- ======================== 3. Checker ========================
local function check_is_color(node, color_str)
    local error_tip = ''
    if color_str == nil or type(color_str) ~= 'string' then
        error_tip = tostring(node) .. ' is nil or not a string; '
    elseif #color_str ~= 7 and #color_str ~= 9 and not E.Utils.start_with(color_str, '#')  then
        error_tip = tostring(node) .. ':' .. tostring(color_str) .. ' is not ARGB or RGB string; '
    end
    
    return error_tip
end

local function check_available_item_type(_type)
    local error_tip = ''
    if _type == nil then
        error_tip = 'item type is nil; '
    elseif M.type[_type] == nil then
        error_tip = 'item type:' .. tostring(_type) .. ' is not available; '
    end
    
    return error_tip
end

local function check_available_item_align(node, align)
    local error_tip = ''
    if align == nil then
        error_tip = node .. '.align is nil;'
    elseif M.align[align] == nil then
        error_tip = node .. '.align:' .. tostring(align) .. ' is not available; '
    end
    
    return error_tip
end

local function check_available_type(keystr, value, available_type)
    local error_tip = ''
    if type(value) ~= available_type then
        error_tip = keystr .. ':' .. tostring(value) .. '('.. tostring(type(value)) .. ') is not a ' .. available_type .. ' value; '
    end
    
    return error_tip
end

local function check_bar(node, bar_config)
    
    local error_tip = ''

    if node and bar_config then
        error_tip = error_tip .. tostring(check_is_color(node..'.background_color', bar_config.background_color))
        if bar_config.items == nil or (bar_config.items and #bar_config.items == 0) then
            error_tip = error_tip .. node ..'.items should be an array and not empty; '
        end

        if bar_config.items then
            for _, item in pairs(bar_config.items) do
                error_tip = error_tip .. tostring(check_available_item_type(item.type))
                local item_type = item.type or ''

                -- icon 检查
                if item.icon then
                    -- color
                    error_tip = error_tip .. tostring(check_is_color(tostring(item_type)..'.icon.color', item.icon.color))
                    -- height
                    if item.icon.height == nil then item.icon.height = TOOLBAR_DEFAUTL_ICON_SIZE end
                    -- width
                    if item.icon.width == nil then item.icon.width = TOOLBAR_DEFAUTL_ICON_SIZE end

                    error_tip = error_tip .. tostring(check_available_type('item.icon.height', item.icon.height, "number"))
                    error_tip = error_tip .. tostring(check_available_type('item.icon.width', item.icon.width, "number"))
                end

                -- 文字检查
                if item.title then
                    -- color 
                    error_tip = error_tip .. tostring(check_is_color(tostring(item_type)..'.title.color', item.title.color))
                    -- align
                    if item.type == M.type.title then
                        if item.title.align == nil then 
                            item.title.align = M.align.center 
                        else 
                            error_tip = error_tip .. tostring(check_available_item_align('item.title', item.title.align))
                        end
                        -- font_size
                        if item.title.font_size == nil then 
                            item.title.font_size = TOOLBAR_DEFAUTL_TITLE_FONT_SIZE 
                        elseif type(item.title.font_size) == 'number' then
                            if item.title.font_size < 0 then item.title.font_size = TOOLBAR_DEFAUTL_TITLE_FONT_SIZE end
                        end
                        
                    else
                        -- font_size
                        if item.title.font_size == nil then 
                            item.title.font_size = TOOLBAR_DEFAUTL_ICON_FONT_SIZE 
                        elseif type(item.title.font_size) == 'number' then
                            if item.title.font_size < 0 then item.title.font_size = TOOLBAR_DEFAUTL_ICON_FONT_SIZE end
                        end

                    end

                    -- bold
                    if item.title.bold == nil then item.title.bold = true end
                    
                    error_tip = error_tip .. tostring(check_available_type('item.title.bold', item.title.bold, "boolean"))
                    error_tip = error_tip .. tostring(check_available_type('item.title.font_size', item.title.font_size, "number"))
                end

                error_tip = error_tip .. tostring(check_available_item_align('item', item.align))
            end
        end
    end

    return error_tip
end


-- 规则检查器
function M.toolbar_checker(toolbar_config)

    -- 1. check available
    if not toolbar_config then
        E.LOG.error(TAG, "toolbar error, code:" .. tostring(CONSTANTS.WEBVIEW_TOOLBAR.TOOLBAR_CONFIG_ERROR) ..  ", msg: toolbar is nil")
        return nil
    end
    
    -- 2. check landscape/portrait available
    local landscape = toolbar_config.landscape
    local portrait = toolbar_config.portrait
    
    if not landscape and not portrait then
        E.LOG.error(TAG, "toolbar error, code:" .. tostring(CONSTANTS.WEBVIEW_TOOLBAR.TOOLBAR_CONFIG_ERROR) ..  ", msg: no available landscape/portrait config")
        return nil
    end

    local p_top_bar = portrait and portrait.top_bar
    local p_bottom_bar = portrait and portrait.bottom_bar

    local l_bottom_bar = landscape and landscape.bottom_bar
    local l_top_bar = landscape and landscape.top_bar

    if not l_bottom_bar and not p_bottom_bar and not l_top_bar and not p_top_bar then
        E.LOG.error(TAG, "toolbar error, code:" .. tostring(CONSTANTS.WEBVIEW_TOOLBAR.TOOLBAR_CONFIG_ERROR) ..  ", msg: no available top_bar/bottom_bar config")
        return nil
    end

    -- 3. check toolbars
    local check_error_tips = ''

    check_error_tips = check_error_tips .. tostring(check_bar('top_bar', p_top_bar))
    check_error_tips = check_error_tips .. tostring(check_bar('bottom_bar', p_bottom_bar))
    check_error_tips = check_error_tips .. tostring(check_bar('top_bar', l_top_bar))
    check_error_tips = check_error_tips .. tostring(check_bar('bottom_bar', l_bottom_bar))

    -- 4. 检测到不兼容的属性
    if check_error_tips and #check_error_tips > 0 then
        E.LOG.error(TAG, "toolbar error, code:" .. tostring(CONSTANTS.WEBVIEW_TOOLBAR.TOOLBAR_CONFIG_ERROR) ..  ", msg:" .. tostring(check_error_tips))
        return nil
    end 
        
    -- 5. 检测配置均成功
    return toolbar_config
end

-- ======================== 4. Toolbar config ========================
--[[
    toolbar_theme : 主题支持light和dark, 默认light
]]
function M.default_toolbar_theme(toolbar_theme)
    local default_toolbar_config

    local background_color = "#FFFFFFFF"
    local color_button = "#FF000000"
    local color_button_title = "#FF1B1B21"
    local color_title = "#FF000000"

    if toolbar_theme == M.theme.dark or toolbar_theme == M.theme.dark_bottom then
        background_color = "#FF000000"
        color_button = "#FFFFFFFF"
        color_button_title = "#FFFFFFFF"
        color_title = "#FFFFFFFF"
    end

    local p_bottom_items = {}
    local l_bottom_items = {}
    local backward_item = general_button(M.type.backward, M.type.backward, color_button, M.align.left, TOOLBAR_DEFAUTL_ICON_PADDING, "")
    local forward_item = general_button(M.type.forward, M.type.forward, color_button, M.align.left, TOOLBAR_DEFAUTL_ICON_PADDING, "")
    local reload_item = general_button(M.type.reload, M.type.reload, color_button, M.align.center, TOOLBAR_DEFAUTL_ICON_PADDING, "")
    local close_item = general_button(M.type.close,M.type.close, color_button, M.align.right, TOOLBAR_DEFAUTL_ICON_PADDING, "")
    local text = Lang.getString('webview_toolbar_close', '返回游戏')
    close_item.title = general_item_title(text, color_button_title, true, TOOLBAR_DEFAUTL_ICON_FONT_SIZE, M.align.right)

    local space_item = general_button(M.type.space, "", "#00FFFFFF", M.align.center, TOOLBAR_DEFAUTL_ICON_PADDING, "")
    
    -- 添加竖屏配置
    table.insert(p_bottom_items, backward_item)
    table.insert(p_bottom_items, forward_item)
    table.insert(p_bottom_items, reload_item)
    table.insert(p_bottom_items, close_item)

    local p_bottom_bar = {
        background_color = background_color,
        items = p_bottom_items,
        visible = true,
    }

    local top_items = {}
    local title_item =  general_title(M.align.center,"0", true, "")
    title_item.title =  general_item_title("", color_title, true, TOOLBAR_DEFAUTL_TITLE_FONT_SIZE, M.align.center)

    -- 添加title
    table.insert(top_items, title_item)

    local top_bar = {
        background_color = background_color,
        items = top_items,
        visible = true,
    }

    -- 添加横屏配置，横屏默认不显示topbar
    table.insert(l_bottom_items, backward_item)
    table.insert(l_bottom_items, forward_item)
    table.insert(l_bottom_items, reload_item)
    table.insert(l_bottom_items, space_item)
    table.insert(l_bottom_items, close_item)

    local l_bottom_bar = {
        background_color = background_color,
        items = l_bottom_items,
        visible = true,
    }
    
    default_toolbar_config = {
        landscape = {
            bottom_bar = l_bottom_bar
        },
        portrait = {
            bottom_bar = p_bottom_bar
        }
    }

    if toolbar_theme == M.theme.dark or toolbar_theme == M.theme.light then
        default_toolbar_config['portrait']['top_bar'] = top_bar
    end

    return default_toolbar_config
end

-- 更新 items的属性
local function replace_items(bar_items, replace_parmas)
    for _, item in pairs(bar_items) do
        if item and item.type == replace_parmas.type then
            local keys = E.Utils.split_string(replace_parmas.key, '.')
            if keys and #keys > 1 then
                if item[keys[1]][keys[2]] ~= nil then
                    item[keys[1]][keys[2]] = replace_parmas["value"]
                end
            else 
                if item[replace_parmas["key"]] ~= nil then
                    item[replace_parmas["key"]] = replace_parmas["value"]
                end
            end
        end
    end
end

-- 更新 bars的属性
local function replace_bars(bar, replace_parmas)

    -- 修改toolbar自身的属性
    if replace_parmas.type == "top_bar" then
        if bar.top_bar then
            local key = replace_parmas.key
            if bar.top_bar[key] ~= nil then
                bar.top_bar[key] = replace_parmas.value
            end
        end
    elseif replace_parmas.type == "bottom_bar" then
        if bar.bottom_bar then
            local key = replace_parmas.key
            if bar.bottom_bar[key] ~= nil then
                bar.bottom_bar[key] = replace_parmas.value
            end
        end
    else 
        
        if bar.top_bar and bar.top_bar.items then 
            replace_items(bar.top_bar.items, replace_parmas)
        end
        
        if bar.bottom_bar and bar.bottom_bar.items then 
            replace_items(bar.bottom_bar.items, replace_parmas)
        end
    end
end

-- 更新toolbar配置
function M.update_toolbar_with_type(toolbar_config, replace_parmas)
    
    if toolbar_config and replace_parmas and replace_parmas.type and replace_parmas.key then
        if toolbar_config.landscape then
            replace_bars(toolbar_config.landscape, replace_parmas)
        end

        if toolbar_config.portrait then
            replace_bars(toolbar_config.portrait, replace_parmas)
        end
    end
    
    return toolbar_config
end

return M