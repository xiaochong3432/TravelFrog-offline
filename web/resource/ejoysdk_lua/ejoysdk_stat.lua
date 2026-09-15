local E = require 'ejoysdk_lua.ejoysdk'
local ET = require 'ejoysdk_lua.ejoysdk_topic'
local UTIL = require 'ejoysdk_lua.ejoysdk_utils'
local uuid = require "ejoysdk_lua.ejoysdk_uuid"
local JSON = require "ejoysdk_lua.ejoysdk_json"
local EM = require "ejoysdk_lua.ejoysdk_module"
local M = {}

local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. "stat"

--设备标识类型
local DEVICE_ID_TYPE_IMEI = 'imei'
local DEVICE_ID_TYPE_IDFA = 'idfa'
local DEVICE_ID_TYPE_GAID = 'gaid'

local acc_info = nil
local dev_info = nil
local chl_info = nil
local game_info = nil
local env_info = nil

local local_ua_cache = nil
local local_umid_token_cache = nil

local LUA_STAT_BIZID = 'sdk.lua.bizid'
local LUA_STAT_ACTION = 'sdk.lua.action'
local LUA_STAT_PUSH = 'sdk.notification.receive'
local acc_info_change_listeners = {}

--[[
acc_info结构
{
       ["accountCh"] => "998233"
       ["chuid"] => "2b358359c7979279efc740412468028a"
       ["chUserType"] => "998233"
       ["accountId"] => "2b358359c7979279efc740412468028a"
    }
--]]
local function on_acc_info_changed()
    E.LOG.debug(TAG, "on_acc_info_changed")
    local _acc_info = M.acc_info()
    for _, lis in ipairs(acc_info_change_listeners) do
        lis(_acc_info)
    end
end

do
    local jf_fill_params_function = function(user_info)
        M.acc_info()
        local account_info = acc_info

        -- 需要额外增加accountCh这个字段，表示账号渠道号
        -- platform国内移动端和PC端都是渠道号，海外PC是渠道号，海外移动端是登陆类型，比如Google，ST_LOGIN这种
        local multi_regions_enabled = E.CONFIG.get_config(E.CONFIG.KEY.MULTI_REGIONS_ENABLED)
        if multi_regions_enabled then
            -- 海外的账号渠道号，三个端保持一致，都是固定值
            account_info.accountCh = '998236' --E.get_channel()
        else
            -- 国内三个端的账号渠道号，可以读取platform字段
            account_info.accountCh = user_info.platform or ''
        end

        -- 这个uid等到进入游戏再读取会更稳，避免acquire时有些场景还没有返回
        account_info.accountId = user_info.uid
        account_info.chuid = user_info.pid

        if user_info.platform ~= nil and user_info.platform ~= '' then
            account_info.chUserType = user_info.platform
        else
            account_info.chUserType = E.get_channel()
        end

        -- 通知acc_info改变
        on_acc_info_changed(account_info)
    end

    ET.subscribe(ET.gangplank.LOGIN, function(user_info)
        jf_fill_params_function(user_info)
        E.log('gangplank LOGIN ---')
        E.log(M.acc_info())
    end)

    ET.subscribe(ET.gangplank.ACQUIRE, function(user_info)
        jf_fill_params_function(user_info)
        E.log('ejoysdk_stat acquire success---')
        E.log(M.acc_info())
    end)

    ET.subscribe(ET.gangplank.USER_INFO_CHANGED, function(user_info)
        jf_fill_params_function(user_info)
        E.log('USER_INFO_CHANGED ---')
        E.log(M.acc_info())
    end)

    ET.subscribe(ET.gangplank.SCAN_LOGIN, function(user_info)
        jf_fill_params_function(user_info)
        E.log('ejoysdk_stat scan_login success---')
        E.log(M.acc_info())
    end)


    ET.subscribe(ET.gangplank.LOGOUT, function()
        -- 退出登陆时清除该字段
        local account_info = acc_info
        account_info.accountCh = ''

        -- 通知acc_info改变
        on_acc_info_changed(account_info)
    end)
end

M.STAT_KEY = {
    -- 是否立即上传
    IS_UPLOAD_NOW = "is_upload_now",
    APUS_ONLY = 'apus_only',
    -- 是否高优先级
    IS_PRIORITY_HIGH = "is_priority_high"
}

function M.acc_info()
    if not acc_info then
        acc_info = {}
    end
    return UTIL.deepcopy(acc_info)
end

function M.dev_info()
    local pkg_info = E.get_pkg_info()
    if not dev_info then
        dev_info = {}
        local storage_info = E.Sysinfo.get_storage_info()
        if storage_info then
            --文档是字符串类型
            dev_info.totalSize = tostring(storage_info.internal_total_storage_size/1024/1024/1024)
        end
        -- 手机设置的语言
        if pkg_info then
            dev_info.language = pkg_info.language
            dev_info.country = pkg_info.country
            dev_info.fr = pkg_info.versions.os_version
            dev_info.brand = pkg_info.brand
            dev_info.ua = pkg_info.ua
            dev_info.uuid = pkg_info.uuid
            dev_info.time_zone = pkg_info.time_zone
            dev_info.hw_machine = pkg_info.hw_machine
            dev_info.model = pkg_info.model
            dev_info.publishArea = pkg_info.publish_area or ''
            dev_info.langScript = pkg_info.lang_script or ''
            dev_info.airline = pkg_info.airline or ''
            dev_info.cloudGameMode = pkg_info.cloud_game_mode or ''
            dev_info.mobileRunMode = pkg_info.cloud_game_runmode or ''
            dev_info.abType = pkg_info.ab_type or ''
        end
        local os = pkg_info.os
        -- todo: iOS目前是待实现, 非必填公参, 后续再补充
        dev_info.net = E.Sysinfo.network_type_name()
        if E.Sysinfo.screen then
            local screenData = E.Sysinfo.screen()
            local h = screenData.height or 0
            local w = screenData.width or 0
            if os == 'windows' then
                --windows都是宽大于高
                dev_info.res = tostring(w) .. '*' .. tostring(h)
            else
                dev_info.res = tostring(h) .. '*' .. tostring(w)
            end
        end
        dev_info.ramSize = E.Sysinfo.memory()

        if not dev_info.ua and local_ua_cache then
            dev_info.ua = local_ua_cache
        end

        if os == 'android' then
            dev_info.os = 'android'
            if pkg_info then
                dev_info.isSimulator = pkg_info.is_simulator
                --get deviceId and deviceIdType
                if pkg_info.imei ~= nil and pkg_info.imei ~= '' then
                    dev_info.deviceId = pkg_info.imei
                    dev_info.deviceIdType = DEVICE_ID_TYPE_IMEI
                elseif pkg_info.gaid ~= nil and pkg_info.gaid ~= '' then
                    dev_info.deviceId = pkg_info.gaid
                    dev_info.deviceIdType = DEVICE_ID_TYPE_GAID
                end
            end
        elseif os == 'ios' then
            dev_info.os = 'ios'
            --get deviceId and deviceIdType
            if pkg_info then
                dev_info.deviceId = pkg_info.idfa
                dev_info.idfv = pkg_info.idfv
                dev_info.idfa = pkg_info.idfa
            end
            dev_info.deviceIdType = DEVICE_ID_TYPE_IDFA
            local ejoyExtInfo = JSON.safe_decode(E.Sysinfo.sysinfo_ejoy_ext_info())
            dev_info.ejoyExtInfo = ejoyExtInfo
        elseif os == 'windows' then
            dev_info.os = 'windows'
            dev_info.caidInfo = {}
            dev_info.cda = {}
            dev_info.weibo = {}
            dev_info.ttDID = ""
            dev_info.uuid = ""
            dev_info.pcAdToken = E.get_pc_ad_token()
        end
    end
    -- 隐私政策合规优化之后，utdid可能从无变有的过程。
    if not dev_info.utdid or dev_info.utdid == '' then
        if pkg_info then
            dev_info.utdid = pkg_info.utdid
        end
    end

    if pkg_info and pkg_info.umid_token and pkg_info.umid_token ~= '' then
        dev_info.umidToken = pkg_info.umid_token
    elseif local_umid_token_cache and local_umid_token_cache ~= '' then
        dev_info.umidToken = local_umid_token_cache
    end

    return UTIL.deepcopy(dev_info)
end

function M.chl_info()
    if not chl_info then
        chl_info = {}

        local pkg_info = E.get_pkg_info()
        chl_info.ch = pkg_info.ds_channel_id or ''
        chl_info.subCh = pkg_info.ds_sub_channel_id or ''
    end
    return UTIL.deepcopy(chl_info)
end

function M.game_info()
    if not game_info then
        game_info = {}
        local pkg_info = E.get_pkg_info()
        game_info.pkgName = pkg_info.pkg_name
        game_info.appVer = pkg_info.versions.app_version_name
        game_info.abType = pkg_info.ab_type
        game_info.ptid = E.get_ptid()
    end
    return UTIL.deepcopy(game_info)
end

function M.env_info()
    if not env_info then
        env_info = {}
        M.acc_info()
        M.dev_info()
        M.chl_info()
        M.game_info()
        env_info.runId = uuid()
        env_info.accInfo = acc_info
        env_info.devInfo = dev_info
        env_info.chInfo = chl_info
        env_info.gmInfo = game_info
    end
    return UTIL.deepcopy(env_info)
end

function M.reset_env_info()
    _ejoysdk.log("reset_env_info begin")
    env_info = nil
    dev_info = nil
    chl_info = nil
    game_info = nil
end

function M.update_umid_token(umid_token)
    local_umid_token_cache = umid_token
    -- update umid token
    if dev_info then
        dev_info.umidToken = umid_token
    end
end

local has_init_public_params = false
local ejoysdk_ver = ''
local lua_ver = ''
local game_ver =''
local os_ver =''
local aligames_ver =''
local security_ver = ''  -- 安全壳的版本
local gamesec_ver = ''  -- 安全SDK的版本

-- 添加lua打点的公参
local function add_public_params(params)
    params = params or {}

    if not has_init_public_params then
        has_init_public_params = true
        local versions = E.get_pkg_info().versions
        if versions then
            ejoysdk_ver = versions.ejoysdk_version
            lua_ver = versions.lua_version
            game_ver = versions.game_version
            os_ver = versions.os_version
            aligames_ver = versions.aligames_version
        end

        local os = E.Sysinfo.os()
        if os == 'android' or os == 'ios' then
            security_ver = E.get_sdk_version_name('SECURITY') or ''
        else
            -- PC端，只有一个PC SDK，没有实际的security插件，所以security_version强制为空串
            security_ver = ''
        end

        local user_info_manager = require "ejoysdk_lua.user_info_manager"
        local mw = user_info_manager.get_mw()
        if mw then
            gamesec_ver = mw.sec_ver
        end
    end
    -- 添加ejoysdk、luasdk 版本，其他公参使用经分SDK的公参即可。
    params.sdk_version = ejoysdk_ver
    params.lua_vesion = lua_ver
    params.game_version = game_ver
    params.os_version = os_ver
    params.aligames_version = aligames_ver
    params.ab_type = E.get_pkg_info().ab_type
    params.security_version = security_ver or ''  -- 安全壳的版本
    params.gamesec_version = gamesec_ver or ''  -- 安全SDK的版本

    -- 添加网络环境
    params.net_type_name = E.Sysinfo.network_type_name()
end

local function commit_event(event_name, params)
    --E.log("commit_event:" .. tostring(event_name) .. ", action:" .. (params and tostring(params.action) or "nil") .. ", params:" .. tostring(JSON.encode(params)))
    add_public_params(params)

    params = params or {}

    local apus_only = params[M.STAT_KEY.APUS_ONLY] or false
    local ETAPUS = require "ejoysdk_lua.ejoysdk_to_apus"
    if apus_only then
        -- 如果接入了apus则上传，windows暂不支持
        ETAPUS.commit_event(event_name, params)
        return
    end

    local JF  = require 'ejoysdk_lua.vendors.jf'

    local is_upload_now = params[M.STAT_KEY.IS_UPLOAD_NOW] or false
    local is_priority_high = params[M.STAT_KEY.IS_PRIORITY_HIGH] or false
    local options = {}
    if is_upload_now then
        options = { [JF.OPTION_KEY.IS_UPLOAD_NOW] = true }
    elseif is_priority_high then
        options = { [JF.OPTION_KEY.IS_PRIORITY_HIGH] = true }
    end

    JF.commit_event(event_name, params, options)

    -- 如果接入了apus则上传，windows暂不支持
    ETAPUS.commit_event(event_name, params)
end

function M.reset_has_init_public_params_flag ()
    has_init_public_params = false
end

-- biz**命名规则是兼容灵犀SDK已有的打点字段
function M.stat_bizid(bizid, biztype, bizresult, params)
    if not params then
        params = {}
    end
    params.bizid = bizid
    params.biztype = biztype
    params.bizresult = bizresult
    commit_event(LUA_STAT_BIZID, params)
end

function M.stat_action(action, action_type, result, params)
    if not params then
        params = {}
    end

    local trim_action = E.Utils.trim(action)
    local trim_action_type = E.Utils.trim(action_type)
    local trim_result = E.Utils.trim(result)
    params.action = trim_action
    params.type = trim_action_type
    params.result = trim_result
    E.LOG.debug(TAG, "stat_action action:" .. tostring(trim_action) .. ", action_type:" .. tostring(trim_action_type) .. ", result:" .. tostring(trim_result))
    E.log(params)
    commit_event(LUA_STAT_ACTION, params)
end

function M.stat_action_apus(action, action_type, result, params)
    if not params then
        params = {}
    end
    params[M.STAT_KEY.APUS_ONLY] = true
    M.stat_action(action, action_type, result, params)
end

function M.flush_cached_events()
    local JF  = require 'ejoysdk_lua.vendors.jf'
    JF.flush_cached_events()
end

function M.stat_fatal_error(action, action_type, result, params)
    if not params then
        params = {}
    end
    params["is_priority_high"] = true
    M.stat_action(action, action_type, result, params)
end

-- relust为false，提取code、msg信息
function M.stat_action_fail(action, action_type, ...)
    local params = {}
    local args = ...
    local args_type = type(args)
    if args_type == 'table' then
        params = args
    else
        local code, msg = ...
        params.code = code
        params.msg = msg
    end

    params.action = action
    params.type = action_type
    params.result = 'false'
    E.LOG.debug(TAG, "stat_action_fail action:" .. tostring(action) .. ", action_type:" .. tostring(action_type) .. ", code:" .. tostring(params.code) .. ", msg:" .. tostring(params.msg))
    commit_event(LUA_STAT_ACTION, params)
end

function M.stat_action_fail_apus(action, action_type, ...)
    local params = {}
    local args = ...
    local args_type = type(args)
    if args_type == 'table' then
        params = args
    else
        local code, msg = ...
        params.code = code
        params.msg = msg
    end

    params.action = action
    params.type = action_type
    params.result = 'false'
    E.LOG.debug(TAG, "stat_action_fail_apus action:" .. tostring(action) .. ", action_type:" .. tostring(action_type) .. ", code:" .. tostring(params.code) .. ", msg:" .. tostring(params.msg))
    M.stat_action_apus(action, action_type, false, params)
end

function M.stat_push(action, action_type, result, params)
    params = params or {}

    local trim_action = E.Utils.trim(action)
    local trim_action_type = E.Utils.trim(action_type)
    local trim_result = E.Utils.trim(result)
    params.action = trim_action
    params.type = trim_action_type
    params.result = trim_result
    E.LOG.debug(TAG, "stat_push action:" .. tostring(trim_action) .. ", action_type:" .. tostring(trim_action_type) .. ", result:" .. tostring(trim_result))
    E.log(params)
    commit_event(LUA_STAT_PUSH, params)
end

function M.get_trace_id()
    local JF  = require 'ejoysdk_lua.vendors.jf'
    return JF.get_trace_id()
end

--[[
    delay_get_ua_state 表示延迟获取UA的状态
    0=还没延迟过
    1=正在延迟中
    2=已经延迟过了
--]]
local delay_get_ua_state = 0
function M.get_jf_format_data(event_name, params, cb)

    add_public_params(params)

    E.LOG.debug(TAG, 'start get_jf_format_data')

    local res = {}

    res.envInfo = M.env_info()
    res.appId = E.get_game_id()
    res.event = event_name
    res.params = params
    res.time = E.time() * 1000

    E.LOG.debug(TAG, 'end get_jf_format_data')

    local userAgent = res.envInfo.devInfo.ua
    if not userAgent or (userAgent == "unknown") then
        if delay_get_ua_state == 0 or delay_get_ua_state == 1 then
            if delay_get_ua_state == 0 then
                delay_get_ua_state = 1
            end
            E.Timer.once(2.5, function()
                delay_get_ua_state = 2
                local_ua_cache = E.Sysinfo.get_user_agent()
                E.LOG.debug(TAG, '延迟获取ua:' .. local_ua_cache)
                if dev_info then
                    dev_info.ua = local_ua_cache
                end

                if not res.envInfo.devInfo.ua and dev_info then
                    res.envInfo.devInfo.ua = dev_info.ua
                end

                cb(res)
            end)
        else
            cb(res)
        end
    else
        cb(res)
    end
end

function M.register_acc_info_change_listener(lis)
    for _, handler in ipairs(acc_info_change_listeners) do
        if handler == lis then
            return
        end
    end
    acc_info_change_listeners[#acc_info_change_listeners + 1] = lis
end

function M.unregister_acc_info_change_listener(lis)
    if acc_info_change_listeners then
        local new = {}
        for _, handler in ipairs(acc_info_change_listeners) do
            if lis ~= handler then
                new[#new + 1] = handler
            end
        end
        acc_info_change_listeners = new
    end
end

local stat_error_cache = {}

-- 带打点上限的经分打点
-- module，模块，可以使用lua文件名
-- stat_key，缓存的key，通过该字段记录打点次数
-- action，需要上报的action
-- action_type，需要上报的action_type
-- param，上报的参数
function M.stat_error_with_limit(module, stat_key, action, action_type, param, max_count)
    if not stat_error_cache[module] then
        stat_error_cache[module] = {}
    end

    local stat_error_cache_one_module = stat_error_cache[module]

    if not stat_error_cache_one_module[stat_key] then
        stat_error_cache_one_module[stat_key] = 1
    end

    -- max_count不传，默认按30次
    if stat_error_cache_one_module[stat_key] <= (max_count or 30) then

        local safe_param = param or {}
        safe_param.count = stat_error_cache_one_module[stat_key]

        M.stat_action(action, action_type, false, safe_param)

        stat_error_cache_one_module[stat_key] = stat_error_cache_one_module[stat_key] + 1
    end
end

-- 命名为action，可以用于常规打点。在语义上区别stat_error_with_limit
M.stat_action_with_limit = M.stat_error_with_limit

function M._test_clear_cache()
    local_ua_cache = nil
    local_umid_token_cache = nil
end

return M