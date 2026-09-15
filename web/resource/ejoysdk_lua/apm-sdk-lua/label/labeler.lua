-------------------------------------------------------------------------------
-- Created Date: 2021.08.08
-- Author: 十影
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local Utils = require "ejoysdk_lua.apm-sdk-lua.common.utils"
local Ver = require "ejoysdk_lua.apm-sdk-lua.version"
local Cfg = require "ejoysdk_lua.apm-sdk-lua.config.configurator"
local apm_stats = require "ejoysdk_lua.apm-sdk-lua.stats.apm_stats"

local NETWORK_NAME = {
    [0] = "default",
    [1] = "unknown", --未知网络类型，例如6G出来，老版本SDK不识别
    [2] = "wifi",
    [3] = "2G",
    [4] = "3G",
    [5] = "4G",
    [6] = "5G"
}

local LOGGER = "apm_label"

local M = {}
M.__index = M

M.get_token_failure = apm_stats:new_counter("failure_get_token", true)

local resource = {}
local attribute_funcs = {}

-- 内建的标签keys 自定义的key不能跟这些keys冲突
local built_in_label_keys = {
    "os",
    "os_ver",
    "device",
    "app_name",
    "app_ver",
    "ejoysdk_ver",
    "apmsdk_ver",
    "game_ver",
    "ej_lua_ver",
    "aligames_ver",
    "network",
    "device_id_type",
    "device_id",
    "oaid",
    "utdid",
    "game_id",
    "channel_id",
    "sub_channel_id",
    "country",
    "env",
    "is_login",
    "collect_interval",
    "cpu_model",
    "uid",
    "game_server",
    "session_id",
    "cpu_score",
    "gpu_score",
    "scene",
    "pos_x",
    "pos_y",
    "pos_z",
    "res",
    "is_simulator",
    "lang_script",
    "publish_area",
    "airline",
    "time_zone",
    "language",
    "game_lang",
    "storage_size",
    "umid_token",
    "uuid",
    "hw_machine",
    "ch_sub_ch",
    "cloud_game_mode",
    "cloud_game_runmode"
}

-- 命名空间 用于区分不同游戏的自定义维度指标名 由游戏方指定
local _namespace = nil

-- 设置命名空间 建议以项目代号指定 如S3,M2,S6等 最大6字节长度
function M.set_namespace(namespace)
    if type(namespace) == "string" and Utils.is_metric_name_valid(namespace) then
        if #namespace >= 6 then
            namespace = string.sub(namespace, 1, 6)
        end
        _namespace = namespace
    end
end

-- 是否命中内建的keys
local function hit_built_in_label_keys(key)
    for _, built_in_key in ipairs(built_in_label_keys) do
        if built_in_key == key then
            return true
        end
    end
    return false
end

-- 刷新token
local function refresh_token()
    local ingester_server = Cfg.get_ingester_server() or ""
    if ingester_server == "" then
        E.LOG.error(LOGGER, "cannot get ingester_server from conf")
        return
    end

    local url = ingester_server .. "/v1/token"
    local app_name = M.get_resource("app_name") or ""
    local utdid = M.get_resource("utdid") or ""

    if app_name == "" or utdid == "" then
        E.LOG.error(LOGGER, "app_name or utdid is empty, unexpected! ")
        return
    end

    local timeout = Cfg.get_http_post_timeout() or 10
    local abnormal_refresh_interval = Cfg.get_abnormal_refresh_token_interval() or 60

    local cb = function(resp)
        if not resp then
            M.get_token_failure:inc()
            return
        end
        local status = tostring(resp.status)
        local resp_body = tostring(resp.body)
        E.LOG.debug(LOGGER, " get_token status=" .. status .. " body:" .. resp_body)
        if resp.status ~= 200 then
            E.LOG.error(LOGGER, "get_token err " .. ",status:" .. status .. " body:" .. resp_body)
            M.get_token_failure:inc()
            resource.token = nil
            -- 400错误是参数错误 没有必要重试 其他错误码都需要重试
            if resp.status ~= 400 then
                E.LOG.debug(LOGGER, " retry refresh_token ...")
                E.Timer.once(abnormal_refresh_interval, refresh_token)
            end
            return
        end
        resource.token = resp_body
    end

    --[[
        获取token的协议
        request:
        POST /v1/token  content-type:application/json
        {"app_name":"...", "utdid":"..."}

        resp:
        200 {"token_str"}
        400 {"err_msg"}
    ]]
    local data = string.format('{"app_name":"%s","utdid":"%s"}', app_name, utdid)
    E.HTTP.post(url, {timeout = timeout}, E.HTTP.CT_JSON, data, cb)
end

local function loop_refresh_token()
    local normal_refresh_interval = Cfg.get_normal_refresh_token_interval() or 21600
    E.Timer.once(normal_refresh_interval, loop_refresh_token)
    E.LOG.debug(LOGGER, "loop_refresh_token ...")
    refresh_token()
end

function M.init() -- luacheck: ignore 561
    -- local game_info = Cfg.get("game_info") or {}
    local env_info = E.get_env_info()
    local pkg_info = E.get_pkg_info()
    local versions = pkg_info.versions
    local tmp_resource = {
        -- 终端操作系统
        os = E.Sysinfo.os() or "",
        -- 终端操作系统版本
        os_ver = E.Sysinfo.os_version() or "",
        -- 设备型号
        device = E.Sysinfo.brand() .. " " .. E.Sysinfo.model(),
        -- App名
        app_name = E.Sysinfo.app_name() or "",
        -- App版本
        app_ver = E.Sysinfo.app_version_name() or "",
        -- EjoySDK版本
        ejoysdk_ver = E.get_sdk_version_name("EJOYSDK") or "",
        -- APM SDK版本
        apmsdk_ver = Ver.VERSION,
        -- 游戏版本
        game_ver = versions and versions.game_version or "",
        -- ejoysdk lua version
        ej_lua_ver = versions and versions.lua_version or "",
        -- 国内独代SDK版本
        aligames_ver = versions and versions.aligames_version or "",
        -- 网络类型
        network = NETWORK_NAME[E.Sysinfo.network_current_state()] or "",
        -- 设备号
        device_id = env_info.devInfo.deviceId or "",
        -- UTDID设备号
        utdid = E.Sysinfo.utdid() or "",
        -- 平台GameID
        game_id = E.get_game_id() or "",
        -- 一级渠道ID
        channel_id = E.Sysinfo.ds_channel_id() or "",
        -- 二级渠道ID
        sub_channel_id = env_info.chInfo.subCh,
        -- 国家
        country = E.Sysinfo.country(),
        -- 环境名
        env = E.CONFIG.get_config("product"),
        -- 是否登录
        is_login = "0",
        -- 采集间隔
        collect_interval = Cfg.get(Cfg.CATEGORY_STATS, "collect_interval", 60),
        -- cpu模型
        cpu_model = E.Sysinfo.get_cpu_model() or "",
        -- 包名(渠道名)
        pkg_name = E.Sysinfo.package_name() or "",
        -- 分辨率
        res = env_info.devInfo.res or "",
        -- 是否模拟器
        is_simulator = env_info.devInfo.isSimulator,
        -- 设备ID类型
        device_id_type = env_info.devInfo.deviceIdType or "",
        -- 语言和变体
        lang_script = env_info.devInfo.langScript or "",
        -- 发布地区
        publish_area = env_info.devInfo.publishArea,
        -- airline
        airline = env_info.devInfo.airline,
        -- time_zone
        time_zone = env_info.devInfo.time_zone,
        -- 语言
        language = env_info.devInfo.language,
        -- 存储空间
        storage_size = env_info.devInfo.totalSize,
        -- 云游模式：cloud 云端包，mobile: 本地包
        cloud_game_mode = pkg_info.cloud_game_mode,
        -- 云游运行模式：
        -- run_connect_remote：连接云游玩
        -- run_in_cloud_side：在云端运行
        -- run_with_local_resource：本地下载完资源，大包玩
        cloud_game_runmode = pkg_info.cloud_game_runmode,
        umid_token = env_info.devInfo.umidToken or "",
        -- ios 取应用唯一标识idfv
        uuid = env_info.devInfo.uuid or "",
        -- hw_machine:
        -- 1. Android留空
        -- 2. ios 取 hw.machine 的值
        hw_machine = env_info.devInfo.hw_machine,
        -- 游戏内部语言设置
        game_lang = pkg_info.game_lang,
        -- oaid
        oaid = pkg_info.oaid
    }

    -- label模块的初始化 有可能在set_static_label之后，防止set_static_label的内容丢失，这里要做merge
    resource = Utils.merge_table(resource, tmp_resource, false)

    -- 登录后设置的一些属性
    ET.subscribe(
        ET.gangplank.SET_PLAYER_INFO,
        function(player_info)
            E.LOG.debug(LOGGER, "Got player info")
            -- E.LOG.debug('apm', player_info)
            resource.uid = player_info.player_id -- 游戏里自定义的角色ID 跟游戏服变化而变化
            resource.account = player_info.uid -- 平台统一的账号信息，不会变
            resource.game_server = player_info.server_id
            resource.session_id = E.get_pkg_info().sdk_trace_id
            resource.is_login = "1"
        end
    )

    -- 角色登出后，reset角色相关的属性
    ET.subscribe(
        ET.gangplank.PLAYER_OFFLINE or "player_offline",
        function()
            E.LOG.debug(LOGGER, "logout player info")
            resource.uid = nil -- 游戏里自定义的角色ID 跟游戏服变化而变化
            resource.game_server = nil
            resource.is_login = "0"
        end
    )

    ET.subscribe(
        ET.gangplank.LOGOUT,
        function()
            resource.is_login = "0"
        end
    )

    ET.subscribe(
        "network_state_change",
        function()
            resource.network = NETWORK_NAME[E.Sysinfo.network_current_state()] or ""
            refresh_token()
        end
    )

    -- 用到时再require，防止ejoysdk init时报错
    local EH = require "ejoysdk_lua.ejoysdk_holo"
    EH.get_device_score(
        function(succ, info)
            if succ then
                resource.cpu_score = info.cpu
                resource.gpu_score = info.gpu
                E.LOG.debug(LOGGER, "apus_modules cpu_score: " .. info.cpu)
            else
                E.LOG.error(LOGGER, "apus_modules get cpu_score fail")
            end
        end
    )

    loop_refresh_token()

    E.LOG.debug(LOGGER, "Labeler initialized.")
    E.LOG.debug(LOGGER, resource)
end

function M.get_resource(key)
    if key == nil then
        return resource
    else
        return resource[key]
    end
end

-- 画质 (0:超高 1:高 2:中 3:低 4:超低)
function M.set_quality_level(level)
    resource.quality_lv = level
end

-- 机型分档信息 (0:超高 1:高 2:中 3:低 4:超低)
function M.set_device_level(level)
    resource.device_lv = level
end

-- 游戏版本
function M.set_game_version(version)
    resource.game_ver = version
end

-- 登录类型（1:正常登录, 2:断线重连）
function M.set_login_type(ltype)
    resource.login_type = ltype
end

-- 登录后端返回码
function M.set_login_ret(ret)
    resource.login_ret = ret
end

-- 登录后的回调函数
function M.set_login_func(func)
    if func == nil then
        return
    end
    ET.subscribe(
        ET.gangplank.SET_PLAYER_INFO,
        function(player_info) -- luacheck: ignore 212
            E.LOG.debug(LOGGER, "login detected")
            Utils.exec(func)
        end
    )
end

-- 登出后的回调函数
function M.set_logout_func(func)
    if func == nil then
        return
    end
    ET.subscribe(
        ET.gangplank.LOGOUT,
        function(player_info) -- luacheck: ignore 212
            E.LOG.debug(LOGGER, "logout detected")
            Utils.exec(func)
        end
    )
end

local function is_custom_key_valid(key)
    if type(key) ~= "string" or key == "" then
        return false
    end
    return not hit_built_in_label_keys(key)
end

local function concate_key(key)
    if _namespace then
        return _namespace .. "_" .. key
    end
    return key
end

-- just for ut
M.is_custom_key_valid = is_custom_key_valid

-- 设置自定义的静态标签
function M.set_static_label(key, value)
    if is_custom_key_valid(key) then
        resource[concate_key(key)] = tostring(value)
    end
end

-- 设置自定义的动态标签，提供获取标签值的方法和参数
function M.add_dynamic_label(key, func, ...)
    if func == nil then
        return
    end
    if is_custom_key_valid(key) then
        attribute_funcs[concate_key(key)] = {func, {...}}
    end
end

-- 删除自定义的动态标签
function M.del_dynamic_label(key)
    if is_custom_key_valid(key) then
        attribute_funcs[concate_key(key)] = nil
    end
end

-- 设置获取场景的方法
function M.set_scene_func(func)
    if func == nil then
        return
    end
    attribute_funcs["scene"] = {func}
end

-- 坐标。提供获取坐标的方法，支持三维，可以只使用二维。
function M.set_position_func(func)
    if func == nil then
        return
    end
    M.position_func = func
end

function M.get_attributes()
    local attributes = {}
    for name, func_args in pairs(attribute_funcs) do
        local func = func_args[1]
        local args = func_args[2]
        local v = Utils.exec(func, args)
        if v ~= nil then
            attributes[name] = tostring(v)
        end
    end

    if M.position_func ~= nil then
        local pos_x, pos_y, pos_z = Utils.exec(M.position_func)
        attributes["pos_x"] = pos_x
        attributes["pos_y"] = pos_y
        attributes["pos_z"] = pos_z
    end
    return attributes
end

-- just for ut
function M.set_is_login(is_login)
    resource.is_login = is_login
end

local first_time_upload_log = true

-- minimise_resource 最小化标签的数量
function M.minimise_resource(res)
    if type(res) ~= "table" or next(res) == nil then
        return res
    end

    -- 不开启最小化标签数量
    if not Cfg.enable_minimised_log_labels() then
        return res
    end

    -- 第一次日志上报 上报全量标签
    if first_time_upload_log then
        first_time_upload_log = false
        return res
    end

    local whitelist_labels = Cfg.get_log_whitelist_labels()
    if type(whitelist_labels) ~= "table" or next(whitelist_labels) == nil then
        return res
    end

    local minimised_resource = {}
    for _, key in ipairs(whitelist_labels) do
        if res[key] ~= nil then
            minimised_resource[key] = res[key]
        end
    end

    -- 必须带上的标签
    minimised_resource.env = res.env

    return minimised_resource
end

return M
