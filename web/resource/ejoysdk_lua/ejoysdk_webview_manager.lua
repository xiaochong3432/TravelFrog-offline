local E = require 'ejoysdk_lua.ejoysdk'
local Q = require 'ejoysdk_lua.ejoysdk_queue'
local WU = require "ejoysdk_lua.ejoysdk_web"
local JSBridge = require "ejoysdk_lua.ejoysdk_js_bridge"
local JSON = require "ejoysdk_lua.ejoysdk_json"
local EWT = require "ejoysdk_lua.ejoysdk_webview_toolbar"
local ET = require "ejoysdk_lua.ejoysdk_topic"

local LIGHTBOAT = require 'ejoysdk_lua.res.lightboat.ejoysdk_lightboat'

local IVK_WEBVIEW_OPEN = 'WEBVIEW_OPEN'
local SYNC_WEBVIEW_OPERATOR= 'WEBVIEW_OPERATOR'
local ACT_WEBVIEW_UPDATE_TOOLBAR = 'update_toolbar'

-- URL和本地文件路径映射表的缓存
--local webview_url_path_table_cache = {}

local M = {}
local TAG = "ejoysdk_webview_manager"

M.WEBVIEW_STATUS = {
    --队列中
    IN_LINE  = 1,
    --显示中
    SHOWING = 2,
    --已关闭
    CLOSED = 3
}

local WEBVIEW_QUEUE_CAPACITY = 10
local queue = Q.create(WEBVIEW_QUEUE_CAPACITY)
local current_show_webview
local check_queue

local function is_support_toolbar_version()
    if _ejoysdk.os() == "android" then
        local version = E.Sdkinfo.getSDKVersionName("EJOYSDK")
        local version_check = require "ejoysdk_lua.ejoysdk_version_check"
        -- 2.7.1版本android修复了关闭问题。2.10.11修复了底部工具栏不显示的问题
        local result = version_check.compare_versions(version,'2.10.11')
        if tonumber(result) >= 0 then
            return true
        else
            E.LOG.debug(TAG, 'version not support toolbar')
            return false
        end
    end

    return true
end

-- 这个默认值是给E.webview.open用的
local function open_webview_with_default_options(_options)
    _options = _options or {}
    if _options.use_cutout == nil then
        _options.use_cutout = false -- 如果不传则默认避开刘海展示webview
    end
    return _options
end

--兼容android/ios/windows
local function show_webview(webview)
    E.LOG.debug(TAG, 'show_webview url is ' .. tostring(webview.url))
    current_show_webview = webview
    webview.status = M.WEBVIEW_STATUS.SHOWING
    --显示webview
    local injection = webview.injection or {}
    if not injection['.ejoy.com'] then
        injection['.ejoy.com'] = {}
    end

    local option = webview.option or {}

    if _ejoysdk.os() == "ios" then
        option.support_luacall = true -- ios上present打开webview不会导致虚拟机暂停
    elseif _ejoysdk.os() == "android" then
        option.support_luacall = (option.use_fragment == true)
    end

    -- 增加工具栏配置
    -- option.enable_toolbar, 开关：向前兼容默认false
    -- option.toolbar 配置, 优先取传递参数，如果不配置取内置的配置
    -- option.toolbar_theme, sdk内置几套主题：light(默认) 和 dark、light_bottom、dark_bottom
    -- 1. 开启了配置
    if option.enable_toolbar and is_support_toolbar_version() then
        -- 2. 获取默认配置
        if option.toolbar == nil then
            option.toolbar = EWT.default_toolbar_theme(option.toolbar_theme or EWT.theme.light)
        else
            -- 3. 检查toolbar 配置 check config
            option.toolbar = EWT.toolbar_checker(option.toolbar)
        end
    end

    WU.fill_injection_with_common_params(injection,option)

    --option = WU.get_fill_default_options(option) --补充默认值
    option = open_webview_with_default_options(option)

    -- 全局监听js event
    JSBridge.init()

    -- 监听游戏的js回调
    WU.webview_callback_helper(webview.url, option, webview.on_js_callback, function(_value)
        webview.status = M.WEBVIEW_STATUS.CLOSED;
        if webview.on_close_callback then
            E.LOG.debug(TAG, 'on_js_callback not nil, now callback >>')
            webview.on_close_callback(_value)
        else
            E.LOG.warn(TAG, 'on_js_callback is nil, NOT callback >>')
        end
        current_show_webview = nil
        --关闭webview回调，延时一秒，因为close后，无法立刻调open显示
        E.Timer.once(1, function()
            E.LOG.debug(TAG, 'webview close callback, check queue')
            check_queue()
        end)
    end)

    if _ejoysdk.os() == "android" then
        return E.invoke(IVK_WEBVIEW_OPEN, {url = webview.url, injection = injection, option = option})
    else
        -- option在上面函数内部会去修改，所以要放到下方再使用，否则关闭时的回调id会没有值
        local optionString = '{}'
        if option then
            local succ, msg = pcall(JSON.encode, option)
            if succ then
                optionString = msg
            end
        end
        local injectionString = JSON.encode(injection)
        return _ejoysdk.webview_open(webview.url, injectionString, optionString)
    end
end

-- 给local_path插入injection数据
local function inject_data_local_path(url, local_path, injection)
    if not injection or not local_path then
        return
    end

    if E.Utils.start_with(local_path, 'file://') then
        local_path = string.gsub(local_path, "file://", '')
    end

    if next(injection) then
        local first_data
        for host,data in pairs(injection) do

            local index = string.find(url, host, 1, true)
            if index and index > 0 then
                -- 优先匹配原来的injection
                injection[local_path] = data
                return
            end

            if not first_data then
                first_data = data
            end
        end
        -- 如果找不到，则取第一个
        injection[local_path] = first_data or {}
    else
        -- 只加白名单
        injection[local_path] = {}
    end
end

-- 检查队列中是否有缓存的任务
function check_queue()
    if not Q.isEmpty(queue) then
        local webview = Q.dequeue(queue)
        if webview.is_cancel then
            check_queue()
        else
            current_show_webview = webview
            show_webview(webview)
        end
    else
        E.LOG.debug(TAG, 'the queue is empty')
    end
end


ET.subscribe('webview_hide', function(_value)
    local is_web_open = E.WebView.is_opened()
    E.log('receive webview hide event, and is_web_open >> ' .. tostring(is_web_open))
    if not is_web_open then
        current_show_webview = nil
        WU.handle_hide_event()
        check_queue()
    end
end)

function M.add_webview(url, injection, option, on_js_callback, on_close_callback, tag)
    -- 检查下有无本次缓存
    injection = injection or {}
    local local_url = LIGHTBOAT.get_url_from_cache(url)
    if local_url and local_url ~= url then
        -- 插入startupdata
        local clipping_url = E.Utils.url_clipping(local_url)
        inject_data_local_path(url,clipping_url,injection)
        url = local_url
    end

    -- 主要是为了限制同一个请求多次重复调用导致同一页面重复打开，判断的依据应该包括所有的参数，如url，injection,option等，但injection,option有可能是每次调用重新生成的，暂不加入判断
    -- tag是for云微端的，云微端与其他页面不一样，会使用同一url并多次调用打开，依赖wv队列的机制来排队显示，但显示的内容是根据startupdata的内容来的
    if(tag == nil and current_show_webview and current_show_webview.status < M.WEBVIEW_STATUS.CLOSED and
            current_show_webview.url ~= nil and url == current_show_webview.url ) then
        -- 当前在显示的url与进来的一致，则忽略
        -- FIXME current_show_webview存在不一定表示正在显示，有可能是webview异常关闭但current_show_webview还在(实际没遇到)
        E.LOG.debug(TAG, 'url has been shown previously, ignored');
        return
    end

    local webview = {
        url = url,
        injection = injection,
        option = option,
        on_js_callback = on_js_callback,
        on_close_callback = on_close_callback,
        tag = tag,
        is_cancel = false
    }
    if current_show_webview and current_show_webview.tag and current_show_webview.tag == tag then
        E.LOG.debug(TAG, 'current showing webview is same, reload it, tag >> ' .. tostring(tag))
        --show_webview(webview)
        E.WebView.close()
    end

    local ignore_queque = option and option.nonmodal_window and option.webview_id ~= nil or false -- 独立窗口/携带webviewid的需要多开，如community，忽略队列
    if ignore_queque then
        show_webview(webview)
        return
    end

    --添加到队列里
    E.LOG.debug(TAG, 'enqueue webview into queue >> ' .. tostring(url) .. ' and tag >> ' .. tostring(tag))
    Q.replace(queue, webview, function(origin, new)
        E.LOG.debug(TAG, 'compare the webview')
        --E.log(origin)
        --E.log(new)
        return origin.tag and origin.tag == new.tag
    end)
    webview.status = M.WEBVIEW_STATUS.IN_LINE
    --如果当前没有显示就触发一次显示事件
    if not current_show_webview and not E.WebView.is_opened() then
        E.LOG.debug(TAG, 'current_show_webview is nil, now check queue')
        check_queue()
    else
        --保底措施,current_show_webview不为空，但webview间隔2秒检测，都是没有打开的，且为同一个对象，判定为出问题了，调用check_queue
        E.LOG.debug(TAG, 'double check webview open')
        local is_opened = E.WebView.is_opened()
        local last_show_webview = current_show_webview
        E.Timer.once(2, function()
            local delay_is_opened = E.WebView.is_opened()
            E.LOG.debug(TAG, '2 s check state >> is_open ' .. tostring(is_opened) .. ' and delay_is_opened >> ' .. tostring(delay_is_opened))
            E.LOG.debug(TAG, 'last show webview >>' .. tostring(last_show_webview))
            E.LOG.debug(TAG, 'current show webview >>' .. tostring(current_show_webview))
            if is_opened == false and delay_is_opened == false and last_show_webview == current_show_webview then
                E.LOG.debug(TAG, 'double check webview open , check queue')
                check_queue()
            else
                E.LOG.debug(TAG, 'double check webview open , queue')
            end
        end)
    end
end

--- 高优先级添加页面，关闭当前显示的界面，且清空队列
function M.add_webview_priority(url, injection, option, on_js_callback, on_close_callback, tag)
    local webview = {
        url = url,
        injection = injection,
        option = option,
        on_js_callback = on_js_callback,
        on_close_callback = on_close_callback,
        tag = tag,
        is_cancel = false
    }
    if not Q.isEmpty(queue) then
        Q.clear(queue)
    end
    Q.enqueue(queue, webview)
    if current_show_webview then
        E.LOG.debug(TAG, 'current showing webview is not nil, close it >> ' .. tostring(tag))
        E.WebView.close()
        local last_show_webview = current_show_webview
        E.Timer.once(2, function()
            local is_web_open = E.WebView.is_opened()
            if not is_web_open and last_show_webview == current_show_webview then
                E.LOG.debug(TAG, 'double check webview open , check queue-1')
                check_queue()
            end
        end)
    else
        --- 当前没有界面在显示的话，则直接显示
        check_queue()
    end
end

-- 队列中，则取消
-- 显示中，则关闭
function M.close_view(tag)
    if current_show_webview and current_show_webview.tag and current_show_webview.tag == tag then
        E.LOG.debug(TAG, 'current showing webview is same, close it, tag >> ' .. tostring(tag))
        E.WebView.close()
    end
    if not Q.isEmpty(queue) then
        local cancel_func = function(webview)
            if webview and webview.tag and webview.tag == tag then
                E.LOG.debug(TAG, 'find the same tag in queue, set it cancel. tag >> ' .. tostring(tag))
                webview.is_cancel = true
            end
        end
        Q.traverse(queue, cancel_func)
    end
end

function M.hide_all_web()
    Q.clear(queue)
    if current_show_webview then
        E.WebView.close()
    end
end

--返回当前显示的webview参数
function M.current_show_webview()
    return current_show_webview
end

function M.update_toolbar(toolbar_config)

    if not toolbar_config then
        return
    end

    local os = _ejoysdk.os()
    if os == "android" then
        E.sync_call(SYNC_WEBVIEW_OPERATOR, { type = ACT_WEBVIEW_UPDATE_TOOLBAR, data = toolbar_config })
    elseif os == "ios" then
        local toolbarOptionString
        local parmas = { type = ACT_WEBVIEW_UPDATE_TOOLBAR, data = toolbar_config }
        if toolbar_config then
            local succ, msg = pcall(JSON.encode, parmas)
            if succ then
                toolbarOptionString = msg or '{}'
                E.sync_call('webview_operator', toolbarOptionString)
            end
        end
    end
end

function M.update_toolbar_item(params)

    if current_show_webview and params then
        local option = current_show_webview.option or {}
        if option.enable_toolbar and option.toolbar then
            EWT.update_toolbar_with_type(option.toolbar, params)
            M.update_toolbar(option.toolbar)
        end
    end
end

return M