--
-- Created by IntelliJ IDEA.
-- User: sean
-- Date: 15-11-27
-- Time: 下午3:06
-- To change this template use File | Settings | File Templates.
--

local JSON = require "ejoysdk_lua.ejoysdk_json"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local LANG = require "ejoysdk_lua.lang.util"
local EM = require "ejoysdk_lua.ejoysdk_module"
local LUA_FILE = require "ejoysdk_lua.libs.luafile"
local ECC = require "ejoysdk_lua.ejoysdk_constants"

-- async call type
local ACT_HTTP_GET = 'HTTP_GET'
local ACT_HTTP_STOP = 'HTTP_STOP'
local ACT_HTTP_POST = 'HTTP_POST'
local ACT_HTTP_HEADERS= 'HTTP_HEADERS'
local ACT_HTTP_UPDATE_CONFIG = "HTTP_UPDATE_CONFIG"
local ACT_MODAL_OPEN = 'MODAL_OPEN'
local ACT_TIMER_ONCE = 'TIMER_ONCE'
local ACT_MEDIA_START_RECORD = 'MEDIA_START_RECORD'
local ACT_MEDIA_STOP_RECORD = 'MEDIA_STOP_RECORD'
local ACT_MEDIA_START_PLAY = 'MEDIA_START_PLAY'
local ACT_MEDIA_STOP_PLAY = 'MEDIA_STOP_PLAY'
local ACT_MEDIA_DELETE = 'MEDIA_DELETE'
local ACT_DETECT_PERMISSION = 'DETECT_PERMISSION'
local ACT_CHECK_PERMISSION = 'CHECK_PERMISSION'
local ACT_CHECK_PERMISSION_V2 = 'CHECK_PERMISSION_V2' -- 这两接口都会顺带就去请求权限
local ACT_HTTP_ADD_CERT = 'HTTP_ADD_CERT'
local ACT_QRCODE_SCAN = 'QRCODE_SCAN'
local ACT_WEBVIEW_CAPTURE= 'WEBVIEW_CAPTURE'
local ACT_SAVE_TO_ALBUM = 'SAVE_TO_ALBUM'
local ACT_RELEASE_BUILTIN_RES = "RELASE_BUILTIN_RES"
local ACT_UNZIP= "UNZIP"
local ACT_ZIP_FILE= "ZIP_FILE"
local ACT_FILE_DELETE="FILE_DELETE"
local ACT_GET_SYS_PATHS="GET_SYS_PATHS"
local ACT_GET_FILE_MD5 = "GET_FILE_MD5"
local ACT_APP_REVIEWS= 'APP_REVIEWS'
local ACT_GET_GPU_INFO = 'GET_GPU_INFO'

-- 日历相关操作
local ACT_CALENDAR_ADD_EVENT = "CALENDAR_ADD_EVENT"
local ACT_CALENDAR_DEL_EVENT = "CALENDAR_DEL_EVENT"
local ACT_CALENDAR_UPDATE_EVENT = "CALENDAR_UPDATE_EVENT"
local ACT_CALENDAR_QUERY_EVENT = "CALENDAR_QUERY_EVENT"
local ACT_CALENDAR_QUERY_EVENT_ID = "CALENDAR_QUERY_EVENT_ID"

-- 摇一摇
local ACT_SENSOR_SHAKE_REGISTER = "ACT_SENSOR_SHAKE_REGISTER"
local ACT_SENSOR_SHAKE_UNREGISTER = "ACT_SENSOR_SHAKE_UNREGISTER"
local ACT_SENSOR_SET_THRESHOLD = "ACT_SENSOR_SET_THRESHOLD"
local IS_SENSOR_SHAKE_SUPPORT = "IS_SENSOR_SHAKE_SUPPORT"

--震动
local ACT_SUPPORT_VIBRATE = 'SUPPORT_VIBRATE'
local ACT_VIBRATE = 'VIBRATE'

--亮度
local ACT_GET_BRIGHTNESS = 'GET_BRIGHTNESS'
local ACT_SET_BRIGHTNESS = 'SET_BRIGHTNESS'
local ACT_RESET_BRIGHTNESS = 'RESET_BRIGHTNESS'

--获取系统属性
local ACT_GET_SYSTEM_PROPERTIES = 'GET_SYSTEM_PROPERTIES'

-- 批量文件操作
local ACT_FILE_BATCH_RENAME = "FILE_BATCH_RENAME"
local ACT_FILE_BATCH_COPY = "FILE_BATCH_COPY"
local ACT_FILE_COPY = "FILE_COPY"
local ACT_FILE_BATCH_REMOVE = "FILE_BATCH_REMOVE"
local ACT_FILE_BATCH_MD5 = "FILE_BATCH_MD5"
local ACT_FILE_BATCH_INFO = "FILE_BATCH_INFO"

-- local ACT_GOOGLE_PLAY_PURCHASE = 'GOOGLE_PLAY_PURCHASE'
-- sync call type
local CT_KEYSTORE_GET = 'KEYSTORE_GET'
local CT_MEDIA_RECORD_DIR = 'MEDIA_RECORD_DIR'
local CT_GET_EXT_STG_DIR = 'GET_EXT_STG_DIR'
local CT_GET_SUPPORT_FUNCTIONS = 'GET_SUPPORT_FUNCTIONS'
local CT_MAKE_DIRS = 'MAKE_DIRS'
--local CT_GET_DATA_DIR = 'GET_DATA_DIR'
local CT_SUPPORT_SAVE_TO_ALBUM='SUPPORT_SAVE_TO_ALBUM'
local CT_SUPPORT_APP_REVIEWS='SUPPORT_APP_REVIEWS'
local CT_SUPPORT_COMPLIANCE_CHECK="SUPPORT_COMPLIANCE_CHECK"
local CT_COPY_CLIPBOARD = 'COPY_CLIPBOARD'
local CT_FILE_IS_DIRECTORY = "FILE_IS_DIRECTORY"
local CT_FILE_LIST_DIRECTORY = "FILE_LIST_DIRECTORY"
local CT_FILE_LIST_BUNDLE = "FILE_LIST_BUNDLE"

-- invoke
--local IVK_LOG_PARAMS = 'LOG_PARAMS'
local IVK_KEYSTORE_SET = 'KEYSTORE_SET'
local IVK_KEYSTORE_DELETE = 'KEYSTORE_DELETE'
local IVK_KEYSTORE_CLEAR = 'KEYSTORE_CLEAR'
--local IVK_WEBVIEW_OPEN = 'WEBVIEW_OPEN'
local IVK_WEBVIEW_CLOSE = 'WEBVIEW_CLOSE'
local IVK_WEBVIEW_IS_OPENED = 'WEBVIEW_IS_OPENED'
local IVK_WEBVIEW_CALLBACK_JS = "WEBVIEW_CALLBACK_JS"
local IVK_WEBVIEW_CALL_JS = "WEBVIEW_CALL_JS"
local ACT_WEBVIEW_SHOW = 'show'
local ACT_WEBVIEW_HIDE = 'hide'
local ACT_WEBVIEW_REMOVE_HIDE_CACHE = 'remove_hide_cache'
local SYNC_WEBVIEW_OPERATOR = 'WEBVIEW_OPERATOR'
local IVK_WEBVIEW_OPERATOR = 'WEBVIEW_OPERATOR'
local ACT_WEBVIEW_GO_BACK = 'go_back'
local ACT_WEBVIEW_GO_FORWARD = 'go_forward'
local ACT_WEBVIEW_RELOAD = 'reload'
local ACT_WEBVIEW_PREPARE = 'prepare'

local IVK_TOAST_OPEN = 'TOAST_OPEN'
local IVK_LOADING_SHOW = 'LOADING_SHOW'
local IVK_LOADING_DISMISS = 'LOADING_DISMISS'
local IVK_SYSINFO_DEVICE_WITH_ANDROID = 'SYSINFO_DEVICE_ANDROID_ID'
local IVK_SYSINFO_OPENGL = 'SYSINFO_OPENGL'
local IVK_SYSINFO_CPU_USAGE = 'SYSINFO_CPU_USAGE'
local IVK_SYSINFO_CPU_START_MONITOR = 'SYSINFO_CPU_START_MONITOR'
local IVK_SYSINFO_CPU_STOP_MONITOR = 'SYSINFO_CPU_STOP_MONITOR'
local IVK_SYSINFO_CPU_MONITOR_ENABLE = 'SYSINFO_CPU_MONITOR_ENABLE'
local IVK_SYSINFO_MEMORY = 'SYSINFO_MEMORY'
local IVK_SYSINFO_MEMORY_V2 = 'SYSINFO_MEMORY_V2'
local IVK_SYSINFO_STORAGE = 'SYSINFO_STORAGE'
local IVK_GET_STORAGE_INFO = 'GET_STORAGE_INFO'
local IVK_KILL_APP = 'KILL_APP'
local IVK_SYSINFO_SCREEN = 'SYSINFO_SCREEN'
local IVK_SYSINFO_SCREEN_CONTENT_SIZE = 'SYSINFO_SCREEN_CONTENT_SIZE'
local IVK_SYSINFO_OPEN_URL = 'SYSINFO_OPEN_URL'
local IVK_SYSINFO_CAN_OPEN_URL = 'SYSINFO_CAN_OPEN_URL'
local IVK_GOTO_APPLICATION_SETTINGS = 'GOTO_APPLICATION_SETTINGS'
local IVK_SYSINFO_BATTERY = 'SYSINFO_BATTERY'
local IVK_SYSINFO_BATTERY_V2 = 'SYSINFO_BATTERY_V2'
local IVK_SYSINFO_BATTERY_EXT = 'SYSINFO_BATTERY_EXT'
local IVK_SYSINFO_LAUNCH_BATTERY = 'SYSINFO_LAUNCH_BATTERY'
local IVK_SYSINFO_NETWORK_TYPE = 'SYSINFO_NETWORK_TYPE'
local IVK_SYSINFO_NETWORK_TYPE_NAME = 'SYSINFO_NETWORK_TYPE_NAME'
--local IVK_SYSINFO_PHONE_SIGNAL = 'SYSINFO_PHONE_SIGNAL'
--local IVK_SYSINFO_APP_NAME = 'SYSINFO_APP_NAME'
--local IVK_SYSINFO_APP_VERSION_CODE = 'SYSINFO_APP_VERSION_CODE'
--local IVK_SYSINFO_APP_VERSION_NAME = 'SYSINFO_APP_VERSION_NAME'
--local IVK_SYSINFO_OS_VERSION = 'SYSINFO_OS_VERSION'
--local IVK_SYSINFO_MODEL = 'SYSINFO_MODEL'
--local IVK_SYSINFO_PACKAGE_NAME = 'SYSINFO_PACKAGE_NAME'
--local IVK_SYSINFO_BRAND = 'SYSINFO_BRAND'
local IVK_SYSINFO_DEVICE_ID = 'SYSINFO_DEVICE_ID'
local IVK_SYSINFO_WIFI_INFO = 'SYSINFO_WIFI_INFO'
local IVK_SYSINFO_MOBILE_INFO = 'SYSINFO_MOBILE_INFO'
local IVK_SYSINFO_VPN_CONNECTED = 'SYSINFO_VPN_CONNECTED'
local IVK_SYSINFO_STATIC_LIST = 'SYSINFO_STATIC_LIST'
local IVK_SYSINFO_IS_APP_INSTALLED = 'HAS_PKG_INSTALLED'
local IVK_SET_SIMULATOR_FLAG = 'SET_SIMULATOR_FLAG'
local IVK_IS_SIMULATOR_BY_C_NATIVE = 'IS_SIMULATOR_BY_C_NATIVE'
local IVK_SYSINFO_CAN_RESOLVE_ACTIVITY = 'CAN_RESOLVE_ACTIVITY'
local IVK_SYSINFO_LAUNCH_TIME = 'SYSINFO_LAUNCH_TIME'
local IVK_IS_EJOYSDK_DEBUGABLE = 'IS_EJOYSDK_DEBUGABLE'

local IVK_GET_UTDID = 'GET_UTDID'
local IVK_GET_UUID = 'GET_UUID'
local IVK_GET_GAID = 'GET_GOOGLE_ADVERTISING_ID'
local IVK_MANIFEST_META_DATA = 'GET_MANIFEST_META_DATA'
local IVK_IS_SUPPORT_HARDWARE_INFO = 'IS_SUPPORT_HARDWARE_INFO'
local IVK_IS_SUPPORT_HANDLING_FILE_CACHE='IS_SUPPORT_HANDLING_FILE_CACHE'
local IVK_OPEN_PERMISSION_SETTING = 'OPEN_PERMISSION_SETTING'
local IVK_OPEN_PERMISSION_COMMON_SETTING = 'OPEN_PERMISSION_COMMON_SETTING'
local IVK_GET_REQUESTED_PERMISSIONS = 'GET_REQUESTED_PERMISSIONS'
local IVK_SCROLL_LOG_FILE = 'SCROLL_LOG_FILE'
local IVK_FLUSH_LOG = 'FLUSH_LOG'
local IVK_GET_LOG_FILES = 'GET_LOG_FILES'
local IVK_GET_CURRENT_LOG_FILE = 'GET_CURRENT_LOG_FILE'

--获取刘海区域
local IVK_GET_CUTOUT_INFO = 'GET_CUTOUT_INFO'
--更新下发异形屏
local IVK_UPATE_CUTOUT_INFO = 'UPATE_CUTOUT_INFO'

--获取sdk的版本号
local IVK_GET_SDK_VERSION_NAME = 'GET_SDK_VERSION_NAME'

-- 网络监测
local IVK_SYSINFO_NETWORK_CURRENT_STATE = 'SYSINFO_NETWORK_CURRENT_STATE'
local IVK_SYSINFO_NETWORK_MONITOR_START = 'SYSINFO_NETWORK_MONITOR_START'
local IVK_SYSINFO_NETWORK_MONITOR_STOP = 'SYSINFO_NETWORK_MONITOR_STOP'

local IVK_GET_LAST_OPENURL_DATA = 'GET_LAST_OPENURL_DATA'

local IVK_GET_GOOGLE_PURCHASE_ITEMS = "GET_GOOGLE_PURCHASE_ITEMS"


local _TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'android'

local M = {}
local cbs = {}
local cb_id = math.random(1000, 9999)
local native_support_functions = nil
local global_request_task_tag = math.random(1000, 9999)
local cache_ext_stg_dir
local http_progress_cbs = {}
local http_progress_tid_cbid_map = {}

M.PLATFORM = {
    OS = 'Android',
    HTTP_UA = 'EjoySDK-http-client/0.1 (Linux; Android)'
}

M.JAVA_CALL_STATIC_CLASS = 'com/ejoy/ejoysdk/LuaCall'

function M.async_call(type, params, chunk, cb, opts)
    chunk = chunk or ''

    local id = cb_id
    cb_id = cb_id + 1
    cbs[id] = cb

    if opts and opts.timeout and opts.timeout_cb then
        M.Timer.once(
            opts.timeout,
            function()
                if cbs[id] then
                    cbs[id] = nil
                    opts.timeout_cb()
                end
            end
        )
    end

    local CJSON = require "ejoysdk_lua.ejoysdk_cjson"
    local json_str = CJSON.encode(params)
    --local json_str = JSON.encode(params)
    return _ejoysdk.async_call(M.JAVA_CALL_STATIC_CLASS, type, id, json_str, chunk)
end

local function async_callback(id, json_str, chunk)
    local cb = cbs[id]
    if cb then
        local CJSON = require "ejoysdk_lua.ejoysdk_cjson"
        local resp = CJSON.decode(json_str)
        --local resp = JSON.decode(json_str)

        cbs[id] = nil
        cb(resp, chunk)
    end

    -- unregister progress if any
    http_progress_cbs[id] = nil
end

_ejoysdk.register_cb('ASYNC_CALL', async_callback)

function M.sync_call(type, params, chunk)
    params = params or {}
    chunk = chunk or ''
    local json_str = JSON.encode(params)
    local json_ret = _ejoysdk.sync_call(M.JAVA_CALL_STATIC_CLASS, type, json_str, chunk)
    return json_ret and JSON.decode(json_ret)
end

function M.invoke(type, params, chunk)
    params = params or {}
    chunk = chunk or ''
    local CJSON = require "ejoysdk_lua.ejoysdk_cjson"
    local json_str = CJSON.encode(params)
    return _ejoysdk.invoke(M.JAVA_CALL_STATIC_CLASS, type, json_str, chunk)
end

function M.register_async_cb(type, cb)
    _ejoysdk.register_cb(type, cb)
end

function M.printl(content)
    M.log({msg = content})
end

function M.is_support_function(func_name)
    if not func_name or func_name == "" then
        _ejoysdk.log("is_support_function failed, func_name invalid")
        return false
    end

    if not native_support_functions then
        native_support_functions = M.sync_call(CT_GET_SUPPORT_FUNCTIONS)
    end
    local ret_type = type(native_support_functions)
    if ret_type ~= "table" then
        _ejoysdk.log("is_support_function failed, ret type invalid:" .. tostring(native_support_functions))
        return false
    end

    if native_support_functions[func_name] or func_name == ECC.NATIVE_SUPPORT_FUNCTION_NAMES.HTTP_DOWNLOAD then
        return true
    else
        return false
    end
end

local _FileBatch = {}
local _FileCompat = {}
do
    local is_support_batch = M.is_support_function(ECC.NATIVE_SUPPORT_FUNCTION_NAMES.BATCH_FILE_OPERATION)
    _ejoysdk.log("android load with support batch:" .. tostring(is_support_batch))
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

-------- lua文件实现开始 ----------
function _FileCompat.process_exists(path)
    return LUA_FILE.exists(path)
end

function _FileCompat.process_remove(file_path)
    local ret = M.sync_call(ACT_FILE_DELETE,{path=file_path})
    ret = ret or {}
    local succ = true
    if type(ret.succ) == 'boolean' then
        succ = ret.succ
    end
    return succ
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

--[[
复制文件
--]]
function _FileCompat.process_copy(src_fullpath, dst_fullpath, opts)
    local override = true -- default override is true， 和之前行为保持一致（Android和lua。windows默认都会覆盖）
    opts = opts or {}
    if type(opts.override) == 'boolean' then
        override = opts.override
    end

    local ret, code, msg = LUA_FILE.copy(src_fullpath, dst_fullpath, override)
    return ret, code, msg
end

function _FileCompat.process_batch_copy(map, cb, opts)
    local override = true -- default override is true， 和之前行为保持一致（Android和lua。windows默认都会覆盖）
    opts = opts or {}
    if type(opts.override) == 'boolean' then
        override = opts.override
    end

    LUA_FILE.batch_copy(map, cb, override)
end

function _FileCompat.process_md5(file_path)
    return LUA_FILE.md5(file_path)
end

function _FileCompat.process_batch_md5(file_list, cb)
    LUA_FILE.batch_md5(file_list, cb)
end

function _FileCompat.process_batch_info(file_list, cb, _opts)
    LUA_FILE.batch_info(file_list, cb, _opts)
end

function _FileCompat.process_is_directory(_file_path)
    -- not support always return false
    return false
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

function _FileCompat.get_ext_file_dir()
    if cache_ext_stg_dir and cache_ext_stg_dir ~= '' then
        return cache_ext_stg_dir
    end

    cache_ext_stg_dir = M.sync_call(CT_GET_EXT_STG_DIR).path
    return cache_ext_stg_dir
end

function _FileCompat._test_reset_exit_file_dir()
    cache_ext_stg_dir = nil
end

function _FileCompat.writefile(filename, filedata, append,is_b64)
    local tmp_path = _FileCompat.get_ext_file_dir()
    if tmp_path == '' or tmp_path == nil then
        _ejoysdk.log('writefile failed, ext files dir is invalid,')
        return false
    end

    local path = string.format("%s/%s", tmp_path, filename)
    _ejoysdk.log('writefile path = ' .. tostring(path))

    return _FileCompat.writefile_fullpath(path,filedata,append, is_b64)
end

-- 写文件的函数，filename是文件的绝对路径
function _FileCompat.writefile_fullpath(full_path, filedata, append, is_b64)
    -- 和 ios 对齐
    if type(append) == "number" then
        if append > 0 then
            append = true
        else
            append = false
        end
    end

    if full_path == '' or full_path == nil then
        _ejoysdk.log('writefile failed, full_path is invalid,')
        return false
    end

    _ejoysdk.log('writefile path = ' .. tostring(full_path))

    -- 确保目录存在
    local EU = require "ejoysdk_lua.res.ejoy_http_res_utils"
    local parent_path = EU.get_parent_folder(full_path)

    if M.is_support_function(M.NATIVE_SUPPORT_FUNCTION_NAMES.MAKE_DIRS) then
        M.File.make_dirs(parent_path)
    end

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

    local file
    if append == true then
        file = io.open(full_path, "ab")
    else
        file = io.open(full_path, "wb")
    end

    if not file then
        _ejoysdk.log('writefile error!!! path = ' .. tostring(full_path))
        return false
    end

    file:write(filedata)
    file:close()

    return true, full_path
end

function _FileCompat.readfile_fullpath(path)
    _ejoysdk.log('readfile fullpath = ' .. tostring(path))
    return _ejoysdk.lread(path)
end

function _FileCompat.readfile(filename)
    local tmp_path = _FileCompat.get_ext_file_dir()
    if tmp_path == '' or tmp_path == nil then
        _ejoysdk.log('readfile failed, external files dir is invalid,')
        return nil
    end

    local path = string.format("%s/%s", tmp_path, filename)
    _ejoysdk.log('readfile path = ' .. tostring(path))
    return _ejoysdk.lread(path)
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

-- 释放内置资源
function _FileCompat.release_bundle_res(src_path,dst_path,cb)
    if(src_path and dst_path and ''~=src_path and ''~=dst_path)then
        local tmp = M.sync_call(CT_GET_EXT_STG_DIR)
        local target_path = string.format("%s/%s", tmp.path, dst_path)
        M.async_call(ACT_RELEASE_BUILTIN_RES,{src=src_path,dst=target_path},'',cb)
    else
        if(cb)then
            cb({succ=false,msg="参数错误"})
        end
    end
end

--解压资源
function _FileCompat.unzip(src_path,dst_path,cb)
    if(src_path and dst_path and ''~=src_path and ''~=dst_path)then
        local tmp = M.sync_call(CT_GET_EXT_STG_DIR)
        local src_full_path = string.format("%s/%s", tmp.path, src_path)
        local target_path = string.format("%s/%s", tmp.path, dst_path)
        M.async_call(ACT_UNZIP,{src=src_full_path,dst=target_path},'',cb)
    else
        if(cb)then
            cb({succ=false,msg="参数错误"})
        end
    end
end

function _FileCompat.unzip_full_path(src_full_path, dst_full_path, cb)
    if(src_full_path and dst_full_path and ''~=src_full_path and ''~=dst_full_path)then
        M.async_call(ACT_UNZIP,{src=src_full_path,dst=dst_full_path},'',cb)
    else
        if(cb)then
            cb({succ=false,msg="参数错误"})
        end
    end
end

function _FileCompat.zip(src_file_path, file_name, dst_path, cb)
    if(src_file_path and dst_path and ''~=src_file_path and ''~=dst_path) then
        -- local tmp = M.sync_call(CT_GET_EXT_STG_DIR)
        local src_full_path = src_file_path
        local src_file_name = file_name or tostring(os.time())
        local target_path = dst_path
        local params = {src=src_full_path,file_name=src_file_name,dst=target_path}

        M.async_call(ACT_ZIP_FILE, params, '', function(ret)
            if cb then
                if ret and ret.succ and ret.succ == 1 then
                    cb(true, ret.data or '')
                else
                    cb(false, -1, ret.data or '')
                end
            end
        end)
    else
        if(cb)then
            cb({succ=false,msg="参数错误"})
        end
    end
end

function _FileCompat.size(src_path, cb)
    if(src_path and ''~=src_path) then
        local tmp = M.sync_call(CT_GET_EXT_STG_DIR)
        if tmp then
            local src_full_path = string.format("%s/%s", tmp.path, src_path)
            M.async_call("get_file_size", {}, '',function(ret)
                if cb then
                    cb(JSON.decode(ret))
                end
            end ,src_full_path)
        end
    else
        if(cb)then
            cb({succ=false,msg="参数错误"})
        end
    end
end

function _FileCompat.is_support_handling_file_cache()
    local result = M.sync_call(IVK_IS_SUPPORT_HANDLING_FILE_CACHE, {})
    if result == nil then
        return false
    else
        return result.value
    end
end

function _FileCompat.process_make_dirs(_path)
    local result = M.sync_call(CT_MAKE_DIRS, {path = _path})
    local succ = false
    --local msg
    if result then
        succ = result.succ
        --msg = result.msg
    end

    _ejoysdk.log("make_dirs, path:" .. tostring(_path) .. ", result:" .. tostring(succ))
    return succ
end

function _FileCompat.get_sys_dirs()
    local result = M.sync_call(ACT_GET_SYS_PATHS)
    return result
end

function _FileCompat.file_md5(_path)
    local result = M.sync_call(ACT_GET_FILE_MD5, {path = _path})
    local md5_value = result and result.value or nil
    return md5_value
end
-------- lua文件实现结束 ----------

local HTTP_EVENT = 'HTTP_EVENT'

_ejoysdk.register_cb(
    HTTP_EVENT,
    function(cbid, js_str, _chunk)
        local params = http_progress_cbs[cbid]
        if params then
            local CJSON = require "ejoysdk_lua.ejoysdk_cjson"
            local resp = CJSON.decode(js_str)
            if resp.type and resp.type=='header'  then
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
                params.progress(params.url, params.file, resp.received, resp.total, resp.headers)
            end
        end
    end
)

local HTTP = {}
M.HTTP = HTTP

-- 快速获取http头
function HTTP.get_headers(url,params,cb)
    M.async_call(ACT_HTTP_HEADERS,{url=url,params=params or{}},'',cb)
end

-- windows对接的curl的证书pin接口，需要放入证书的publickey。而其它端需要的是证书的certificate内容。
-- 详细见：https://curl.se/libcurl/c/CURLOPT_PINNEDPUBLICKEY.html 和 https://blog.csdn.net/u010980938/article/details/111050830
function HTTP.add_cert(ca_name, ca_chunk, cb)
    M.async_call(
        ACT_HTTP_ADD_CERT,
        {name = ca_name},
        ca_chunk,
        function(resp, _chunk)
            if cb then
                cb(resp.succ)
            end
        end
    )
end

function HTTP.add_cert_pin(_host_pattern, _ca_name, _ca_chunk, _cb)
    -- 这里可能需要按照域名维度配置证书
    -- TODO
end

-- 获取request tag
local function gen_request_tag()
    local request_tag = global_request_task_tag
    global_request_task_tag = global_request_task_tag + 1
    return "ejoy_http_" .. tostring(request_tag)
end

function HTTP.process_get(url, params, cb)
    local headers = params and params.headers
    assert(headers, 'params.headers should not be nil')

    -- 暂时只对Android补充taskId，待ios和windows验证OK后去掉该限制
    local task_id = params.taskId
    if not task_id then
        task_id = gen_request_tag()
        params.taskId = task_id
    end

    local progress = params.progress
    params.progress = nil
    local finish_cb = params.finish_cb
    params.finish_cb = nil
    local header_cb = params.header_cb
    params.header_cb = nil

    local cbid =
        M.async_call(
        ACT_HTTP_GET,
        {url = url, params = params},
        '',
        function(info, body)
            info.headers = HTTP.Header.New(info.headers)

            info.body = body
            cb(info)
        end,
        {
            timeout = params.timeout,
            timeout_cb = function()
                cb({status = 0})
            end
        }
    )

    -- 尝试反注册之前的progress cb
    M.HTTP.unregister_progress_cb(task_id)

    if params.file and progress then
        http_progress_cbs[cbid] = {url = url, file = params.file, progress = progress, finish_cb = finish_cb, header_cb = header_cb}
    end

    http_progress_tid_cbid_map[task_id] = cbid
end

function HTTP.process_post(url, params, _content_type, body, cb)
    params = params or {}
    assert(params.headers, 'params.headers should not be nil')

    local task_id = params.taskId
    if not task_id then
        task_id = gen_request_tag()
        params.taskId = task_id
    end

    local progress = params.progress
    params.progress = nil
    local cbid =
        M.async_call(
        ACT_HTTP_POST,
        {url = url, params = params},
        body,
        function(info, resp_body)
            info.headers = HTTP.Header.New(info.headers)

            info.body = resp_body
            cb(info)
        end,
        {
            timeout = params.timeout,
            timeout_cb = function()
                cb({status = 0})
            end
        }
    )

    -- 尝试反注册之前的progress cb
    M.HTTP.unregister_progress_cb(task_id)

    if params.file and progress then
        http_progress_cbs[cbid] = {url = url, file = params.file, progress = progress, finish_cb = params.finish_cb}
    end

    http_progress_tid_cbid_map[task_id] = cbid
end

function HTTP.process_stop(_task_id_arr, params, cb)
    if not _task_id_arr or next(_task_id_arr) == nil then
        cb(false, {})
        return
    end

    local _task_id = _task_id_arr[1]
    M.async_call(
            ACT_HTTP_STOP,
            {
                        taskId = _task_id,
                        taskIdArr = _task_id_arr
                },
            '',
            function(info)
                cb(info.succ, info)
            end,
            {
                timeout = params.timeout,
                timeout_cb = function()
                    cb(false, {})
                end
            }
    )
end

function HTTP.unregister_progress_cb(_task_id)
    if not _task_id then
        return
    end

    local _cb_id = http_progress_tid_cbid_map[_task_id]
    if not _cb_id then
        return
    end

    _ejoysdk.log("unregister_progress_cb:" .. tostring(_cb_id))
    http_progress_cbs[_cb_id] = nil
    http_progress_tid_cbid_map[_task_id] = nil
end

function HTTP.http_remove_cache()
    -- 空实现，iOS才需要清除接口
end

function HTTP.http_enable_cache()
    -- 空实现，iOS才有此接口
end

-- 限速相关：
-- limit_speed: 限制速度
-- limit_interval：限速检查间隔
function HTTP.update_with_config(params)
    M.invoke(ACT_HTTP_UPDATE_CONFIG, params)
end

local KEYSTORE_KEY = 'ejoysdk'
local KeyStore = {}
M.KeyStore = KeyStore

function KeyStore.get(key)
    return M.sync_call(CT_KEYSTORE_GET, {service = KEYSTORE_KEY, key = key}).value
end

-- 空实现
function KeyStore.get_group(_access_group)
    return nil
end


function KeyStore.set(key, value, _apply)
    if value == nil then
        return
    end
    M.invoke(IVK_KEYSTORE_SET, {service = KEYSTORE_KEY, key = key, value = value, apply = _apply})
end

function KeyStore.set_group(_key, _access_group, _value)
    -- 空实现
end

function KeyStore.delete(key)
    M.invoke(IVK_KEYSTORE_DELETE, {service = KEYSTORE_KEY, key = key})
end

function KeyStore.delete_group(_key, _access_group)
    -- 空实现
end

function KeyStore.clear()
    M.invoke(IVK_KEYSTORE_CLEAR, {service = KEYSTORE_KEY})
end

function KeyStore.clear_group(_access_group)
    -- 空实现
end

function KeyStore.custom_sub_dir(_sub_dir_param)
    -- do nothing here
end

M.UnRecoverKeyStore = KeyStore

-- sharedpreferences raw api
local SPRawKeyStore = {}
function SPRawKeyStore.get(sp_name, key)
    return M.sync_call(CT_KEYSTORE_GET, {service = sp_name, key = key}).value
end

function SPRawKeyStore.set(sp_name, key, value, _apply)
    M.invoke(IVK_KEYSTORE_SET, {service = sp_name, key = key, value = value, apply = _apply})
    return true
end

function SPRawKeyStore.delete(sp_name, key)
    M.invoke(IVK_KEYSTORE_CLEAR, {service = sp_name})
end

M.SPRawKeyStore = SPRawKeyStore

local WebView = {}
M.WebView = WebView

-- 方法描述：打开webview 加载url
-- @param url： 必填，string 类型， url 地址
-- @param injection: 可选， object 类型，一个域名白名单mapping, 值为该域名对应的参数列表。注意：不在白名单的域名是无法调用端的JS接口的。
-- @param option: object 可选，类型，可以设置该webview相关的可选项，包含compactMode，closeEventData
-- @param on_js_callback：可选，拦截处理JS调用
-- @param on_close_callback: 可选，拦截处理webview关闭事件
function WebView.open(url, injection, option, on_js_callback, on_close_callback)
    local EWB = require "ejoysdk_lua.ejoysdk_webview_manager"
    return EWB.add_webview(url, injection, option, on_js_callback, on_close_callback)
end

function WebView.close()
    return M.invoke(IVK_WEBVIEW_CLOSE)
end

function WebView.capture(callback)
   M.async_call(ACT_WEBVIEW_CAPTURE,{},'',callback,nil)
end

-- 通知回调H5页面
function WebView.callback_js(js_cb_id, message, ext)
    return M.invoke(IVK_WEBVIEW_CALLBACK_JS, { cb_id = js_cb_id, message = message, ext = ext})
end

-- 执行JS脚本
function WebView.call_js(script, ext)
    return M.invoke(IVK_WEBVIEW_CALL_JS, {script = script, ext = ext})
end

function WebView.is_opened()
    return (M.sync_call(IVK_WEBVIEW_IS_OPENED) or {}).isOpened == true
end

function WebView.go_back()
    return (M.sync_call(SYNC_WEBVIEW_OPERATOR, { type = ACT_WEBVIEW_GO_BACK }) or {}).value == true
end

function WebView.go_forward()
    return (M.sync_call(SYNC_WEBVIEW_OPERATOR, { type = ACT_WEBVIEW_GO_FORWARD }) or {}).value == true
end

function WebView.reload()
    M.sync_call(SYNC_WEBVIEW_OPERATOR, { type = ACT_WEBVIEW_RELOAD })
end

function WebView.show(params)
    params = params or {}
    return M.invoke(IVK_WEBVIEW_OPERATOR, { type = ACT_WEBVIEW_SHOW, data = params })
end

function WebView.hide(params)
    params = params or {}
    return M.invoke(IVK_WEBVIEW_OPERATOR, { type = ACT_WEBVIEW_HIDE, data = params })
end

function WebView.remove_hide_cache(params)
    params = params or {}
    return M.invoke(IVK_WEBVIEW_OPERATOR, { type = ACT_WEBVIEW_REMOVE_HIDE_CACHE, data = params })
end

function WebView.prepare(_params)
    _params = _params or {}
    return M.invoke(IVK_WEBVIEW_OPERATOR, { type = ACT_WEBVIEW_PREPARE, data = _params })
end

function WebView.update_toolbar(toolbar_config)
    local EWB = require "ejoysdk_lua.ejoysdk_webview_manager"
    EWB.update_toolbar(toolbar_config)
end

function WebView.update_toolbar_item(params)
    local EWB = require "ejoysdk_lua.ejoysdk_webview_manager"
    EWB.update_toolbar_item(params)
end

local WEBVIEW_EVENT = 'WEBVIEW_EVENT'
local WEBVIEW_JSARGS_EVENT = 0
local WEBVIEW_CLOSE_EVENT = 1
local WEBVIEW_URL_REDIRECT = 2
local WEBVIEW_LIFE_CYCLE_EVENT = 3;
local WBEVIEW_HIDE_EVENT = 4

_ejoysdk.register_cb(
    WEBVIEW_EVENT,
    function(cbid, js_str, _chunk)
        _ejoysdk.log('WEBVIEW_EVENT callback')
        local value = JSON.safe_decode(js_str)
        if cbid == WEBVIEW_JSARGS_EVENT then
            -- 避免前端传递数据错误导致全局异常
            if value and value.args then
                if value.args.type == 'oauthUri' then
                    ET.publish('logindone', value)
                else
                    ET.publish('webview_jsargs', value)
                end
            end
        elseif cbid == WEBVIEW_CLOSE_EVENT then
            ET.publish('webview_close', value)
        elseif cbid == WEBVIEW_URL_REDIRECT then
            ET.publish('webview_url_redirect', value)
        elseif cbid == WEBVIEW_LIFE_CYCLE_EVENT then
            -- url,event=type,data
            ET.publish('webview_life_cycle',value)
        elseif cbid == WBEVIEW_HIDE_EVENT then
            ET.publish('webview_hide',value)
        end
    end
)

-- 提供给非js,非nativeapi接入的原生调用
local LUA_CALL_EVENT = 'LUA_CALL_EVENT'
_ejoysdk.register_cb(
       LUA_CALL_EVENT,
        function(_eventid, params, _chunk)
            local ADAPTER = require 'ejoysdk_lua.ejoysdk_lua_adapter'
            if _eventid == 2 then
                ADAPTER.input(params)
            else
                -- plain, 旧的协议
                ADAPTER.input(JSON.safe_decode(params), true)
            end
        end
)

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
        local UTILS = require 'ejoysdk_lua.ejoysdk_utils'
        return UTILS.deepcopy(url_open_datas) or {}
    end
end

-- 从native侧获取openurl_data的缓存(SDK内部用，游戏不要调本接口)
function M.get_last_openurl_data()
    -- {"value":{xx=yy}}结构，所以是取value字段
    local last_openurl_data = M.sync_call(IVK_GET_LAST_OPENURL_DATA, {})
    if last_openurl_data and last_openurl_data.value and next(last_openurl_data.value) then
        -- 返回值是数组类型，为了和get_url_open_datas接口保持一致
        local UTILS = require 'ejoysdk_lua.ejoysdk_utils'
        return UTILS.deepcopy({last_openurl_data.value})
    else
        return {}  -- 空数组
    end
end

local function publish_urlopen(data)
    _ejoysdk.log('url_open, [v2]_app_event_handler, publish_data:' .. JSON.encode(data))
    ET.publish('urlopen_v2', 'url', data)

    -- 兼容旧的通知
    if data.url then
        _ejoysdk.log('url_open, _app_event_handler, publish_url:' .. data.url)
        ET.publish('urlopen', data.url)
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

    M.Sysinfo.network_monitor_start()
    M.Sysinfo.cpu_start_monitor()
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
    local APP_BACK_PRESS_EVENT = 2
    local APP_ON_CONFIGURATION_CHANGE = 3
    local APP_NETWORK_STATE_CHANGE_EVENT = 10
    local APP_AUDIO_MUTE_CHANGE_EVENT = 11

    local _app_event_handler = {
        [APP_OPENURL_EVENT] = function(value, _chunk)
            local data = value or {}

            if gangplank_inited then
                publish_urlopen(data)
            else
                _ejoysdk.log('url_open, [v2]_app_event_handler, add cache:' .. JSON.encode(value))

                url_open_datas = url_open_datas or {}
                table.insert(url_open_datas, data)
                -- 存储避免多vm前置消费的情况
                local ukeystore = M.get_url_data_keystore()
                if ukeystore then
                    ukeystore:set(url_open_datas)
                end
            end
        end,
        [APP_ON_STOP_EVENT] = function()
            ET.publish('app_on_stop')
        end,
        [APP_BACK_PRESS_EVENT] = function()
            ET.publish('backpress')
        end,
        [APP_ON_CONFIGURATION_CHANGE] = function(value)
            local data = value or {}
            ET.publish('on_configuration_change',data)
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
        [APP_AUDIO_MUTE_CHANGE_EVENT] = function(mute_info)
            _ejoysdk.log('lua receive audio_mute_change, type=' .. tostring(mute_info.type) .. ', is_mute=' .. tostring(mute_info.isMute))
            ET.publish("audio_mute_change", mute_info)
        end
    }
    _ejoysdk.register_cb(
            APP_EVENT,
            function(cbid, js_str, chunk)
                local handler = _app_event_handler[cbid]
                if handler then
                    local value = JSON.safe_decode(js_str)
                    handler(value, chunk)
                else
                    _ejoysdk.log("app event handler not found")
                end
            end
    )
end

register_event()

local Modal = {}
M.Modal = Modal

function Modal.open(title, option, cb)
    option = option or {}
    cb = cb or function()
        end
    M.async_call(
        ACT_MODAL_OPEN,
        {title = title, option = option},
        '',
        function(info, _body)
            cb(info.index)
        end
    )
end

function Modal.close(cb)
    M.sync_call('MODAL_CLOSE')
    if cb then
        cb()
    end
end

function Modal.alert(title, message, cb)
    local option = {
        message = message,
        buttons = {'确定'}
    }
    local cb_wrap = function(_index)
        if cb then
            cb()
        end
    end
    Modal.open(title, option, cb_wrap)
end

function Modal.confirm(title, message, cb)
    local option = {
        message = message,
        buttons = {'取消', '确定'}
    }
    local cb_wrap = function(index)
        cb(index ~= 0)
    end
    Modal.open(title, option, cb_wrap)
end

local Toast = {}
M.Toast = Toast

function Toast.show(message, option)
    option = option or {}
    return M.invoke(IVK_TOAST_OPEN, {message = message, option = option})
end

function Toast.hide()
    return M.invoke(IVK_TOAST_OPEN, {message = '', option = {}})
end

local Loading = {}
M.Loading = Loading

function Loading.show(option)
    option = option or {}
    return M.invoke(IVK_LOADING_SHOW, {option = option})
end

function Loading.dismiss()
    return M.invoke(IVK_LOADING_DISMISS, {})
end

local device_static_info_list = nil
local function get_device_info_list()
    if not device_static_info_list then
        device_static_info_list = M.sync_call(IVK_SYSINFO_STATIC_LIST, {})
    end

    return device_static_info_list
end

function M.get_device_info_list()
    return get_device_info_list()
end

local Sysinfo = {}
M.Sysinfo = Sysinfo

local _native_utdid = nil
function Sysinfo.utdid()
    if not _native_utdid or _native_utdid == '' then
        _native_utdid = M.sync_call(IVK_GET_UTDID, {}).value
    end
    return _native_utdid or ''
end

function Sysinfo.oaid()
    return get_device_info_list().oaid
end

function Sysinfo.app_name()
    return get_device_info_list().app_name
end

function Sysinfo.app_version_code()
    return get_device_info_list().app_version_code
end

function Sysinfo.app_version_name()
    return get_device_info_list().app_version
end

--android 系统版本，例如：8.0.1
function Sysinfo.os_version()
    return get_device_info_list().os_version
end

function Sysinfo.install_time()
    return ''
end

function Sysinfo.update_time()
    return ''
end

--手机型号
function Sysinfo.model()
    return get_device_info_list().model
end

--手机品牌
function Sysinfo.brand()
    return get_device_info_list().brand
end

function Sysinfo.package_name()
    return get_device_info_list().pkg_name
end

--手机屏幕宽度，单位:px
function Sysinfo.screen_width()
    return get_device_info_list().width
end

--手机屏幕高度，单位:px
function Sysinfo.screen_height()
    return get_device_info_list().height
end

function Sysinfo.is_passive_mode()
    return get_device_info_list().is_passive_mode
end

function Sysinfo.content_size(cb)
    local default_width = Sysinfo.screen_width()
    local default_height = Sysinfo.screen_height()
    local opts = {
        timeout = 3,
        timeout_cb = function()
            if cb then
                _ejoysdk.log("content_size timeout, return default:" .. tostring(default_width) .. ", " .. tostring(default_height))
                cb(default_width, default_height)
            end
        end
    }

    M.async_call(IVK_SYSINFO_SCREEN_CONTENT_SIZE, {}, nil, function(info, _body)
        local content_width = info.content_width
        local content_height = info.content_height
        if not content_width or not content_height then
            content_width = default_width
            content_height = default_height
        end

        if cb then
            cb(content_width, content_height)
        end
    end, opts)
end

--从lua调native的c库判断模拟器
local function is_simulator_by_c_native()
    local is_simulator = M.sync_call(IVK_IS_SIMULATOR_BY_C_NATIVE, {})
    if is_simulator == nil then
        return false
    else
        return is_simulator.value or false
    end
end

--判断是否支持从lua调native的c库判断模拟器,新版本支持后，不再需要使用get_device_info_list().simulatorjaq
local function support_c_native_detect_simulator()
    local is_simulator = M.sync_call(IVK_IS_SIMULATOR_BY_C_NATIVE, {})
    return is_simulator ~= nil
end

--根据模拟器特性判断是否是模拟器
local function detect_simulator_by_feature()
    if M.is_support_function('get_system_properties') then
        local simulatorFlagCount = 0
        local hardware = M.get_system_properties('ro.hardware', 'default')
        local flavor = M.get_system_properties('ro.build.flavor', 'default')
        local product_model = M.get_system_properties('ro.product.model', 'default')
        local manufacturer = M.get_system_properties('ro.product.manufacturer', 'default')
        local board = M.get_system_properties('ro.product.board', 'default')
        local board_platform = M.get_system_properties('ro.board.platform', 'default')
        local base_band_version = M.get_system_properties('gsm.version.baseband', 'default')
        M.log('simulator feature: hardware is ' .. tostring(hardware) .. ', flavor is ' .. tostring(flavor) .. ', product_model is ' .. tostring(product_model)
                .. ', manufacturer is ' .. tostring(manufacturer) .. ', board is ' .. tostring(board) .. ', board_platform is '
                .. tostring(board_platform) .. ', base_band_version is ' .. tostring(base_band_version))

        if string.find(hardware, 'ttvm') or string.find(hardware, 'nox') or string.find(hardware, 'cancro')
                or string.find(hardware, 'intel') or string.find(hardware, 'vbox')
                or string.find(hardware, 'vbox86') or string.find(hardware, 'android_x86') then
            simulatorFlagCount = simulatorFlagCount + 1
        end

        if string.find(flavor, 'vbox') or string.find(flavor, 'sdk_gphone') then
            simulatorFlagCount = simulatorFlagCount + 1
        end

        --雷电模拟器, 再加上基带信息为空各1分判断
        if flavor =='aosp-user' then
            simulatorFlagCount = simulatorFlagCount + 1
        end

        --MuMu模拟器
        if flavor == 'cancro_x86_64-user' then
            simulatorFlagCount = simulatorFlagCount + 2
        end

        if string.find(product_model, 'google_sdk') or string.find(product_model, 'emulator') or string.find(product_model, 'android sdk build for x86') then
            simulatorFlagCount = simulatorFlagCount + 1
        end

        if string.find(manufacturer, 'genymotion') or string.find(manufacturer, 'Netease') then
            simulatorFlagCount = simulatorFlagCount + 1
        end

        if string.find(board, 'android') or string.find(board, 'goldfish') then
            simulatorFlagCount = simulatorFlagCount + 1
        end

        if string.find(board_platform, 'android') then
            simulatorFlagCount = simulatorFlagCount + 1
        end

        --逍遥模拟器
        if board_platform == 'gmin' then
            simulatorFlagCount = simulatorFlagCount + 2
        end

        if string.find(base_band_version, '1.0.0.0') then
            simulatorFlagCount = simulatorFlagCount + 1
        end

        --基带版本为空，判断为模拟器
        if base_band_version == 'default' then
            simulatorFlagCount = simulatorFlagCount + 1
        end

        if simulatorFlagCount >= 2 then
            return true
        end
    end
    return false
end

--lua判断是否模拟器，优先于native
local lua_detect_simulator_result = nil
local function detect_simulator_by_lua()
    if lua_detect_simulator_result == nil then
        lua_detect_simulator_result = false
        --判断是否安装模拟器特征apk
        local pkg_names = {
            "com.mumu.launcher", --mumu模拟器
            "com.blue.huang17.launcher", --blue模拟器
            "cn.itools.vm.launcher", --iTools模拟器
            "com.bignox.launcher", --夜神模拟器
            "com.windroy.launcher", --windroy模拟器
            "com.microvirt.launcher", --逍遥模拟器
            "com.microvirt.launcher2", --逍遥模拟器
            "com.vphone.launcher", --vphone模拟器
            "com.bluestacks.home", --蓝叠模拟器
            "com.android.flysilkworm" --雷电模拟器
        }
        for _, pkg_name in pairs(pkg_names) do
            local is_simulator_apk_installed = Sysinfo.is_app_install(pkg_name)
            if is_simulator_apk_installed then
                lua_detect_simulator_result = true
                break
            end
        end
        lua_detect_simulator_result = lua_detect_simulator_result or is_simulator_by_c_native() or detect_simulator_by_feature() or false
        --将该值设置给native, native使用lua设置的值给经分
        M.sync_call(IVK_SET_SIMULATOR_FLAG, {is_simulator = lua_detect_simulator_result})
    end
    return lua_detect_simulator_result
end

local is_simulator = nil
--是否是模拟器
function Sysinfo.is_simulator()
    if is_simulator == nil then
        --安卓12及以上，只使用模拟器特征包名判断
        local os_version = Sysinfo.os_version() or ''
        local os_version_number = tonumber(os_version)
        if (os_version_number and os_version_number >= 31) or support_c_native_detect_simulator() then
            is_simulator = detect_simulator_by_lua()
            --修正device_info_list里的值
            get_device_info_list().simulatorjaq = is_simulator
            return is_simulator
        end
        --安卓12以下且ejoysdk为旧版本, 继续使用旧的判断
        is_simulator = get_device_info_list().simulatorjaq
    end
    return is_simulator
end

--屏幕密度
function Sysinfo.density()
    return get_device_info_list().dp
end

--系统启动时间：返回时间戳
function Sysinfo.get_boot_time()
    return get_device_info_list().boot
end

--cpu详细信息，例如：abi: arm64-v8a\nHardware\t: Qualcomm Technologies, Inc SDM636\n
function Sysinfo.get_cpu_detail()
    return get_device_info_list().cpu
end

--cpu型号，例如：Qualcomm Technologies, Inc SDM636
function Sysinfo.get_cpu_model()
    return get_device_info_list().cpu_model
end

function Sysinfo.get_cpu_max_freq()
    return get_device_info_list().cpu_max_freq
end

--辅助功能是否开启
function Sysinfo.is_accessibility_enable()
    return get_device_info_list().acc
end

--是否有自动化脚本
function Sysinfo.is_param_mod_inuse()
    return get_device_info_list().mod
end

--是否是QEMU设备
function Sysinfo.is_qemu_device()
    return get_device_info_list().qe
end

--是否开启adb调试
function Sysinfo.is_adb_enabled()
    return get_device_info_list().adb
end

--app安装时间
function Sysinfo.get_app_install_time()
    return get_device_info_list().appins
end

--android webview user agent
function Sysinfo.get_user_agent()
    return get_device_info_list().useragent
end

--是否安装了xposed
function Sysinfo.is_xposed_installed()
    return get_device_info_list().xp
end

function Sysinfo.get_ejoy_referer()
    return get_device_info_list().ejoy_referer
end

function Sysinfo.is_app_install(package_name)
    local ret = M.sync_call(IVK_SYSINFO_IS_APP_INSTALLED, {pkgName = package_name})
    if ret and ret.value then
        return ret.value == 'true'
    else
        return false
    end
end

function Sysinfo.can_resolve_activity(package_name, package_activity_name)
    local ret = M.sync_call(IVK_SYSINFO_CAN_RESOLVE_ACTIVITY, {package_name = package_name, package_activity_name = package_activity_name})
    if ret and ret.value then
        return ret.value == 'true'
    else
        return false
    end
end

--获取系统的安装时间，返回时间戳
function Sysinfo.get_system_install_time()
    return get_device_info_list().sysins
end

--获取cpu核心数
function Sysinfo.get_cpu_cores_count()
    return get_device_info_list().cores
end

--获取手机制造厂商
function Sysinfo.get_manufacturer()
    return get_device_info_list().mt
end

function Sysinfo.get_disk_info_async(cb)
    if cb then
        cb(false, -1, 'only windows support')
    end
end

--cpu id
function Sysinfo.get_cpu_id()
    return get_device_info_list().cid
end

--设备是否root
function Sysinfo.is_device_root()
    return get_device_info_list().rt
end

--android_id
function Sysinfo.android_id()
    return get_device_info_list().android_id
end

--独代一级渠道号
function Sysinfo.ds_channel_id()
    return get_device_info_list().ds_ch_id
end

--独代一级渠道号
function Sysinfo.ds_sub_channel_id()
    return get_device_info_list().ds_sub_ch_id
end

-- 获得国家地区信息
function Sysinfo.country()
    return get_device_info_list().country
end

-- 获得系统语言
function Sysinfo.language()
    return get_device_info_list().language
end

function Sysinfo.language_script()
    return get_device_info_list().language_script
end

-- 获得系统时区
function Sysinfo.time_zone()
    return get_device_info_list().time_zone
end

function Sysinfo.sysinfo_ios_app_on_mac()
    return false
end

--设备唯一标识，用于在ejoy业务之间关联，和{@link M.Sysinfo.device_id()}不同的是该id不允许为空
--例如：android的内部业务统一为utdid，ios业内统一为idfa
function Sysinfo.idfa()
    return M.Sysinfo.utdid()
end

function Sysinfo.device_with_android_id()
    return M.sync_call(IVK_SYSINFO_DEVICE_WITH_ANDROID, {}).value
end

-- 安装标识
function Sysinfo.uuid()
    return M.sync_call(IVK_GET_UUID).value
end

function Sysinfo.screen()
    return M.sync_call(IVK_SYSINFO_SCREEN)
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
    注意：只有开启了cpu_start_monitor，cpu_usage才能获取到有效值
--]]
function Sysinfo.cpu_usage(cb)
    M.async_call(IVK_SYSINFO_CPU_USAGE,
            {},
            '',
            cb
    )
end

--[[
    开启cpu_start_monitor
    安卓获取CPU使用率，比较慢，所以需要开启cpu_start_monitor，减少延时
--]]
function Sysinfo.cpu_start_monitor()
    M.sync_call(IVK_SYSINFO_CPU_START_MONITOR);
end

--[[
    关闭cpu_start_monitor
--]]
function Sysinfo.cpu_stop_monitor()
    M.sync_call(IVK_SYSINFO_CPU_STOP_MONITOR);
end

--[[
    cpu_monitor是否已开启
--]]
function Sysinfo.cpu_monitor_enable()
    return M.sync_call(IVK_SYSINFO_CPU_MONITOR_ENABLE);
end

--[[
    同步方法
    总内存, 返回值, {'Total':value}, value类型整型，单位字节，推荐使用memory_detail
--]]
function Sysinfo.memory()
    return M.sync_call(IVK_SYSINFO_MEMORY)
end

function Sysinfo.memory_info()
    -- android待实现
    return {}
end

--[[
    异步方法
    异步获取内存信息
    Android 10及以上有限制，频繁调用会返回上次的值
    cb: function(result)
        -- 系统有限制非高频刷新（5min才刷新一次）
        -- result.total 表示操作系统的总内存, 单位是字节
        -- result.free 表示操作系统的可用内存, 单位是字节
        -- result.threshold 表示操作系统的可用内存是该值时，就会杀进程了, 单位是字节
        -- result.isLowMemory 表示操作系统是否处于低内存状态, 单位是字节
        -- result.dalvikPSS 表示dalvikPSS, 单位是字节
        -- result.javaHeap 表示java的堆内存(安卓6.0及以上才有), 单位是字节
        -- result.appPSS 表示程序的PSS, 单位是字节

        -- 支持实时刷新的值，性能考虑频率同引擎一致（5s）
        -- result.VmRSS 进程的RSS内存, 单位是字节
    end
--]]
function Sysinfo.memory_detail(cb)
    M.async_call(IVK_SYSINFO_MEMORY_V2,
            {},
            '',
            cb
    )
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
    result.memory: table类型, eg. {'total'=1231234, 'free'=12312312, 'threshold'=123213, 'isLowMemory'=false, 'dalvikPSS'=1232,'appPSS'=12312, 'javaHeap'=2312}
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
    返回值 table类型，{"availableInternalStorage"=xx}
--]]
function Sysinfo.storage()
    return M.sync_call(IVK_SYSINFO_STORAGE)
end

--[[
  返回值 table类型，{"internal_total_storage_size"=xx
                   "internal_available_storage_size"=xx
                   "external_total_storage_size"=xx
                   "external_available_storage_size"=xx}
--]]
function Sysinfo.get_storage_info()
    return M.sync_call(IVK_GET_STORAGE_INFO)
end

function Sysinfo.opengl()
    return M.sync_call(IVK_SYSINFO_OPENGL)
end

function Sysinfo.open_url(url)
    return M.invoke(IVK_SYSINFO_OPEN_URL, {url = url})
end

function Sysinfo.can_open_url(url)
    local ret = M.sync_call(IVK_SYSINFO_CAN_OPEN_URL, {url = url})
    return ret and ret.value or false
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
    return M.sync_call(IVK_SYSINFO_BATTERY, {})
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
    M.async_call(IVK_SYSINFO_BATTERY_V2,
            {},
            '',
            cb
    )
end

--[[
    异步方法
    获取当前电池额外的信息，
    cb: function(ret)
        -- ret.temperature: 温度，获取基本无耗时0ms
        -- ret.voltage: 电压:V，获取基本无耗时0ms
        -- ret.capacity: 总电流容量:mA，获取基本耗时 1ms
        -- ret.rest_rate: 剩余电流百分比: float, 如0.23，获取基本无耗时0ms
        -- ret.electricity: 瞬时电流，充电源进入电池的净电流或从电池放电的净电流；不同系统充电和放电正负值不一样，如果做计算建议使用绝对值，获取基本耗时<2ms
    end
    注意：
        1. Android 5.0以下的系统不支持获取capacity、rest_rate、electricity
        2. 不同渠道的系统，获取不到capacity和electricity（为0）或不准确，目前测试场景小米高版本Android 9+系统获取的值较准确
        3. 此接口建议仅用于测试阶段

    参数：传入_filter，支持仅获取指定值的调用（其余返回0）损耗，传空则获取全部; capacity同时控制rest_rate和capacity，相关指标。
    local _filter = {"temperature","voltage","capacity","electricity"}
--]]
function Sysinfo.battery_ext(_filter, cb)
    local filter = _filter or {}
    local map_filter = {}

    for _,v in pairs(filter) do
        map_filter[v] = true
    end
    
    M.async_call(IVK_SYSINFO_BATTERY_EXT,
            map_filter,
            '',
            cb
    )
end

-- APP启动时，电池状态，{'level'=90,'scale'=100,'status'=2}
-- level: 当前电量
-- scale: 总电量
-- state: 0未知状态，1非充电状态，2充电状态，3充满状态（连接充电器充满状态）
function Sysinfo.launch_battery()
    return M.sync_call(IVK_SYSINFO_LAUNCH_BATTERY, {})
end

function Sysinfo.wifi()
    return M.sync_call(IVK_SYSINFO_WIFI_INFO, {})
end

function Sysinfo.mobile_info()
    return M.sync_call(IVK_SYSINFO_MOBILE_INFO, {})
end

function Sysinfo.is_vpn_connected()
    local ret =  M.sync_call(IVK_SYSINFO_VPN_CONNECTED, {})
    return ret and ret.value or false
end

-- 获取网络类型
-- 返回值：
-- 0=断网,1=wifi,2=移动网络,3=未知网络类型
function Sysinfo.network_type()
    return (M.sync_call(IVK_SYSINFO_NETWORK_TYPE, {}) or { type = 3 }).type
end

function Sysinfo.network_type_cache()
    if last_network_type == nil then
        last_network_type = M.Sysinfo.network_type()
    end

    return last_network_type
end

-- 返回：unknown, wifi, 2g, 3g, 4g
function Sysinfo.network_type_name()
    local ret = M.sync_call(IVK_SYSINFO_NETWORK_TYPE_NAME, {})
    local network_type_name = (ret and ret.name) or ''
    return network_type_name
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
    local res = M.sync_call(IVK_SYSINFO_NETWORK_CURRENT_STATE) or 0
    return res
end

-- 返回值eg: cb({succ = true, state = 3}})
function Sysinfo.network_current_state_async(cb)
    local net_state = Sysinfo.network_current_state()
    cb({succ = true, state = net_state})
end

function Sysinfo.network_monitor_start()
    M.sync_call(IVK_SYSINFO_NETWORK_MONITOR_START)
end

function Sysinfo.network_monitor_stop()
    M.sync_call(IVK_SYSINFO_NETWORK_MONITOR_STOP)
end

function Sysinfo.network_ping(_params, _cb)
    -- 移动端，是走unisdk的，详见vendors/apm.lua
end

function Sysinfo.network_traceroute(_params, _cb)
    -- 移动端，是走unisdk的，详见vendors/apm.lua
end

function Sysinfo.update_screen_scale_ratio(_ratio)
    --先留空
end


-- 1. 优先使用配置中心返回的预制到native，因为native也依赖异形数据。
-- 2. 如果没有则使用原方案：Lua预制 + 系统方案；保留Lua预制可以解决首次调用的问题。
-- 3. 接入文档：https://yuque.antfin.com/ejoy-platform/user_guide/tpqngx ；
function Sysinfo.cutout()
    return M.sync_call(IVK_GET_CUTOUT_INFO, {}).value
end

function Sysinfo.cutout_async(cb)
    local cutout_info = Sysinfo.cutout()
    cb(cutout_info)
end

function Sysinfo.update_cutout(params)
    M.sync_call(IVK_UPATE_CUTOUT_INFO, params)
end

function Sysinfo.device_id()
    return M.sync_call(IVK_SYSINFO_DEVICE_ID, {}).value
end

--gaid是异步获取的，该同步方法会获取当前预加载的gaid值，可能为空
function Sysinfo.gaid()
    return M.sync_call(IVK_GET_GAID, {}).value
end

--gaid 是异步获取的，该方法会等待异步的获取结果
function Sysinfo.gaid_async(cb)
    M.async_call(IVK_GET_GAID, {}, '', cb)
end

function Sysinfo.manifest_meta_data(type, key)
    return M.sync_call(IVK_MANIFEST_META_DATA, { type = type, key = key }).value
end

--[[
    返回值：table类型，
    eg:{
            ["model"]=xxx
            ["vendor"]=xxx
            ["version"]=xxx
        }
--]]
function Sysinfo.get_gpu_info(cb)
    M.async_call(ACT_GET_GPU_INFO, {}, '', cb)
end

function Sysinfo.is_support_hardware_info()
    local result = M.sync_call(IVK_IS_SUPPORT_HARDWARE_INFO, {})
    if result == nil then
        return false
    else
        return result.value
    end
end

function Sysinfo.sysinfo_ejoy_ext_info()
    return ""
end

local function stat_hardware_info_error(hardware_info)
    local HAS_STATED_STORAGE = M.LazyKeyStore:New('HAS_STATED_STORAGE', false, false, false)
    local has_stated = HAS_STATED_STORAGE:get()
    if has_stated == 'true' then
        M.log('has_stated hardware info error')
        return -- 只上报一次
    end

    local function do_stat(type)
        local stat = require 'ejoysdk_lua.ejoysdk_stat'
        local stat_action = 'hardware_info_error'
        local stat_params = {
            url = JSON.encode(hardware_info),
            sub_params_code = hardware_info.cpu.model,
            sub_params_message = hardware_info.cpu.max_freq,
            trace_id = hardware_info.gpu.model,
        }
        stat.stat_action(stat_action, type, false, stat_params)
        HAS_STATED_STORAGE:set('true')
    end

    local cpu_model = hardware_info.cpu.model
    if cpu_model == nil or (type(cpu_model) == 'string' and #cpu_model == 0)  then
        do_stat('cpu_model_empty')
        return
    end

    local cpu_max_freq = hardware_info.cpu.max_freq
    if cpu_max_freq == nil or cpu_max_freq == -1 then
        do_stat('cpu_max_freq_empty')
        return
    end
end

function Sysinfo.get_hardware_info(cb)
    if not Sysinfo.is_support_hardware_info() then
        cb({})
        return
    end
    local hardware_info = {
        cpu = {
            model = Sysinfo.get_cpu_model(),
            core_num = Sysinfo.get_cpu_cores_count(),
            max_freq = Sysinfo.get_cpu_max_freq()
        },
        gpu = {},
        memory = {
            total_size = Sysinfo.memory().Total,
        },
        model = Sysinfo.model(),
        brand = Sysinfo.brand()
    }
    if hardware_info.cpu.max_freq and hardware_info.cpu.max_freq > 0 then
        hardware_info.cpu.max_freq = hardware_info.cpu.max_freq / 1000000
    end
    if hardware_info.memory.total_size and hardware_info.memory.total_size > 0 then
        hardware_info.memory.total_size = hardware_info.memory.total_size / 1000000
    end
    stat_hardware_info_error(hardware_info)
    if cb then
        cb(hardware_info)
    end
    --Sysinfo.get_gpu_info(function(gpu_info)
    --    hardware_info.gpu.model = gpu_info.model
    --    hardware_info.gpu.version = gpu_info.version
    --    hardware_info.gpu.vendor = gpu_info.vendor
    --
    --    stat_hardware_info_error(hardware_info)
    --
    --    if cb then
    --        cb(hardware_info)
    --    end
    --end)
end

-- APP启动时间，时间戳，单位毫秒
function Sysinfo.launch_time()
    return M.sync_call(IVK_SYSINFO_LAUNCH_TIME, {})
end

function Sysinfo.launch_time_async(_cb)

end

-- APP运行时间，单位毫秒
function Sysinfo.run_time()
    -- os.time()的单位是秒，安卓返回的是毫秒，需要转换
    return os.time() * 1000 - Sysinfo.launch_time()
end

function Sysinfo.run_time_async(_cb)

end

--[[
    获取当前禁音键的状态
    返回值，table类型，结构如下
    {
       ["isMute"] = false
       ["ringerMode"] = 1
    }

    isMute: 是否处于 无声模式 下，无声模式包括(静音模式和震动模式)
    ringerMode: 铃声模式，0表示静音模式，1表示震动模式，2表示响铃模式，只有安卓下，才有ringerMode字段
--]]
function Sysinfo.get_audio_mute_info(cb)
    -- 安卓是同步的, 但是为了和ios保持接口形式的统一，把接口做成了异常调用
    if cb then
        local ret = M.sync_call('SYSINFO_AUDIO_MUTE_INFO')
        if not ret then
            cb(false, -1, 'native error')
            return
        end

        cb(true, ret)
    end
end

--[[
    开始监听禁音键的变化

    游戏可通过订阅 'audio_mute_change' 这个广播获取变化后的静音键信息。
    变化后的静音键信息结构如下, table类型
    {
       ["ringerMode"] = 0
       ["type"] = "audioMuteChange"
       ["isMute"] = true
    }

    ringerMode: 铃声模式，0表示静音模式，1表示震动模式，2表示响铃模式，只有安卓下，才有ringerMode字段
    type: 广播类型
    isMute: 是否处于 无声模式 下，无声模式包括(静音模式和震动模式)
--]]
function Sysinfo.start_listen_audio_mute()
    M.sync_call('START_LISTEN_AUDIO_MUTE_INFO')
end

-- 停止监听禁音键的变化
function Sysinfo.stop_listen_audio_mute()
    M.sync_call('STOP_LISTEN_AUDIO_MUTE_INFO')
end

-- 当前是否正在监听禁音键
function Sysinfo.is_audio_mute_listen_open()
    return M.sync_call('IS_AUDIO_MUTE_LISTEN_OPEN')
end

-- 获取屏幕刷新率，返回table数据结构
function Sysinfo.get_screen_refresh_rate(cb)
    --安卓是大写的，iOS和PC是小写
    M.async_call('GET_SCREEN_REFRESH_RATE', {}, '', cb)
end

local Timer = {}
M.Timer = Timer

function Timer.once(interval, cb)
    -- _ejoysdk.log("timer once begin:" .. tostring(interval))
    M.async_call(
        ACT_TIMER_ONCE,
        {interval = interval, ver='v2'},
        '',
        function(_info, _body)
            -- _ejoysdk.log("timer once end:" .. tostring(interval))
            cb()
        end
    )
end

function M.tick(once)
    register_event()

    repeat
        local cb_type, cbid, msg, chunk = _ejoysdk.tick(M.JAVA_CALL_STATIC_CLASS)
        if cb_type then
            local cb = _ejoysdk.get_register_cb(cb_type)
            if cb then
                cb(cbid, msg, chunk)
            end
        else
            return false
        end
    until once == true
    return true
end

function M.on_stop()
    ET.publish('app_on_stop')
end

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


local MEDIA_RECORD = 'MEDIA_RECORD'
local media_record_cb = {}
_ejoysdk.register_cb(
    MEDIA_RECORD,
    function(cbid, js_str, _chunk)
        local params = media_record_cb[cbid]
        if params and params.volume_cb then
            local resp = JSON.decode(js_str)
            local stop = resp.stop or false
            if stop then
                media_record_cb[cbid] = nil
            else
                local volume = resp.volume
                local db = math.log(volume, 10) * 20
                _ejoysdk.log('lua volume: ' .. volume .. ' ,db: ' .. db)
                params.volume_cb(db, volume)
            end
        end
    end
)

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
        show_permission_request = opt.show_permission_request or true,
        volume_trace_period = opt.volume_trace_period or 200,
        trace_volume = trace_volume
    }

    if params.format == 'amr' then
        if params.sampling_rate ~= 8000 and params.sampling_rate ~= 16000 then
            error('when format is amr, sampling_rate should be 8000 or 16000')
            return
        end
        if params.bit_depth_rate ~= 16 then
            error('when format is amr, bit_depth_rate should be 16')
            return
        end
        if params.channel ~= 1 then
            error('when format is amr, channel should be 1')
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

    local cbid = M.async_call(ACT_MEDIA_START_RECORD, params, '', cb)
    if trace_volume then
        media_record_cb[cbid] = {volume_cb = opt.volume_cb}
    end
end

function Media.stop_record(opt, cb)
    local params = opt or {}
    local cb_wrap = function(info, body)
        info.bytes = body
        cb(info)
    end
    M.async_call(ACT_MEDIA_STOP_RECORD, params, '', cb_wrap)
end

local MEDIA_PLAY = 'MEDIA_PLAY'
local media_play_cbs = {}

_ejoysdk.register_cb(
    MEDIA_PLAY,
    function(cbid, _js_str, _chunk)
        local params = media_play_cbs[cbid]
        if params and params.finish_cb then
            params.finish_cb()
            media_play_cbs[cbid] = nil
        end
    end
)

function Media.start_play(opt, cb)
    opt = opt or {}

    local format = 'amr'
    if opt.format ~= 'auto' then
        format = opt.format
    end

    local params = {
        filename = opt.filename or 'noname',
        format = format,
        volume = opt.volume or 1.0
    }
    local cbid = M.async_call(ACT_MEDIA_START_PLAY, params, '', cb)
    media_play_cbs[cbid] = {finish_cb = opt.finish_cb}
end

function Media.stop_play(opt, cb)
    local params = opt or {}
    M.async_call(ACT_MEDIA_STOP_PLAY, params, '', cb)
end

function Media.delete(opt, cb)
    local params = opt or {}
    M.async_call(ACT_MEDIA_DELETE, params, '', cb)
end

function Media.get_record_dir()
    local ret = M.sync_call(CT_MEDIA_RECORD_DIR)
    return ret.path
end

function M.goto_application_settings()
    M.invoke(IVK_GOTO_APPLICATION_SETTINGS)
end

local Permission = {}
M.Permission = Permission

--local permission_detail = {
--    permissions = {
--        'android.permission.READ_PHONE_STATE',
--        'android.permission.READ_EXTERNAL_STORAGE',
--        'android.permission.WRITE_EXTERNAL_STORAGE'
--    },
--
--    title = "允许权限",
--    msg = "为了正常运行游戏，需要您提供游戏环境的允许权限。请放心，这些权限内容不会泄漏您的任何个人信息。\n\n好的 \n不好 ",
--    okBtn = "允许",
--    cancelBtn = "拒绝",
--    titleGoSet = "允许权限",
--    msgGoSet = "本游戏需要使用机器照片、媒体以及exe文件/电话的管理和使用权限。拒绝权限需求将可能影响到游戏的部分服务功能。请打开手机的系统设置界面，在【设定】>【应用程序】的应用信息中进行相关设置。",
--    okBtnGoSet = "允许",
--    cancelBtnGoSet = "拒绝"
--}

--local function onGrant()
--    _ejoysdk.log('权限申请成功')
--end
--
--local function onDeny()
--    _ejoysdk.log('权限申请失败')
--end
--
--cb = { onGrant = onGrant, onDeny = onDeny}

-- 判断是否支持合规检查
function Permission.support_compliance_check()
    if(M.sync_call(CT_SUPPORT_COMPLIANCE_CHECK, {}, nil)) then
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

function Permission.checkPermission(permission_detail, cb)
    M.async_call(
        ACT_CHECK_PERMISSION,
        permission_detail,
        '',
        function(resp, _chunk)
            if resp.ret == '0' then
                cb.onDeny()
            elseif resp.ret == '1' then
                cb.onGrant()
            end
        end
    )
end

function Permission.check_permission_v2(permission, cb)

    -- M.is_support_function('notification_permission')是判断，native是否支持'notification'的权限判断
    if permission == 'notification' and not M.is_support_function('notification_permission') then
        cb(true)
    end

    M.async_call(
        ACT_CHECK_PERMISSION_V2,
        {permission = permission},
        '',
        function(resp, _chunk)
            cb(resp.succ,resp)
        end
    )
end


-- 带提示的及引导的权限申请
function Permission.check_permission_v3(options, cb)
    cb = cb or function()  end
    if not options or not options.permissions then
        cb(true)
        return
    end

    local util = require 'ejoysdk_lua.ejoysdk_utils'
    local detect_finish_cb = function(not_allow_list,forbidden_list)
        if forbidden_list and next(forbidden_list) then
            -- 如果有权限是永久拒绝的不用想直接就优先弹出来
            local title, desc = M.Permission.permission_default_description(forbidden_list)
            local default_str = "系统拒绝应用申请此权限。如需使用功能，请前往系统设置内手动打开此权限。"
            local result_str = LANG.getString('system_deny_permission_des', default_str)
            desc =  result_str .. "\n\n" .. desc
            local tempOptions = {
                buttons = {LANG.getString('cancel',"取消"), LANG.getString('goto_system_auth',"前往系统授权")},
                title = title,
                message = desc,
                permissions = forbidden_list
            }

            --直接显示跳转弹窗
            M.Permission.show_usage_dialog(tempOptions,function(ret)
                local is_open_settings = false
                if ret == 1 then
                    M.Permission.openSetting({['forbidden_list']=forbidden_list})
                    is_open_settings = true
                end
                cb(false, is_open_settings)
            end)
        elseif not_allow_list and next(not_allow_list) then
            -- 显示用途说明
            local title, desc = M.Permission.permission_default_description(not_allow_list)
            local tempOptions = {
                buttons = {LANG.getString('confirm',"确定")},
                title = title,
                message = desc,
                permissions = not_allow_list
            }

            M.Permission.show_usage_dialog(tempOptions,function()
                local grant_ret = true
                local not_allow_array = {}
                for p, _ in pairs(not_allow_list) do
                    table.insert(not_allow_array, p)
                end

                local not_allow_size = #not_allow_array
                local p_index = 1

                local check_permission_cb
                check_permission_cb = function(ret)
                    _ejoysdk.log("check_permission_v2 result:" .. tostring(ret) .. ", p_index:" .. tostring(p_index) .. ", size：" .. tostring(not_allow_size))
                    p_index = p_index + 1
                    grant_ret = grant_ret and ret
                    if p_index > not_allow_size then
                        _ejoysdk.log("check_permission_v2 return:" .. tostring(grant_ret) .. ", p_index:" .. tostring(p_index) .. ", size：" .. tostring(not_allow_size))
                        cb(grant_ret)
                    else
                        M.Permission.check_permission_v2(not_allow_array[p_index],check_permission_cb)
                    end
                end

                -- 开始真授权
                M.Permission.check_permission_v2(not_allow_array[p_index],check_permission_cb)
            end)
        else
            -- 没拒绝，都授权了，回调成功
            cb(true)
        end
    end

    local index = util.tablelength(options.permissions)
    local not_allow_permissions = {}
    local forbidden_permissions = {}
    for permission,description in pairs(options.permissions) do
        M.Permission.detect_permission(permission,function(succ,resp)
            index = index - 1
            if not succ then
                -- not allowed
                local status = resp.status
                if 0 == status then
                    -- deny, show rationale
                    not_allow_permissions[permission] = description
                elseif -1 == status then
                    -- forbidden
                    forbidden_permissions[permission] = description
                end
            end

            if index <= 0 then detect_finish_cb(not_allow_permissions,forbidden_permissions) end
        end)
    end
end

function Permission.detect_permission(permission,cb)

    -- M.is_support_function('notification_permission')是判断，native是否支持'notification'的权限判断
    if permission == 'notification' and not M.is_support_function('notification_permission') then
        cb(true)
    end

    M.async_call(
            ACT_DETECT_PERMISSION,
            {permission = permission},
            '',
            function(resp, _chunk)
                if cb then
                    cb(resp.status == 1,resp)
                end
            end
    )
end

function Permission.openSetting(ext_param)
    M.sync_call(IVK_OPEN_PERMISSION_SETTING,ext_param or {},nil)
end

function Permission.openApplicationSetting()
    if M.is_support_function(M.NATIVE_SUPPORT_FUNCTION_NAMES.OPEN_COMMON_SETTING) then
        M.sync_call(IVK_OPEN_PERMISSION_COMMON_SETTING,{},nil)
    else
        Permission.openSetting()
    end
end

function Permission.get_requested_permissions()
    return M.sync_call(IVK_GET_REQUESTED_PERMISSIONS)
end

function Permission.async_get_requested_permissions(cb)
    if cb then
        cb(M.Permission.get_requested_permissions())
    end
end

-- 显示权限用途说明弹窗,
-- 可同时申请多个权限，可使用同一份说明
function Permission.show_usage_dialog(options,cb)
    cb = cb or function()  end
    options = options or {}
    if not options.permissions then
        cb(-1)
        return
    end

    options['style']='lingxi'
    if not options.title or not options.message then
        local title,desc = M.Permission.permission_default_description(options.permissions)
        options.title = options.title or title or ''
        options.message = options.message or desc or ''
    end

    options.buttons = options.buttons or {'确定'}
    M.Modal.open(options.title,options,cb)
end

local Sdkinfo = {}
M.Sdkinfo = Sdkinfo

-- 获取sdk的版本号
function Sdkinfo.getSDKVersionName(sdkName)
    return M.sync_call(IVK_GET_SDK_VERSION_NAME, {name = sdkName}).value
end

function M.qrcode_scan(cb)
    local scan_result_handler = function(info)
        _ejoysdk.log('android qrcode_scan result: ')
        M.log(info)
        if info.succ then
            cb(true, info.result)
        else
            cb(false, info.err_code, info.err_msg)
        end
    end
    M.async_call(ACT_QRCODE_SCAN, {}, '', scan_result_handler)
end

function M.get_cba_tweleve_info()
    return {}
end

function M.support_save_to_album()
    if(M.sync_call(CT_SUPPORT_SAVE_TO_ALBUM, {}, nil)) then
        return true
    end
    return false
end

function M.save_to_album(path, need_delete, cb)
    if(M.support_save_to_album())then
        local params = {
            img_path = path,
            need_delete = need_delete
        }

        M.async_call(ACT_SAVE_TO_ALBUM, params, '', cb)
    else
        cb({code=-99,msg='保存失败，暂不支持该功能'})
    end
end

function M.kill_app()
    _ejoysdk.log("kill_app begin")
    return M.sync_call(IVK_KILL_APP)
end

function M.support_app_reviews()
    local ret = M.sync_call(CT_SUPPORT_APP_REVIEWS,{},nil)
    return ret and ret.support == true
end

function M.async_support_app_reviews(cb)
    if cb then
        cb(M.support_app_reviews())
    end
end

function M.app_reviews(cb)
    M.async_call(ACT_APP_REVIEWS,{},'',function(ret)
        if(cb)then
            cb(ret)
        end
    end)
end

function M.comment_app()
    M.app_reviews()
end

function M.copy_clipboard(params)
    return M.sync_call(CT_COPY_CLIPBOARD,params)
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

-- 同步到三端
local Calendar = {}
M.Calendar = Calendar

-- 添加日历事件提醒
function Calendar.add_event(params, cb)
    M.async_call(ACT_CALENDAR_ADD_EVENT, params, '', function(ret)
        if cb then
            local data = ret.data
            local succ = ret.succ
            if succ then
                cb(true, data)
            else
                local code = ret.code
                local msg = ret.msg
                cb(false, code, msg)
            end
        end
    end)
end

function Calendar.delete_event(params, cb)
    M.async_call(ACT_CALENDAR_DEL_EVENT, params, '', function(ret)
        if cb then
            local data = ret.data
            local succ = ret.succ
            if succ then
                cb(true, data)
            else
                local code = ret.code
                local msg = ret.msg
                cb(false, code, msg)
            end
        end
    end)
end

function Calendar.update_event(params, cb)
    M.async_call(ACT_CALENDAR_UPDATE_EVENT, params, '', function(ret)
        if cb then
            local data = ret.data
            local succ = ret.succ
            if succ then
                cb(true, data)
            else
                local code = ret.code
                local msg = ret.msg
                cb(false, code, msg)
            end
        end
    end)
end

function Calendar.query_event(params, cb)
    M.async_call(ACT_CALENDAR_QUERY_EVENT, params, '', function(ret)
        if cb then
            local data = ret.data
            local succ = ret.succ
            if succ then
                cb(true, data)
            else
                local code = ret.code
                local msg = ret.msg
                cb(false, code, msg)
            end
        end
    end)
end

function Calendar.query_event_id(params, cb)
    M.async_call(ACT_CALENDAR_QUERY_EVENT_ID, params, '', function(ret)
        if cb then
            local data = ret.data
            local succ = ret.succ
            if succ then
                cb(true, data)
            else
                local code = ret.code
                local msg = ret.msg
                cb(false, code, msg)
            end
        end
    end)
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
        M.sync_call(ACT_SENSOR_SET_THRESHOLD, {value = M.Sensor.TimeThreshold})
    end
end

function Sensor.register_shake(cb)
    shake_cb = cb
    M.sync_call(ACT_SENSOR_SHAKE_REGISTER, {value = M.Sensor.TimeThreshold})
end

function Sensor.unregister_shake()
    shake_cb = nil
    M.sync_call(ACT_SENSOR_SHAKE_UNREGISTER)
end

function Sensor.is_shake_support()
    local ret = M.sync_call(IS_SENSOR_SHAKE_SUPPORT)
    if ret then
        _ejoysdk.log('ret support >> ' .. tostring(ret.support))
        return ret.support or false
    end
    return false
end

function M.get_brightness()
    local result = M.sync_call(ACT_GET_BRIGHTNESS)
    if result == nil or result.value == nil then
        return -1
    else
        return result.value
    end
end

function M.set_brightness(brightness)
    M.sync_call(ACT_SET_BRIGHTNESS, {value = brightness})
end

function M.reset_brightness()
    M.sync_call(ACT_RESET_BRIGHTNESS)
end

function M.vibrate(milliseconds)
    M.sync_call(ACT_VIBRATE, {time = milliseconds})
end

function M.is_vibrate_support()
    local result = M.sync_call(ACT_SUPPORT_VIBRATE)
    if result == nil then
        return false
    else
        return result.value == 'true'
    end
end

function M.get_system_properties(key, default_value)
    local params = {
        key = key,
        default_value = default_value
    }
    local result = M.sync_call(ACT_GET_SYSTEM_PROPERTIES, params)
    if result then
        return result.value
    end
end

function M.set_app_orientation(_orientation)
    -- android do nothing
end

function M.set_audio_category(_category)
    -- ios api, android do nothing
end

function M.get_audio_category()
    -- ios api, android do nothing
end

function M.support_webview()
    return true
end

function M.disable_embed_webview()
    -- pc api, android do nothing
    return false
end

function M.scroll_log_file(file_name)
    return M.sync_call(IVK_SCROLL_LOG_FILE, { file_name = file_name or "" })
end

function M.flush_log()
    return M.sync_call(IVK_FLUSH_LOG)
end

function M.get_log_file_infos(_params, cb)
    local params = _params or {}
    M.async_call(IVK_GET_LOG_FILES, params, '', function(ret)
        if cb then
            cb(ret)
        end
    end)
end

function M.get_current_log_file(_params, cb)
    local params = _params or {}
    M.async_call(IVK_GET_CURRENT_LOG_FILE, params, '', function(ret)
        if cb then
            cb(ret)
        end
    end)
end

function M.get_ej_debugable()
    return M.sync_call(IVK_IS_EJOYSDK_DEBUGABLE, {})
end

function M.switch_to_game()
    -- DOTHING
    return false
end

function M.set_pc_ad_token(_pc_ad_token)
    -- pc api, android do nothing
end

function M.get_pc_ad_token()
    -- pc api, android do nothing
end

function M.get_pre_order_items(cb)
    cb = cb or function()  end
    local platform = 'google'
    if M.is_support_function("get_google_purchase_items") then
        M.async_call(IVK_GET_GOOGLE_PURCHASE_ITEMS,{},nil, function(ret)
            local succ = ret.succ
            if succ == true then
                cb(true,platform, ret.data or {})
            else
                cb(false, platform, ret.code or -2, ret.msg or 'unknown')
            end
        end)
    else
        cb(false, platform, -1, 'not support')
    end
end

-------- 批量文件实现开始 ----------
function _FileBatch.process_batch_remove(list, cb)
    list = list or {}
    local list_size = #list
    if list_size == 0 then
        if cb then
            cb(true)
        end
    end

    _ejoysdk.log("_FileBatch process_batch_remove begin:" .. tostring(list_size))
    M.async_call(ACT_FILE_BATCH_REMOVE, { files = list }, '', function(ret)
        ret = ret or {}
        if cb then
            cb(ret.succ, ret.code, ret.msg, ret.result_ext)
        end
    end)
end

function _FileBatch.process_batch_rename(map, cb)
    _ejoysdk.log("_FileBatch process_batch_rename begin")
    M.async_call(ACT_FILE_BATCH_RENAME, { files = map }, '', function(ret)
        ret = ret or {}
        if cb then
            cb(ret.succ, ret.code, ret.msg, ret.result_ext)
        end
    end)
end

--[[
复制文件
--]]
function _FileBatch.process_copy(src_fullpath, dst_fullpath, opts)
    local override = true -- default override is true， 和之前行为保持一致（Android和lua。windows默认都会覆盖）
    opts = opts or {}
    if type(opts.override) == 'boolean' then
        override = opts.override
    end

    local result = M.sync_call(ACT_FILE_COPY, {src_path = src_fullpath, dst_path = dst_fullpath, need_override = override}, '')
    --M.log("sync copy operation, succ:" .. tostring(result.succ) .. ", code:" .. tostring(result.code) .. ", msg:" .. tostring(result.msg))
    return result.succ, result.code, result.msg
end

function _FileBatch.process_batch_copy(map, cb, opts)
    local override = true -- default override is true， 和之前行为保持一致（Android和lua。windows默认都会覆盖）
    opts = opts or {}
    if type(opts.override) == 'boolean' then
        override = opts.override
    end

    _ejoysdk.log("_FileBatch process_batch_copy begin:" .. tostring(override))
    M.async_call(ACT_FILE_BATCH_COPY, { files = map, need_override = override }, '', function(ret)
        ret = ret or {}
        if cb then
            cb(ret.succ, ret.code, ret.msg, ret.result_ext)
        end
    end)
end

function _FileBatch.process_batch_md5(file_list, cb)
    _ejoysdk.log("_FileBatch process_batch_md5 begin:" .. tostring(file_list and #file_list or 0))
    M.async_call(ACT_FILE_BATCH_MD5, { files = file_list }, '', function(ret)
        ret = ret or {}
        if cb then
            ret.result_ext = ret.result_ext or {}
            if ret.succ then
                cb(true, ret.result_ext.succ_data or {})
            else
                cb(false, ret.code, ret.msg, ret.result_ext.succ_data or {}, ret.result_ext.fail_data)
            end
        end
    end)
end

function _FileBatch.process_batch_info(file_list, cb, _opts)
    M.async_call(ACT_FILE_BATCH_INFO, { files = file_list, opts = _opts }, '', function(ret)
        ret = ret or {}
        if cb then
            ret.result_ext = ret.result_ext or {}
            cb(ret.result_ext)
        end
    end)
end

function _FileBatch.process_is_directory(file_path)
    _ejoysdk.log("_FileBatch process_is_directory begin:" .. tostring(file_path))
    local ret = M.sync_call(CT_FILE_IS_DIRECTORY, {path = file_path} )
    ret = ret or {}
    return ret.value, ret.code, ret.msg
end

function _FileBatch.process_list_directory(dir_path, recursive, cb)
    _ejoysdk.log("_FileBatch process_list_directory begin:" .. tostring(dir_path) .. ", recur:" .. tostring(recursive))
    M.async_call(CT_FILE_LIST_DIRECTORY, {path = dir_path, recur = recursive}, '', function(ret)
        ret = ret or {}
        local data = ret.value or {}
        if cb then
            cb(data)
        end
    end)
end

function _FileBatch.process_list_bundle(dir_path, recursive, cb)
    _ejoysdk.log("_FileBatch process_list_bundle begin:" .. tostring(dir_path) .. ", recur:" .. tostring(recursive))
    M.async_call(CT_FILE_LIST_BUNDLE, {path = dir_path, recur = recursive}, '', function(ret)
        ret = ret or {}
        local data = ret.value or {}
        if cb then
            cb(data)
        end
    end)
end

-------- 批量文件实现结束 ----------

return M
