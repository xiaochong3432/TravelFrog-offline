local JSON = require "ejoysdk_lua.ejoysdk_json"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local EM = require "ejoysdk_lua.ejoysdk_module"
local EC = require "ejoysdk_lua.ejoysdk_constants"
local LUA_FILE = require "ejoysdk_lua.libs.luafile"
local ECC = require "ejoysdk_lua.ejoysdk_constants"
-- local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local unpack = unpack or table.unpack
local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'win'

local M = {}
local cbs = {}
local cb_id = math.random(1000, 9999)
local native_support_functions = nil
local idfa_cache = nil

M.PLATFORM = {
    OS = "Windows",
    HTTP_UA = "libcurl/7.61.0 (Windows; PC)"
}

function M.async_call(fn_name, cb, ...)
    if cb then
        -- cb应该可以为nil，所以类型检查加个判空，不为空才判断类型
        assert(type(cb) == 'function', "cb参数必须要是函数类型！！！")
    end

    local id = cb_id
    cb_id = cb_id + 1
    cbs[id] = cb
    local func = _ejoysdk[fn_name]
    if func ~= nil then
        func(id, ...)
    else
        _ejoysdk.log(TAG .. tostring(fn_name) .. " 该函数不存在！！！！！")
    end

    return id
end

-- 同步调用
function M.sync_call(fn_name, ...)
    local func = _ejoysdk[fn_name]
    local value = nil
    if func ~= nil then
        value = func(...)
    end
    return value
end

function M.async_call_with_opts(fn_name, opts, cb, ...)
    local id = M.async_call(fn_name, cb, ...)

    if opts and opts.timeout and opts.timeout_cb then
        M.Timer.once(opts.timeout, function()
            if cbs[id] then
                cbs[id] = nil
                opts.timeout_cb()
            end
        end)
    end

    return id
end

local function async_callback(id, json_str, chunk)
    local cb = cbs[id]
    if cb then
        local resp = JSON.decode(json_str)
        cbs[id] = nil
        cb(resp, chunk)
    end
end

local gangplank_inited = false
local did_register_event = false

local function init_handler ()
    if gangplank_inited == false then
        gangplank_inited = true
        local WLU = require "ejoysdk_lua.windows_launcher.updater"
        pcall(WLU.cleanup)
    end
end

local register_event = function()
    if did_register_event then
        return
    end
    did_register_event = true

    ET.subscribe(ET.gangplank.INITED, init_handler)
end
register_event()

_ejoysdk.register_cb("ASYNC_CALL", async_callback)
local HTTP_EVENT = 'HTTP_EVENT'
local http_progress_cbs = {}
local http_progress_tid_cbid_map = {}

_ejoysdk.register_cb(HTTP_EVENT, function(cbid, js_str, _chunk)
    local params = http_progress_cbs[cbid]
    if params then
        local resp = JSON.decode(js_str)
        if resp.type and resp.type == 'header' then
            if resp.ext and resp.ext.headers then
                if params.header_cb then
                    params.header_cb(resp.ext.headers)
                end
            end
        elseif resp.received == -1 then
            http_progress_cbs[cbid] = nil
            if params.finish_cb then
                params.finish_cb()
            end
        else
            params.progress(params.url, params.file, resp.received, resp.total)
        end
    end
end)

function M.printl(content)
    M.log({
        msg = content
    })
end

local HTTP = {}
M.HTTP = HTTP

function HTTP.add_cert(ca_name, ca_chunk, cb)
    local function cb_wrap(resp)
        if type(resp) == 'string' then
            resp = JSON.decode(resp)
        end
        local result = resp
        if cb then
            cb(result.succ)
        end
    end
    local optStr = JSON.encode({
        name = ca_name
    })
    M.async_call('http_add_cert', cb_wrap, optStr, ca_chunk)
end

-- windows对接的curl的证书pin接口，需要放入证书的publickey。而其它端需要的是证书的certificate内容。
-- 详细见：https://curl.se/libcurl/c/CURLOPT_PINNEDPUBLICKEY.html 和 https://blog.csdn.net/u010980938/article/details/111050830
function HTTP.add_cert_pin(_host_pattern, ca_name, ca_chunk, cb)
    -- 这里可能需要按照域名维度配置证书
    local function cb_wrap(resp)
        if type(resp) == 'string' then
            resp = JSON.decode(resp)
        end
        local result = resp
        if cb then
            cb(result.succ)
        end
    end
    local optStr = JSON.encode({
        name = ca_name,
        host_pattern = _host_pattern
    })
    M.async_call('http_add_cert_pin', cb_wrap, optStr, ca_chunk)
end

function HTTP.process_get(url, params, cb)
    _ejoysdk.log('HTTP GET: ' .. url)
    local name = 'http_get'
    if params.file then
        name = 'http_get_file'
    end

    local headers = params and params.headers
    assert(headers, 'params.headers should not be nil')

    -- 参考android处理，缓存一下传入的func，避免encode异常
    local progress = params.progress
    params.progress = nil
    local finish_cb = params.finish_cb
    params.finish_cb = nil
    local header_cb = params.header_cb
    params.header_cb = nil

    local _cbid = M.async_call_with_opts(name, {
        timeout = params.timeout,
        timeout_cb = function()
            cb({
                status = 0
            })
        end
    }, function(info, body)
        info.headers = HTTP.Header.New(info.headers)

        info.body = body
        cb(info)
    end, url, headers, params)

    if params.file and progress then
        http_progress_cbs[_cbid] = {
            url = url,
            file = params.file,
            progress = progress,
            finish_cb = finish_cb,
            header_cb = header_cb
        }
    end

    local task_id = params.taskId
    if task_id then
        http_progress_tid_cbid_map[task_id] = _cbid
    end
end

function HTTP.process_post(url, params, _content_type, body, cb)
    _ejoysdk.log('HTTP POST: ' .. url)
    local headers = params and params.headers
    assert(headers, 'params.headers should not be nil')

    M.async_call_with_opts('http_post', {
        timeout = params.timeout,
        timeout_cb = function()
            cb({
                status = 0
            })
        end
    }, function(info, resp_body)
        info.headers = HTTP.Header.New(info.headers)

        info.body = resp_body
        cb(info)
    end, url, headers, body)
end

function HTTP.process_stop(_task_id_arr, params, cb)
    if not _task_id_arr or next(_task_id_arr) == nil then
        cb(false, {})
        return
    end

    local _task_id = _task_id_arr[1]
    M.async_call_with_opts("http_stop_file", {}, function(info, body)
        local succ = info.succ
        info.body = body
        cb(succ, info)
    end, _task_id, params)
end

function HTTP.unregister_progress_cb(_task_id)
    if not _task_id then
        return
    end

    local _cb_id = http_progress_tid_cbid_map[_task_id]
    if not _cb_id then
        return
    end

    http_progress_cbs[_cb_id] = nil
end

--[[
limit_speed
read_buffer_size_bytes
--]]
function HTTP.update_with_config(_params)
    -- not support
    _ejoysdk.http_update_download_config(_params)
end

function HTTP.http_remove_cache()
    -- 空实现，iOS才需要清除接口
end

function HTTP.http_enable_cache()
    -- 空实现，iOS才有此接口
end

local KeyStore = {}
M.KeyStore = KeyStore

function KeyStore.get(key)
    return _ejoysdk.keystore_get(key)
end

-- 空实现
function KeyStore.get_group(_access_group)
    return nil
end

function KeyStore.set(key, value)
    if value == nil then
        return
    end
    _ejoysdk.keystore_set(key, value)
end

function KeyStore.set_group(_key, _access_group, _value)
    -- 空实现
end

function KeyStore.delete(key)
    _ejoysdk.keystore_delete(key)
end

function KeyStore.delete_group(_key, _access_group)
    -- 空实现
end

function KeyStore.clear()
    _ejoysdk.keystore_clear()
end

function KeyStore.clear_group(_access_group)
    -- 空实现
end

function KeyStore.custom_sub_dir(sub_dir_param)
    if not sub_dir_param or next(sub_dir_param) == nil then
        _ejoysdk.log("custom_sub_dir sub_dir_param is invalid")
        return
    end

    local sub_dir_param_string = JSON.encode(sub_dir_param)
    _ejoysdk.log("custom_sub_dir:" .. tostring(sub_dir_param_string))
    _ejoysdk.keystore_custom_sub_dir(sub_dir_param_string)
end

M.UnRecoverKeyStore = KeyStore

-- sharedpreferences raw api
local SPRawKeyStore = {}
function SPRawKeyStore.get(_sp_name, _key)
    -- luacheck: ignore
    -- TODO
end

function SPRawKeyStore.set(_sp_name, _key, _value)
    -- luacheck: ignore
    -- TODO
    return false
end

function SPRawKeyStore.delete(_sp_name, _key)
    -- luacheck: ignore
    -- TODO
end

M.SPRawKeyStore = SPRawKeyStore

local SYNC_WEBVIEW_OPERATOR = 'webview_operator'
-- local ACT_WEBVIEW_GO_BACK = 'go_back'
-- local ACT_WEBVIEW_GO_FORWARD = 'go_forward'
-- local ACT_WEBVIEW_RELOAD = 'reload'
local ACT_WEBVIEW_SHOW = 'show'
local ACT_WEBVIEW_HIDE = 'hide'
local ACT_WEBVIEW_REMOVE_HIDE_CACHE = 'remove_hide_cache'

local WebView = {}
M.WebView = WebView
local disable_embed_webview
function WebView.open(url, injection, option, on_js_callback, on_close_callback)

    -- 如果设置了disable_embed_webview, 则默认增加webview_type,走系统浏览器，无论是否接了webview2
    option = option or {}
    if disable_embed_webview then
        option.webview_type = 'os_browser'
    end

    -- 特殊处理：windows的WebView.open支持走系统浏览器，移动端则走的是端内，没有该情况
    local use_os_browser = false
    if option.webview_type and option.webview_type == 'os_browser' then
        use_os_browser = true
    end

    -- 内部浏览器，支持队列
    if M.support_webview() and not use_os_browser then
        local EWB = require "ejoysdk_lua.ejoysdk_webview_manager"
        return EWB.add_webview(url, injection, option, on_js_callback, on_close_callback)
    end

    -- 外部浏览器直接打开
    injection = injection or {}
    if not injection['.ejoy.com'] then
        injection['.ejoy.com'] = {}
    end

    local WU = require "ejoysdk_lua.ejoysdk_web"
    WU.fill_injection_with_common_params(injection, option)

    local JSBridge = require "ejoysdk_lua.ejoysdk_js_bridge"
    -- 全局监听js event
    JSBridge.init()

    -- 监听游戏的js回调
    WU.webview_callback_helper(url, option, on_js_callback, on_close_callback)

    -- option在上面函数内部会去修改，所以要放到下方再使用，否则关闭时的回调id会没有值
    local optionString = '{}'
    local succ, msg = pcall(JSON.encode, option)
    if succ then
        optionString = msg
    end

    local injectionString = JSON.encode(injection)
    return _ejoysdk.webview_open(url, injectionString, optionString)
end

function WebView.close()
    return _ejoysdk.webview_close()
end

function WebView.is_opened()
    return _ejoysdk.webview_is_opened()
end

-- 工具栏相关能力补充 windows未实现
function WebView.go_back()

end

function WebView.go_forward()

end

function WebView.reload()

end

function WebView.show(params)
    params = params or {}
    local parmasString = JSON.encode({
        type = ACT_WEBVIEW_SHOW,
        data = params
    })
    return M.sync_call(SYNC_WEBVIEW_OPERATOR, parmasString)
end

function WebView.hide(params)
    params = params or {}
    local parmasString = JSON.encode({
        type = ACT_WEBVIEW_HIDE,
        data = params
    })
    return M.sync_call(SYNC_WEBVIEW_OPERATOR, parmasString)
end

function WebView.remove_hide_cache(params)
    params = params or {}
    local parmasString = JSON.encode({
        type = ACT_WEBVIEW_REMOVE_HIDE_CACHE,
        data = params
    })
    return M.sync_call(SYNC_WEBVIEW_OPERATOR, parmasString)
end

function WebView.prepare(_params)
    return false
end

function WebView.update_toolbar(_toolbar_config)

end

function WebView.update_toolbar_item(_params)

end

-- 执行JS脚本
function WebView.call_js(script)
    if _ejoysdk.webview_call_js then
        _ejoysdk.webview_call_js(script)
    end
end

function WebView.callback_js(id, message)
    if _ejoysdk.webview_callback_js then
        _ejoysdk.webview_callback_js(id, message)
    end
end
function WebView.capture(_callback)
    -- Windows不用实现截屏，函数留空就好
end

local WEBVIEW_EVENT = 'WEBVIEW_EVENT'
local WEBVIEW_JSARGS_EVENT = 0;
local WEBVIEW_CLOSE_EVENT = 1;
local WEBVIEW_URL_REDIRECT = 2;
local WEBVIEW_LIFE_CYCLE_EVENT = 3;

_ejoysdk.register_cb(WEBVIEW_EVENT, function(cbid, value)
    value = JSON.safe_decode(value)

    if cbid == WEBVIEW_JSARGS_EVENT then
        -- 避免前端传递数据错误导致全局异常
        if value and value.args then
            if value.args.type == 'oauthUri' then
                ET.publish('logindone', value);
            else
                ET.publish('webview_jsargs', value);
            end
        end
    elseif cbid == WEBVIEW_CLOSE_EVENT then
        ET.publish('webview_close', value);
    elseif cbid == WEBVIEW_URL_REDIRECT then
        ET.publish('webview_url_redirect', value);
    elseif cbid == WEBVIEW_LIFE_CYCLE_EVENT then
        -- url,event=type,data
        ET.publish('webview_life_cycle', value)
    end

end)

local Sysinfo = {}
M.Sysinfo = Sysinfo

function Sysinfo.idfa()
    if idfa_cache then
        return idfa_cache
    end

    idfa_cache = M.KeyStore.get("ej_win_ut")
    local from_cache = true
    if not idfa_cache then
        idfa_cache = _ejoysdk.sysinfo_idfa() or ''
        M.KeyStore.set("ej_win_ut", idfa_cache)
        from_cache = false
    end
    _ejoysdk.log("win idfa:" .. tostring(idfa_cache) .. ", is_cache:" .. tostring(from_cache))
    return idfa_cache -- 取idfa，其实就是deviceid,是CPU，MAC地址和disk_id一起换算的值
end

function Sysinfo.device_id()
    return Sysinfo.idfa()
end

function Sysinfo.package_name()
    return M.get_pkg_info().pkg_name or ''
end

function Sysinfo.app_name()
    return Sysinfo.package_name()
end

function Sysinfo.os_version()
    if _ejoysdk.sysinfo_os_version then
        return _ejoysdk.sysinfo_os_version() or 'windows'
    end
    return 'windows'
end

function Sysinfo.install_time()
    if _ejoysdk.sysinfo_install_time then
        local install_time = tonumber(_ejoysdk.sysinfo_install_time())
        if install_time then
            return math.floor(install_time)
        end
    end
    return -1
end

function Sysinfo.update_time()
    if _ejoysdk.sysinfo_update_time then
        local update_time = tonumber(_ejoysdk.sysinfo_update_time())
        if update_time then
            return math.floor(update_time)
        end
    end
    return -1
end

function Sysinfo.mobile_info()
    return ''
end

function Sysinfo.is_vpn_connected()
    return false -- 未实现
end

function Sysinfo.network_type()
    return 1
end

function Sysinfo.network_type_cache()
    return M.Sysinfo.network_type()
end

-- 返回：unknown, wifi, 2g, 3g, 4g
function Sysinfo.network_type_name()
    return 'wifi'
end

-- 手机屏幕宽度，单位:px
function Sysinfo.screen_width()
    if _ejoysdk.sysinfo_screen_width then
        return _ejoysdk.sysinfo_screen_width() or -1
    end
    return -1
end

-- 手机屏幕高度，单位:px
function Sysinfo.screen_height()
    if _ejoysdk.sysinfo_screen_height then
        return _ejoysdk.sysinfo_screen_height() or -1
    end
    return -1
end

function Sysinfo.content_size(cb)
    if not cb then
        return
    end

    local width = Sysinfo.screen_width()
    local height = Sysinfo.screen_height()
    cb(width, height)
end

function Sysinfo.screen()
    local width = Sysinfo.screen_width()
    local height = Sysinfo.screen_height()

    if _ejoysdk.sysinfo_window_size then
        local window_width, window_height = _ejoysdk.sysinfo_window_size()

        return {
            width = width,
            height = height,
            scale = -1,
            window_width = window_width or -1,
            window_height = window_height or -1
        }
    end
    return {
        width = width,
        height = height,
        scale = -1
    }
end

function Sysinfo.si()
    return Sysinfo.idfa() -- 取idfa代替by hufeng
end

-- 安装标识
function Sysinfo.uuid()
    return Sysinfo.idfa()
end

function Sysinfo.utdid()
    return Sysinfo.idfa() -- 取idfa，其实就是deviceid,是CPU，MAC地址和disk_id一起换算的值
end

local computer_info = {
    model = nil,
    brand = nil
}

function Sysinfo.get_computer_info_async(cb)
    if computer_info and computer_info.model then
        cb(true, computer_info)
    end
    if _ejoysdk.get_computer_info_async then
        M.async_call_with_opts('get_computer_info_async', {}, function(result)
            M.log('get_computer_info_async result')
            M.log(result)
            if result.succ then
                computer_info = {
                    model = result.model,
                    brand = result.manufacturer
                }
                cb(true, computer_info)
            else
                cb(false, result.code or -1, result.message or '')
            end
        end)
    else
        cb({ false, -1, '' })
    end
end

function Sysinfo.brand()
    return computer_info.brand or ''
end

function Sysinfo.model()
    return computer_info.model or ''
end

function Sysinfo.time_zone()
    if _ejoysdk.sysinfo_time_zone then
        return _ejoysdk.sysinfo_time_zone() or ''
    else
        return ''
    end
end

function Sysinfo.country()
    if _ejoysdk.sysinfo_country then
        return _ejoysdk.sysinfo_country() or ''
    end
    return ''
end

function Sysinfo.language()
    if _ejoysdk.sysinfo_language then
        return _ejoysdk.sysinfo_language() or ''
    end
    return ''
end

function Sysinfo.language_script()
    return ''
end

function Sysinfo.app_version_code()
    return ''
end

function Sysinfo.app_version_name()
    if _ejoysdk.sysinfo_app_version_name then
        return _ejoysdk.sysinfo_app_version_name() or ''
    end
    return ''
end

-- 返回单位：字节
function Sysinfo.get_storage_info()
    local disk_total_size = -1
    if _ejoysdk.sysinfo_disk_size then
        disk_total_size = _ejoysdk.sysinfo_disk_size()
    end
    -- TODO 未实现，返回-1
    local storage_info = {
        internal_total_storage_size = disk_total_size,
        internal_available_storage_size = -1,
        external_total_storage_size = -1,
        external_available_storage_size = -1
    }
    return storage_info
end

function Sysinfo.storage()
    local storage_info = M.Sysinfo.get_storage_info()
    if storage_info then
        local available = storage_info["internal_available_storage_size"]
        return {
            availableInternalStorage = available
        }
    end
    return {}
end

function Sysinfo.open_url(url)
    -- 使用浏览器打开URL，原open_url函数被修改为默认走内置的webview组件了。
    return M.WebView.open(url, nil, {
        webview_type = "os_browser"
    })
    -- return _ejoysdk.sysinfo_open_url(url, '', '')
end

function Sysinfo.can_open_url(_url)
    return true -- windows允许直接使用浏览器打开URL
end

function Sysinfo.is_app_install(_app_name)
    return false -- 暂不支持判断，返回false！
end

function Sysinfo.async_can_open_url(_url, cb)
    if cb then
        cb(Sysinfo.can_open_url(_url))
    end
end

function Sysinfo.sysinfo_ejoy_ext_info()
    return ""
end

function Sysinfo.update_screen_scale_ratio(_ratio)
    -- 先留空
end

function Sysinfo.cutout()
    local result = {
        cutout_rects = { {
                             x = 0,
                             y = 0,
                             width = 0,
                             height = 0
                         } },
        safe_inset = {
            top = 0,
            left = 0,
            bottom = 0,
            right = 0
        }
    }

    return result
end

function Sysinfo.cutout_async(cb)
    local cutout_info = Sysinfo.cutout()
    cb(cutout_info)
end

function Sysinfo.update_cutout(_params)
    -- 空实现
end

-- 独代一级渠道号
function Sysinfo.ds_channel_id()
    return ''
end

-- 独代一级渠道号
function Sysinfo.ds_sub_channel_id()
    return ''
end

function Sysinfo.get_user_agent()
    return M.PLATFORM.HTTP_UA
end

--[[
    同步获取内存信息
--]]
function Sysinfo.memory()
    local default = {
        Total = -1
    }
    if _ejoysdk.sysinfo_memory_size then
        return _ejoysdk.sysinfo_memory_size() or default
    end
    return default
end

-- 单位都是字节
--[[ 返回值示例:
    {
       ["Length"] => 64.0
       ["TotalVirtual"] => 1.4073748822426e+14
       ["TotalPhys"] => 16925155328.0
       ["AvailExtendedVirtual"] => 0.0
       ["AvailPageFile"] => 32744689664.0
       ["MemoryLoad"] => 77.0
       ["AvailPhys"] => 3747409920.0
       ["AvailVirtual"] => 1.4073284192256e+14
       ["TotalPageFile"] => 53432377344.0
    }
--]]
function Sysinfo.memory_info()
    local default = {
        TotalPhys = -1,
        TotalVirtual = -1,
        AvailPhys = -1,
        AvailVirtual = -1,
        TotalPageFile = -1,
        AvailPageFile = -1,
        AvailExtendedVirtual = -1,
        Length = -1,
        MemoryLoad = -1
    }
    if _ejoysdk.sysinfo_memory_info then
        return _ejoysdk.sysinfo_memory_info() or default
    end
    return default
end

--[[
    异步获取内存信息(windows待实现)
--]]
function Sysinfo.memory_detail(cb)
    M.async_call('sysinfo_memory', cb)
end

--[[
    types: table类型，表示调用放需要获取哪些类型的数据，table内元素类型是字符串类型，支持'cpu','memory'类型的字符串

    cb: function类型
    function(succ, ...)
        -- succ: 表示获取成功or失败
    end

    获取成功时:
    local result = ...
    result.cpu： table类型，eg. {'succ'=true, 'usage'=1.2}
    result.memory: table类型, eg. {'total'=1231234, 'free'=12312312, 'appPSS'=12312}

    获取失败时:
    local msg = ...
    msg: 表示错误信息
--]]
function Sysinfo.device_info(types, cb)

    local valid_type_names = {
        ['cpu'] = true,
        ['memory'] = true
    }

    local get_type_result = {}
    local get_type_count = 0

    for _, v in pairs(types) do
        if valid_type_names[v] then
            get_type_result[v] = {}
            get_type_count = get_type_count + 1
        end
    end

    -- 不获取，就不往下走了
    if get_type_count == 0 then
        cb(false, 'get type count zero')
        return
    end

    local time_out = false
    local async_come_full = false
    local async_come_count = 0
    local check_end = function()
        if not time_out then
            if async_come_count == get_type_count then
                async_come_full = true
                cb(true, get_type_result)
            end
        end
    end

    M.Timer.once(3, function()
        if not async_come_full then
            cb(true, get_type_result)
        end
        time_out = true
    end)

    for k, _ in pairs(get_type_result) do
        if k == 'cpu' then
            Sysinfo.cpu_usage(function(ret)
                async_come_count = async_come_count + 1
                if ret and ret['succ'] == true then
                    get_type_result['cpu'] = ret
                end
                check_end()
            end)
        elseif k == 'memory' then
            Sysinfo.memory_detail(function(ret)
                async_come_count = async_come_count + 1
                if ret then
                    get_type_result['memory'] = ret
                end
                check_end()
            end)
        end
    end
end

local cpu_info = {
    model = nil,
    core_num = -1,
    max_freq = -1
}

function Sysinfo.get_cpu_info_async(cb)
    if cpu_info and cpu_info.model then
        cb(true, cpu_info)
        return
    end
    if _ejoysdk.get_cpu_info_async then
        M.async_call_with_opts('get_cpu_info_async', {}, function(result)
            M.log('get_cpu_info_async result')
            M.log(result)
            if result.succ then
                cpu_info = {
                    model = result.model,
                    core_num = result.core_num,
                    max_freq = result.max_freq
                }
                cb(true, cpu_info)
            else
                cb(false, result.code or -1, result.message or '')
            end
        end)
    else
        cb({ false, -1, '' })
    end
end

function Sysinfo.get_disk_info_async(cb)
    if _ejoysdk.get_disk_info_async then
        M.async_call_with_opts('get_disk_info_async', {}, function(result)
            M.log('get_disk_info_async result')
            M.log(result)
            if result.succ then
                cb(true, result.disk_info_list)
            else
                cb(false, result.code or -1, result.message or '')
            end
        end)
    else
        cb(false, -1, 'native is old version')
    end
end

do
    Sysinfo.get_cpu_info_async(function()
        Sysinfo.get_computer_info_async(function()
        end)
    end)
end

function Sysinfo.get_cpu_model()
    return cpu_info.model
end

function Sysinfo.get_cpu_cores_count()
    return cpu_info.core_num
end

function Sysinfo.get_cpu_max_freq()
    return cpu_info.max_freq
end

function Sysinfo.get_gpu_info(cb)
    if _ejoysdk.get_gpu_info_async then
        local options = {
            timeout = 6,
            timeout_cb = function()
                cb({})
            end
        }

        M.async_call_with_opts('get_gpu_info_async', options, function(result)
            M.log('get_gpu_info_async result')
            M.log(result)
            if result.succ then
                cb(result)
            else
                local error_code = result.code
                local error_message = result.message
                M.log('get_gpu_info fail, code: ' .. tostring(error_code) .. ' ,message: ' .. tostring(error_message))
                cb({})
            end
        end)
    else
        cb({})
    end
end

function Sysinfo.manifest_meta_data(_type, _key)
    -- luacheck: ignore
    return '' -- 无manifest，返回空
end

function Sysinfo.is_support_hardware_info()
    if _ejoysdk.get_cpu_info_async and _ejoysdk.get_gpu_info_async then
        return true
    else
        return false
    end
end

function Sysinfo.sysinfo_ios_app_on_mac()
    return false
end

function Sysinfo.get_hardware_info(cb)
    if not Sysinfo.is_support_hardware_info() then
        cb({})
        return
    end
    local hardware_info = {
        cpu = {},
        gpu = {},
        memory = {
            total_size = Sysinfo.memory()
        },
        model = Sysinfo.model(),
        brand = Sysinfo.brand()
    }
    Sysinfo.get_cpu_info_async(function(succ, ...)
        if succ then
            hardware_info.cpu = ...
            Sysinfo.get_gpu_info(function(gpu_info)
                hardware_info.gpus = gpu_info.gpus
                cb(hardware_info)
            end)
        else
            cb({})
        end
    end)
end

function Sysinfo.is_passive_mode()
    if _ejoysdk.is_passive_mode then
        local passive_mode_val = _ejoysdk.is_passive_mode()
        if passive_mode_val == 0 then
            return false -- 主动模式
        else
            return true -- 默认为被动模式
        end
    else
        return nil
    end
end

local Timer = {}
M.Timer = Timer

function Timer.once(interval, cb)
    M.async_call('timer_once', cb, interval)
end

local function table_maxn(t)
    local mn = 0
    for k, _ in pairs(t) do
        if mn < k then
            mn = k
        end
    end
    return mn
end

function M.tick(once)
    repeat

        local result = { _ejoysdk.tick() }
        local cb_type = result[1]
        if cb_type then
            local cb = _ejoysdk.get_register_cb(cb_type)
            if cb then
                table.remove(result, 1)
                local result_size = table_maxn(result)
                -- cb(unpack(result))
                -- 直接unpack的方式，如果返回值数组的中间有nil，则nil后面的参数会解析失败拿不到，这里unpack传入数组长度就可以拿到所有参数了
                cb(unpack(result, 1, result_size))
            end
        else
            -- 这个return非常重要，当队列里的事件被消费完时它可以把线程执行权交回给游戏
            return false
        end

    until once == true
    return true
end

function M.get_url_open_datas()
    return {}
end

-- 从native侧获取openurl_data的缓存(SDK内部用，游戏不要调本接口)
function M.get_last_openurl_data()
    return {}
end

local Modal = {}
M.Modal = Modal

function Modal.alert(title, message, _cb)
    local option = {
        message = tostring(message),
        buttons = { '确定' }
    }

    -- local optionString = JSON.encode(option)
    local cb_wrap = function(data)
        if _cb then
            local index = data["index"]
            _cb(index)
        end
    end

    M.async_call('modal_open', cb_wrap, title, option.message)
end

-- 推荐使用这个，跟移动端统一
function Modal.open(title, option, _cb)
    local optionString = '{}'
    if option then
        optionString = JSON.encode(option)
    end

    local cb_wrap = function(data)
        if _cb then
            local index = data["index"]
            _cb(index)
        end
    end

    M.async_call('modal_open', cb_wrap, title, optionString)
end

function Modal.close(_cb)
    -- TODO
end

function M.is_support_function(func_name)
    if not func_name or func_name == "" then
        _ejoysdk.log("is_support_function failed, func_name invalid")
        return false
    end

    if not _ejoysdk.get_support_functions then
        return false
    end

    if not native_support_functions then
        local data_str = _ejoysdk.get_support_functions()
        native_support_functions = JSON.decode(data_str)
    end

    local ret_type = type(native_support_functions)
    if ret_type ~= "table" then
        _ejoysdk.log("is_support_function failed, ret type invalid:" .. tostring(native_support_functions))
        return false
    end

    if native_support_functions[func_name]
            or func_name == ECC.NATIVE_SUPPORT_FUNCTION_NAMES.HTTP_DOWNLOAD
            or func_name == ECC.NATIVE_SUPPORT_FUNCTION_NAMES.TIMER_FLOAT_INTERVAL then
        return true
    else
        return false
    end
end

local _FileBatch = {}
local _FileCompat = {}
do
    local is_support_batch = M.is_support_function(ECC.NATIVE_SUPPORT_FUNCTION_NAMES.BATCH_FILE_OPERATION)
    _ejoysdk.log("windows load with support batch:" .. tostring(is_support_batch))
    local File
    if is_support_batch then
        File = _FileBatch
    else
        File = {}
    end

    setmetatable(File, {
        __index = _FileCompat
    })

    M.File = File
    M._TEST_FileBatch = _FileBatch -- 测试用例使用
end

--- 文件操作接口，兼容旧实现，新实现见_FileBatch
local cache_ext_stg_dir
function _FileCompat.get_ext_file_dir()
    if cache_ext_stg_dir and cache_ext_stg_dir ~= '' then
        return cache_ext_stg_dir
    end

    local files = _FileCompat.get_sys_dirs()
    if files then
        cache_ext_stg_dir = files["program_private_dir"]
    end

    return cache_ext_stg_dir
end

function _FileCompat.writefile(filename, filedata, append)
    local append_int = 0
    if append == true then
        append_int = 1
    end
    local succ, result = pcall(_ejoysdk.writefile, filename, filedata, append_int) -- windows 层 writefile 会抛出 lua error
    if succ then
        return result
    else
        M.log('windows failed to writefile, error: ' .. tostring(result))
        return nil
    end
end

-- 写文件的函数，filename是文件的绝对路径
function _FileCompat.writefile_fullpath(filename, filedata, append, is_b64)
    if filename == '' or filename == nil then
        _ejoysdk.log('writefile failed, full_path is invalid,')
        return false, ECC.EJOY_LIB_ERROR.PARAMETER_INVALID, "file data invalid"
    end

    -- 和 ios 对齐
    if type(append) == "number" then
        if append > 0 then
            append = true
        else
            append = false
        end
    end

    if M.is_support_function(M.NATIVE_SUPPORT_FUNCTION_NAMES.FILE_DIR_OPERATION) then
        local append_int = 0
        if append == true then
            append_int = 1
        end

        if is_b64 == true then
            -- binary文件,内容需要b64编码
            local succ, data = pcall(_ejoysdk_crypt.base64decode, filedata)
            if succ == true then
                filedata = data
            else
                filedata = nil
            end
        end

        if not filedata then
            _ejoysdk.log('writefile error!!! invalid data')
            return false, ECC.EJOY_LIB_ERROR.PARAMETER_INVALID, "file data invalid"
        end

        local is_full_path = 1
        local succ, result = pcall(_ejoysdk.writefile, filename, filedata, append_int, is_full_path) -- windows 层 writefile 会抛出 lua error
        if succ then
            if not result then
                result = true
            elseif type(result) == 'number' then
                result = result > 0
            end
            return result
        else
            M.log('windows failed to writefile new, error: ' .. tostring(result))
            return false
        end
    else
        M.log("not support write full path")
        local E = require "ejoysdk_lua.ejoysdk"
        E.Path.ensure_parent_dir(filename)

        local ret, code, msg = LUA_FILE._do_write_file(filename, filedata, append, is_b64)
        if not ret and _ejoysdk.utf8_to_acp then
            local acp_filename = _ejoysdk.utf8_to_acp(filename)
            ret, code, msg = LUA_FILE._do_write_file(acp_filename, filedata, append, is_b64)
            _ejoysdk.log("write_file acp begin:" .. tostring(acp_filename) .. ", ret:" .. tostring(ret))
        end

        return ret, code, msg
    end
end

function _FileCompat.readfile_fullpath(_filename)
    return _ejoysdk.lread(_filename)
end

function _FileCompat.readfile(filename)
    return _ejoysdk.lread(filename)
end

function _FileCompat.process_exists(path)
    local exists
    if _ejoysdk.is_file_exists then
        exists = _ejoysdk.is_file_exists(path)
    else
        exists = LUA_FILE.exists(path)

        -- if not exists, it maybe the path not support, so try use utf8_to_acp again
        if not exists and _ejoysdk.utf8_to_acp then
            local acp_path = _ejoysdk.utf8_to_acp(path)
            exists = LUA_FILE.exists(acp_path)
        end
    end

    return exists
end

function _FileCompat.process_remove(file_path)
    local ret, code, msg
    if _ejoysdk.removefile then
        ret, msg = _ejoysdk.removefile(file_path)
    end

    if not ret then
        ret, code, msg = LUA_FILE.remove(file_path)
    end

    if not ret and _ejoysdk.utf8_to_acp then
        local acp_path = _ejoysdk.utf8_to_acp(file_path)
        ret, code, msg = LUA_FILE.remove(acp_path)
    end

    if ret then
        code = nil
        msg = nil
    end

    return ret, code, msg
end

function _FileCompat.process_batch_remove(list, cb)
    list = list or {}
    local list_size = #list
    if list_size == 0 then
        if cb then
            cb(true)
        end
    end

    for _, path in ipairs(list) do
        _FileCompat.process_remove(path)
    end

    if cb then
        cb(true)
    end
end

local function _do_copy(src_fullpath, dst_fullpath, need_override)
    local ret, code, msg
    if _ejoysdk.copy_file then
        ret, code, msg = _ejoysdk.copy_file(src_fullpath, dst_fullpath, need_override)
        --_ejoysdk.log("_do_copy >>>>>>>>>>>>>>>>>>>>>1" .. tostring(ret) .. ", src:" .. tostring(src_fullpath) .. ", dst:" .. tostring(dst_fullpath) .. ", code:" .. tostring(code) .. ", msg:" .. tostring(msg))
    else
        ret, code, msg = LUA_FILE.copy(src_fullpath, dst_fullpath, need_override)

        if not ret and _ejoysdk.utf8_to_acp then
            local acp_src_fullpath = _ejoysdk.utf8_to_acp(src_fullpath)
            local acp_dst_fullpath = _ejoysdk.utf8_to_acp(dst_fullpath)
            ret, code, msg = LUA_FILE.copy(acp_src_fullpath, acp_dst_fullpath, need_override)
        end
        --_ejoysdk.log("_do_copy >>>>>>>>>>>>>>>>>>>>>2" .. tostring(ret) .. ", src:" .. tostring(src_fullpath) .. ", dst:" .. tostring(dst_fullpath) .. ", code:" .. tostring(code) .. ", msg:" .. tostring(msg))
    end

    if ret then
        code = nil
        msg = nil
    end

    return ret, code, msg
end

--[[
复制文件
--]]
function _FileCompat.process_copy(src_fullpath, dst_fullpath, opts)
    opts = opts or {}

    local override = true -- default override is true， 和之前行为保持一致（Android和lua。windows默认都会覆盖）
    if type(opts.override) == 'boolean' then
        override = opts.override
    end

    local ret, code, msg = _do_copy(src_fullpath, dst_fullpath, override)
    return ret, code, msg
end

function _FileCompat.process_batch_copy(map, cb, opts)
    opts = opts or {}
    local override = true -- default override is true， 和之前行为保持一致（Android和lua。windows默认都会覆盖）
    if type(opts.override) == 'boolean' then
        override = opts.override
    end

    local _batch_op = function(src, dst, _override)
        return _do_copy(src, dst, _override)
    end
    LUA_FILE.batch_src_dst_operation(map, _batch_op, function(succ, code, msg, result_ext)
        if cb then
            cb(succ, code, msg, result_ext)
        end
    end, override)
end

function _FileCompat.is_support_handling_file_cache()
    return true
end

function _FileCompat.zip(_src_file_path, _file_name, _dst_path, _cb)
end

function _FileCompat.list(_src_path, _dst_path, _cb)
end

function _FileCompat.process_make_dirs(_path)
    if _ejoysdk.make_dirs then
        local result_str = _ejoysdk.make_dirs(_path)
        local result = JSON.decode(result_str)
        local succ = false
        -- local msg
        if result then
            succ = result.succ
            -- msg = result.msg
        end

        _ejoysdk.log("make_dirs, path:" .. tostring(_path) .. ", result:" .. tostring(succ))
        return succ
    else
        _ejoysdk.log("make_dirs")
        local file = io.open(_path, "rb")
        local file_exists = file ~= nil

        if file then
            file:close()
        end

        return file_exists
    end
end

function _FileCompat.get_sys_dirs()
    if not _ejoysdk.get_paths then
        _ejoysdk.log("get_sys_dirs get_paths not support")
        return nil
    end

    local path_json_str = _ejoysdk.get_paths()
    local paths = JSON.decode(path_json_str)
    return paths
end

_FileCompat.sep = '\\'

function _FileCompat.join(path)
    -- 有空写下去除中间 \ 的处理，防止出现{'a\', b} = a\\b 这样的事情
    return table.concat(path, _FileCompat.sep)
end

function _FileCompat.dirname(path)
    local dirname = string.gsub(path, "(.*" .. _FileCompat.sep .. ").*", "%1")
    return dirname
end

--[[
重命名文件或者目录
以下场景会rename失败：
1. 如果目标目录存在且不为空

@param src_fullpath: string, 必传，源文件绝对路径
@param dst_fullpath：string, 必传，目标文件绝对路径

@return bool true rename成功； nil rename 失败，同时第二个参数为msg
--]]
function _FileCompat.process_rename(src_fullpath, dst_fullpath)
    -- 老版本也有这些接口
    if _ejoysdk.renamefile then
        return _ejoysdk.renamefile(src_fullpath, dst_fullpath)
    end

    local ret, code, msg = LUA_FILE.rename(src_fullpath, dst_fullpath)
    if not ret and _ejoysdk.utf8_to_acp then
        local acp_src_fullpath = _ejoysdk.utf8_to_acp(src_fullpath)
        local acp_dst_fullpath = _ejoysdk.utf8_to_acp(dst_fullpath)
        ret, code, msg = LUA_FILE.rename(acp_src_fullpath, acp_dst_fullpath)
    end

    return ret, code, msg
end

function _FileCompat.process_batch_rename(map, cb)
    LUA_FILE.batch_src_dst_operation(map, _FileCompat.process_rename, function(succ, code, msg)
        if cb then
            cb(succ, code, msg)
        end
    end)
end

function _FileCompat.process_md5(file_path)
    local md5_hex_str
    local error_code
    local error_msg
    if _ejoysdk.readfile_offset_length and _ejoysdk.file_length then
        -- 文件存在才需要用新函数来计算md5
        local file_exists = _ejoysdk.is_file_exists(file_path)
        if not file_exists then
            return nil, EC.EJOYSDK_ERROR_CODES.RES_FILE_NOT_EXISTS, "file not exists"
        end

        local real_size = _ejoysdk.file_length(file_path)
        if real_size and real_size > 0 then
            local md5_ud = _ejoysdk_crypt.md5.start_md5c()
            local offset = 0
            local length = 200 * 1024
            repeat
                local str = _ejoysdk.readfile_offset_length(file_path, offset, length)
                offset = offset + length

                if str then
                    _ejoysdk_crypt.md5.update_md5c(md5_ud, str)
                end
            until (not str or offset >= real_size)

            local md5_data = _ejoysdk_crypt.md5.finish_md5c(md5_ud)
            if md5_data then
                md5_hex_str = _ejoysdk_crypt.hexencode(md5_data)
            else
                _ejoysdk.log("md5 data is empty for path:" .. tostring(file_path))
                md5_hex_str = nil
                error_code = EC.EJOY_LIB_ERROR.FILE_MD5_FINISH_FAILED
                error_msg = "md5 finish error"
            end
        elseif real_size and real_size == 0 then
            md5_hex_str = "d41d8cd98f00b204e9800998ecf8427e" -- 空文件md5是固定的
        else
            _ejoysdk.log("get file size failed for path:" .. tostring(file_path))
            md5_hex_str = nil
            error_code = EC.EJOY_LIB_ERROR.FILE_SIZE_GET_FAILED
            error_msg = "file size error"
        end
    else
        md5_hex_str, error_code, error_msg = LUA_FILE.md5(file_path)
        if not md5_hex_str and _ejoysdk.utf8_to_acp then
            local acp_file_path = _ejoysdk.utf8_to_acp(file_path)
            md5_hex_str, error_code, error_msg = LUA_FILE.md5(acp_file_path)
        end
    end

    _ejoysdk.log("read md5 return :" .. tostring(md5_hex_str))
    return md5_hex_str, error_code, error_msg
end

function _FileCompat.process_batch_md5(file_list, cb)
    file_list = file_list or {}
    local succ_data = {}
    local fail_data = {}
    local last_err_code
    local last_err_msg
    for _, f in ipairs(file_list) do
        local md5_val, _code, _msg = _FileCompat.process_md5(f)
        if md5_val then
            succ_data[f] = md5_val
        else
            last_err_code = _code
            last_err_msg = _msg
            fail_data[f] = {
                code = last_err_code,
                msg = last_err_msg
            }
        end
    end

    if cb then
        if last_err_code then
            cb(false, last_err_code, last_err_msg, succ_data, fail_data)
        else
            cb(true, succ_data)
        end
    end
end

function _FileCompat.process_is_directory(_file_path)
    -- not support always return false
    return false
end

function _FileCompat.process_batch_info(file_list, cb, _opts)
    local _exists_status_handler = function(path, opts)
        opts = opts or {}
        local check_size = opts.check_size or false

        local exists = _FileCompat.process_exists(path)
        local real_size
        if exists then
            if check_size then
                if _ejoysdk.file_length then
                    real_size = _ejoysdk.file_length(path)
                else
                    local file = io.open(path, "rb")
                    if not file and _ejoysdk.utf8_to_acp then
                        local acp_file_path = _ejoysdk.utf8_to_acp(path)
                        file = io.open(acp_file_path, "rb")
                    end

                    if file then
                        real_size = file:seek("end")
                        real_size = real_size or -1
                        file:close()
                    end
                end
            end
        end

        return exists, real_size
    end
    LUA_FILE.batch_info_op(file_list, cb, _opts, _exists_status_handler)
end

function _FileCompat.process_list_directory(dir_path, _recursive, cb)
    -- 旧接口只支持列举目录下面的文件，不包含子目录目录。这里包装返回的格式和新的list_dir_ex一致
    if not dir_path then
        if cb then
            cb(nil)
        end
        return
    end

    if _recursive then
        _ejoysdk.log("!!! process_list_directory in old version could not do recursive list, if need please update new version")
    end

    local path_len = #dir_path
    local dir_path_last_ch = dir_path:sub(path_len, path_len)
    local dir_path_has_sep_suffix = dir_path_last_ch == '/' or dir_path_last_ch == '\\'
    if dir_path_has_sep_suffix then
        dir_path = dir_path .. "*"
    else
        dir_path = dir_path .. _FileCompat.sep .. "*"
    end

    local ret = _ejoysdk.listdir(dir_path)
    ret = ret or {}
    local result = {}
    for _, path in ipairs(ret) do
        -- 子路径统一都不带前缀分隔符，确保逻辑处理一致性，同时三端保持统一
        local _path = M.Path.trim_begin_separator(path)
        table.insert(result, {
            ["path"] = _path,
            ["is_dir"] = false
        })
    end

    --M.log("paths >>>>>>>>>>>>>>>>")
    --M.log(result)
    if cb then
        cb(result)
    end
end

function _FileCompat.process_list_bundle(_dir_path, _recursive, cb)
    -- not support always return nil
    if cb then
        cb(nil)
    end
end

-- 释放内置资源
function _FileCompat.release_bundle_res(_src_path, _dst_path, _cb)
    if _cb then
        _cb(false, "not support")
    end
end

---- 文件操作接口，兼容旧native实现 end

-- >>>>>>>>>>>> 批量文件接口，新native实现 begin
function _FileBatch.process_remove(file_path)
    local ret, code, msg = _ejoysdk.removefile(file_path)
    return ret, code, msg
end

function _FileBatch.process_batch_remove(list, cb)
    list = list or {}
    local list_size = #list
    _ejoysdk.log("_FileBatch.process_batch_remove, list_size:" .. tostring(list_size))
    if list_size == 0 then
        if cb then
            cb(true)
        end
    end

    local params = JSON.encode({ files = list })
    M.async_call("batch_remove", function(ret)
        ret = ret or {}
        if cb then
            cb(ret.succ, ret.code, ret.msg, ret.result_ext)
        end
    end, params)
end

--[[
复制文件
--]]
function _FileBatch.process_copy(src_fullpath, dst_fullpath, opts)
    opts = opts or {}
    local override = true -- default override is true， 和之前行为保持一致（Android和lua。windows默认都会覆盖）
    if type(opts.override) == 'boolean' then
        override = opts.override
    end
    --_ejoysdk.log("_FileBatch.process_copy, override:" .. tostring(override))
    -- here return code and msg, and support directory
    local succ, code, msg = _ejoysdk.copy_file(src_fullpath, dst_fullpath, override)
    return succ, code, msg
end

function _FileBatch.process_batch_copy(map, cb, opts)
    opts = opts or {}
    local override = true -- default override is true， 和之前行为保持一致（Android和lua。windows默认都会覆盖）
    if type(opts.override) == 'boolean' then
        override = opts.override
    end
    _ejoysdk.log("_FileBatch.process_batch_copy, override:" .. tostring(override))
    local params = JSON.encode({ files = map, need_override = override })
    M.async_call("batch_copy", function(ret)
        ret = ret or {}
        if cb then
            cb(ret.succ, ret.code, ret.msg, ret.result_ext)
        end
    end, params)
end

--[[
重命名文件或者目录
以下场景会rename失败：
1. 如果目标目录存在且不为空

@param src_fullpath: string, 必传，源文件绝对路径
@param dst_fullpath：string, 必传，目标文件绝对路径

@return bool true rename成功； nil rename 失败，同时第二个参数为msg
--]]
function _FileBatch.process_rename(src_fullpath, dst_fullpath)
    return _ejoysdk.renamefile(src_fullpath, dst_fullpath)
end

function _FileBatch.process_batch_rename(map, cb)
    _ejoysdk.log("_FileBatch.process_batch_rename")
    local params = JSON.encode({ files = map })
    M.async_call("batch_rename", function(ret)
        ret = ret or {}
        if cb then
            cb(ret.succ, ret.code, ret.msg, ret.result_ext)
        end
    end, params)
end

function _FileBatch.process_batch_md5(file_list, cb)
    _ejoysdk.log("_FileBatch.process_batch_md5")
    local params = JSON.encode({ files = file_list })
    M.async_call('batch_md5', function(ret)
        ret = ret or {}
        if cb then
            if ret.succ then
                cb(true, ret.succ_data or {})
            else
                cb(false, ret.code, ret.msg, ret.succ_data or {}, ret.fail_data)
            end
        end
    end, params)
end

function _FileBatch.process_is_directory(file_path)
    local exists = M.sync_call("is_directory", file_path)
    return exists
end

function _FileBatch.process_batch_info(file_list, cb, _opts)
    _ejoysdk.log("_FileBatch.process_batch_info")
    local params = JSON.encode({ files = file_list, opts = _opts })
    M.async_call("batch_info", function(ret)
        ret = ret or {}
        --M.log("process_batch_info >>")
        --M.log(ret)
        if ret.succ then
            if cb then
                ret.succ_info = ret.succ_info or {}
                cb(ret.succ_info)
            end
        else
            if cb then
                cb(nil, ret.code, ret.msg)
            end
        end
    end, params)
end

function _FileBatch.process_list_directory(dir_path, recursive, cb)
    _ejoysdk.log("_FileBatch.process_list_directory")
    M.async_call("list_dir_ex", function(data_obj)
        data_obj = data_obj or {}
        --M.log("process_list_directory >>")
        --M.log(data_obj)
        local data = data_obj.data
        local code = data_obj.code
        local msg = data_obj.msg
        if data then
            if cb then
                cb(data)
            end
        else
            if cb then
                --_ejoysdk.log(">>>>>>>>>>>>>>>>> process_list_directory failed code:" .. tostring(code) .. ", msg:" .. tostring(msg))
                cb(nil, code, msg)
            end
        end
    end, dir_path, recursive)
end
-- <<<<<<<<<<<<<<< 批量文件接口，新native实现 end

local Media = {
    DEFAULT_MAX_FILESIZE = 1024 * 1024 * 5,
    DEFAULT_MAX_DURATION = 60 * 1000 * 3,
    DEFAULT_SAMPLING_RATE = 8000,
    DEFAULT_ENCODING_BIT_RATE = 16,
    DEFAULT_CHANNEL = 1
}
M.Media = Media

function Media.start_record(_opt, _cb)
end

function Media.stop_record(_opt, _cb)
end

function Media.start_play(opt, cb)
    opt = opt or {}

    local format = 'amr'
    if opt.format ~= 'auto' then
        format = opt.format
    end

    local params = {
        filename = opt.filename or 'noname',
        format = format,
        volume = opt.volume or 1.0 -- 预留参数，windows现在没有播放功能，参数和iOS/Android保持一致；后续开发留意需要支持此功能
    }

    local optStr = JSON.encode(params)
    M.async_call('media_start_play', cb, optStr);

    -- -- todo cbid
    -- _ejoysdk.media_start_play(0, optStr)
end

function Media.stop_play(opt, cb)
    local params = opt or {}
    M.async_call('media_stop_play', cb, params)
end

function Media.delete(opt, cb)
    local params = opt or {}
    M.async_call('media_delete', cb, params)
end

function Media.get_record_dir()
end

local Sdkinfo = {}
M.Sdkinfo = Sdkinfo

-- 获取sdk的版本号
function Sdkinfo.getSDKVersionName(sdkName)
    return _ejoysdk.sdkinfo_get_version_name(sdkName);
end

-- 针对接了高版本native，但又不接webview2的，需要调用关闭webview2功能接口
function M.disable_embed_webview(disable)
    M.log("disable_embed_webview")
    if disable == nil then
        disable_embed_webview = true
    else
        disable_embed_webview = disable
    end
    return disable_embed_webview
end

function M.support_webview()
    if disable_embed_webview then
        return false
    end
    local version = M.Sdkinfo.getSDKVersionName("EJOYSDK")
    local version_check = require "ejoysdk_lua.ejoysdk_version_check"
    -- 2.2.0版本开始支持webview组件的
    local result = version_check.compare_versions(version, '2.2.0')
    if tonumber(result) >= 0 then
        return true
    end

    return false
end

local QRCode = {}
M.QRCode = QRCode

function QRCode.gen_bmp(text)
    local succ, data = _ejoysdk.qrcode_gen_bmp(text)
    return succ, data
end

local Calendar = {}
M.Calendar = Calendar

-- 添加日历事件提醒
function Calendar.add_event(_params, _cb)
    _ejoysdk.log("todo add_event")
    -- M.async_call(ACT_CALENDAR_ADD_EVENT, params, '', function(ret)
    --    if cb then
    --        local data = ret.data
    --        local succ = ret.succ
    --        if succ then
    --            cb(true, data)
    --        else
    --            local code = ret.code
    --            local msg = ret.msg
    --            cb(false, code, msg)
    --        end
    --    end
    -- end)
end

function Calendar.delete_event(_params, _cb)
    _ejoysdk.log("todo delete_event")
    -- M.async_call(ACT_CALENDAR_DEL_EVENT, params, '', function(ret)
    --    if cb then
    --        local data = ret.data
    --        local succ = ret.succ
    --        if succ then
    --            cb(true, data)
    --        else
    --            local code = ret.code
    --            local msg = ret.msg
    --            cb(false, code, msg)
    --        end
    --    end
    -- end)
end

function Calendar.update_event(_params, _cb)
    _ejoysdk.log("todo update_event")
    -- M.async_call(ACT_CALENDAR_UPDATE_EVENT, params, '', function(ret)
    --    if cb then
    --        local data = ret.data
    --        local succ = ret.succ
    --        if succ then
    --            cb(true, data)
    --        else
    --            local code = ret.code
    --            local msg = ret.msg
    --            cb(false, code, msg)
    --        end
    --    end
    -- end)
end

function Calendar.query_event(_params, _cb)
    _ejoysdk.log("todo query_event")
    -- M.async_call(ACT_CALENDAR_QUERY_EVENT, params, '', function(ret)
    --    if cb then
    --        local data = ret.data
    --        local succ = ret.succ
    --        if succ then
    --            cb(true, data)
    --        else
    --            local code = ret.code
    --            local msg = ret.msg
    --            cb(false, code, msg)
    --        end
    --    end
    -- end)
end

function Calendar.query_event_id(_params, _cb)
    _ejoysdk.log("todo query_event")
    -- M.async_call(ACT_CALENDAR_QUERY_EVENT_ID, params, '', function(ret)
    --    if cb then
    --        local data = ret.data
    --        local succ = ret.succ
    --        if succ then
    --            cb(true, data)
    --        else
    --            local code = ret.code
    --            local msg = ret.msg
    --            cb(false, code, msg)
    --        end
    --    end
    -- end)
end

function M.support_save_to_album()
    return false
end

function M.save_to_album(_path, _need_delete, cb)
    if (cb) then
        cb({
            code = -99,
            msg = '保存失败，不支持windows'
        })
    end
end

-- todo
function M.kill_app()
    error('kill_app 需要实现');
end

function M.support_app_reviews()
    return false
end

function M.async_support_app_reviews(cb)
    if cb then
        cb(M.support_app_reviews())
    end
end

function M.app_reviews()
    M.log("rate_app is not supported in Windows")
end

function M.comment_app()
    M.log("comment_app is not supported in Windows")
end

function M.set_app_orientation(_orientation)
    -- windows do nothing
end

function M.copy_clipboard(_params)
    -- not support yet
end

function M.get_cba_tweleve_info()
    return {}
end

function Sysinfo.get_ejoy_referer()
    return nil
end

local Permission = {}
M.Permission = Permission

function Permission.check_permission_v3(_options, _cb)
    -- windows留空
end

function Permission.get_requested_permissions()
    -- windows留空
    return {}
end

function Permission.async_get_requested_permissions(cb)
    if cb then
        cb(M.Permission.get_requested_permissions())
    end
end

function Permission.show_usage_dialog(_options, _cb)
    -- windows留空
end

function Permission.checkPermission(_permission_detail, _cb)
    -- windows留空
end

function Permission.check_permission_v2(_permission, _cb)
    -- windows留空
end

function Permission.detect_permission(_permission, _cb)
    -- windows留空
end

function Permission.openSetting(_ext_param)
    -- windows留空
end

function Permission.openApplicationSetting()
    -- windows留空
end

-- 判断是否支持合规检查
function Permission.support_compliance_check()
    return false
end

-- 判断是否支持合规检查(异步)
function Permission.async_support_compliance_check(cb)
    if cb then
        cb(M.Permission.support_compliance_check())
    end
end

_ejoysdk.register_cb("FOREIGN_NATIVE_CALL", function(...)
    local lua_adapter = require 'ejoysdk_lua.ejoysdk_foreign_call'
    return lua_adapter.input(...)
end)

_ejoysdk.register_cb("FOREIGN_JSON_DECODE", JSON.decode)
_ejoysdk.register_cb("FOREIGN_JSON_ENCODE", JSON.encode)

local Loading = {}
M.Loading = Loading

function Loading.show(_option, _cb)
    -- windows留空
end

function Loading.dismiss()
    -- windows留空
end

local Toast = {}
M.Toast = Toast

function Toast.show(_message, _option)
    -- windows留空
end

function Toast.hide()
    -- windows 留空
end

--[[
    CPU使用率
    异步方法
    cb: function(ret)
        boolean succ = ret.succ
        local usage = ret.usage
    end

    succ: 获取成功or获取失败
    usage: 使用率，浮点型，1.5表示1.5%，10.0表示10.0%
--]]
function Sysinfo.cpu_usage(cb)
    M.async_call('sysinfo_cpu_usage', cb)
end

--[[
    cpu_monitor (windows待实现)
--]]
function Sysinfo.cpu_start_monitor()

end

--[[
    cpu_monitor (windows待实现)
--]]
function Sysinfo.cpu_stop_monitor()

end

--[[
    cpu_monitor (windows待实现)
--]]
function Sysinfo.cpu_monitor_enable()
    return false
end

--[[
    同步获取当前电量(windows待实现)
--]]
function Sysinfo.battery()
    return {}
end

--[[
    异步获取当前电量(windows待实现)
--]]
function Sysinfo.battery_v2(_cb)

end

-- 获取电池更多信息，Windows不支持
function Sysinfo.battery_ext(_filter, _cb)

end

function Sysinfo.launch_battery()
    return {}
end

function Sysinfo.launch_time()
    return -1
end

function Sysinfo.launch_time_async(cb)
    M.async_call('sysinfo_launch_time', cb, {})
end

function Sysinfo.run_time()
    return -1
end

function Sysinfo.run_time_async(cb)
    if not cb then
        return
    end
    Sysinfo.launch_time_async(function(info)
        if info.succ then
            local run_time = os.time() * 1000 - info.launch_time
            cb({
                succ = true,
                run_time = run_time
            })
        else
            cb({
                succ = false
            })
        end
    end)
end

function Sysinfo.network_current_state()
    return -1
end

--[[
-- 获取当前网络状态
返回值eg: cb({succ = true, state = 3}}) 或 cb({succ = false, code = -1, message = ''}})
    -1 不支持
    0=默认值，或旧版本获取不到网络
    1=无网络/未知
    2=wifi
    3=有线
--]]
function Sysinfo.network_current_state_async(cb)
    M.async_call('network_current_state', cb)
end

function Sysinfo.network_monitor_start()

end

function Sysinfo.network_monitor_stop()

end

function Sysinfo.network_ping(_params, _cb)
    -- 先空实现，等apus native实现了该功能，在放开
    -- local params = _params or {}
    -- local params_string = JSON.encode(params)
    -- M.async_call('sysinfo_network_ping', cb, params_string)
end

function Sysinfo.network_traceroute(_params, _cb)
    -- 先空实现，等apus native实现了该功能，在放开
    -- local params = _params or {}
    -- local params_string = JSON.encode(params)
    -- M.async_call('sysinfo_network_traceroute', cb, params_string)
end

-- 获取当前静音键的相关信息
function Sysinfo.get_audio_mute_info(_cb)
    -- todo: win待实现
end

-- 开始监听禁音键的变化
function Sysinfo.start_listen_audio_mute()
    -- todo: win待实现
end

-- 停止监听禁音键的变化
function Sysinfo.stop_listen_audio_mute()
    -- todo: win待实现
end

-- 当前是否正在监听禁音键
function Sysinfo.is_audio_mute_listen_open()
    -- todo: win待实现
    return false
end

function M.set_audio_category(_category)
    -- ios api, windows do nothing
end

function Sysinfo.can_resolve_activity(_package_name, _package_activity_name)
    -- android api, windows do nothing
    return false
end

-- 获取屏幕刷新率，返回table数据结构
function Sysinfo.get_screen_refresh_rate(cb)
    M.async_call('get_screen_refresh_rate', function(temp)
        if temp then
            if not temp.frame_rate_now then
                temp.frame_rate_now = -1 -- PC 取不到帧率，默认写-1
            end
            if not temp.device_rate_max and temp.frame_rate_max then
                temp.device_rate_max = temp.frame_rate_max -- 补上设备最大刷新率，PC就直接取当前用户设置的屏幕刷新率
            end
        end

        if cb then
            cb(temp)
        end
    end)
end

local Sensor = {}
M.Sensor = Sensor

M.Sensor.SHAKE_EVENT = {
    BEGIN = "SHAKE_BEGIN",
    END = "SHAKE_END",
    CANCEL = "SHAKE_CANCEL"
}

function Sensor.set_threshold(_threshold)
    -- windows do nothing
end

function Sensor.register_shake(_cb)
    -- windows do nothing
end

function Sensor.unregister_shake()
    -- windows do nothing
end

function M.get_brightness()
    -- windows do nothing
    return -1
end

function M.set_brightness(_brightness)
    -- windows do nothing
end

function M.reset_brightness()
    -- windows do nothing
end

function M.vibrate(_milliseconds)
    -- windows do nothing
end

function M.is_vibrate_support()
    return false
end

function M.get_audio_category()
    -- ios api, windows do nothing
end

function M.scroll_log_file(_file_name)

end

function M.flush_log()

end

function M.get_log_file_infos(_params, _cb)

end

function M.get_current_log_file(_params, _cb)

end

function M.get_ej_debugable()
    return false
end

-- 显示游戏窗口
function M.switch_to_game()
    if _ejoysdk.switch_to_game then
        return _ejoysdk.switch_to_game() == 1
    end
    return false
end

local cache_pc_ad_token
function M.set_pc_ad_token(pc_ad_token)
    if pc_ad_token and pc_ad_token ~= '' then
        cache_pc_ad_token = pc_ad_token
        -- 调用set_pc_ad_token的时机可能比get_pkg_info要晚，这里补充给pkg_info中设置pc_ad_token
        M.get_pkg_info().pc_ad_token = cache_pc_ad_token
        -- 重置env_info， set_pc_ad_token的时机可能比拼接env_info时机晚
        local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
        ESTAT.reset_env_info()
    end
end

function M.get_pc_ad_token()
    if cache_pc_ad_token == nil then
        -- 尝试读取文件获取
        local config_content = M.File.readfile('ejoysdk_pc_ad.ini')
        if config_content ~= nil then
            local data = JSON.safe_decode(config_content)
            if data and data.pcAdToken then
                cache_pc_ad_token = data.pcAdToken
            end
        end
    end
    return cache_pc_ad_token
end

function M.get_pre_order_items(cb)
    -- NOT SUPPORT
    cb = cb or function()
    end
    cb(false, 'windows', -1, 'not support')
end

function M.get_system_properties(_key, _default_value)
    -- android api, pc do nothing
end

return M
