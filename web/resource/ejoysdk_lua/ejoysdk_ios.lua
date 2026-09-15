-- iOS 平台相关的ejoysdk lua 代码
local JSON = require "ejoysdk_lua.ejoysdk_json"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local unpack = unpack or table.unpack
local UTILS = require 'ejoysdk_lua.ejoysdk_utils'
local EM = require "ejoysdk_lua.ejoysdk_module"
local LANG = require "ejoysdk_lua.lang.util"
local LUA_FILE = require "ejoysdk_lua.libs.luafile"
local ECC = require "ejoysdk_lua.ejoysdk_constants"
--local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'

local _TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'ios'

local M = {}
local cbs = {}
local cb_id = math.random(1000, 9999)

local UTDID = nil

M.PLATFORM = {
    OS = "iOS",
    HTTP_UA = "AFNetworking/2.4.5 (iOS; iPhone)"
}

local native_support_functions = {}

function M.is_support_function(func_name)
    local cache_result = native_support_functions[func_name]
    if type(cache_result) ~= 'nil' then
        return cache_result
    end
    if _ejoysdk[func_name] ~= nil
            or func_name == ECC.NATIVE_SUPPORT_FUNCTION_NAMES.HTTP_DOWNLOAD
            or func_name == ECC.NATIVE_SUPPORT_FUNCTION_NAMES.DOWNLOAD_SINGLE_POOL
            or func_name == ECC.NATIVE_SUPPORT_FUNCTION_NAMES.TIMER_FLOAT_INTERVAL then
        native_support_functions[func_name] = true
        return true
    end

    if func_name == ECC.NATIVE_SUPPORT_FUNCTION_NAMES.BATCH_FILE_OPERATION
            or func_name == ECC.NATIVE_SUPPORT_FUNCTION_NAMES.FILE_DIR_OPERATION then
        local ret = _ejoysdk.batch_remove ~= nil-- similar apis
        native_support_functions[func_name] = ret
        return ret
    end

    native_support_functions[func_name] = false
    _ejoysdk.log("is_support_function failed, func_name = "..tostring(func_name))
    return false
end

function M.async_call(fn_name, cb, ...)
    local id = cb_id
    cb_id = cb_id + 1
    cbs[id] = cb
    local func = _ejoysdk[fn_name]
    if func ~= nil then
        func(id, ...)
    else
        _ejoysdk.log(fn_name .. " 该函数不存在！！！！！")
    end

    return id
end

-- 同步调用
function M.sync_call(fn_name, ...)
    local func = _ejoysdk[fn_name]
    if func ~= nil then
        return func(...)
    end

    return nil
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

local function async_callback(id, ...)
    local cb = cbs[id]
    if cb then
        cbs[id] = nil
        cb(...)
    end
end

_ejoysdk.register_cb("ASYNC_CALL", async_callback)

function M.printl(content)
    M.log({msg= content})
end

local HTTP_EVENT = 'HTTP_EVENT'
local http_progress_cbs = {}
local http_progress_tid_cbid_map = {}

_ejoysdk.register_cb(HTTP_EVENT, function(cbid, received, total, type, ext)
    local params  = http_progress_cbs[cbid]
    if params then
        if type and type=='header'  then
            if ext and ext.headers then
                if params.header_cb then
                    params.header_cb(ext.headers)
                end
            end
        elseif received == -1 then
            http_progress_cbs[cbid] = nil
            if params.finish_cb then
                params.finish_cb()
            end
        else
            params.progress(params.url, params.file, received, total)
        end
    end
end)



local HTTP = {}
M.HTTP = HTTP

-- 快速获取http头
function HTTP.get_headers(url,_params,cb)
    local headers = HTTP.check_and_update_headers({})
    M.async_call('http_get_headers', function(resp)
        if(cb)then
            cb(JSON.decode(resp))
        end
    end , url, headers);
end

-- windows对接的curl的证书pin接口，需要放入证书的publickey。而其它端需要的是证书的certificate内容。
-- 详细见：https://curl.se/libcurl/c/CURLOPT_PINNEDPUBLICKEY.html 和 https://blog.csdn.net/u010980938/article/details/111050830
function HTTP.add_cert(ca_name, ca_chunk, cb)
    local function cb_wrap(resp) -- resp : string
        local succ, result = pcall(JSON.decode, resp) -- 可能有未知的结果，打点跟踪
        if not succ then
            local error_msg = result
            local stat = require 'ejoysdk_lua.ejoysdk_stat'
            stat.stat_action('ios_add_cert', 'wrong_type', false, {resp = resp ,error_msg = error_msg })
            if cb then
                cb(false)
            end
            return
        else
            if cb then
                cb(result.succ)
            end
        end
    end
    local optStr = JSON.encode({name = ca_name})
    M.async_call('http_add_cert', cb_wrap, optStr, ca_chunk)
end

function HTTP.add_cert_pin(_host_pattern, _ca_name, _ca_chunk, _cb)
    -- 这里可能需要按照域名维度配置证书
    -- TODO
end

function HTTP.process_get(url, params, cb)
    local headers = params and params.headers
    assert(headers, 'params.headers should not be nil')

    local task_id = params.taskId

    -- 参考android处理，缓存一下传入的func，避免encode异常
    local progress = params.progress
    params.progress = nil
    local finish_cb = params.finish_cb
    params.finish_cb = nil
    local header_cb = params.header_cb
    params.header_cb = nil

    local name = 'http_get'
    if params.file then
        name = 'http_get_file'
        if params.enable_limit_speed and _ejoysdk.http_get_file_limit_speed then
            name = 'http_get_file_limit_speed' -- 此次下载带限速
        end

        -- 断点续传的函数也是去调用下载限速的函数，这里分开两个函数是为了方便判断native是否支持而已
        local temp_name = M.NATIVE_SUPPORT_FUNCTION_NAMES.HTTP_DOWNLOAD_RANGE
        if params.enable_download_range and params.file and M.is_support_function(temp_name) then
            name = temp_name
        end
    end

    local CJSON = require "ejoysdk_lua.ejoysdk_cjson"
    local params_str = CJSON.encode(params or {})
    local cbid = M.async_call_with_opts(name, {
        timeout=params.timeout,
        timeout_cb=function() cb({status=0}) end
    }, function(status, resp_headers, body, http_ext_params)
        resp_headers = HTTP.Header.New(resp_headers)
        local info = {
            status=status,
            headers=resp_headers,
        }

        info.body = body
        info.http_ext_params = CJSON.safe_decode(http_ext_params)
        cb(info)
    end, url, headers, params.file, params_str)
    if params.file and progress then
        http_progress_cbs[cbid] = {url = url, file = params.file, progress = progress, finish_cb = finish_cb, header_cb = header_cb}
    end

    if task_id then
        http_progress_tid_cbid_map[task_id] = cbid
    end
end

function HTTP.process_post(url, params, content_type, body, cb)
    local headers = params and params.headers
    assert(headers, 'params.headers should not be nil')

    -- 参考android的一些处理，实现外部有可能传了func，还是保证已知的安全的参数给到native
    -- 注意：后续新增的参数可以放这里，约定可控的前缀 safe_ 则自动扩展
    local safe_params = {}
    safe_params.use_gzip = params.use_gzip or false
    for pkey, pvalue in pairs(params) do
        if pkey and type(pkey) == 'string' and pkey:sub(1, 5) == 'safe_' and type(pvalue) ~= 'function' then
            -- 如 safe_params.safe_formdata = params.safe_formdata
            safe_params[pkey] = pvalue
        end
    end
    local safe_params_str = JSON.encode(safe_params)

    M.async_call_with_opts('http_post', {
        timeout=params.timeout,
        timeout_cb=function() cb({status=0}) end
    }, function(status, resp_headers, resp_body, http_ext_params)
        resp_headers = HTTP.Header.New(resp_headers)
        local info = {
            status=status,
            headers=resp_headers,
        }

        info.body = resp_body
        info.http_ext_params = JSON.safe_decode(http_ext_params)
        cb(info)
    end, url, headers, body, content_type, safe_params_str)
end

function HTTP.process_stop(_task_id_arr, _params, cb)
    if not _task_id_arr or next(_task_id_arr) == nil then
        return
    end

    local _task_id = _task_id_arr[1]
    -- _params有个timeout，暂时没用到，跟安卓保持接口一致而已
    _params = _params or {}
    _params.task_array = _task_id_arr
    local CJSON = require "ejoysdk_lua.ejoysdk_cjson"
    local optionString = CJSON.encode(_params)

    M.async_call('http_stop', cb, _task_id , optionString)
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

function HTTP.update_with_config(params)
    local optionString = '{}'
    if params then
        local CJSON = require "ejoysdk_lua.ejoysdk_cjson"
        optionString = CJSON.encode(params)
    end
    M.sync_call('http_update_config', optionString)

end

function HTTP.http_remove_cache()
    M.sync_call('http_remove_cache')
end

-- iOS才有此接口, 默认关闭afn缓存
-- is_open, int类型： 1表示开启，0表示关闭
function HTTP.http_enable_cache(is_open)
    M.sync_call('http_enable_cache', is_open)
end

local KEYSTORE_KEY = 'ejoysdk'
local KeyStore = {}
M.KeyStore = KeyStore

function KeyStore.get(key)
  local store = _ejoysdk.load_from_keychain(KEYSTORE_KEY) or {}
  return store[key]
end

-- 增加的一组带共享group的函数，用于APP之间的keychain数据共享，不要乱调用
function KeyStore.get_group(access_group)
    if access_group and _ejoysdk.load_from_keychain_group then
        local store = _ejoysdk.load_from_keychain_group(KEYSTORE_KEY, access_group) or {}
        return store
    end

    return nil
end

function KeyStore.set(key, value)
    local store = _ejoysdk.load_from_keychain(KEYSTORE_KEY) or {}
    store[key] = value
    _ejoysdk.save_to_keychain(KEYSTORE_KEY, store)
end

function KeyStore.set_group(key, access_group, value)
    if access_group and _ejoysdk.save_to_keychain_group then
        local store = KeyStore.get_group(access_group) or {}
        store[key] = value
        _ejoysdk.save_to_keychain_group(KEYSTORE_KEY, access_group, store)
    end
end

function KeyStore.delete(key)
  local store = _ejoysdk.load_from_keychain(KEYSTORE_KEY)
  if store then
    store[key] = nil
    _ejoysdk.save_to_keychain(KEYSTORE_KEY, store)
  end
end

function KeyStore.delete_group(key, access_group)
    if access_group and _ejoysdk.save_to_keychain_group then
        local store = KeyStore.get_group(access_group)
        if store then
            store[key] = nil
            _ejoysdk.save_to_keychain_group(KEYSTORE_KEY, access_group, store)
        end
    end
end

function KeyStore.clear()
  _ejoysdk.delete_from_keychain(KEYSTORE_KEY)
end

function KeyStore.clear_group(access_group)
    if access_group and _ejoysdk.delete_from_keychain_group then
        _ejoysdk.delete_from_keychain_group(KEYSTORE_KEY, access_group)
    end
end

function KeyStore.custom_sub_dir(_sub_dir_param)
    -- do nothing here
end

local UnRecoverKeyStore = {}
M.UnRecoverKeyStore = UnRecoverKeyStore

function UnRecoverKeyStore.get(key)
    local store = _ejoysdk.load_from_userdefault(KEYSTORE_KEY) or {}
    return store[key]
end

function UnRecoverKeyStore.set(key, value)
    local store = _ejoysdk.load_from_userdefault(KEYSTORE_KEY) or {}
    store[key] = value
    _ejoysdk.save_to_userdefault(KEYSTORE_KEY, store)
end

function UnRecoverKeyStore.delete(key)
    UnRecoverKeyStore.set(key, nil)
end

function UnRecoverKeyStore.clear()
    _ejoysdk.delete_from_userdefault(KEYSTORE_KEY)
end

-- sharedpreferences raw api
local SPRawKeyStore = {}
function SPRawKeyStore.get(_sp_name, key)
    local succ, msg = pcall(_ejoysdk.load_from_userdefault, key)
    if not succ then
        M.log('iOS SPRawKeyStore get value error, key: ' .. tostring(key))
        M.log('sdk catch error msg: ' .. tostring(msg))
        return nil
    else
        return msg
    end
end

-- iOS native 层的 save_to_userdefault 旧版本不支持写入 string 类型，会抛出 lua error
-- save_to_userdefault 支持写入 string，从 ejoysdk-iOS v2.1.10 开始支持
function SPRawKeyStore.set(_sp_name, key, value)
    local succ, msg = pcall(_ejoysdk.save_to_userdefault, key, value)
    if not succ then
        M.log('iOS SPRawKeyStore set value error, key: ' .. tostring(key) .. ' ,value: ' .. tostring(value))
        M.log('sdk catch error msg: ' .. tostring(msg))
    end
    return succ
end

function SPRawKeyStore.delete(_sp_name, key)
    _ejoysdk.delete_from_userdefault(key)
end

M.SPRawKeyStore = SPRawKeyStore

local SYNC_WEBVIEW_OPERATOR= 'webview_operator'
local ACT_WEBVIEW_GO_BACK = 'go_back'
local ACT_WEBVIEW_GO_FORWARD = 'go_forward'
local ACT_WEBVIEW_RELOAD = 'reload'
local ACT_WEBVIEW_SHOW = 'show'
local ACT_WEBVIEW_HIDE = 'hide'
local ACT_WEBVIEW_REMOVE_HIDE_CACHE = 'remove_hide_cache'
-- local ACT_WEBVIEW_PREPARE = 'prepare'

local WebView = {}
M.WebView = WebView

function WebView.open(url, injection, option, on_js_callback, on_close_callback)
    local EWB = require "ejoysdk_lua.ejoysdk_webview_manager"
    return EWB.add_webview(url, injection, option, on_js_callback, on_close_callback)
end

function WebView.close()
    return _ejoysdk.webview_close()
end

function WebView.prepare(_params)
    return false
end

-- 工具栏相关能力补充
function WebView.go_back()
    local parmas = { type = ACT_WEBVIEW_GO_BACK }
    local parmasString = JSON.encode(parmas)
    return M.sync_call(SYNC_WEBVIEW_OPERATOR, parmasString) or false
end

function WebView.go_forward()
    local parmas = { type = ACT_WEBVIEW_GO_FORWARD }
    local parmasString = JSON.encode(parmas)
    return M.sync_call(SYNC_WEBVIEW_OPERATOR, parmasString) or false
end

function WebView.reload()
    local parmas = { type = ACT_WEBVIEW_RELOAD }
    local parmasString = JSON.encode(parmas)
    M.sync_call(SYNC_WEBVIEW_OPERATOR, parmasString)
end

function WebView.show(params)
    params = params or {}
    local parmasString = JSON.encode({ type = ACT_WEBVIEW_SHOW, data = params })
    return M.sync_call(SYNC_WEBVIEW_OPERATOR, parmasString)
end

function WebView.hide(params)
    params = params or {}
    local parmasString = JSON.encode({ type = ACT_WEBVIEW_HIDE, data = params })
    return M.sync_call(SYNC_WEBVIEW_OPERATOR,parmasString )
end

function WebView.remove_hide_cache(params)
    params = params or {}
    local parmasString = JSON.encode({ type = ACT_WEBVIEW_REMOVE_HIDE_CACHE, data = params })
    return M.sync_call(SYNC_WEBVIEW_OPERATOR, parmasString)
end

function WebView.update_toolbar(toolbar_config)
    local EWB = require "ejoysdk_lua.ejoysdk_webview_manager"
    EWB.update_toolbar(toolbar_config)
end

function WebView.update_toolbar_item(params)
    local EWB = require "ejoysdk_lua.ejoysdk_webview_manager"
    EWB.update_toolbar_item(params)
end

function WebView.capture(callback)
    M.async_call('webview_capture',function(resp)
        local body=JSON.decode(resp)
        callback(body)
    end)
end

function WebView.is_opened()
    return _ejoysdk.webview_is_opened()
end

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
        ET.publish('webview_life_cycle',value)
    end

end)

local url_open_datas = {}
local gangplank_inited = false
local did_register_event = false

-- 提供游戏主动获取拉起数据的接口
function M.get_url_open_datas()
    -- 优先从native的内存缓存里去取
    local last_openurl_data = M.get_last_openurl_data()
    if last_openurl_data and next(last_openurl_data) then
        return last_openurl_data
    else
        return UTILS.deepcopy(url_open_datas) or {}
    end
end

-- 从native侧获取openurl_data的缓存(SDK内部用，游戏不要调本接口)
function M.get_last_openurl_data()
    local last_openurl_data_json = M.sync_call('get_last_openurl_data')
    local last_openurl_data = JSON.safe_decode(last_openurl_data_json)
    if last_openurl_data and last_openurl_data.value and next(last_openurl_data.value) then
        -- 返回值是数组类型，为了和get_url_open_datas接口保持一致
        return UTILS.deepcopy({last_openurl_data.value})
    else
        return {}  -- 空数组
    end
end

local function publish_urlopen(data)
    _ejoysdk.log('url_open, [v2]_app_event_handler, publish_data:' .. JSON.encode(data))

    if data.type and data.type == 'handleOpenUniversalLink' then
        ET.publish('urlopen_v2', 'universal_link', data)
    else
        ET.publish('urlopen_v2', 'url', data)

        -- 兼容旧的通知
        if data.url then
            _ejoysdk.log('url_open, _app_event_handler, publish_url:' .. data.url)
            ET.publish('urlopen', data.url)
        end
    end
end

local function init_handler ()
    gangplank_inited = true

    if (url_open_datas and #url_open_datas == 0) or (url_open_datas == nil) then
        local ukeystore = M.get_url_data_keystore()
        if ukeystore then
            url_open_datas = ukeystore:get()
            ukeystore:delete()
        end
    end

    if url_open_datas then
        for _, data in pairs(url_open_datas) do
            publish_urlopen(data)
        end
        -- 内存缓存保留
        --url_open_datas = nil
    end

    -- 开启网络变化的监测
    M.Sysinfo.network_monitor_start()
end

local last_network_type

local register_event = function()
    if did_register_event then
        return
    end

    did_register_event = true

    ET.subscribe(ET.gangplank.INITED, init_handler)

    local APP_EVENT = 'APP_EVENT'
    local APP_OPENURL_EVENT = 0
    local APP_ON_STOP_EVENT = 1
    local APP_NETWORK_STATE_CHANGE_EVENT = 10
    local APP_AUDIO_MUTE_CHANGE_EVENT = 11

    local _app_event_handler = {
        [APP_OPENURL_EVENT] = function(obj)
            local data = obj or {}

            if gangplank_inited then
                publish_urlopen(data)
            else
                url_open_datas = url_open_datas or {}
                table.insert(url_open_datas, data)
                -- 存储避免多vm前置消费的情况
                local ukeystore = M.get_url_data_keystore()
                if ukeystore then
                    ukeystore:set(url_open_datas)
                end
            end

            if data and data.type and data.type == 'handleOpenUniversalLink' then
                if data.data and data.data.ejoysdk_debugable then
                    M.File.writefile('ejoysdk.debug', '')
                elseif data.data and data.data.ejoysdk_debugdisable then
                    M.File.remove('ejoysdk.debug')
                end
            end
        end,
        [APP_ON_STOP_EVENT] = function()
            ET.publish("app_on_stop")
        end,
        [APP_NETWORK_STATE_CHANGE_EVENT] = function(state_info)
            _ejoysdk.log('lua receive network_state_change, type=' .. tostring(state_info.type) .. ', state=' .. tostring(state_info.state))
            -- 如果当前的网路状态和上一次回调的一致，那就不在推送事件
            -- 在部分机型上面，state_info返回状态有问题，所以通过network_type来做判断
            local network_type = M.Sysinfo.network_type()
            _ejoysdk.log('get the network type >> ' .. tostring(network_type) .. ', and last type >> ' .. tostring(last_network_type))
            if last_network_type == nil or network_type ~= last_network_type then
                last_network_type = network_type
                ET.publish("network_state_change", state_info)
            else
                _ejoysdk.log('new network type is same to last network type, do not publish event')
            end
        end,
        [APP_AUDIO_MUTE_CHANGE_EVENT] = function(audio_mute_info)
            _ejoysdk.log('lua receive audio_mute_change, type=' .. tostring(audio_mute_info.type) .. ', is_mute=' .. tostring(audio_mute_info.isMute))
            ET.publish("audio_mute_change", audio_mute_info)
        end
    }
    _ejoysdk.register_cb(
            APP_EVENT,
            function(cbid, js_str, chunk)
                local handler = _app_event_handler[cbid]
                if handler then
                    local value = JSON.safe_decode(js_str)
                    handler(value, chunk)
                end
            end
    )
end

register_event()

local Modal = {}
M.Modal = Modal

function Modal.open(title, option, cb)
    local optionString = '{}'
    if option then
        optionString = JSON.encode(option)
    end
    cb = cb or function() end
    M.async_call('modal_open', cb, title, optionString)
end

function Modal.close(cb)
    cb = cb or function() end
    M.async_call("modal_close", cb)
end

function Modal.alert(title, message, cb)
    local option = {
        message= tostring(message),
        buttons= {'确定'}
    }
    local optionString = JSON.encode(option)
    local cb_wrap = function(_index) cb() end
    M.async_call('modal_open', cb_wrap, title, optionString)
end

function Modal.confirm(title, message, cb)
    local option = {
        message= tostring(message),
        buttons= {'取消', '确定'}
    }
    local optionString = JSON.encode(option)
    local cb_wrap = function(index)
        cb(index ~= 0);
    end
    M.async_call('modal_open', cb_wrap, title, optionString)
end

local Toast = {}
M.Toast = Toast

function Toast.show(message, option)
    local optionString = '{}'
    if option then
        optionString = JSON.encode(option)
    end
    return _ejoysdk.toast_open(message or '', optionString)
end

function Toast.hide()
    return _ejoysdk.toast_open('', '{}')
end

local Loading = {}
M.Loading = Loading

function Loading.show(option, cb)
    local optionString = '{}'
    if option then
        optionString = JSON.encode(option)
    end

    local cb_wrap = function(_index) cb() end

    M.async_call('loading_show', cb_wrap, optionString)
end

function Loading.dismiss()
    return M.async_call('loading_dismiss')
end

local Sysinfo = {}
M.Sysinfo = Sysinfo

function Sysinfo.idfa()
    return _ejoysdk.sysinfo_idfa()
end

function Sysinfo.device_id()
    return Sysinfo.idfa()
end

function Sysinfo.idfv()
    return _ejoysdk.sysinfo_idfv()
end

-- 安装标识
function Sysinfo.uuid()
    return Sysinfo.idfv()
end

local keychain_group_share_name = nil
local function get_keychain_share_group_name()
    if keychain_group_share_name then
        return keychain_group_share_name
    end

    local group_name =  M.Sysinfo.package_name() -- 大包用包名当做group来共享

    -- 如果是云微端则从sdkconfig.json里读取group
    local UNI = require "ejoysdk_lua.vendors.unisdk"
    local sdk_infos = UNI.get_sdk_infos()
    local cloud_game = 'CLOUD_GAME'
    local cloud_data = sdk_infos[cloud_game]
    if cloud_data and cloud_data['meta_data'] then
        local meta_data = cloud_data['meta_data']
        if meta_data['keychain_share_group'] then
            group_name = meta_data['keychain_share_group']
        end
    end

    keychain_group_share_name = group_name

    return keychain_group_share_name
end

function Sysinfo.utdid()
    if UTDID == nil then
        local utdid_key = "utdid"

        local set_utdid_to_share_group_keychain_func = function(utdid_value)
            local group_name = get_keychain_share_group_name()
            M.KeyStore.set_group(utdid_key, group_name, utdid_value)
        end

        local value = M.KeyStore.get(utdid_key)
        if value and type(value)=='string' and string.len(value) > 0 then
            -- 如果keychain里已经有值，则直接使用
            UTDID = value
            set_utdid_to_share_group_keychain_func(value)
        else
            -- keychain里没有值，则从库里读取一份，然后写入keychain
            UTDID = _ejoysdk.sysinfo_utdid()
            if UTDID and type(UTDID)=='string' and string.len(UTDID) > 0 then
                M.KeyStore.set(utdid_key, UTDID)
                set_utdid_to_share_group_keychain_func(UTDID)
            end
        end


    end
    return UTDID or ''
end

local function check_if_support_aligames_login(vendor_name)
    if not vendor_name then
        return false
    end

    local UNI = require "ejoysdk_lua.vendors.unisdk"
    local sdk_infos = UNI.get_sdk_infos()
    for sdk_name, _sdk_info in pairs(sdk_infos) do
        if sdk_name == vendor_name then
            return true
        end
    end

    return false
end

function Sysinfo.ds_channel_id()
    if M.CONFIG.get_config(M.CONFIG.KEY.MULTI_REGIONS_ENABLED) then
        -- 海外没有大圣渠道号
        return ''
    else
        -- 国内渠道号
        local has_aligames = check_if_support_aligames_login("ALIGAMES")
        if has_aligames then
            -- 有接入ALIGAMES
            return '998233'
        end

        return ''
    end
end

function Sysinfo.ds_sub_channel_id()
    return _ejoysdk.sysinfo_sub_channel_id and _ejoysdk.sysinfo_sub_channel_id() or ''
end

-- 获得国家地区信息
function Sysinfo.country()
    if _ejoysdk.sysinfo_country then
        return _ejoysdk.sysinfo_country()
    else
        return ""
    end
end

function Sysinfo.language()
    if _ejoysdk.sysinfo_apple_languages then
        local apple_languages = _ejoysdk.sysinfo_apple_languages()
        local strs = M.Utils.split_string(apple_languages, '-')
        if strs and #strs > 0 then
            return strs[1] or ""
        end
    end
    return ""
end

function Sysinfo.language_script()
    if _ejoysdk.sysinfo_apple_languages then
        local apple_languages = _ejoysdk.sysinfo_apple_languages()
        local strs = M.Utils.split_string(apple_languages, '-')
        if strs and #strs == 3 then
             return strs[2] or ""
        end
    end
    return ""
end

function Sysinfo.time_zone()
    if _ejoysdk.sysinfo_time_zone then
        return _ejoysdk.sysinfo_time_zone()
    else
        return ""
    end
end

function Sysinfo.set_audio_category(category)
    _ejoysdk.sysinfo_set_audio_category(category)
end

function Sysinfo.get_audio_category()
    return _ejoysdk.sysinfo_audio_category()
end

function Sysinfo.open_url(url)
    return _ejoysdk.sysinfo_open_url(url)
end

function Sysinfo.can_open_url(url)
    return M.sync_call('can_open_url', url)
end

function Sysinfo.async_can_open_url(url, cb)
    if cb then
        cb(Sysinfo.can_open_url(url))
    end
end

--[[
    同步方法
    当前电池状态
    返回值： table类型, eg. {'level'=90,'scale'=100,'status'=2}
    level: 当前电量
    scale: 总电量
    state= 0未知状态，1非充电状态，2充电状态，3充满状态（连接充电器充满状态）
--]]
function Sysinfo.battery()
    return _ejoysdk.sysinfo_battery()
end

--[[
    异步方法
    当前电池状态，
    cb: function(ret)
        -- ret.level: 当前电量, 整型
        -- ret.scale: 总电量，整型
        -- ret.state= 0未知状态，1非充电状态，2充电状态，3充满状态（连接充电器充满状态）
    end
--]]
function Sysinfo.battery_v2(cb)
    M.async_call('sysinfo_battery_v2', cb)
end

-- 获取电池更多信息，iOS不支持
function Sysinfo.battery_ext(_filter, _cb)

end

--[[
    同步方法
    APP启动时的电量
    返回值：table类型, eg. {'level'=90,'scale'=100,'status'=2}
    level: 当前电量
    scale：总电量
    status： 0未知状态，1非充电状态，2充电状态，3充满状态（连接充电器充满状态）
--]]
function Sysinfo.launch_battery()
    return _ejoysdk.sysinfo_launch_battery()
end

--
-- 获取网络类型
-- 返回值：
-- 0=断网,1=wifi,2=移动网络,3=未知网络类型
-- 注：推荐使用network_current_state方法
function Sysinfo.network_type()
    return _ejoysdk.sysinfo_network_type()
end

function Sysinfo.network_type_cache()
    if last_network_type == nil then
        last_network_type = M.Sysinfo.network_type()
    end

    return last_network_type
end

-- 未实现
-- 注：推荐使用network_current_state方法
function Sysinfo.network_type_name()
    --TODO
    return ''
end

--[[
-- 获取当前网络状态（推荐使用该方法）
-- 返回值:
-- 0=默认值
-- 1=未知网络类型，例如6G出来，老版本SDK不识别
-- 2=wifi
-- 3=2G
-- 4=3G
-- 5=4G
-- 6=5G
--]]
function Sysinfo.network_current_state()
    local res = M.sync_call('network_current_state') or 0
    return res
end

function Sysinfo.network_current_state_async(cb)
    local net_state = Sysinfo.network_current_state()
    cb({succ = true, state = net_state})
end

-- 开启网络监测, SDK初始化后，会默认开启
function Sysinfo.network_monitor_start()
    M.sync_call('sysinfo_network_monitor_start')
end

-- 关闭网络监测
function Sysinfo.network_monitor_stop()
    M.sync_call('sysinfo_network_monitor_stop')
end

function Sysinfo.network_ping(_params, _cb)
    -- 移动端，是走unisdk的，详见vendors/apm.lua
end

function Sysinfo.network_traceroute(_params, _cb)
    -- 移动端，是走unisdk的，详见vendors/apm.lua
end

function Sysinfo.app_name()
    return _ejoysdk.sysinfo_app_name() or ''
end

function Sysinfo.app_version_code()
    return _ejoysdk.sysinfo_app_version_code()
end

function Sysinfo.app_version_name()
    return _ejoysdk.sysinfo_app_version_name()
end

-- iOS 云游会使用到这个参数，和Android对齐
function Sysinfo.device_with_android_id()
    return M.Sysinfo.utdid()
end

function Sysinfo.is_passive_mode()
    return _ejoysdk.is_passive_mode and _ejoysdk.is_passive_mode()
end

local userAgent = nil
function Sysinfo.get_user_agent()
    -- 如果获取不到iOS会返回unknown
    if not userAgent or (userAgent == "unknown") then
        userAgent = M.sync_call('_sysinfo_get_user_agent')
    end

    -- 再尝试从经分里里获取
    if not userAgent or (userAgent == "unknown") then
        local userAgent_jf = M.sync_call('_sysinfo_get_user_agent_jf')
        if userAgent_jf then
            userAgent = userAgent_jf
        end
    end

    return userAgent
end

local hwMachine = nil
function Sysinfo.hw_machine()
    if not hwMachine then
        hwMachine = M.sync_call('sysinfo_hw_machine')
    end
    return hwMachine
end

--返回单位：字节
--[[
    返回值，table类型，{"internal_total_storage_size"=xx,
                      "internal_available_storage_size"=xx
                     }
--]]
function Sysinfo.get_storage_info()
    return M.sync_call('get_storage_info')
end

--[[
    返回值，table类型，{
                      "internal_available_storage_size"=xx
                     }
--]]
function Sysinfo.storage()
    local storage_info  = M.Sysinfo.get_storage_info()
    if storage_info then
        local available = storage_info["internal_available_storage_size"]
        return {
            availableInternalStorage = available
        }
    end
    return {}
end


function Sysinfo.os_version()
    return _ejoysdk.sysinfo_os_version()
end

function Sysinfo.install_time()
    return ''
end

function Sysinfo.update_time()
    return ''
end

function Sysinfo.screen_width()
    return M.Sysinfo.screen().width
end

function Sysinfo.screen_height()
    return M.Sysinfo.screen().height
end

function Sysinfo.content_size(cb)
    if not cb then
        return
    end

    local width = Sysinfo.screen_width()
    local height = Sysinfo.screen_height()
    cb(width, height)
end

function Sysinfo.model()
    return _ejoysdk.sysinfo_model()
end

function Sysinfo.machine()
    return _ejoysdk.sysinfo_machine()
end

function Sysinfo.brand()
    return 'Apple'
end

function Sysinfo.package_name()
    return _ejoysdk.sysinfo_bundleid()
end

function Sysinfo.screen()
    return _ejoysdk.sysinfo_screen_size()
end

function Sysinfo.is_jailbroken()
    return _ejoysdk.sysinfo_is_jailbroken()
end

function Sysinfo.device_name()
    return _ejoysdk.sysinfo_device_name()
end

-- APP启动时间，时间戳，单位毫秒, 整型
function Sysinfo.launch_time()
    return _ejoysdk.sysinfo_launch_time()
end

function Sysinfo.launch_time_async(_cb)

end

-- APP运行时间，单位毫秒，整型
function Sysinfo.run_time()
    return os.time() * 1000 - Sysinfo.launch_time()
end

function Sysinfo.run_time_async(_cb)

end

function Sysinfo.mobile_info()
    return _ejoysdk.sysinfo_mobile_info()
end

function Sysinfo.is_vpn_connected()
    if _ejoysdk.is_vpn_connected then
        return _ejoysdk.is_vpn_connected()
    else
        return false
    end
end

function Sysinfo.get_boot_time()
    return _ejoysdk.sysinfo_get_boot_time()
end

function Sysinfo.is_app_install(query_scheme)
    if _ejoysdk.can_open_url then
        return _ejoysdk.can_open_url(query_scheme)
    else
        return false
    end
end

function Sysinfo.can_resolve_activity(_package_name, _package_activity_name)
    -- android api, ios do nothing
   return false
end

function Sysinfo.get_install_time()
    return _ejoysdk.sysinfo_get_install_time()
end

function Sysinfo.device_idfv()
    return _ejoysdk.sysinfo_device_idfv()
end

local ejoyExtInfoStr = nil
function Sysinfo.sysinfo_ejoy_ext_info()
    if not ejoyExtInfoStr then
        ejoyExtInfoStr = M.sync_call('sysinfo_ejoy_ext_info')
    end
    return ejoyExtInfoStr
end

local g_screen_scale_ratio = 1.0
-- 给云游戏用的，云游SDK计算出需要缩小的比例，云游插件来设置这个值到lua
function Sysinfo.update_screen_scale_ratio(ratio)
    if ratio < 1 then
        g_screen_scale_ratio = ratio
    end
end

function Sysinfo.cutout ()

    local orientation = _ejoysdk.sysinfo_statusbar_orientation()
    local screen_size = _ejoysdk.sysinfo_screen_size()
    local scale = screen_size.scale

    local safe_inset = _ejoysdk.sysinfo_safearea_inset()

    local model = _ejoysdk.sysinfo_model()
    local cutout_height = 0

    if model == 'iPhone X' or model == 'iPhone XS' or model == 'iPhone XS Max' then
        cutout_height = 30 * scale
    elseif model == 'iPhone XR' then
        cutout_height = 33 * scale
    end


    local cutout_rect = {
        x = 0,
        y = 0,
        width  = 0,
        height = 0
    }

    if orientation == 1 then
        -- portrait
        cutout_rect.width  = screen_size.width * scale
        cutout_rect.height = cutout_height
    elseif orientation == 2 then
        -- portrait upsidedown
        cutout_rect.y = screen_size.height * scale - cutout_height
        cutout_rect.width  = screen_size.width * scale
        cutout_rect.height = cutout_height

    elseif orientation == 3 then
        -- LandscapeRight
        cutout_rect.width  = cutout_height
        cutout_rect.height = screen_size.height * scale

    elseif orientation == 4 then
        -- LandscapeLeft
        cutout_rect.x = screen_size.width * scale - cutout_height
        cutout_rect.width  = cutout_height
        cutout_rect.height = screen_size.height * scale

    end


    local result = {
        cutout_rects = {
            cutout_rect
        },
        safe_inset = {
            top    = safe_inset.top * scale,
            left   = safe_inset.left * scale,
            bottom = safe_inset.bottom * scale,
            right  = safe_inset.right * scale
        }
    }


    return result
end

function Sysinfo.cutout_async(cb)
    local cutout_info = Sysinfo.cutout()
    if cutout_info.safe_inset then
        cutout_info.safe_inset.top  = math.floor(cutout_info.safe_inset.top * g_screen_scale_ratio)
        cutout_info.safe_inset.left  = math.floor(cutout_info.safe_inset.left * g_screen_scale_ratio)
        cutout_info.safe_inset.bottom  = math.floor(cutout_info.safe_inset.bottom * g_screen_scale_ratio)
        cutout_info.safe_inset.right  = math.floor(cutout_info.safe_inset.right * g_screen_scale_ratio)
    end

    if cutout_info.cutout_rects and type(cutout_info.cutout_rects) == 'table' then
        -- 这是个数组，需要遍历
        for _i, rect in pairs(cutout_info.cutout_rects) do
            rect.x  = math.floor(rect.x * g_screen_scale_ratio)
            rect.y  = math.floor(rect.y * g_screen_scale_ratio)
            rect.width  = math.floor(rect.width * g_screen_scale_ratio)
            rect.height  = math.floor(rect.height * g_screen_scale_ratio)
        end

    end


    cb(cutout_info)
end


function Sysinfo.update_cutout(_params)
   -- 空实现
end

function Sysinfo.get_disk_info_async(cb)
    if cb then
        cb(false, -1, 'only windows support')
    end
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
    iOS获取CPU耗时很快，不需要开启cpu_monitor，所以是空方法
--]]
function Sysinfo.cpu_start_monitor()

end

--[[
    iOS获取CPU耗时很快，不需要开启cpu_monitor，所以是空方法
--]]
function Sysinfo.cpu_stop_monitor()

end

--[[
    iOS获取CPU耗时很快，不需要开启cpu_monitor，所以始终返回false
--]]
function Sysinfo.cpu_monitor_enable()
    return false
end

--[[
    总内存, 返回值类型浮点，单位字节, 同步方法
    该接口memory(iOS)返回值是浮点型，为了和安卓对齐，升级memory_detail接口，推荐使用memory_detail接口
--]]
function Sysinfo.memory()
    return M.sync_call('sysinfo_total_memory')
end

function Sysinfo.memory_info()
    -- iOS待实现
    return {}
end

--[[
    types: table类型，表示调用放需要获取哪些类型的数据，table内元素类型是字符串类型，支持'cpu','memory','battery'这3个类型的字符串

    cb: function类型
    function(succ, ...)
        -- succ: 表示获取成功or失败
    end

    获取成功时:
    local result = ...
    result.cpu： table类型，eg. {'succ'=true, 'usage'=1.2}
    result.memory: table类型, eg. {'total'=1231234, 'free'=12312312, 'appPSS'=12312}
    result.battery: table类型, eg. {'level'=70, 'scale'=100, 'state'=2}

    获取失败时:
    local msg = ...
    msg: 表示错误信息
--]]
function Sysinfo.device_info(types, cb)

    local valid_type_names = {['cpu']=true,
                              ['memory']=true,
                              ['battery']=true}

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

    for k,_ in pairs(get_type_result) do
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
        elseif k == 'battery' then
            Sysinfo.battery_v2(function(ret)
                async_come_count = async_come_count + 1
                if ret then
                    get_type_result['battery'] = ret
                end
                check_end()
            end)
        end
    end
end

--[[
    异步方法
    异步获取内存信息
    cb: function(result)
        -- result.total表示总内存, 单位是字节
        -- result.free表示可用内存, 单位是字节
        -- result.appPSS表示当前进程占用的物理内存, 单位是字节
    end
--]]
function Sysinfo.memory_detail(cb)
    M.async_call('sysinfo_memory', cb)
end

function Sysinfo.get_cpu_model()
    return nil
end

function Sysinfo.get_cpu_max_freq()
    return -1
end

function Sysinfo.get_cpu_cores_count()
    return M.sync_call('sysinfo_cores_count')
end

function Sysinfo.sysinfo_ios_app_on_mac()
    return M.sync_call('sysinfo_ios_app_on_mac')
end

function Sysinfo.get_gpu_info(cb)
    cb({}) -- iOS 无法获取 gpu 信息，返回空 table
end

function Sysinfo.manifest_meta_data(type, key) -- luacheck: ignore
    return '' -- iOS 无manifest，返回空
end

function Sysinfo.is_support_hardware_info()
    if _ejoysdk['sysinfo_cores_count'] and _ejoysdk['sysinfo_total_memory'] then
        return true
    else
        return false
    end
end

function Sysinfo.get_ejoy_referer()
    return nil
end

function Sysinfo.get_hardware_info(cb)
    if not Sysinfo.is_support_hardware_info() then
        cb({})
        return
    end
    local hardware_info = {
        cpu = {
            model = nil, -- 无法获取
            core_num = Sysinfo.get_cpu_cores_count(),
            max_freq = nil -- 无法获取
        },
        gpu = {}, -- 无法获取
        memory = {
            total_size = Sysinfo.memory(),
        },
        model = Sysinfo.hw_machine(),
        brand = Sysinfo.brand()
    }
    if hardware_info.memory.total_size and hardware_info.memory.total_size > 0 then
        hardware_info.memory.total_size = hardware_info.memory.total_size / 1000000
    end
    if cb then
        cb(hardware_info)
    end
end

--[[
    获取当前禁音键的状态
    返回值，table类型，结果如下（注：ios没有ringerMode字段）
    {
       ["isMute"] = false
    }

    isMute: 是否处于静音模式下
--]]
function Sysinfo.get_audio_mute_info(cb)
    -- ios是异步的
    if cb then
        M.async_call('sysinfo_audio_mute_info', function (js_str)
            if not js_str then
                cb(true, -1, 'native error')
                return
            end

            local ret = JSON.safe_decode(js_str)
            if ret then
                cb(true, ret)
            else
                cb(false, -1, 'json decode error')
            end
        end)
    end
end

--[[
    开始监听禁音键的变化

    游戏可通过订阅 'audio_mute_change' 这个广播获取变化后的静音键信息。
    变化后的静音键信息结构如下，table类型（注：ios没有ringerMode字段）
    {
       ["type"] = "audioMuteChange"
       ["isMute"] = true
    }

    type: 广播类型
    isMute: 是否处于静音模式下
--]]
function Sysinfo.start_listen_audio_mute()
    M.sync_call('start_listen_audio_mute')
end

-- 停止监听禁音键的变化
function Sysinfo.stop_listen_audio_mute()
    M.sync_call('stop_listen_audio_mute')
end

-- 当前是否正在监听禁音键
function Sysinfo.is_audio_mute_listen_open()
    return M.sync_call('is_audio_mute_listen_open')
end


-- 获取屏幕刷新率，返回table数据结构
function Sysinfo.get_screen_refresh_rate(cb)
    M.async_call('get_screen_refresh_rate', function (temp)
        if temp then
            if not temp.device_rate_max and temp.frame_rate_max then
                temp.device_rate_max = temp.frame_rate_max -- 补上设备最大刷新率，iOS就直接取当前用户设置的屏幕刷新率
            end
        end

        if cb then
            cb(temp)
        end
    end)
end


local Timer = {}
M.Timer = Timer

function Timer.once(interval, cb)
    M.async_call('timer_once', cb, interval)
end

function M.tick(once)
    register_event()

    local tick = _ejoysdk.tick_nopcall or _ejoysdk.tick
    repeat
        local result = {tick()}
        local cb_type = result[1]
        if not cb_type then -- nil or false
            return false
        elseif type(cb_type) == 'string' then -- tick_nopcall，返回 cb_type
            local cb = _ejoysdk.get_register_cb(cb_type)

            if cb then
                table.remove(result, 1)
                cb(unpack(result))
            end
        end
    until once == true
    return true
end

local _FileBatch = {}
local _FileCompat = {}
do
    local is_support_batch = M.is_support_function(ECC.NATIVE_SUPPORT_FUNCTION_NAMES.BATCH_FILE_OPERATION)
    _ejoysdk.log("ios load with support batch:" .. tostring(is_support_batch))
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
end

local function get_doc_path()
    local paths = _ejoysdk.sysinfo_paths()
    return paths['document_path']
end

------------- 文件兼容接口，新接口见 _FileBatch begin
local cache_ext_stg_dir
function _FileCompat.get_ext_file_dir()
    if cache_ext_stg_dir and cache_ext_stg_dir ~= '' then
        return cache_ext_stg_dir
    end

    local paths = _ejoysdk.sysinfo_paths()
    cache_ext_stg_dir = paths['document_path']
    return cache_ext_stg_dir
end

function _FileCompat.writefile(filename, filedata, append,is_b64)

    local paths = _ejoysdk.sysinfo_paths()
    local file_path = paths['document_path'] .. '/' .. filename

    -- 确保目录存在
    local EU = require "ejoysdk_lua.res.ejoy_http_res_utils"
    local parent_path = EU.get_parent_folder(file_path)
    M.File.make_dirs(parent_path)

    if is_b64 == true then
        local succ, data = pcall(_ejoysdk_crypt.base64decode, filedata)
        if succ == true then
            filedata = data
        else
            filedata = nil
        end
    end

    if not filedata then
        _ejoysdk.log('writefile error!!! invalid data')
        return false
    end

    local file,error,append_value
    if append == true then
        file,error = io.open(file_path, "ab")
        append_value = 1
    else
        file,error = io.open(file_path, "wb")
        append_value = 0
    end

    if not file then
        _ejoysdk.log('writefile error!!! path = ' .. tostring(file_path))
        _ejoysdk.log('error = '..tostring(error))

        return _FileCompat.writefile_fullpath(file_path, filedata, append_value)
    end

    file:write(filedata)
    file:close()
    return true, file_path
end

-- 写文件的函数，filename是文件的绝对路径, append传0或1
function _FileCompat.writefile_fullpath(filepath, filedata, append, is_b64)
    if type(append) == "boolean" then
        if append then
            append = 1
        else
            append = 0
        end
    elseif type(append) == 'nil' then
        append = 0
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
        return false
    end

    M.sync_call("writefile", filepath, filedata, append)
    return true, filepath
end

function _FileCompat.readfile_fullpath(filename)
    if not filename then
        return nil
    end

    local ret = M.sync_call("read_file", filename)
    return ret
end


-- from_doc: 此函数优先会从bundle里读，但有场景需要优先读沙箱的
function _FileCompat.readfile(filename,from_bundle)
    local ret
    local doc_path = _FileCompat.get_ext_file_dir()
    local path = string.format("%s/%s", doc_path, filename)
    if from_bundle then
        ret = _ejoysdk.lread(filename) --or M.sync_call("read_file", path)
    else
        ret = M.sync_call("read_file", path) --or _ejoysdk.lread(filename)
    end
    return ret
end

function _FileCompat.process_exists(path)
    local exists = LUA_FILE.exists(path)
    return exists
end

function _FileCompat.process_is_directory(_file_path)
    -- not support always return false
    return false
end

-- 删除文件（夹）
function _FileCompat.process_remove(file_path)
    M.sync_call("remove_files", -1, file_path)
    local exists = _FileCompat.process_exists(file_path)
    if exists then
        return false, ECC.EJOY_LIB_ERROR.FILE_REMOVE_FILE_FAILED, "remove file fail"
    end
    return true
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

--[[
复制文件
--]]
function _FileCompat.process_copy(src_fullpath, dst_fullpath, opts)
    local succ, code, msg
    local override = true -- default override is true， 和之前行为保持一致（Android和lua。windows默认都会覆盖）
    opts = opts or {}
    if type(opts.override) == 'boolean' then
        override = opts.override
    end

    succ, code, msg = LUA_FILE.copy(src_fullpath, dst_fullpath, override)
    return succ, code, msg
end

function _FileCompat.process_batch_copy(map, cb, opts)
    LUA_FILE.batch_src_dst_operation(map, _FileCompat.process_copy, function(succ, code, msg, result_ext)
        if cb then
            cb(succ, code, msg, result_ext)
        end
    end, opts)
end

_FileCompat.sep = '/'

function _FileCompat.join(path)
    -- 有空写下去除中间 斜杠sep 的处理，防止出现{'a\', b} = a\\b 这样的事情
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
    return LUA_FILE.rename(src_fullpath, dst_fullpath)
end

function _FileCompat.process_batch_rename(map, cb)
    LUA_FILE.batch_rename(map, cb)
end

-- 释放内置资源
function _FileCompat.release_bundle_res(src_path,dst_path,cb)
    if(src_path and dst_path and ''~=src_path and ''~=dst_path)then
        --local src_full_path= string.format("%s/%s", get_bundle_path(), dst_path)
        local target_path = string.format("%s/%s", get_doc_path(), dst_path)
        M.async_call("release_bundle_res",function(ret)
            if cb then
                cb(JSON.decode(ret))
            end
        end ,src_path,target_path)
    else
        if(cb)then
            cb({succ=false,msg="参数错误"})
        end
    end
end

--解压资源
function _FileCompat.unzip(src_path,dst_path,cb)
    if(src_path and dst_path and ''~=src_path and ''~=dst_path)then
        local src_full_path = string.format("%s/%s", get_doc_path(), src_path)
        local target_path = string.format("%s/%s", get_doc_path(), dst_path)
        M.async_call("unzip",function(ret)
            if cb then
                cb(JSON.decode(ret))
            end
        end ,src_full_path,target_path)
    else
        if(cb)then
            cb({succ=false,msg="参数错误"})
        end
    end
end

function _FileCompat.unzip_full_path(src_full_path, dst_full_path, cb)
    if(src_full_path and dst_full_path and ''~=src_full_path and ''~=dst_full_path)then
        M.async_call("unzip",function(ret)
            if cb then
                cb(JSON.decode(ret))
            end
        end ,src_full_path,dst_full_path)
    else
        if(cb)then
            cb({succ=false,msg="参数错误"})
        end
    end
end

function _FileCompat.zip(src_file_path, file_name, dst_path, cb)
    if(src_file_path and dst_path and ''~=src_file_path and ''~=dst_path)then
        local src_full_path = src_file_path
        local src_file_name = file_name or tostring(os.time())
        local target_path = dst_path
        
        M.async_call("zip_file",function(ret_str)
            if cb then
                local ret = JSON.safe_decode(ret_str)
                if ret and ret.succ then  
                    cb(true, ret.data or '')
                else 
                    cb(false, -1, ret.data or '')
                end
            end
        end ,src_full_path, src_file_name, target_path)
    else
        if(cb)then
            cb({succ=false,msg="参数错误"})
        end
    end
end

-- function _FileCompat.list(src_path, cb)
--     if(src_path and ''~=src_path) then
--         local src_full_path = string.format("%s/%s", get_doc_path(), src_path)
--         M.async_call("get_files_in_dir",function(ret)
--             if cb then
--                 cb(ret)
--             end
--         end ,src_full_path)
--     else
--         if(cb)then
--             cb({succ=false,msg="参数错误"})
--         end
--     end
-- end

function _FileCompat.size(src_path, cb)
    if(src_path and ''~=src_path) then
        local src_full_path = string.format("%s/%s", get_doc_path(), src_path)
        M.async_call("get_file_size",function(ret)
            if cb then
                cb(JSON.decode(ret))
            end
        end ,src_full_path)
    else
        if(cb)then
            cb({succ=false,msg="参数错误"})
        end
    end
end

function _FileCompat.is_support_handling_file_cache()
    if _ejoysdk['unzip'] and _ejoysdk['release_bundle_res'] and _ejoysdk['remove_files'] then
        return true
    else
        return false
    end
end


function _FileCompat.process_make_dirs(dir)
    local ret = M.sync_call('make_dirs', dir)
    ret = ret or {}
    return ret.succ or false
end

function _FileCompat.file_md5(_path)
    local result = M.sync_call('file_md5', _path)
    local code, msg
    if not result then
        code = ECC.EJOY_LIB_ERROR.FILE_MD5_FINISH_FAILED
        msg = 'md5 failed'
    end
    return result, code, msg
end

function _FileCompat.process_md5(file_path)
    return _FileCompat.file_md5(file_path)
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

function _FileCompat.process_batch_info(file_list, cb, _opts)
    LUA_FILE.batch_info(file_list, cb, _opts)
end

function _FileCompat.process_list_directory(_dir_path, _recursive, _cb)
    -- not support always return nil
    if _cb then
        _cb(nil)
    end
end

function _FileCompat.process_list_bundle(_dir_path, _recursive, _cb)
    -- not support always return nil
    if _cb then
        _cb(nil)
    end
end

------------- 文件兼容接口，新接口见 _FileBatch end

------------- 批量文件接口 _FileBatch begin
function _FileBatch.process_exists(path)
    local exists = M.sync_call("file_exists", path)
    return exists
end

function _FileBatch.process_is_directory(file_path)
    local is_dir = M.sync_call("is_directory",  file_path)
    return is_dir
end

function _FileBatch.process_batch_remove(list, cb)
    list = list or {}
    local list_size = #list
    if list_size == 0 then
        if cb then
            cb(true)
        end
    end

    local params = JSON.encode({ files = list })
    M.async_call("batch_remove", function(ret)
        local ret_obj = JSON.safe_decode(ret);
        ret_obj = ret_obj or {}
        if cb then
            cb(ret_obj.succ or false, ret_obj.code, ret_obj.msg, ret_obj.result_ext)
        end
    end, params)
end

--[[
复制文件
--]]
function _FileBatch.process_copy(src_fullpath, dst_fullpath, opts)
    local succ, code, msg
    local override = true -- default override is true， 和之前行为保持一致（Android和lua。windows默认都会覆盖）
    opts = opts or {}
    if type(opts.override) == 'boolean' then
        override = opts.override
    end

    succ, code, msg = M.sync_call("copy_file", src_fullpath, dst_fullpath, override)
    --M.log("process_copy succ:" .. tostring(succ) .. ", " .. tostring(code) .. ", " .. tostring(msg))
    return succ, code, msg
end

function _FileBatch.process_batch_copy(map, cb, opts)
    local override = true -- default override is true， 和之前行为保持一致（Android和lua。windows默认都会覆盖）
    opts = opts or {}
    if type(opts.override) == 'boolean' then
        override = opts.override
    end

    local CJSON = require "ejoysdk_lua.ejoysdk_cjson"
    local params = CJSON.encode({ files = map, need_override = override })
    M.async_call("batch_copy", function(ret)
        local ret_obj = CJSON.safe_decode(ret);
        ret_obj = ret_obj or {}
        --M.log("process_batch_copy resp>>>>>>>")
        --M.log(ret_obj)
        if cb then
            cb(ret_obj.succ, ret_obj.code, ret_obj.msg, ret_obj.result_ext)
        end
    end, params)
end

function _FileBatch.process_batch_rename(map, cb)
    local CJSON = require "ejoysdk_lua.ejoysdk_cjson"
    local params = CJSON.encode({ files = map })
    M.async_call("batch_rename", function(ret)
        local ret_obj = CJSON.safe_decode(ret);
        ret_obj = ret_obj or {}
        if cb then
            cb(ret_obj.succ, ret_obj.code, ret_obj.msg, ret_obj.result_ext)
        end
    end, params)
end

function _FileBatch.process_batch_md5(file_list, cb)
    local CJSON = require "ejoysdk_lua.ejoysdk_cjson"
    local params = CJSON.encode({ files = file_list })
    M.async_call('batch_md5', function(ret)
        local ret_obj = CJSON.decode(ret);
        ret_obj = ret_obj or {}
        local result_ext = ret_obj.result_ext or {}
        if cb then
            if ret_obj.succ then
                cb(true, result_ext.succ_data or {})
            else
                cb(false, ret_obj.code, ret_obj.msg, result_ext.succ_data or {}, result_ext.fail_data)
            end
        end
    end, params)
end

function _FileBatch.process_batch_info(file_list, cb, _opts)
    local CJSON = require "ejoysdk_lua.ejoysdk_cjson"
    local params_str = CJSON.encode({ files = file_list, opts = _opts })
    M.async_call("batch_file_info", function(ret)
        local ret_obj = CJSON.decode(ret) or {}
        local result_ext = ret_obj.result_ext or {}
        if cb then
            local succ_data = result_ext.succ_data or {}
            cb(succ_data)
        end
    end, params_str)
end

function _FileBatch.process_list_directory(dir_path, recursive, cb)
    M.async_call("list_directory", function(ret)
        local CJSON = require "ejoysdk_lua.ejoysdk_cjson"
        local ret_obj = CJSON.safe_decode(ret) or {}
        if cb then
            cb(ret_obj)
        end
    end , dir_path, recursive)
end

function _FileBatch.process_list_bundle(dir_path, recursive, cb)
    M.async_call("list_bundle", function(ret)
        local CJSON = require "ejoysdk_lua.ejoysdk_cjson"
        local ret_obj = CJSON.safe_decode(ret) or {}
        if cb then
            cb(ret_obj)
        end
    end, dir_path, recursive)
end

------------- 批量文件接口 _FileBatch end

local Media = {
    DEFAULT_MAX_FILESIZE = 1024 * 1024 * 5,
    DEFAULT_MAX_DURATION = 60 * 1000 * 3,
    DEFAULT_SAMPLING_RATE = 16000,
    DEFAULT_ENCODING_BIT_RATE = 16000,
    DEFAULT_BIT_DEPTH_RATE = 16,
    DEFAULT_CHANNEL = 1,
    DEFAULT_AMR_NB_ENCODING_BIT_RATE = 12200,
    DEFAULT_AMR_WB_ENCODING_BIT_RATE = 18250
}
M.Media = Media

function Media.start_record(opt, cb)
    opt = opt or {}

    local max_filesize = Media.DEFAULT_MAX_FILESIZE
    if opt.max_filesize and opt.max_filesize <= max_filesize then
        max_filesize = opt.max_filesize
    end
    local max_duration = Media.DEFAULT_MAX_DURATION
    if opt.max_duration and opt.max_duration <= max_duration then
        max_duration = opt.max_duration
    end

    local trace_volume = opt.volume_cb and true or false

    local params = {
        filename = opt.filename or 'noname',
        format = opt.format or 'amr',
        max_filesize = max_filesize,
        max_duration = max_duration,
        sampling_rate = opt.sampling_rate or Media.DEFAULT_SAMPLING_RATE,
        encoding_bit_rate = opt.encoding_bit_rate or Media.DEFAULT_ENCODING_BIT_RATE,
        bit_depth_rate = opt.bit_depth_rate or Media.DEFAULT_BIT_DEPTH_RATE,
        channel = opt.channel or Media.DEFAULT_CHANNEL,
        volume_trace_period = opt.volume_trace_period or 200,
        trace_volume = trace_volume
    }

    if params.format == 'amr' then
        _ejoysdk.log('params.format sampling_rate: ' .. tostring(params.sampling_rate))
        if params.sampling_rate ~= 8000 and params.sampling_rate ~= 16000 then
            error('when format is amr, sampling_rate should be 8000 or 16000');
            return
        end
        if params.bit_depth_rate ~= 16 then
            error('when format is amr, bit_depth_rate should be 16');
            return
        end
        if params.channel ~= 1 then
            error('when format is amr, channel should be 1');
            return
        end
        local constants = require 'ejoysdk_lua.ejoysdk_constants'
        if params.sampling_rate == 8000 then
            if not constants.AMR_NB_BIT_RATE[params.encoding_bit_rate] then
                params.encoding_bit_rate = Media.DEFAULT_AMR_NB_ENCODING_BIT_RATE
            end
        end
        if params.sampling_rate == 16000 then
            if not constants.AMR_WR_BIT_RATE[params.encoding_bit_rate] then
                params.encoding_bit_rate = Media.DEFAULT_AMR_WB_ENCODING_BIT_RATE
            end
        end
    end

    local cb_wrap = function(info, body)
        info = JSON.decode(info)
        cb(info, body);
    end

    local optStr = (opt and JSON.encode(params))
    M.async_call('media_start_record', cb_wrap, optStr)
end

function Media.stop_record(opt, cb)
    local optStr = (opt and JSON.encode(opt)) or '{}'
    local cb_wrap = function(info, body)
        info = JSON.decode(info)
        info.bytes = body
        cb(info);
    end
    M.async_call('media_stop_record', cb_wrap, optStr)
end

local MEDIA_PLAY = 'MEDIA_PLAY'
local media_play_cbs = {}

_ejoysdk.register_cb(MEDIA_PLAY, function(cbid, _js_str, _chunk)
    local params  = media_play_cbs[cbid]
    if params and params.finish_cb then
        params.finish_cb()
        media_play_cbs[cbid] = nil
    end
end)

function Media.start_play(opt, cb)
    opt = opt or {}

    local format = 'amr'
    if opt.format ~= 'auto' then
        format = opt.format
    end

    local params = {
        filename = opt.filename or 'noname',
        format = format,
        audio_category = opt.audio_category,
        volume = opt.volume or 1.0,
        volume_multiplier = opt.volume_multiplier or 1
    }

    local cb_wrap = function(info, body)
        if cb then
            info = JSON.decode(info)
            cb(info, body)
        end
    end

    local optStr = (opt and JSON.encode(params))
    local cbid = M.async_call('media_start_play', cb_wrap, optStr);
    media_play_cbs[cbid] = {finish_cb = opt.finish_cb}
end

function Media.stop_play(opt, cb)
    local optStr = (opt and JSON.encode(opt)) or '{}'
    local cb_wrap = function(info, body)
        info = JSON.decode(info)
        cb(info, body);
    end
    M.async_call('media_stop_play', cb_wrap, optStr);
end

function Media.delete(opt, cb)
    local optStr = (opt and JSON.encode(opt)) or '{}'
    local cb_wrap = function(info, body)
        info = JSON.decode(info)
        cb(info, body);
    end
    M.async_call('media_delete', cb_wrap, optStr);
end

function Media.get_record_dir()
    return _ejoysdk.media_record_dir()
end

local Permission = {}
M.Permission = Permission

-- 判断是否支持合规检查
function Permission.support_compliance_check()
    if M.sync_call('support_compliance_check') then
        return true
    end
    return false
end

-- 判断是否支持合规检查(异步)
function Permission.async_support_compliance_check(cb)
    if cb then
        cb(M.Permission.support_compliance_check())
    end
end

function Permission.checkPermission(_permission_detail, _cb)
    -- ios留空
end

function Permission.check_permission_v2(permission, cb)
    local originPermissionName = permission
    if permission == "NSCameraUsageDescription" then
        originPermissionName = "camera"
    elseif permission == "NSPhotoLibraryUsageDescription" or permission == "NSPhotoLibraryAddUsageDescription" then
        originPermissionName = "photo"
    elseif permission == "NSMicrophoneUsageDescription" then
        originPermissionName = "microphone"
    end

    local optStr = JSON.encode({permission=originPermissionName})
    local function wrap(info)
        _ejoysdk.log('iOS get permission')
        info = JSON.decode(info)
        M.log(info)
        cb(info.succ);
    end
    M.async_call('check_permission_v2', wrap, optStr)
end

-- 带提示的及引导的权限申请
local handle_on_check_permission_v3 = {}  -- 正在执行的check_permission_v3的操作，会记录在handle_on_check_permission_v3里，防止玩家连续点击
function Permission.check_permission_v3(options, cb)
    M.log(options)
    if not options or not options.permissions or not next(options.permissions) then
        cb(true)
        return
    end

    local permission_names = {}
    for permission_name, _ in pairs(options.permissions) do
        table.insert(permission_names, permission_name:lower())
    end
    table.sort(permission_names)
    local total_permission_names = table.concat(permission_names, '-')
    if total_permission_names and #total_permission_names > 0 and handle_on_check_permission_v3[tostring(total_permission_names)] then
        -- 正在处理中，相同的权限申请，这种情况一般是 游戏逻辑错误 或者 游戏连续UI点击 导致的。
        table.insert(handle_on_check_permission_v3[tostring(total_permission_names)], cb)
        return
    end

    handle_on_check_permission_v3[tostring(total_permission_names)] = {}

    local util = require 'ejoysdk_lua.ejoysdk_utils'
    local index = util.tablelength(options.permissions)

    local grant_ret = true

    local limit_permissions = {}
    for permission,description in pairs(options.permissions) do
        Permission.check_permission_v2(permission, function(succ)

            grant_ret = grant_ret and succ
            if not succ then
                limit_permissions[permission] = description
            end

            index = index - 1
            if index <= 0 then

                if not grant_ret then
                    local title,desc = M.Permission.permission_default_description(limit_permissions)

                    local tempOptions = {
                        title = title or '',
                        message = desc or '',
                        buttons = {LANG.getString('cancel',"取消"), LANG.getString('setting',"设置")},
                        permissions = {
                            limit_permissions
                        }
                    }

                    -- 延迟一下，再弹这个弹框。bug-fix:https://aone.alibaba-inc.com/v2/project/770618/task/47567694
                    M.Timer.once(0.75, function()
                        Permission.show_usage_dialog(tempOptions, function(tempIndex)
                            if tempIndex == 1 then
                                M.Permission.openSetting()
                            end
                        end)

                        util.safe_call_cb(cb, grant_ret)

                        for _, cached_cb in ipairs(handle_on_check_permission_v3[tostring(total_permission_names)]) do
                            util.safe_call_cb(cached_cb, grant_ret)
                        end

                        handle_on_check_permission_v3[tostring(total_permission_names)] = nil
                    end)
                else
                    util.safe_call_cb(cb, grant_ret)

                    for _, cached_cb in ipairs(handle_on_check_permission_v3[tostring(total_permission_names)]) do
                        util.safe_call_cb(cached_cb, grant_ret)
                    end

                    handle_on_check_permission_v3[tostring(total_permission_names)] = nil
                end
            end
        end)
    end
end


function Permission.detect_permission(permission,cb)
    if permission == 'notification' then
        -- detect_permission对'notification'是错的，所以要转到check_permission_v2去判断权限
        M.Permission.check_permission_v2('notification', function (succ)
            local resp = {}
            if succ then
                resp.status = 1
            else
                resp.status = 0
            end
            cb(succ, resp)
        end)
    else
        M.async_call(
                'detect_permission',
                function(resp, _chunk)
                    if cb and resp then
                        cb(resp.status == 1,resp)
                    end
                end, permission)
    end
end

function Permission.get_requested_permissions()
    -- TODO 获取包体列表
    return {}
end

function Permission.async_get_requested_permissions(cb)
    if cb then
        cb(M.Permission.get_requested_permissions())
    end
end

-- 跳转到手机设置里当前APP的设置页面
function Permission.openSetting(_ext_param)
    local setting_url = 'app-settings:'
    if M.Sysinfo.can_open_url(setting_url) then
        M.Sysinfo.open_url(setting_url)
    end
end

function Permission.openApplicationSetting()
    Permission.openSetting()
end

-- 显示权限用途说明弹窗
function Permission.show_usage_dialog(options,cb)
    -- ios 直接返回就可以了
    options = options or {}
    if not options.permissions then
        if cb then
            cb(-1)
        end
        return
    end

    options['style']='lingxi'
    if not options.title or not options.message then
        local title,desc = M.Permission.permission_default_description(options.permissions)
        options.title = options.title or title
        options.message = options.message or desc
    end

    options.buttons = options.buttons or {LANG.getString('cancel',"取消"), LANG.getString('setting',"设置")}


    local cb_wrap = function(index)
        if cb then
            cb(index)
        end
    end

    M.Modal.open(options.title,options,cb_wrap)

end

local Sdkinfo = {}
M.Sdkinfo = Sdkinfo

-- 获取sdk的版本号
function Sdkinfo.getSDKVersionName(sdkName)
    return M.sync_call('sdkinfo_get_version_name', sdkName)
end

function M.qrcode_scan(cb)

    local app_on_mac = M.Sysinfo.sysinfo_ios_app_on_mac()
    if app_on_mac then
        local opt = {buttons =  {'好'}}
        M.Modal.open('扫码登陆功能仅用于手机端~', opt)
        return
    end

    local scan_result_handler = function(result)
        _ejoysdk.log("ios qrcode_scan result: ")
        M.log(result)
        cb(true, result)
    end
    M.async_call('qrcode_scan', scan_result_handler)
end


function M.get_cba_tweleve_info()
    local info = M.sync_call('get_cba_tweleve_info') or '{}'
    local infoTable = JSON.safe_decode(info)
    return infoTable
end

function M.support_save_to_album()
    local ret=M.sync_call('support_save_to_album')
    return ret and ret == true
end

function M.save_to_album(path, need_delete, cb)
    if M.support_save_to_album() then
        M.async_call('save_to_album', function(resp)
            local body=JSON.decode(resp)
            cb(body)
        end, path, tostring(need_delete))
    else
        cb({code=-99,msg='保存失败，暂不支持该功能'})
    end
end

function M.copy_clipboard(params)
    local ret = M.sync_call('copy_clipboard',JSON.encode(params))
    return {succ=ret} --与android一致
end

function M.kill_app()
    _ejoysdk.log("kill_app begin")
    _ejoysdk.kill_app()
end

--function M.is_class_exsit(class_name)
--    return  M.sync_call('is_class_exsit', class_name)
--end

function M.support_app_reviews()
    return true
end

function M.async_support_app_reviews(cb)
    if cb then
        cb(M.support_app_reviews())
    end
end

function M.app_reviews()
    UTILS.appstore_score()
end

function M.comment_app(appId)
    UTILS.appstore_write_comment(appId)
end


local QRCode = {}
M.QRCode = QRCode

function QRCode.gen_bmp(text)
    if _ejoysdk.qrcode_gen_bmp then
        local succ, data = _ejoysdk.qrcode_gen_bmp(text)
        return succ, data
    else
        return false
    end
end

local Calendar = {}
M.Calendar = Calendar

-- 添加日历事件提醒
function Calendar.add_event(_params, _cb)
    _ejoysdk.log("todo add_event")
    --M.async_call(ACT_CALENDAR_ADD_EVENT, params, '', function(ret)
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
    --end)
end

function Calendar.delete_event(_params, _cb)
    _ejoysdk.log("todo delete_event")
    --M.async_call(ACT_CALENDAR_DEL_EVENT, params, '', function(ret)
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
    --end)
end

function Calendar.update_event(_params, _cb)
    _ejoysdk.log("todo delete_event")
    --M.async_call(ACT_CALENDAR_UPDATE_EVENT, params, '', function(ret)
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
    --end)
end

function Calendar.query_event(_params, _cb)
    _ejoysdk.log("todo query_event")
    --M.async_call(ACT_CALENDAR_QUERY_EVENT, params, '', function(ret)
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
    --end)
end

function Calendar.query_event_id(_params, _cb)
    _ejoysdk.log("todo query_event_id")
    --M.async_call(ACT_CALENDAR_QUERY_EVENT_ID, params, '', function(ret)
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
    --end)
end


-- 同步到三端
local Sensor = {}
M.Sensor = Sensor
-- 这个参数是指在摇一摇过程中，停止摇晃多长时间后触发SHAKE_END通知，单位：毫秒
M.Sensor.TimeThreshold = 300

M.Sensor.SHAKE_EVENT = {
    BEGIN = "SHAKE_BEGIN",
    END = "SHAKE_END",
    CANCEL = "SHAKE_CANCEL"
}

local SHAKE_EVENT = 'SHAKE_EVENT'

local shake_cb

_ejoysdk.register_cb(SHAKE_EVENT, function(_cbid, value)
    local result = JSON.decode(value) or {}
    if result and result.event then
        local event = result.event
        _ejoysdk.log('receive shake cb event >> ' .. tostring(event))
        if shake_cb then
            shake_cb(event)
        end
    end
end)

function Sensor.set_threshold(threshold)
    if threshold and threshold > 0 then
        M.Sensor.TimeThreshold = threshold
        M.sync_call('set_threshold', M.Sensor.TimeThreshold)
    end
end

function Sensor.is_shake_support()
    local support = M.sync_call("is_shake_support")
    _ejoysdk.log('ret support >> ' .. tostring(support))
    return support or false
end


function Sensor.register_shake(cb)
    shake_cb = cb
    M.sync_call('register_shake', M.Sensor.TimeThreshold)
end

function Sensor.unregister_shake()
    shake_cb = nil
    M.sync_call('unregister_shake')
end

function M.get_brightness()
    return M.sync_call('get_brightness') or -1
end

function M.set_brightness(brightness)
    M.sync_call('set_brightness', brightness)
end

function M.reset_brightness()
    M.sync_call('reset_brightness')
end

function M.vibrate(milliseconds)
    M.sync_call('vibrate', milliseconds)
end

function M.is_vibrate_support()
    return M.sync_call('is_vibrate_support') or false
end

function M.set_app_orientation(orientation)
    --local aligames = require 'ejoysdk_lua.vendors.aligames'
    --aligames.set_app_orientation(orientation)
    return M.sync_call('set_app_orientation', orientation)
end

function M.support_webview()
    return true
end

function M.disable_embed_webview()
    -- pc api, ios do nothing
    return false
end

function M.scroll_log_file(file_name)
    return M.sync_call('scroll_log_file', file_name or "")
end

function M.flush_log()
    return M.sync_call('flush_log')
end

function M.get_log_file_infos(_params, cb)
    local paramsStr = (_params and JSON.encode(_params)) or '{}'
    M.async_call('get_log_file_infos', function(ret)
        if cb then
            cb(JSON.decode(ret))
        end
    end, paramsStr)
end

function M.get_current_log_file(_params, cb)
    local paramsStr = (_params and JSON.encode(_params)) or '{}'
    M.async_call('get_current_log_file', function(ret)
        if cb then
            cb(JSON.decode(ret))
        end
    end, paramsStr)
end

function M.get_ej_debugable()
    local is = M.File.exists('ejoysdk.debug')
    return is
end

function M.switch_to_game()
    -- DOTHING
    return false
end

function M.set_pc_ad_token(_pc_ad_token)
    -- pc api, ios do nothing
end

function M.get_pc_ad_token()
    -- pc api, ios do nothing
end

function M.get_pre_order_items(cb)
    cb = cb or function()  end
    local platform = 'ios'
    if M.is_support_function("get_purchase_items") then
        M.async_call("get_purchase_items",function(result)
            local ret = result and JSON.decode(result) or {}
            local succ = ret.succ
            if succ then
                cb(true,platform, ret.data or {})
            else
                cb(false, platform, ret.code or -2, ret.msg or 'unknown')
            end
        end)
    else
        cb(false, platform, -1, 'not support')
    end
end

function M.get_system_properties(_key, _default_value)
    -- android api, ios do nothing
end
return M
