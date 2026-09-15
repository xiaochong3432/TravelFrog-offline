local E = require "ejoysdk_lua.ejoysdk"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local UNI = require "ejoysdk_lua.vendors.unisdk"
local Vendor = require "ejoysdk_lua.vendors.vendor"
local UIM = require "ejoysdk_lua.user_info_manager"
local JF_WINDOWS = require 'ejoysdk_lua.jf.jf_windows'
local EM = require "ejoysdk_lua.ejoysdk_module"
--经分SDK
local CHANNEL = "JF"

local M = Vendor:Inherit(CHANNEL)

local TAG = EM.MODULE.VENDORS.JF
--初始化经分
local CAST_INIT_JF = "CAST_INIT_JF"
--经分打点
local CAST_COMMIT_EVENT = "CAST_COMMIT_EVENT"
local CAST_UPLOAD_EVENT = "CAST_UPLOAD_EVENT" -- 直接HTTP上传，失败再落地
--经分更新数据
local CAST_UPDATE_DATA = "CAST_UPDATE_DATA"
--更新经分的设备信息
local CAST_UPDATE_DEVICE_INFO = "CAST_UPDATE_DEVICE_INFO"
--是否支持高优先级提交
local SYNC_IS_SUPPORT_PRIORITY_HIGH = "SYNC_IS_SUPPORT_PRIORITY_HIGH"

--时间常量
--local TIME_MILLS_SECOND = 1000
--local TIME_MILLS_MINUTE = 60 * 1000

--默认经分参数白名单
local DEFAULT_WHITE_PRIVACY_FIELDS = {
    'brand','model','mac','country','lang','ramSize','availRamSize','hwf','fr', 'cpu'
}

local cp_white_privacy_fields = DEFAULT_WHITE_PRIVACY_FIELDS

local uid = nil
local pid = nil
local platform = nil
local jf_inited = false
local open_pre_order = false -- 是否检查预约打点
local log_collector_host = nil
local cached_commit_events = {}

-- 注意：system_clock的Android自定义实现返回的系统启动时间戳，与os.time有区别，
local init_time = E.system_clock()
local trace_id = nil

M.EVENT_NAMES = {
    --端启动
    SDK_START_UP = "sdk.startup",
    --游戏外，链接拉起
    SDK_START_UP_LINK_LAUNCH = "sdk.startup.link_launch",
    --端启动成功
    SDK_START_UP_SUCCESS = "sdk.startup.success",
    --登录角色成功
    SDK_ROLE_ONLINE = "sdk.role.online",
    --创建角色成功
    SDK_ROLE_CREATE = "sdk.role.create",
    --角色升级
    SDK_ROLE_LEVEL_UP = "sdk.role.levelup",
    --预约用户启动打点
    SDK_START_UP_PRE_ORDER = "sdk.startup.pre_order",
}

M.EVENT_OCCASION = {
    ENTERGAME = "enterGame";
    UPDATES = "updates";
    CREATEROLE = "createRole";
    EXITGAME = "exitGame";
}

M.OPTION_KEY = {
    -- 是否立即上传
    IS_UPLOAD_NOW = "is_upload_now",
    -- 高优先级
    IS_PRIORITY_HIGH = "is_priority_high"
}

local function is_support_priority_high()
    local ret = UNI.sync_call(CHANNEL, SYNC_IS_SUPPORT_PRIORITY_HIGH, {}, nil)
    local support = (ret and ret['support']) or false
    return support
end

local function uni_cast(channel, cast_commit_event, event_params)
    if E.Sysinfo.os() == 'windows' then
        return
    end
    if jf_inited then
        UNI.cast(channel, cast_commit_event, event_params)
    end
end

function M.flush_cached_events()
    -- first check cached events and send them
    if next(cached_commit_events) ~= nil then
        E.LOG.debug(TAG, "has cache now commit cached events:" .. tostring(#cached_commit_events))
        for _, cached_data in ipairs(cached_commit_events) do
            -- E.LOG.debug(TAG, "recommit cached event:" .. tostring(cached_data.event_name))
            if E.Sysinfo.os() == 'windows' then
                JF_WINDOWS.commit_event(cached_data)
            else
                UNI.cast(CHANNEL, CAST_COMMIT_EVENT, cached_data)
            end
        end

        cached_commit_events = {}
    end
end

M.enable_ldu = false
-- 调用经分SDK打点
-- 为避免与默认事件冲突，事件名不能以'sdk.'开头
-- options: is_upload_now: 是否立即上传 （注：非必须情况，不要用is_upload_now，如果优先级比较高，可以使用is_priority_high)
-- options: is_priority_high: 是否高优先级(延迟5s上传)
function M.commit_event(event_name, params, options)
    if params == nil then
        params = {}
    end

    if type(params) == "table" then
        params.trace_id = M.get_trace_id()
        params.trace_uptime = E.system_clock() - init_time
    end

    -- is_upload_now 有另一层意思是主路径，方便过滤统计
    local is_upload_now_str = tostring(options and options[M.OPTION_KEY.IS_UPLOAD_NOW] or nil)
    local is_priority_high_str = tostring(options and options[M.OPTION_KEY.IS_PRIORITY_HIGH] or nil)
    params[M.OPTION_KEY.IS_UPLOAD_NOW] = is_upload_now_str
    params[M.OPTION_KEY.IS_PRIORITY_HIGH] = is_priority_high_str

    -- ios在lua解析options后换个接口来支持立即上传功能
    local event_params = {
        event_name = event_name,
        params = params,
        opts = options
    }

    if jf_inited then
        -- first check cached events and send them
        M.flush_cached_events()

        E.LOG.debug(TAG, "commit_event event_name:" .. tostring(event_name))
        if E.Sysinfo.os() == 'windows' then
            JF_WINDOWS.commit_event(event_params)
        elseif E.Sysinfo.os() == 'ios' then
            if options and string.lower(is_upload_now_str) == 'true' then
                uni_cast(CHANNEL, CAST_UPLOAD_EVENT, event_params)
            else
                -- native侧，会取event_params.opts.is_priority_high字段，判断是否高优先级
                uni_cast(CHANNEL, CAST_COMMIT_EVENT, event_params)
            end
        else
            -- native侧，会取event_params.opts.is_upload_now字段，判断是否立即上报
            -- native侧，会取event_params.opts.is_priority_high字段，判断是否高优先级
            uni_cast(CHANNEL, CAST_COMMIT_EVENT, event_params)
        end
    else
        E.LOG.debug(TAG, "commit_event save to cache, event_name:" .. tostring(event_name))
        table.insert(cached_commit_events, event_params)
    end
end

-- 更新经分参数
local function update_data(params)
    if E.Sysinfo.os() == 'windows' then
        JF_WINDOWS.update_data(params)
    else
        uni_cast(CHANNEL, CAST_UPDATE_DATA, params)
    end
end

local function ejoysdk_config_changed_handler()
    local host = E.CONFIG.get_config("log-collector")
    E.LOG.debug(TAG, 'ejoysdk_config_changed_handler entered, get host:'..(host or 'nil')..', last host:'..(log_collector_host or 'nil'))
    if host ~= log_collector_host then
        log_collector_host = host

        local jf_api_server = host .. '/log/gbi_log'
        local params = {
            api_server = jf_api_server
        }
        E.LOG.debug(TAG, 'ejoysdk_config_changed_handler，update api_server of JF:' .. tostring(jf_api_server))
        update_data(params)
    end
end

-- 根据规则获取事件黑名单列表
local function get_black_event_arr(cloud_mode)
    local black_events = {}

    if cloud_mode then
        local CC = require "ejoysdk_lua.cloud_game.cloud_config"
        if cloud_mode == CC.CLOUD_MODE.CLOUD then
            E.LOG.debug(TAG, "get_black_event_arr, its cloud side, so it has black event array")
            -- 黑名单规则为sdk.开头的事件
            black_events["type"] = "event_arr"
            black_events["data"] = {"sdk.role.online", "sdk.role.create","sdk.role.level.up","sdk.user.create","sdk.user.online","sdk.startup","sdk.startup.success","sdk.install","sdk.startup.native","sdk.list","sdk.heartbeat"}
            return black_events
        end
    end

    E.LOG.debug(TAG, "no black commit events")
    return nil
end

--初始化经分
local function init_jf_sdk(opt)
    --local cert_info = E.get_cert_info()
    --触发lua模拟器判断逻辑,设置模拟器判断值给ejoysdk native，安卓经分从ejoysdk native中获取
    if E.Sysinfo.os() == 'android' then
        E.Sysinfo.is_simulator()
    end
    local ch = E.get_channel()
    local game_id = tostring(E.get_game_id())

    log_collector_host = E.CONFIG.get_config("log-collector")
    local jf_api_server = log_collector_host .. '/log/gbi_log'
    E.LOG.debug(TAG, 'init_jf_sdk, jf_api_server:' .. tostring(jf_api_server))

    if opt and opt.launch_delay_report and type(opt.launch_delay_report) == 'boolean' then
        M.update_launch_delay_report(opt.launch_delay_report)
    end

    local has_cp_set_white_fields = type(opt.white_privacy_fields)
    if has_cp_set_white_fields == "table" then
        cp_white_privacy_fields = opt.white_privacy_fields
    else
        -- 国内游戏，如果游戏没有设置opt.white_privacy_fields，则默认加上imei，为了买量oaid的上报
        local is_overseas = E.CONFIG.get_config(E.CONFIG.KEY.MULTI_REGIONS_ENABLED)
        if not is_overseas then
            table.insert(cp_white_privacy_fields, 'imei')
        end
    end

    local ds_channel_id = nil
    local ds_sub_channel_id = nil
    if E.Sysinfo.os() == 'android' or E.Sysinfo.os() == 'ios' then
        ds_channel_id = E.Sysinfo.ds_channel_id()
        ds_sub_channel_id = E.Sysinfo.ds_sub_channel_id()
    end

    -- 尝试获取云游模式
    local cloud_info = UIM.get_cloud_game_info()
    local cloud_mode = cloud_info[UIM.PKG_INFO_KEY.KEY_CLOUD_GAME_MODE]
    local cloud_run_mode = cloud_info[UIM.PKG_INFO_KEY.KEY_CLOUD_GAME_RUN_MODE]
    local black_events = get_black_event_arr(cloud_mode)

    -- 获取是否是instant模式
    local instant_mode = UIM.get_instant_mode() or 'normal'
    E.LOG.debug(TAG, "instant mode >> " .. tostring(instant_mode))

    -- 获取是否预约包模式
    local predownload_game_mode = UIM.get_predownload_game_mode()
    if predownload_game_mode and predownload_game_mode[UIM.PKG_INFO_KEY.KEY_PREDOWNLOAD_GAME_RUN_MODE] then
        cloud_run_mode = predownload_game_mode[UIM.PKG_INFO_KEY.KEY_PREDOWNLOAD_GAME_RUN_MODE]
    end

    local install_referrer = E.Sysinfo.get_ejoy_referer() or 'none'
    E.LOG.debug(TAG, "install referrer >> " .. tostring(install_referrer))
    -- 获取buildId
    local apk_build_seq = E.get_apk_build_seq()
    -- 获取ptid
    local ptid = E.get_ptid()

    local init_param = {
        white_privacy_fields = cp_white_privacy_fields,
        white_event_prefix_arr = {
            'ejoy.',"gamesec."
        },
        upload_internal_events_enable = false,
        api_server = jf_api_server,
        channel_id = ch,
        game_id = game_id,
        debuggable = opt.debug or false,
        ds_ch_id = ds_channel_id,
        ds_sub_ch_id = ds_sub_channel_id,
        -- iOS Only
        debug = opt.debug or false,
        utdid = E.Sysinfo.utdid(),
        forbidden_keys = {
            'mac', 'imei'
        },
        cloud_game_mode = cloud_mode,
        cloud_game_run_mode = cloud_run_mode,
        black_event_arr = black_events,
        instantMode = instant_mode,
        installReferrer = install_referrer,
        apk_build_seq = apk_build_seq,
        ptid = ptid
    }

    if E.Sysinfo.os() == 'windows' then
        JF_WINDOWS.init(init_param)
    else
        uni_cast(CHANNEL, CAST_INIT_JF, init_param)
    end

    E.LOG.debug(TAG, "is_support_priority_high(native): " .. tostring(is_support_priority_high()))

    --JF_WINDOWS.init(init_param)
    --监听ejoysdk_config变化
    ET.subscribe(ET.config.CONFIG_CHANGED, ejoysdk_config_changed_handler)

    open_pre_order = opt.open_pre_order or false
end

local player_offline_handler = function()
    --经分sdk 设置角色打点
    local params = {
        server_id = '',
        server_name = '',
        player_id = '',
        player_name = '',
        player_level = '',
        uid = uid or ''
    }
    E.LOG.debug(TAG, 'player_offline_handler，update role data of JF')
    update_data(params)
end

local set_player_info_handler_with_type = function(player_info, _type)
    --经分sdk 设置角色打点
    local params = {
        server_id = player_info.server_id,
        server_name = player_info.server_name,
        player_id = player_info.player_id,
        player_name = player_info.player_name,
        player_level = player_info.player_level,
        uid = uid or ''
    }
    E.LOG.debug(TAG, 'setPlayerInfo，update role data of JF')
    update_data(params)

    --local event_name = nil
    --if type == M.EVENT_OCCASION.UPDATES then
    --    event_name = M.EVENT_NAMES.SDK_ROLE_LEVEL_UP
    --elseif type == M.EVENT_OCCASION.CREATEROLE then
    --    event_name = M.EVENT_NAMES.SDK_ROLE_CREATE
    --elseif type == M.EVENT_OCCASION.ENTERGAME then
    --    event_name = M.EVENT_NAMES.SDK_ROLE_ONLINE
    --end
    --
    ----设置角色信息打点
    --M.commit_event(event_name, params)
end

local set_player_info_handler = function(_player_info)

end

local login_handler = function(user_info)
    --登录成功打点
    uid = user_info.uid;
    pid = user_info.pid;
    platform = user_info.platform

    -- update stat account param
    local params = {
        uid = uid,
        chuid = pid,
        chUserType = platform,
        server_id = '',
        server_name = '',
        player_id = '',
        player_name = '',
        player_level = ''
    }
    E.LOG.debug(TAG, 'login，clear cached role data and update account data of JF')
    update_data(params)
end

local function gangplank_logout_handler()
    --登出成功，更新经分数据
    uid = ''
    pid = ''
    platform = ''
    -- update stat account param
    local params = {
        server_id = '',
        server_name = '',
        player_id = '',
        player_name = '',
        player_level = '',
        uid = '',
        chuid = '',
        chUserType = ''
    }
    E.LOG.debug(TAG, 'logout，clear cached account and role data of JF')
    update_data(params)
end

local function gangplank_exit_handler()
    uid = ''
    pid = ''
    platform = ''
    -- update stat account param
    local params = {
        server_id = '',
        server_name = '',
        player_id = '',
        player_name = '',
        player_level = '',
        uid = '',
        chuid = '',
        chUserType = ''
    }
    E.LOG.debug(TAG, 'exit，clear cached account and role data of JF')
    update_data(params)
end

local function has_value (table, val)
    local tab = table or {}
    for _, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

local STAT_PRE_ORDER_STATUS = E.LazyKeyStore:New("EJOY_STAT_PRE_ORDER_STATUS", false, false, false)
local function commit_pre_order_status()
    local post_status = 'posted'
    local status = STAT_PRE_ORDER_STATUS:get()
    if status == post_status then
        -- 已经请求,跳过
        E.LOG.debug(TAG,"pre-order#has been counted pre_order status")
        return
    else
        E.LOG.debug(TAG,"pre-order#getting pre-order status")
        E.get_pre_order_status(function(post_succ, is_pre_order_user)
            if is_pre_order_user == true then
                -- 预约用户打点
                E.LOG.debug(TAG,"pre-order# pre_order status not count yet, commit now")
                M.commit_event(M.EVENT_NAMES.SDK_START_UP_PRE_ORDER,nil,{[M.OPTION_KEY.IS_UPLOAD_NOW] = true,[M.OPTION_KEY.IS_PRIORITY_HIGH] = true})
            end
            if post_succ == true then
                STAT_PRE_ORDER_STATUS:set(post_status)
                if is_pre_order_user == false then
                    E.LOG.debug(TAG,"pre-order#not target pre-order user")
                end
            end
        end)
    end
end

local function gangplank_inited_handler(succ, ...)
    E.LOG.debug(TAG, 'jinfen gangplank_inited_handler! ' .. tostring(succ))

    local is_imei_in_white_field = has_value(cp_white_privacy_fields, 'imei')
    local is_imei_in_white_field_result
    if is_imei_in_white_field then
        is_imei_in_white_field_result = 'true'
    else
        is_imei_in_white_field_result = 'false'
    end
    E.LOG.debug(TAG, 'jinfen gangplank_inited_handler, is_imei_in_white_field: ' .. tostring(is_imei_in_white_field_result))
    -- stat init success
    -- 按照工信部的要求不申请READ_PHONE_STATE权限，留在aligames申请
    --if E.Sysinfo.os() == 'android' and is_imei_in_white_field then
    --    _ejoysdk.log('xdata# jinfen gangplank_inited_handler! start request read phone state permission:')
    --    E.Permission.check_permission_v2("android.permission.READ_PHONE_STATE", function(succ2, ...)
    --        local result
    --        if succ2 then
    --            result = 'true'
    --        else
    --            result = 'false'
    --        end
    --        _ejoysdk.log('xdata# jinfen gangplank_inited_handler! check permission callback:'..result)
    --        M.commit_event(M.EVENT_NAMES.SDK_START_UP_SUCCESS)
    --    end)
    --else
    --    M.commit_event(M.EVENT_NAMES.SDK_START_UP_SUCCESS)
    --end

    local params = {}

    local url_open_datas = E.get_url_open_datas()
    if url_open_datas and next(url_open_datas) ~= nil and url_open_datas[1] ~= nil then
        local link_data = url_open_datas[1]
        -- 只有url字符串有值，才赋值link_data字段
        if link_data.url and type(link_data.url) == 'string' and #(link_data.url) > 0 then
            -- 走这个分支，说明是从get_last_openurl_data获取到数据
            params = {link_data=link_data}
        elseif link_data.data and link_data.data.url and type(link_data.data.url) == 'string' and #(link_data.data.url) > 0 then
            -- 走这个分支，说明是从 UTILS.deepcopy(url_open_datas) 获取到数据
            -- 把 link_data.data.url 提到 link_data.url 外面来，发行侧是读取的link_data.url这个字段
            link_data.url = link_data.data.url
            params = {link_data=link_data}
        end
    end

    M.commit_event(M.EVENT_NAMES.SDK_START_UP_SUCCESS, params, {[M.OPTION_KEY.IS_UPLOAD_NOW] = true})

    -- 预约打点，需要依赖si等初始化环境，放到初始化后再上报

    if(open_pre_order == true) then
        commit_pre_order_status()
    end
end

local function update_jf_pkg_info(pkg_info_data)
    E.LOG.debug(TAG, "its pkg_info changed, now update jf data >>>>")
    E.LOG.debug(TAG, pkg_info_data)

    uni_cast(CHANNEL, CAST_UPDATE_DEVICE_INFO, pkg_info_data)
end

local function update_cloud_game_info(cloud_game_info)
    E.LOG.debug(TAG, "its cloud_game_info changed, now update jf data >>>>")
    E.LOG.debug(TAG, cloud_game_info)

    local params = {
        cloud_game_run_mode = cloud_game_info[UIM.PKG_INFO_KEY.KEY_CLOUD_GAME_RUN_MODE]
    }
    E.LOG.debug(TAG, 'update_cloud_game_info, cloud_game_run_mode:' .. tostring(params.cloud_game_run_mode))
    update_data(params)
end

local function on_pkg_info_changed(data)
    E.LOG.debug(TAG, "on_pkg_info_changed >>")
    E.LOG.debug(TAG, data)

    if not data or next(data) == nil then
        E.LOG.warn(TAG, "on_pkg_info_changed data is nil")
        return
    end

    local data_type = data[UIM.TOPIC_DATA_KEY.KEY_DATA_TYPE]
    if data_type == UIM.INFO_KEY.KEY_PKG_INFO then
        E.LOG.debug(TAG, "receive pkg info changed")
        local pkg_info_data = data[UIM.TOPIC_DATA_KEY.KEY_DATA]
        update_jf_pkg_info(pkg_info_data)
    elseif data_type == UIM.INFO_KEY.KEY_CLOUD_GAME_INFO then
        E.LOG.debug(TAG, "receive cloud game info changed:" .. tostring(data_type))
        local cloud_game_info = data[UIM.TOPIC_DATA_KEY.KEY_DATA]
        update_cloud_game_info(cloud_game_info)
    end
end


function M.init(opt, cb)
    --if E.Sysinfo.os() == 'windows' then
    --    jf_inited = false
    --
    --    -- callback init success
    --    cb(true)
    --    return
    --end

    E.LOG.debug(TAG, 'jinfen stat start init!')

    -- 初始化经分sdk
    jf_inited = true
    init_jf_sdk(opt)

    -- 游戏启动打点
    M.commit_event(M.EVENT_NAMES.SDK_START_UP)

    ET.subscribe(ET.gangplank.LOGIN, login_handler)
    ET.subscribe(ET.gangplank.LOGOUT, gangplank_logout_handler)
    ET.subscribe(ET.gangplank.EXIT, gangplank_exit_handler)
    ET.subscribe(ET.gangplank.INITED, gangplank_inited_handler)
    --设置角色打点是游戏来打，ejoysdk不需要处理
    ET.subscribe(ET.gangplank.SET_PLAYER_INFO_WITH_TYPE, set_player_info_handler_with_type)
    ET.subscribe(ET.gangplank.PLAYER_OFFLINE, player_offline_handler)

    ET.subscribe(ET.gangplank.SET_PLAYER_INFO, set_player_info_handler)

    --监听本地设备信息变更
    local user_pkg_info = UIM.get_user_pkg_info()
    if not user_pkg_info then
        ET.subscribe(UIM.TOPIC.TOPIC_INFO_CHANGES, on_pkg_info_changed)
    else
        update_jf_pkg_info(user_pkg_info)
    end


    -- callback init success
    cb(true)
end

function M.get_trace_id()
    trace_id = E.get_pkg_info().sdk_trace_id
    E.LOG.debug(TAG, "get_trace_id use trace_id:" .. tostring(trace_id))

    return trace_id
end

function M.disable_pc_media_event()
    JF_WINDOWS.disable_media_event()
end

-- jf 包含统计
M:is_implemented({Vendor.ABILITY.STATS})

return M