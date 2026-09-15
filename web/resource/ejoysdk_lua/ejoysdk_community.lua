local SC = require 'ejoysdk_lua.shortcut.ejoysdk_shortcut_webview'
local E = require 'ejoysdk_lua.ejoysdk'
local EM = require "ejoysdk_lua.ejoysdk_module"
local e_utils = require "ejoysdk_lua.ejoysdk_utils"
local TAG = EM.MODULE.VENDORS.SHORTCUT
local M = {}
local biz_type = SC.Type.Community

--[[
打开微社区前先设置on_callbacks，游戏内图标和快捷方式桌面图标都可能打开微社区，所以需要提前设置
    on_callbacks, table, 支持设置 on_close_callback 和 on_js_callback 以及 on_live_callback
    eg:
        local EEC = require "ejoysdk_lua.ejoysdk_community"
        local function on_js_callback(value) 
            local args = value.args
            if args then
                if args.type == 'community_hide' then -- 从js过来的隐藏处理，页面被暂时隐藏了
                    -- 边看边玩时候的隐藏 params:{ 'biz_type':'live', 'is_open':true }
                    -- 其他隐藏 { 'biz_type':'community', 'is_open':false }
                    if args.params and args.params.biz_type == 'community' then
                        -- 游戏背景声音打开处理
                        E.LOG.debug(TAG, 'game sound open')
                    end
                elseif (args.type == 'community_show') then
                    if args.params and args.params.biz_type == 'community' then
                        -- 游戏背景声音关闭处理
                        E.LOG.debug(TAG, 'game sound mute')
                    end
                elseif (args.type == 'test_call_game') then -- 与微社区前端协商对齐的协议，如打开战报等
                    -- 获取到参数执行游戏相关动作
                    -- log(args.params.xxx)
                    E.LOG.debug(TAG, 'test_call_game')
                end
            end
        end

        local function on_close_callback(value) 
            -- 顶号等情况关闭社区，需要恢复声音
            E.LOG.debug(TAG, 'game sound open')
        end

        local function on_live_callback(event, params)
            local ELF = require "ejoysdk_lua.webview.live_floater"
            if event == ELF.LIVE_EVENT.ON_LIVE_SHOW then
                -- 游戏背景声音关闭处理
                E.LOG.debug(TAG, 'game sound mute - live')
            elseif event == ELF.LIVE_EVENT.ON_LIVE_DESTROY then
                -- 游戏背景声音打开处理，这里需要判断微社区是否打开了（从直播窗体返回的）params.biz_type == 'community' and params.is_open == false
                if params.biz_type == 'community' and params.is_open == false then
                    E.LOG.debug(TAG, 'game sound open - live')
                end
            end
        end

        local on_callbacks = {
            on_close_callback = on_close_callback
            on_js_callback = on_js_callback
            on_live_callback = on_live_callback
        }

        EEC.register(on_callbacks)
]]
function M.register(on_callbacks)
    SC.register(biz_type, on_callbacks)
end

-- 游戏端内的打开，如果需要传递参数可以使用open_with_option
-- 如果已接入快捷方式，有调用游戏方法的前提下可以前置调用register，然后再调用open
function M.open()
    SC.open_shortcut_webview(biz_type)
end

--[[
游戏端内的打开，支持自定义打开参数设置
params, 默认打开可以传空
    params.default_url: 微社区支持多一个参数传递兜底的url
    params.from_source_data : 自定义打开携带参数
option 为webview相关option，默认可不传，结构同webview一致
on_callbacks 会覆盖register的传递参数
]]
function M.open_with_option(params, option, on_callbacks)
    SC.open_shortcut_webview(biz_type, params, option, on_callbacks)
end


--[[
    webview打开社区，支持webview的单向跳转
    params, 默认打开可以传空
    params.from_source_data : 自定义打开携带参数
]]
function M.open_from_webview(params, cb)
    -- 先关闭当前webview，然后
    SC.open_from_webview(biz_type, params, nil, cb)
end

function M.hide()
    SC.hide_shortcut_webview(biz_type)
end

function M.close()
    SC.close_shortcut_webview(biz_type)
end

function M.reload()
    SC.reload(biz_type)
end

-- option: table，可不传。支持关闭android权限弹窗 option.disable_alert = true
function M.add_shortcut(cb, option)
    SC.add_shortcut_webview(biz_type, cb, option)
end

function M.is_support_shortcut()
    return SC.is_support_shortcut(biz_type)
end

-- 隐藏下的展示调用，内部预留方法。调用open即可
function M.show(_params)
    SC.show_shortcut_webview(biz_type, _params)
end

--[[
        params的结构 {
            ['local_params'] = {
                ['from_source'] = 'shortcut'
            },
            ['from_source_data'] = {
                ['biz_data'] = biz_data or {}
            }  -- 根据前端的要求，填充from_source_data
        }
--]]
function M.notification_open(params)
    local has_open = false
    if E.WebView.is_opened() then
        E.LOG.debug(TAG, 'webview is opening, not enable to open')
        -- 当前打开的正好是biz_typet的shortcut
        if SC.is_opened_biz(biz_type) then
            -- 已打开的情况
            SC.set_from_source_data(biz_type, params.from_source_data)

            SC.call_js(biz_type, "window.luaNotify('community', 'open');", false)
            has_open = true
        end
    end

    if not has_open then
        SC.open_shortcut_webview('community', params)
    end
end

-- 快捷方式的切换到游戏
function M.start_game()
    E.LOG.debug(TAG, 'start_game')
    SC.start_game()
end

function M.call_js(js_script)
    SC.call_js(biz_type, js_script)
end

function M.remove_hide_cache()
    SC.remove_hide_cache(biz_type)
end

function M.get_from_source_data()
    return SC.get_from_source_data(biz_type)
end

function M.get_preload_config()
    return SC.get_preload_config(biz_type)
end

-- live：暂存上一次从快捷方式进入的直播信息
local LAST_SCLIVE_STORAGE = E.LazyKeyStore:New("LAST_SCLIVE_STORAGE", false, true, false)
function M.save_last_shortcut_live(url, frame, parmas)
    if url and parmas then 
        local safe_parmas = {}
        safe_parmas.injectJS = parmas.injectJS
        safe_parmas.create_type = parmas.create_type or ''
        safe_parmas.use_center_per = parmas.use_center_per
        local last_p = {
            url = url,
            frame = frame,
            parmas = safe_parmas,
            timestamp = os.time()
        }
        LAST_SCLIVE_STORAGE:set(last_p)
    end
end

-- live：游戏如果准备好了可以恢复, 返回并清除
function M.remove_last_shortcut_live()
    local last_p =  e_utils.deepcopy(LAST_SCLIVE_STORAGE:get())
    LAST_SCLIVE_STORAGE:delete()
    return last_p
end

-- 勿调用，SDK内无游戏方法，这里仅mock供前端测试游戏链路
function M._test_register()
    local on_callbacks = {
        on_js_callback = function (value)
            local args = value.args
            if args then
                E.LOG.debug(TAG, "_test_register -- args:")
                E.LOG.debug(TAG, args)
                if args.type == 'community_hide' then -- 从js过来的隐藏处理，页面被暂时隐藏了
                    -- 边看边玩时候的隐藏 params:{ 'biz_type':'live', 'is_open':true }
                    -- 其他隐藏 { 'biz_type':'community', 'is_open':false }
                    if args.params and args.params.biz_type == 'community' then
                        -- 游戏背景声音打开处理
                        E.LOG.debug(TAG, 'game sound open')
                    end
                elseif (args.type == 'community_show') then
                    if args.params and args.params.biz_type == 'community' then
                        -- 游戏背景声音关闭处理
                        E.LOG.debug(TAG, 'game sound mute')
                    end
                elseif (args.type == 'test_call_game') then -- 与微社区前端协商对齐的协议，如打开战报等
                    -- 获取到参数执行游戏相关动作
                    -- log(args.params.xxx)
                    E.LOG.debug(TAG, 'test_call_game')
                end
            end
        end,
        on_close_callback = function ()
            E.LOG.debug(TAG, "_test_register on_close_callback")
            E.LOG.debug(TAG, 'game sound open')
        end,
        on_live_callback = function (event, params)
            E.LOG.debug(TAG, "_test_register on_live_callback")
            E.LOG.debug(TAG, "event = " .. tostring(event))
            E.LOG.debug(TAG, params)
            local ELF = require "ejoysdk_lua.webview.live_floater"
            if event == ELF.LIVE_EVENT.ON_LIVE_SHOW then
                -- 游戏背景声音关闭处理
                E.LOG.debug(TAG, 'game sound mute - live')
            elseif event == ELF.LIVE_EVENT.ON_LIVE_DESTROY then
                -- 游戏背景声音打开处理，这里需要判断微社区是否打开了（从直播窗体返回的）params.biz_type == 'community' and params.is_open == false
                if params.biz_type == 'community' and params.is_open == false then
                    E.LOG.debug(TAG, 'game sound open - live')
                end
            end
        end,
    }
    SC.register(biz_type, on_callbacks)
end

return M