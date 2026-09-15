local E = require "ejoysdk_lua.ejoysdk"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local EM = require "ejoysdk_lua.ejoysdk_module"
local M = {}

local TAG = EM.MODULE.CLOUD_GAME .. "cloud_config"

--资源下载的url，cdn是在该url中配置的
--该url由网络请求下发
M.REMOTE_URLS = ""
M.SaveAssetDir = nil
-- E.CONFIG.autoconfig
M.ProductId = nil
M.ProductIdAppleReview = nil
--下载完资源能继续游玩的时间，分钟
M.FinishDownloadContinuePlayTime = 30
--云端游戏游玩时间限制
M.CloudGamePlayTimeLimit = 120
--并行下载个数
M.HttpJobCnt = 8
-- 默认最小下载速度
M.DEFAULT_MIN_DOWN_SPEED = 200
-- 默认最大下载速度, 注意！这个单位是KByte, 但是传给游戏或者云游SDK的单位都是bit
M.DEFAULT_MAX_DOWN_SPEED = 1024 * 125
--限速每秒多少kBype(-1或者不配置表示不限速)
M.HttpKpsLimit = 900 * 1
--限速检查间隔
--修改至0.2目的是解决计算下载速度时的误差，另外加快限速的响应速度
M.HttpIntervalLimit = 0.2
--http下载的大小一般会压缩下，这里加个修正，避免玩家看到太大
M.DownloadSizeFix = 0.8
--下载百分比超过多少的时候就显示
M.ShowProgressByPercent = 50
--native缓存大小
M.READ_BUFFER_SIZE_BYTES = 4 * 1024
-- 是否对wifi限速
M.is_limit_speed_for_wifi = true

local DEFAULT_UPDATE_WITH_CONNECT_LIMIT = 500 * 1024 * 1024
-- 覆盖安装更新资源时是否现实连接云端的大小限制
M.UPDATING_WITH_CONNECT_LIMIT = DEFAULT_UPDATE_WITH_CONNECT_LIMIT

-- 95%的时候显示下载即将完成发tips
M.ShowDownloadCompleteTipsPercent = 95

-- 跳转大包提示的时间间隔，默认15分钟
M.LaunchInstalledPkgTipInterval = 60 * 15

-- 云游连接成功后，首次展示下载打包气泡的时间，默认10分钟
M.ShowInstallPkgFloaterDelay = 60 * 10

-- 非首次展示下载打包气泡的时间间隔，默认30分钟
M.ShowInstallPkgFloaterInterval = 60 * 30

-- 浮窗面板上面显示的剩余试玩时长文案模版
M.RemainTimeTemplete = '剩余时长：${remainTimeTick}。（每天重置10小时）'



M.CLOUD_TOPIC = {
    TOPIC_LUA_CLOSED = "cloud_game_topic_lua_closed",
    TOPIC_ACTIVITY_STATE_CHANGED = "cloud_game_activity_state_changed",
    TOPIC_ACTIVITY_STATE_CHANGED_INNER = "cloud_game_activity_state_changed_inner",
    TOPIC_DOWNLOAD_STATE_CHANGED = "cloud_game_download_state_changed",
    TOPIC_LIMIT_STATE_CHANGE = "cloud_game_limit_state_changed"
}

--[[
0: 默认值，什么控制也没有
1: 放开了限速
其它值暂时留着
--]]
M.DOWNLOAD_LIMIT_CONTROL_STATE = {
    STATE_DEFAULT = 0,
    STATE_NO_LIMIT = 1
}

M.ACTIVITY_STATE = {
    ON_START = "onStart",
    ON_STOP = "onStop"
}

local function is_limit_for_current_net_type()
    local net_type_name = E.Sysinfo.network_type_name()
    local limit_result
    if net_type_name == "wifi" and not M.is_limit_speed_for_wifi then
        limit_result = false
    else
        limit_result =  true
    end

    E.LOG.debug(TAG, "is_limit_for_current_net_type net_type_name:" .. tostring(net_type_name) .. ", limit_result:" .. tostring(limit_result))
    return limit_result
end

function M.get_http_kps_limit()
    local speed
    if M.force_http_kps then
        speed = M.force_http_kps
    else
        if M.server_config_http_kps_limit and is_limit_for_current_net_type() then
            speed = M.server_config_http_kps_limit
        else
            speed = M.HttpKpsLimit
        end
    end

    E.LOG.debug(TAG, "[download]get_http_kps_limit:" .. tostring(speed))
    return speed
end

-- -1表示不限速,nil恢复原来速度
function M.force_http_kps_limit(kps)
    E.LOG.debug(TAG,"[download]force_http_kps_limit " .. tostring(kps))
    M.force_http_kps = kps

    if kps == -1 then
        ET.publish(M.CLOUD_TOPIC.TOPIC_LIMIT_STATE_CHANGE, M.DOWNLOAD_LIMIT_CONTROL_STATE.STATE_NO_LIMIT)
    else
        ET.publish(M.CLOUD_TOPIC.TOPIC_LIMIT_STATE_CHANGE, M.DOWNLOAD_LIMIT_CONTROL_STATE.STATE_DEFAULT)
    end
end

function M.update_default_http_kps_limit(kps)
    E.LOG.debug(TAG, "[download]update_default_http_kps_limit:" .. tostring(kps))
    M.server_config_http_kps_limit = kps
end

function M.update_limit_for_wifi(is_limit_for_wifi)
    E.LOG.debug(TAG, "[download]update_limit_for_wifi:" .. tostring(is_limit_for_wifi))
    M.is_limit_speed_for_wifi = is_limit_for_wifi
end

M.CLOUD_MODE = {
    -- 云端
    CLOUD = "cloud",
    -- 移动端
    MOBILE = "mobile",
    -- 未知
    UNKNOWN = "unknown"
}

M.CLOUD_ENV = {
    -- 测试环境
    TEST = "test",
    -- 生产环境
    PRODUCT = "product",
    -- 预发布环境
    PRE_RELEASE = "pre_release",
}

M.CloudGameMode = M.CLOUD_MODE.MOBILE
M.CloudGameId = 0
M.CloudGameIdAppleReview = 0
M.IsLuaHardening = false
M.CloudEnv = M.CLOUD_ENV.PRODUCT
M.ODRConfig = nil;
M.DOWNLOAD_DISABLE = false;

--测试配置
M.DEBUG_OPTIONS = {
    --云服务测试ip：不设置ip，则会调度
    TestCloudServerIP = nil,
    TestCloudServerPort = nil,
    -- true则使用IP启动，false则使用调度方式启动
    cloudStartWithIpEnabled = true,
    -- 是否能让云端独立直接运行
    TestRunCloudSingle = false,
    Debug = false,
---region 开发测试，不需要加到配置表
    --每次都启动云游
    TestAlwayStartCloud = false,
    --测试不下载
    TestDisableDownload = false,
    TestEnableLuaProfile = false,
    --下载目录包含该文件则会返回空间不足
    TestNoStorageFile = "_test_no_storage.flg",
    TestMobileNetworkFile = "_test_mobile.flg",
    TestCloudStartErrorFile = "_test_cloud_start.flg",
    TestCloudCGErrorFile = "_test_cloud_cg.flg",
    TestCloudTimeLimit = nil,-- 测试云游使用最长时间

    TestConnectFailed = false, -- 测试连接失败
    TestConnectRequestTimeFailed = false, -- 测试连接过程获取时间失败
    TestConnectTimeEnd = false, -- 测试时间到期
    TestConnectedDelayTimeEnd = false, -- 测试时间到期
    TestCountDownStopSmall = false, -- 云游暂停倒计时设置很小
    TestCountDownStopBig = false, -- 云游暂停倒计时设置很小
    TestTimeLimitComing = false, -- 试玩时长到期
    TestConnectedRecvFailed = false, -- 连接成功过程中失败弹窗
    TestDownloadFinish = false, -- 测试下载完成
    TestInitDownloadFinish = false, -- 测试初始化时下载完成
    TestInitDownloading = false, -- 测试初始化时下载中
    TestDownloadProgressSync = false, -- 测试下载进度同步
    TestDownloadFinishForceToLocal = false, -- 下载完成倒计时结束
    TestDownloadCompleteAutoSwith = false, -- 测试下载完成30分钟自动切大包，需要和TestDownloadFinish一起使用
    TestUpdating = false, -- 测试覆盖安装场景
    TestSendMessageFailed = false -- 测试发送消息失败
---endregion
}

M.CONFIG_KEYS = {
    -- 云游模式，{@see M.CLOUD_MODE}
    CLOUD_GAME_MODE = "cloud_game_mode",
    -- 云游分配的gameid
    CLOUD_GAME_ID = "cloud_game_id",
    -- 苹果审核用
    CLOUD_GAME_ID_APPLE_REVIEW = "cloud_game_id_apple",
    -- lua是否加固
    IS_LUA_HARDENING = "is_lua_hardening",
    -- 云游运行的环境，test：测试环境，product: 生产环境；{@see M.CLOUD_ENV}
    CLOUD_ENV = "cloud_env",
    -- 调试模式，true: 开启调试模式，false：未开启调试模式
    CLOUD_DEBUGGABLE = "debuggable",
    -- 游戏资源下载地址，可以为数组
    GAME_RES_URLS = "game_res_urls",
    -- 游戏资源下载存放路径
    GAME_RES_SAVE_PATH = "game_res_save_path",
    -- 游戏资源存放路径类型
    GAME_RES_PATH_TYPE = "game_res_path_type",
    -- 同Lua productId
    GAME_PRODUCT_ID = "game_product_id",
    -- 苹果审核用
    GAME_PRODUCT_ID_APPLE = "game_product_id_apple",
    -- 测试直连IP时使用，需要配合端口一起
    DIRECT_CONNECT_IP = "direct_connect_ip",
    -- 测试直连IP时使用，需要配合IP一起
    DIRECT_CONNECT_PORT = "direct_connect_port",
    -- 调试选项
    DEBUG_OPTIONS = "debug_options",

    -- odr资源配置
    ODR_CONFIG = "odr_config",

    -- 云游支持的paas平台，目前包括ttg(九游)，aliyun（阿里云）
    PAAS_PLATFORM = "paas_platform",

    -- 是否关闭下载
    DOWNLOAD_DISABLE = "download_disable",

    -- 是否是自行启动
    SELF_START = "self_start",

    -- 资源类型 M.RESOURCE_TYPE
    RESOURCE_TYPE = "resource_type",

    -- 目标安装包的包名 Android
    INSTALL_PKG_NAME = "install_pkg_name",

    -- iOS目标安装包的scheme，用来判断是否可以拉起
    APPSTORE_APP_SCHEME = 'appstore_app_scheme',

    -- iOS目标安装包的app_id，用来拉起APP Store安装
    APPSTORE_APP_ID = 'appstore_app_id',

    -- 是否是从launcherActivity启动
    LAUNCHER_START_CONFIG = 'launcher_start'

}

M.RES_PATH_TYPE = {
    INTERNAL = 'internal',  -- 内部存储
    EXTERNAL = 'external'   -- 外部存储
}

M.ODR_TYPES = {
    INSTALL_TIME = "install_time",
    FAST_FOLLOW = "fast_follow",
    ON_DEMAND = "on_demand",
}

M.ODR_TAG_CONFIG_KEYS = {
    NAME = "name",
    SIZE = "size"
}

M.PAAS_PLATFORM = {
    TTG = "ttg",
    ALIYUN = "aliyun"
}

M.RESOURCE_TYPE = {
    GAME_RES = "game_res",  -- 游戏资源
    ODR = "odr",  -- ODR
    PACKAGE = "package"  -- 安装包
}

-- 云游支持的paas平台，目前包括ttg(九游)，aliyun（阿里云）
M.PaasPlatform = M.PAAS_PLATFORM.ALIYUN

M.DisableDownload = false
M.SelfStart = false
M.SelfStartInit = false
M.ResourceType = M.RESOURCE_TYPE.GAME_RES -- 默认下载游戏资源
M.InstallPkgName = nil -- 目标安装包的包名
M.AppStoreAppID = nil
M.AppStoreScheme = nil

-- ALAWAYS_CLOUD: 始终走云游
-- CHECK_NO_STORAGE：检测本地存储时始终返回false
-- ALWAYS_MOBILE_NETWORK：检测网络状态时始终返回移动网络
-- RUN_CLOUD_SINGLE: 云端独立能直接运行
-- DISABLE_DOWNLOAD：禁止下载
M.DEBUG_OPTIONS_VALUE = {
    ALAWAYS_CLOUD = "ALAWAYS_CLOUD",
    CHECK_NO_STORAGE = "CHECK_NO_STORAGE",
    ALWAYS_MOBILE_NETWORK = "ALWAYS_MOBILE_NETWORK",
    RUN_CLOUD_SINGLE = "RUN_CLOUD_SINGLE",
    DISABLE_DOWNLOAD = "DISABLE_DOWNLOAD",
    ENABLE_LUA_PROFILE = "ENABLE_LUA_PROFILE" -- 是否开启lua_profile
}

local CLOUD_VENDOR_NAME = "CLOUD_GAME"
local cloud_sdk_meta_config = nil
local META_KEY = {
    CLOUD_GAME_MODE = "cloud_game_mode",
    CLOUD_ENV = "cloud_env"
}

local is_ab_test_switch_checked = false
local ab_test_switch_status = false
local config_abtest_enable = nil
local ab_flag = nil
local cloud_model_name = nil

local is_show_splash_btn = true
local is_download_progress_notification_enable = true

function M.fix_url(path)
    if string.sub(path, -1) ~= "/" then
        path = path .. "/"
    end
    return path
end

function M.get_cloud_meta_config()
    -- E.LOG.debug(TAG, "get_cloud_meta_config begin")
    if cloud_sdk_meta_config and next(cloud_sdk_meta_config) ~= nil then
        return cloud_sdk_meta_config
    end

    -- E.LOG.debug(TAG, "get_cloud_meta_config from assets")
    local _UNI = require "ejoysdk_lua.vendors.unisdk"
    local cloud_game_meta
    local sdk_infos = E.get_meta_config("sdks")
    for _, sdk_info in ipairs(sdk_infos) do
        local abilities = sdk_info["ability"]
        if abilities then
            for _, ab in ipairs(abilities) do
                if ab == CLOUD_VENDOR_NAME then
                    cloud_game_meta = sdk_info["meta"]
                    break
                end
            end
        end

        -- 尝试判断vendor_name, windows 可能没有ability
        local config_vendor_name = sdk_info["name"]
        if config_vendor_name == CLOUD_VENDOR_NAME then
            E.LOG.debug(TAG, "find cloud_game vendor name, return this meta")
            cloud_game_meta = sdk_info["meta"]
            break
        end
    end

    cloud_sdk_meta_config = cloud_game_meta or {}
    --_ejoysdk.log("CC get_cloud_meta_config >>")
    --E.log(cloud_sdk_meta_config)
    return cloud_sdk_meta_config
end

-- cloud_mode values in {@link M.CLOUD_MODE}
function M.get_cloud_mode()
    local meta_config = M.get_cloud_meta_config()
    meta_config = meta_config or {}

    local mode = meta_config[META_KEY.CLOUD_GAME_MODE]
    -- E.LOG.debug(TAG, "check_is_cloud_side, mode:" .. (mode or 'nil'))
    return mode
end

function M.get_cloud_mode_name()
    if cloud_model_name then
        return cloud_model_name
    end

    local mode = M.get_cloud_mode()
    -- map mode
    if mode then
        if mode == "cloud" then
            cloud_model_name = M.CLOUD_MODE.CLOUD
        else
            cloud_model_name = M.CLOUD_MODE.MOBILE
        end
    else
        cloud_model_name = M.CLOUD_MODE.UNKNOWN
    end

    E.LOG.debug(TAG, "get_cloud_mode in adapter, mode:" .. tostring(cloud_model_name))
    return cloud_model_name
end

function M.init_config(sdk_meta_configs)
    E.LOG.debug(TAG, "init_config begin >>")
    if not sdk_meta_configs or next(sdk_meta_configs) == nil then
        E.LOG.debug(TAG, "init_config failed, config obj is nil, try get from local config")
        sdk_meta_configs = M.get_cloud_meta_config()
        if not sdk_meta_configs then
            E.LOG.debug(TAG, "init_config failed, config obj is nil, return")
            return
        end
    end

    cloud_sdk_meta_config = sdk_meta_configs
    E.LOG.debug(TAG, sdk_meta_configs)

    local start_with = E.Utils.start_with

    M.CloudGameMode = sdk_meta_configs[M.CONFIG_KEYS.CLOUD_GAME_MODE] or M.CLOUD_MODE.MOBILE
    if M.CloudGameMode == M.CLOUD_MODE.MOBILE then
        E.LOG.debug(TAG, "init_config in mobile mode")
        M.CloudEnv = sdk_meta_configs[M.CONFIG_KEYS.CLOUD_ENV] or M.CLOUD_ENV.PRODUCT
        M.CloudGameId = sdk_meta_configs[M.CONFIG_KEYS.CLOUD_GAME_ID] or 0
        M.CloudGameIdAppleReview = sdk_meta_configs[M.CONFIG_KEYS.CLOUD_GAME_ID_APPLE_REVIEW] or 0
        M.ProductId = sdk_meta_configs[M.CONFIG_KEYS.GAME_PRODUCT_ID] or nil
        M.ProductIdAppleReview = sdk_meta_configs[M.CONFIG_KEYS.GAME_PRODUCT_ID_APPLE] or nil
        -- config productid
        E.CONFIG.autoconfig("", M.ProductId)

        local luaHardeningStr = sdk_meta_configs[M.CONFIG_KEYS.IS_LUA_HARDENING] or "false"
        M.IsLuaHardening = ("true" == luaHardeningStr)

        local save_data_relative_path = sdk_meta_configs[M.CONFIG_KEYS.GAME_RES_SAVE_PATH] or ""
        -- 存放资源目录类型，默认值，内部存储
        local save_data_path_type = sdk_meta_configs[M.CONFIG_KEYS.GAME_RES_PATH_TYPE] or M.RES_PATH_TYPE.INTERNAL
        local start_with_path = start_with(save_data_relative_path, "/")
        if not start_with_path then
            save_data_relative_path = "/" .. save_data_relative_path
        end
        local res_facade = require 'ejoysdk_lua.res.ejoysdk_res_facade'
        if save_data_path_type == M.RES_PATH_TYPE.EXTERNAL then
            local external_path = res_facade.get_storage_path_by_type(res_facade.STORAGE_TYPE.EXTERNAL_APP_PRIVATE)
            M.SaveAssetDir = external_path .. save_data_relative_path
        else
            local internal_path = res_facade.get_storage_path_by_type(res_facade.STORAGE_TYPE.INTERNAL_APP_PRIVATE)
            M.SaveAssetDir = internal_path .. save_data_relative_path
        end
        M.SaveAssetDir = M.fix_url(M.SaveAssetDir)
        E.LOG.debug(TAG, "SaveAssetDir " .. M.SaveAssetDir)

        M.PaasPlatform = sdk_meta_configs[M.CONFIG_KEYS.PAAS_PLATFORM]
        M.DisableDownload = sdk_meta_configs[M.CONFIG_KEYS.DOWNLOAD_DISABLE] or false
        --M.SelfStart = sdk_meta_configs[M.CONFIG_KEYS.SELF_START] or false
        M.SelfStart = sdk_meta_configs[M.CONFIG_KEYS.LAUNCHER_START_CONFIG] or false
        M.SelfStartInit = true
        E.LOG.debug(TAG, "paas platform is " .. tostring(M.PaasPlatform))
        M.ResourceType = sdk_meta_configs[M.CONFIG_KEYS.RESOURCE_TYPE] or M.RESOURCE_TYPE.GAME_RES
        M.InstallPkgName = sdk_meta_configs[M.CONFIG_KEYS.INSTALL_PKG_NAME]
        M.AppStoreAppID = sdk_meta_configs[M.CONFIG_KEYS.APPSTORE_APP_ID]
        M.AppStoreScheme = sdk_meta_configs[M.CONFIG_KEYS.APPSTORE_APP_SCHEME]

        M.DEBUG_OPTIONS.Debug = sdk_meta_configs[M.CONFIG_KEYS.CLOUD_DEBUGGABLE] or false
        if M.DEBUG_OPTIONS.Debug then
            E.LOG.debug(TAG, "init_config is debug mode")
            M.DEBUG_OPTIONS.TestCloudServerIP = sdk_meta_configs[M.CONFIG_KEYS.DIRECT_CONNECT_IP] or nil
            M.DEBUG_OPTIONS.TestCloudServerPort = sdk_meta_configs[M.CONFIG_KEYS.DIRECT_CONNECT_PORT] or 0
            if
                M.DEBUG_OPTIONS.TestCloudServerIP and M.DEBUG_OPTIONS.TestCloudServerIP ~= "" and
                    M.DEBUG_OPTIONS.TestCloudServerPort > 0
             then
                E.LOG.debug(
                    TAG,
                    "init_config with directIP enabled, ip:" ..
                        tostring(M.DEBUG_OPTIONS.TestCloudServerIP) ..
                            ", port:" .. tostring(M.DEBUG_OPTIONS.TestCloudServerPort)
                )
                M.DEBUG_OPTIONS.cloudStartWithIpEnabled = true
            else
                E.LOG.debug(TAG, "init_config with directIP disabled!")
                M.DEBUG_OPTIONS.cloudStartWithIpEnabled = false
            end

            local debug_options = sdk_meta_configs[M.CONFIG_KEYS.DEBUG_OPTIONS] or {}
            E.LOG.debug(TAG, "debug options >>")
            E.LOG.debug(TAG, debug_options)
            if debug_options and next(debug_options) ~= nil then
                for _, opt in ipairs(debug_options) do
                    if opt == M.DEBUG_OPTIONS_VALUE.ALAWAYS_CLOUD then
                        M.DEBUG_OPTIONS.TestAlwayStartCloud = true
                    elseif opt == M.DEBUG_OPTIONS_VALUE.DISABLE_DOWNLOAD then
                        E.LOG.debug(TAG, "set config disable download")
                        M.DEBUG_OPTIONS.TestDisableDownload = true
                    -- elseif opt == M.DEBUG_OPTIONS_VALUE.ALWAYS_MOBILE_NETWORK then
                    --     M.DEBUG_OPTIONS.TestMobileNetwork = true
                    -- elseif opt == M.DEBUG_OPTIONS_VALUE.CHECK_NO_STORAGE then
                    --     M.DEBUG_OPTIONS.TestNoStorage = true
                    elseif opt == M.DEBUG_OPTIONS_VALUE.ENABLE_LUA_PROFILE then
                        E.LOG.debug(TAG, "enabled lua profile")
                        M.DEBUG_OPTIONS.TestEnableLuaProfile = true
                    end
                end
            end
        else
            E.LOG.debug(TAG, "init_config is release mode")
        end
    else
        E.LOG.debug(TAG, "init_config in cloud mode")
        M.DEBUG_OPTIONS.Debug = sdk_meta_configs[M.CONFIG_KEYS.CLOUD_DEBUGGABLE] or false
        E.LOG.debug(TAG, "sdk_meta_configs >>")
        E.LOG.debug(TAG, sdk_meta_configs)
        if M.DEBUG_OPTIONS.Debug then
            E.LOG.debug(TAG, "init_config is debug mode")

            local debug_options = sdk_meta_configs[M.CONFIG_KEYS.DEBUG_OPTIONS] or {}
            E.LOG.debug(TAG, "debug options >>")
            E.LOG.debug(TAG, debug_options)
            if debug_options and next(debug_options) ~= nil then
                for _, opt in ipairs(debug_options) do
                    if opt == M.DEBUG_OPTIONS_VALUE.RUN_CLOUD_SINGLE then
                        M.DEBUG_OPTIONS.TestRunCloudSingle = true
                        E.LOG.debug(TAG, "enable TestRunCloudSingle")
                    end
                end
            end
        else
            E.LOG.debug(TAG, "init_config is release mode")
        end
    end

    -- 打开日志开关
    if M.DEBUG_OPTIONS.Debug then
        -- debug log 开关
        local ELOG = require 'ejoysdk_lua.ejoysdk_log'
        -- 后续改动留意不支持Windows
        local ej_debugable = E.get_ej_debugable()
        _ejoysdk.log('=======>ej_debugable:' .. tostring(ej_debugable))
        ELOG.setup_ej_debugable(ej_debugable)
        if ej_debugable then
            E.open_log(ej_debugable)
        end
    end

    M.ODRConfig = sdk_meta_configs[M.CONFIG_KEYS.ODR_CONFIG]
    E.LOG.debug(TAG, "print odr config from lua!")
    E.LOG.debug(TAG, M.ODRConfig)

    -- M.URLS={
    --     "http://yunweiduan.ejoy.com/star/_cloud_game_url.json"
    -- }
end

function M.is_self_start()
    if M.SelfStartInit then
        return M.SelfStart
    end

    local cloud_meta = M.get_cloud_meta_config()
    M.SelfStart = cloud_meta.self_start
    M.SelfStartInit = true

    return M.SelfStart
end

function M.update_ab_test_flag(_ab_flag)
    E.LOG.debug(TAG, "update_ab_test_flag: " .. tostring(_ab_flag))
    ab_flag = _ab_flag
end

function M.get_ab_flag()
    return ab_flag
end

function M.is_ab_test_switch_on()
    if is_ab_test_switch_checked then
        return ab_test_switch_status
    end

    if config_abtest_enable ~= nil then
        if config_abtest_enable == false then
            E.LOG.debug(TAG, "is_ab_test_switch_on ab test switch from server is false, now return false")
            return false
        end

        -- 判断开关，判断是否AB
        local utdid = E.get_pkg_info().utdid
        local key = _ejoysdk_crypt.hashkey(tostring(utdid))
        local hex_val = _ejoysdk_crypt.hexencode(key)
        local last_character = string.sub(hex_val, -1)
        local last_number = tonumber(last_character, 16)
        ab_test_switch_status = last_number > 0 and last_number < 9
        is_ab_test_switch_checked = true
        E.LOG.debug(TAG, "is_ab_test_switch_on, utdid:" .. tostring(utdid) .. ", hex:".. hex_val .. ", last_character:" .. tostring(last_character) .. ", last_number:" .. tostring(last_number) .. ", isDisable:" .. tostring(ab_test_switch_status) .. ", configAB enable:" .. tostring(config_abtest_enable))
        return ab_test_switch_status
    else
        E.LOG.debug(TAG, "is_ab_test_switch_on server config not received, now default return false")
        return false
    end
end

function M.set_remote_urls(remote_url)
    if remote_url == nil or remote_url == '' then
        E.LOG.error(TAG, "[set_remote_url] the url is nil!")
    else
        E.LOG.debug(TAG, "[set_remote_url] the assets url is : " .. tostring(remote_url))
        M.REMOTE_URLS = remote_url
    end
end

function M.update_updating_connect_size_limit(updating_limit_size)
    if updating_limit_size > 0 then
        M.UPDATING_WITH_CONNECT_LIMIT = updating_limit_size
    else
        M.UPDATING_WITH_CONNECT_LIMIT = DEFAULT_UPDATE_WITH_CONNECT_LIMIT
    end

    E.LOG.debug(TAG, "update_updating_connect_size_limit result:" .. tostring(M.UPDATING_WITH_CONNECT_LIMIT))
end

function M.set_is_splash_btn(is_show)
    E.LOG.debug(TAG, 'set is splash btn >> ' .. tostring(is_show))
    is_show_splash_btn = is_show
end

-- 更新下载完成后，可以继续试玩的时长，单位:minute
function M.set_continue_play_time(time)
    E.LOG.debug(TAG, 'set download finish continue play time  >> ' .. tostring(time))
    if time and time > 0 then
        M.FinishDownloadContinuePlayTime = time
    end
end

function M.update_remain_time_templete(templete)
    E.LOG.debug(TAG, 'update remain time templete  >> ' .. tostring(templete))
    if templete and #templete > 0 then
        M.RemainTimeTemplete = templete
    end
end

function M.get_is_splash_btn()
    return is_show_splash_btn
end

function M.set_download_progress_notification_enabled(is_enable)
    E.LOG.debug(TAG, "set_download_progress_enabled:" .. tostring(is_enable))
    is_download_progress_notification_enable = is_enable
end

function M.is_download_progress_notification_enable()
    return is_download_progress_notification_enable
end

--fixme 这个方法是native测试界面调用的，方便测试关闭下载
function M.disable_download()
    E.LOG.debug(TAG, "disable download")
    M.DEBUG_OPTIONS.TestDisableDownload = true
end

return M
