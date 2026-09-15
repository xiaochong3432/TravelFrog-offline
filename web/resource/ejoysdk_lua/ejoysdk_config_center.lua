-------------------------------------------------------------------------------
-- 后台配置中心 https://yuque.antfin.com/ejoy-platform/ejoy-platform/nh0s7k
--
-- Created Date: 2021.08.24
-- Author: 四境
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local V = require "ejoysdk_lua.version"
local UTIL = require 'ejoysdk_lua.ejoysdk_utils'
local JSON = require 'ejoysdk_lua.ejoysdk_json'
local uuid = require "ejoysdk_lua.ejoysdk_uuid"
local EGC = require 'ejoysdk_lua.ejoysdk_gangplank_config'
local STAT = require 'ejoysdk_lua.ejoysdk_stat'
local EM = require "ejoysdk_lua.ejoysdk_module"
local EC = require "ejoysdk_lua.ejoysdk_constants"

-- ======================== 1.全局配置 ========================
local M = {}
local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'config_center'
local inited = false

-- 所有的NAMESPACE定义
M.NAMESPACE = {
    EJOYSDK_CORE = 'ejoysdk_core',
    EJOYSDK_BIZ = 'ejoysdk_biz',
    APM = 'apm',
    NETWORK = 'network',
    USERCENTER_CN = 'usercenter_cn',
    USERCENTER_OVERSEA = 'usercenter_oversea',
    LUA_RESOURCE = 'lua_resource', -- SDK的lua热更，用于独代游戏场景（旧的，保留）
    H5_RESOURCE = 'h5_resource', -- qookka登录页（旧的，保留）
    MARKET_H5_RESOURCE ='qz_h5_res', -- 市场活动用的H5资源
    EJOYSDK_H5_RESOURCE = 'ejoysdk_h5res' , -- ejoysdk内部用的h5资源
    GAME_RES = "game_res", -- 游戏资源namespace
    PREDOWNLOAD = 'predownload',
    QZ_CUSTOM_RES = 'qz_custom_res',
    QZ_CONFIG = "qz_config", -- 启动配置
    QZ_BOOT = "qz_boot", -- 启动资源
    QZ_PATCH = "qz_patch" -- 游戏热更资源
}

-- 初始化关心的NAMESPACE，只生效一次
-- 关心初始化前的配置需要这里配置
local INIT_NAMESPACES = {
    EJOYSDK_CORE = M.NAMESPACE.EJOYSDK_CORE,
    EJOYSDK_BIZ = M.NAMESPACE.EJOYSDK_BIZ,
    APM = M.NAMESPACE.APM,
    NETWORK = M.NAMESPACE.NETWORK,
    USERCENTER_CN = M.NAMESPACE.USERCENTER_CN,
    USERCENTER_OVERSEA = M.NAMESPACE.USERCENTER_OVERSEA,
    H5_RESOURCE = M.NAMESPACE.H5_RESOURCE,
    LUA_RESOURCE = M.NAMESPACE.LUA_RESOURCE,
    EJOYSDK_H5_RESOURCE = M.NAMESPACE.EJOYSDK_H5_RESOURCE -- 内部使用的h5资源，如登录等
}

-- 常驻的请求源
-- 轮询的请求源和订阅的合并后会定时请求
local LONG_NAMESPACES = {
    EJOYSDK_CORE = M.NAMESPACE.EJOYSDK_CORE,
    EJOYSDK_BIZ = M.NAMESPACE.EJOYSDK_BIZ
}

-- 默认配置项, 默认2分钟
local LOOP_SEC = 120 

-- namespace 白名单，用于控制get_config_from_server的获取
-- eg: { ejoysdk_core = true }
local white_namespace_list = {
    ejoysdk_core = true,
    ejoysdk_biz = true,
    apm = true,
    ejoy_cloud_game = true,
    ejoy_cloud_game_test = true, -- 游戏上线前云游预发环境配置
    h5_resource = true,
    lua_resource = true,
    usercenter_cn = true,
    qz_custom_res = true,
    qz_patch = true,
    usercenter_oversea = true
}

-- 更新逻辑
local CONFIG_CENTER_UPDATE_TYPE = {
    ALL = 0, -- 全域更新
    INC = 1, -- 变更更新
}
M.CONFIG_CENTER_UPDATE_TYPE = CONFIG_CENTER_UPDATE_TYPE

M.ENV = {
    DEBUG = 'debug',
    RELEASE = 'release',
    PRE_RELEASE = 'pre_release'
}

-- 正式
M.URL_BASE = {
    CONFIG_QUERY = 'https://carbon-api.lingxigames.com'
}

-- 测试；测试环境只搞一套环境国内海外共用
M.URL_BASE_DEBUG = {
    CONFIG_QUERY = 'https://ww-hk-carbon-api-test.qookkagames.com'
}

M.SERVICE = {
    GET_CONFIG_QUERY = 'api.config.query'
}

local SERVICE_MAPPING = {
    [M.SERVICE.GET_CONFIG_QUERY] = 'CONFIG_QUERY'
}

local l_env

-- 响应码定义
local CONFIG_CENTER_API = {
    RSP_CODE_SUCC = 2000000,         -- 成功
    RSP_CODE_PARAMS_ERROR = 4000000, -- 请求参数错误
    RSP_CODE_BIZ_ERROR = 4000001,    -- 业务参数错误
    RSP_CODE_SER_ERROR = 5000000,    -- 服务器内部错误
    RSP_CODE_SYS_ERROR = 5000003     -- 服务被降级处理
}

local NAMESPACE_INFOS = E.LazyKeyStore:New("NAMESPACE_INFOS", true, true, false) -- 记录namespace信息
M.NAMESPACE_INFOS = NAMESPACE_INFOS

-- 请求公参变量
local uid = nil
local pid = nil
local platform = nil

-- 允许外部设置base url
local qz_base_url = nil

-- 外部设置的url数组，优先使用，如没有，再用单个设置的/默认的兜底
local prioritized_base_urls = nil

-- ======================== 2.配置相关 ========================
-- 环境
function M.set_env(env)
    E.LOG.debug(TAG, "set_env: " .. tostring(env))
    l_env = env
end

function M.get_env()
    if l_env then
        return l_env
    end

    local EI = require "ejoysdk_lua.ejoysdk_init"
    return EI.env()
end

function M.set_url_base(url_base)
    qz_base_url = url_base
end

function M.set_prioritized_base_urls(base_urls)
    prioritized_base_urls = base_urls
end

local function get_prefer_product_code(product_code)
    -- 防护一下类型
    if product_code and type(product_code) ~= 'string' then
        product_code = nil
    end

    local prefer_product_code = product_code and product_code:lower()
    if not prefer_product_code then
        local current_product_code = E.CONFIG.get_config("product")
        prefer_product_code = current_product_code and current_product_code:lower() or ''
    end
    return prefer_product_code
end

local request_namespaces = UTIL.deepcopy(LONG_NAMESPACES)

-- 添加请求的namespace
local function add_request_namespace(new_np)

    if new_np == nil then return end

    -- 去重
    for _, np in pairs(request_namespaces) do
        if np == new_np then
            return
        end
    end
    -- 添加
    request_namespaces[#request_namespaces + 1] = new_np
end

-- 剔除请求的namespace
local function remove_request_namespace(del_np)

    if del_np == nil then return end

    -- 常驻的不能去除
    for _, np in pairs(LONG_NAMESPACES) do
        if np == del_np then
            return
        end
    end

    local new = {}
    for k, np in pairs(request_namespaces) do
        if del_np ~= np then
            new[k] = np
        end
    end

    request_namespaces = new
end

-- 缓存配置
local cache_configs
local cache_ex_infos = {}

local function load_configs()
    if cache_configs == nil then
        cache_configs = NAMESPACE_INFOS:get()
        
        if cache_configs == nil or type(cache_configs) ~= 'table' then
            cache_configs = {}
        end
    end

    return cache_configs
end

local function save_cache_config(ns_info)

    if ns_info ~= nil and ns_info.namespace ~= nil then
        local namespace = ns_info.namespace
        if cache_configs == nil then
            cache_configs = {
                namespace = ns_info
            }
        else
            cache_configs[namespace] = ns_info
        end
    end
    
end

local function save_disk_configs()
    if cache_configs ~= nil then
        NAMESPACE_INFOS:set(cache_configs)
        NAMESPACE_INFOS:save()
    end
end

local function get_local_config(namespace)

    if cache_configs or load_configs() then 
        return cache_configs[namespace] 
    end

    return nil
end

-- 获取本地缓存配置
function M.get_configs()
    return UTIL.deepcopy(load_configs())
end

-- 获取本地缓存指定的namespace配置
function M.get_config(namespace)
    return UTIL.deepcopy(get_local_config(namespace))
end

-- 设置额外请求的namespace信息
-- 当前是静态的，下一个轮询会带上对应namespace的额外信息
function M.set_ex_info(namespace, np_ex_info)

    if namespace ~= nil and type(np_ex_info) == 'table' then
        cache_ex_infos[namespace] = np_ex_info
    end
    
end

function M.get_ex_info(namespace)
    return UTIL.deepcopy(cache_ex_infos[namespace])
end

function M.get_ex_infos()
    return UTIL.deepcopy(cache_ex_infos)
end

local random_time_in_mills = 0
local function get_request_id()
    if random_time_in_mills == 0 then
        math.randomseed(os.time())
        local random_mills = math.random(1, 1000)
        local sys_clock = os.time() * 1000
        random_time_in_mills = sys_clock + random_mills
        E.LOG.debug(TAG, 'get_request_id :'.. random_time_in_mills .. ', sys_clock:'..sys_clock..', random_mills:'..random_mills)
    else 
        random_time_in_mills = random_time_in_mills + 1
    end
    return random_time_in_mills
end
-- ======================== 3.订阅分发 ========================
local dispatcher = {}
-- 订阅
function M.subscribe(namespace, cb)

    if namespace == nil then return end

    E.LOG.debug(TAG, 'subscribe: ' .. namespace)

    local handlers = dispatcher[namespace]
    if not handlers then
        handlers = {}
        dispatcher[namespace] = handlers
    end

    for _, handler in ipairs(handlers) do
        if handler == cb then
            return
        end
    end
    handlers[#handlers + 1] = cb

    -- 更新订阅的namespace添加到请求
    add_request_namespace(namespace)
end

-- 取消订阅
function M.unsubscribe(namespace, cb)
    
    if namespace == nil then return end

    E.LOG.debug(TAG, 'unsubscribe: ' .. namespace)

    local handlers = dispatcher[namespace]
    if handlers then
        local new = {}
        for _, handler in ipairs(handlers) do
            if cb ~= handler then
                new[#new + 1] = handler
            end
        end
        dispatcher[namespace] = new

        if #new == 0 then
            -- 取消订阅的namespace从请求移除
            -- 只有无任何业务方订阅的时候才需要移除
            remove_request_namespace(namespace)
        end        
    end
end

-- 发布
local function publish(namespace, ...)
    local handlers = dispatcher[namespace]
    if handlers then
        for _, cb in ipairs(handlers) do
            local succ, err = pcall(cb, ...)
            if not succ then
                E.LOG.debug(TAG, 'error namespace ' .. tostring(namespace) .. ': ' .. tostring(err))
            end
        end
    end
end

-- add init namespace
function M.add_init_namespace(namespace)
    if INIT_NAMESPACES and namespace and type(namespace) == 'string' then
        INIT_NAMESPACES[namespace] = namespace
    end
end

-- ======================== 4.网络请求 ========================
-- 请求Header
local function get_request_params()
    -- header 字段描述：https://yuque.antfin-inc.com/ejoy-platform/lqmsz2/qtl6lh
    local md5_utdid = nil
    local utdid = E.Sysinfo.utdid() or ''
    if type(_ejoysdk_crypt.md5) == 'function' then
        md5_utdid = _ejoysdk_crypt.md5(utdid)
    elseif type(_ejoysdk_crypt.md5) == 'table' and _ejoysdk_crypt.md5.sum then
        md5_utdid = _ejoysdk_crypt.hexencode(_ejoysdk_crypt.md5.sum(utdid))
    end

    local request_params = {
        trace = true,
        headers = {
            did = md5_utdid,
            gid = E.get_pkg_info().game_id,
            gver = E.get_pkg_info().versions.app_version_name,
            os = E.get_pkg_info().os,
            ch = '', -- 海外暂时没有渠道
            cver = V.LUA_VERSION
        }
    }

    for k, v in pairs(E.get_pkg_info().versions) do
        request_params.headers[k] = v
    end

    return request_params
end

local function get_full_url(url_base, service_api)
    return url_base ..'/client/'.. service_api .. '?ver=1.3&df=json&gt=ng&cver='..V.LUA_VERSION..'&os='..E.Sysinfo.os()
end

-- 请求url
-- 海外从gangplank-config 获取请求url，对应cdn字段名 config_center
-- 国内hardcode
local function get_default_base_url(service_api)
    -- 海外从config拿，国内hardcode
    local is_overseas = E.CONFIG.get_config(E.CONFIG.KEY.MULTI_REGIONS_ENABLED)
    local url_base
    local server = SERVICE_MAPPING[service_api]

    if qz_base_url and qz_base_url ~= "" then
        url_base = qz_base_url
    end

    if url_base == nil then
        if is_overseas then

            -- 读取config_center
            local current_cdn_config = EGC.get_current_cdn_config()
            if current_cdn_config then
                url_base = current_cdn_config.config_center
            end

        else
            local _env = M.get_env()
            if _env == M.ENV.RELEASE then
                url_base = M.URL_BASE[server]
            else
                url_base = M.URL_BASE_DEBUG[server]
            end
        end
    end

    return url_base
end

-- 更新请求公参
local role_info = nil
local acc_info = nil
local env_info = nil

local function update_role_info(params)
    if params then
        role_info = params
    end

    if role_info and env_info then
        env_info.roleInfo = role_info
    end
end

function M.role_info()
    if not role_info then
        role_info = {}
    end
    return UTIL.deepcopy(role_info)
end

function M.acc_info()
    if not acc_info then
        acc_info = {}
    end
    return UTIL.deepcopy(acc_info)
end

function M.env_info()
    if not env_info then
        env_info = {}
        
        local stat_env_info = STAT.env_info()
        if stat_env_info then
            M.acc_info()
            if stat_env_info.acc_info then
                acc_info = stat_env_info.acc_info
            end
            env_info.accInfo = acc_info
            env_info.devInfo = stat_env_info.devInfo
            env_info.chInfo = stat_env_info.chInfo
            env_info.gmInfo = stat_env_info.gmInfo
        end

        -- 额外参数
        env_info.runId = uuid()
        env_info.roleInfo = role_info

        if env_info.devInfo then
            -- 品牌参数，国内海外来源不一致
            local is_overseas = E.CONFIG.get_config(E.CONFIG.KEY.MULTI_REGIONS_ENABLED)
            if is_overseas then
                local gangplank_config = EGC.get_current_cdn_config()
                if gangplank_config then
                    local airline_info = (gangplank_config['ext'] and gangplank_config['ext']['airline_info'])
                    env_info.devInfo.airline = airline_info and airline_info.brand or 'qookka'
                end
            else
                -- airline设置
                local airlineStr = E.get_pkg_info().airline or ''
                if airlineStr == '' then
                    env_info.devInfo.airline = 'lingxi'
                end
                -- publisharea设置，国内默认是cn
                if (not env_info.devInfo.publishArea) or (env_info.devInfo.publishArea == '') then
                    env_info.devInfo.publishArea = 'cn'
                end
            end


        end

        -- 补充SDK插件版本号
        if env_info.gmInfo and type(env_info.gmInfo) == 'table' then
            local versions = E.get_pkg_info().versions
            if versions and type(versions) == 'table'  then
                for k, v in pairs(versions) do
                    env_info.gmInfo[k] = v
                end
            end
        end


        -- 补充云游的相关参数
        if env_info.devInfo then 
            local pkg_info = E.get_pkg_info()
            local UIM = require "ejoysdk_lua.user_info_manager"
            env_info.devInfo[UIM.PKG_INFO_KEY.KEY_CLOUD_GAME_MODE] = pkg_info[UIM.PKG_INFO_KEY.KEY_CLOUD_GAME_MODE]
            env_info.devInfo[UIM.PKG_INFO_KEY.KEY_INSTANT_MODE] = pkg_info[UIM.PKG_INFO_KEY.KEY_INSTANT_MODE]
            env_info.devInfo[UIM.PKG_INFO_KEY.KEY_INSTALL_REFERRER] = pkg_info[UIM.PKG_INFO_KEY.KEY_INSTALL_REFERRER]
            env_info.devInfo[UIM.PKG_INFO_KEY.KEY_CLOUD_GAME_RUN_MODE] = pkg_info[UIM.PKG_INFO_KEY.KEY_CLOUD_GAME_RUN_MODE]
        end

    end
    return UTIL.deepcopy(env_info)
end

function M.reset_env_info()
    env_info = nil
    role_info = nil
end

-- 分发处理
local function dispatch_and_save_remote_data(data, req_product_code)

    if not data then
        E.LOG.debug(TAG, 'data is nil')
        return
    end

    local namespaces = data.configList

    if not namespaces then
        E.LOG.debug(TAG, 'data.configList is nil')
        return
    end

    local save_count = 0

    local update_info = {}
    for _, ns_info in pairs(namespaces) do

        local namespace = ns_info.namespace
        -- local ns_config = ns_info.config
        local hash = ns_info.hash
        local version = ns_info.version
        local is_test = ns_info.test or false
        -- 记录下请求的product_code
        ns_info.product_code = req_product_code or ''

        local last_ns_info = get_local_config(namespace)
        if last_ns_info ~= nil then
            local last_ns_product_code = last_ns_info.product_code
            if req_product_code and last_ns_product_code
                    and req_product_code ~= ''
                    and last_ns_product_code ~= ''
                    and req_product_code ~= last_ns_product_code then
                E.LOG.warn(TAG, "dispatch_and_save_remote_data cache pcode different from request pcode, for ns:"
                        .. tostring(namespace) .. ", cache pcode:" .. tostring(last_ns_product_code) .. ", req pcode:" .. tostring(req_product_code))
                last_ns_info = nil
            end
        end

        if last_ns_info ~= nil then
            local last_hash = last_ns_info.hash
            local last_version = last_ns_info.version or -1

            -- namespace间是增量的，namespace内是覆盖的
            -- 1 last_version < 服务器version
            --     hash不一致：更新
            --     hash一致：只更新version
            -- 2 last_version >= 服务器version : 不更新
            -- 3 test 走测试配置流程，直接忽略版本号
            if last_version < version or last_version == -1 or is_test then
                if hash ~= last_hash then
                    save_cache_config(ns_info)
                    save_count = save_count + 1
                    -- namespace内是覆盖的，可以直接分发出去
                    table.insert(update_info,ns_info)
                    --publish(namespace, UTIL.deepcopy(ns_info))
                    E.LOG.debug(TAG, 'namespace:' .. tostring(namespace) .. ', update [new version]:' .. tostring(version))
                else
                    -- 只更新版本号，不需要publish
                    last_ns_info.version = version
                    save_count = save_count + 1
                    save_cache_config(last_ns_info)
                    E.LOG.debug(TAG, 'namespace:' .. tostring(namespace) .. ', update [only version]:' .. tostring(version))
                end
            elseif last_version == version and hash ~= last_hash then
                save_cache_config(ns_info)
                save_count = save_count + 1
                -- namespace内是覆盖的，可以直接分发出去
                table.insert(update_info,ns_info)
                --publish(namespace, UTIL.deepcopy(ns_info))
                E.LOG.debug(TAG, 'namespace:' .. tostring(namespace) .. ', update [new hash]:' .. tostring(version))
            end
        else
            save_cache_config(ns_info)
            table.insert(update_info,ns_info)
            --publish(namespace, UTIL.deepcopy(ns_info))
            save_count = save_count + 1
            E.LOG.debug(TAG, 'namespace:' .. tostring(namespace) .. ', update [no cache]:' .. tostring(version))
        end
    end

    -- 数据落地
    if save_count > 0 then
        E.LOG.debug(TAG, 'update namespace count:' .. tostring(save_count))
        save_disk_configs()
    end

    -- 广播通知
    for _, info in pairs(update_info) do
        publish(info.namespace, UTIL.deepcopy(info))
    end
end

-- 请求接口
-- https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/on6zlt
-- type 0 全域更新; 1 变更更新
-- namespaceList - 业务空间描述 - 客户端用到的namespace必须上报， 不上报的namespace的配置会被忽略。 
-- exInfos - 额外信息
local function get_configs_from_server(_namespaces, update_type, cb, product_code, disable_update_cache)

    -- 1.组织请求header
    local req_params = get_request_params()

    -- 2.获取请求url，兜底url
    local default_base_url = get_default_base_url(M.SERVICE.GET_CONFIG_QUERY)

    -- 如果兜底的url不存在，直接报错
    if not default_base_url then
        cb(false, EC.CONFIG_CENTER_ERROR_CODES.NO_REQUEST_URL, 'default base url is nil')
        return
    end

    -- 3.配置下发的域名

    -- 4.组织请求body - data
    local req_product_code = get_prefer_product_code(product_code)

    local namespace_list = {}
    for _, np_name in pairs(_namespaces) do
        -- 拼接请求list
        local np_config = get_local_config(np_name)

        if np_config then 
            local np_version = {
                namespace = string.lower(np_config.namespace) or '',
                hash = np_config.hash or '',
                version = np_config.version or -1,
            }
            table.insert(namespace_list, np_version)
        else
            local np_version = {
                namespace = string.lower(np_name),
                hash = '',
                version = -1,
            }
            table.insert(namespace_list, np_version)
        end
    end

    local np_ex_infos = M.get_ex_infos()

    -- 5.组织请求body - 公参
    local public_params = {
        contextInfo = M.env_info(),
        appId = E.get_game_id(),
        env = req_product_code or '',
        os = E.CONFIG.get_config("os"),
        ve = V.LUA_VERSION
    }

    -- 6.组织请求body
    local id = get_request_id()
    local body_params = {
        id = id,
        data = {
            type = update_type,
            namespaceList = namespace_list,
            exInfos = np_ex_infos
        },
        client = public_params
    }

    -- E.LOG.debug(TAG, "get_request_params >>")
    -- E.log(req_params)
    -- E.LOG.debug(TAG, "get_request_body >>")
    -- E.log(body_params)
    --
    --local body_str = JSON.safe_encode(body_params)
    --E.LOG.debug(TAG, 'body str is ' .. tostring(body_str))

    local current_retry_times = 1
    local all_url_bases = prioritized_base_urls or {}
    table.insert(all_url_bases, default_base_url)
    local all_retry_count = #all_url_bases

    local retry_request_server_wrapper
    retry_request_server_wrapper = function(current_base_url, _cb)
        local config_center_url = get_full_url(current_base_url, M.SERVICE.GET_CONFIG_QUERY)
        E.LOG.debug(TAG, 'config_center_url is ' .. tostring(config_center_url))
        E.HTTP.post(config_center_url, req_params, E.HTTP.CT_JSON, body_params, function(resp)
            if resp.status == 200 then
                _cb(true, resp, config_center_url)
            else
                E.LOG.warn(TAG, 'post response failed, url:' .. tostring(config_center_url) .. ', status: ' .. tostring(resp.status))
                --失败，进行重试
                local retry_index = current_retry_times + 1
                if retry_index <= all_retry_count then
                    current_retry_times = retry_index
                    local retry_base_url = all_url_bases[retry_index]
                    E.LOG.debug(TAG, 'get_configs_from_server retry, retry base url is ' .. tostring(retry_base_url))
                    retry_request_server_wrapper(retry_base_url, _cb)
                else
                    _cb(false, resp, config_center_url)
                end
            end
        end)
    end

    local base_url = all_url_bases[1]
    retry_request_server_wrapper(base_url, function(succ, resp, real_config_center_url)
        if succ then
            E.LOG.debug(TAG, "get resp >>")
            E.log(resp)
            local body_json = resp.body
            if type(resp.body) == 'string' then
                body_json = JSON.safe_decode(resp.body)
            end
            --local body_json_str = JSON.safe_encode(body_json)
            --E.LOG.debug(TAG, 'body json is ' .. tostring(body_json_str))
            if body_json and body_json.state then
                if body_json.state.code == CONFIG_CENTER_API.RSP_CODE_SUCC then
                    -- E.LOG.debug(TAG, 'post response succ, url:'..config_center_url)
                    if not disable_update_cache then
                        dispatch_and_save_remote_data(body_json.data, req_product_code)

                        -- 从缓存里面拿出来
                        local cb_np_list = {}
                        for _, np_name in pairs(_namespaces) do
                            local new_config = get_local_config(np_name)
                            if new_config then
                                table.insert(cb_np_list, get_local_config(np_name))
                            end
                        end
                        cb(true, cb_np_list)
                    else
                        local config_list = body_json.data and body_json.data.configList or {}
                        for _, v in pairs(config_list) do
                            if v and v.namespace then
                                v.product_code = req_product_code
                            end
                        end
                        cb(true, config_list)
                    end
                else
                    E.LOG.warn(TAG, 'post response failed, url:'..tostring(real_config_center_url)..', code:'..tostring(body_json.state.code)..', msg:'..tostring(body_json.state.msg))
                    cb(false, body_json.state.code or EC.CONFIG_CENTER_ERROR_CODES.SERVICE_ERROR, body_json.state.msg or '', body_json.data)
                end
            else
                E.LOG.warn(TAG, 'post response failed, url:'..tostring(real_config_center_url)..', body.state is nil')
                cb(false, EC.CONFIG_CENTER_ERROR_CODES.PARSE_DATA_FAIL, 'response could not be parsed')
            end
        else
            E.LOG.warn(TAG, 'post response failed, url:'..tostring(real_config_center_url)..', status:'..tostring(resp.status))
            cb(false, resp.status or EC.CONFIG_CENTER_ERROR_CODES.HTTP_REQUEST_FAIL, 'request error')
        end
    end)
end

local function timer_fire_request_configs()
    
    get_configs_from_server(request_namespaces, CONFIG_CENTER_UPDATE_TYPE.INC, function ()
        
    end)
end

-- 获取单个namespace
-- 内部有白名单控制
-- namespaces 是一个table，eg: {'apm','ejoysdk_core'} 。必须全部在白名单内; ex_infos 只依附于namespaces的存在
function M.get_configs_in_whitelist(str_namespaces, cb)

    local in_white_list_nps = {}
    if str_namespaces and type(str_namespaces) == 'table' then
        for _, v in pairs(str_namespaces) do
            if white_namespace_list[v] ~= nil then
                table.insert(in_white_list_nps, v)
            end
        end
    end

    if #in_white_list_nps > 0 then
        get_configs_from_server(in_white_list_nps, CONFIG_CENTER_UPDATE_TYPE.INC, cb)
    else
        cb(false, EC.CONFIG_CENTER_ERROR_CODES.NAMESPACE_NOT_IN_WHITE_LIST, 'all namespaces is not in white list')
    end
end

-- 该接口直接获取namespace配置
function M._get_configs_from_server(str_namespaces, cb)
    get_configs_from_server(str_namespaces, CONFIG_CENTER_UPDATE_TYPE.INC, cb)
end

-- 获取指定配置项
--   options.product_code可以从特定product_code获取配置等
--   options.disable_update_cache默认true,不，响更新其他本地缓存
function M.get_configs_with_options(options, str_namespaces, cb)
    options = options or {}
    local product_code = options.product_code
    local disable_update_cache = true
    if options.disable_update_cache ~= nil then
        disable_update_cache = options.disable_update_cache
    end
    local update_type = options.update_type or CONFIG_CENTER_UPDATE_TYPE.ALL
    get_configs_from_server(str_namespaces, update_type, cb, product_code, disable_update_cache)
end

local need_update_init_namespace = false
-- 传指定_namespace进行删除，不传删除全部
function M.delete_config(_namespace)
    if load_configs() then
        if not _namespace then
            cache_configs = {}
        elseif cache_configs[_namespace] then
            cache_configs[_namespace] = nil
        end
        save_disk_configs()
        need_update_init_namespace = true
    end
end

-- 变更productcode前调用，判断是否有变更来删除本地配置, 如果没有变更则不会删除
-- _new_productcode即将变更的productcode，_namespace不传删除全部
function M.delete_with_new_product(_new_productcode, _namespace)

    local cur_productcode = E.CONFIG.get_config("product")
    if _new_productcode and cur_productcode then
        cur_productcode = cur_productcode:lower()
        if cur_productcode == _new_productcode:lower() then
            E.LOG.debug(TAG, "new_productcode = current productcode is no need to delete")
            return
        end
    end

    E.LOG.debug(TAG, "delete current productcode: " .. tostring(cur_productcode))
    M.delete_config(_namespace)
end

-- ======================== 5.handler ========================
local set_player_info_handler = function(player_info, _type)
    E.LOG.debug(TAG, "set_player_info_handler")
    -- 设置角色公参
    local params = {
        serverId = player_info.server_id,
        serverName = player_info.server_name,
        playerId = player_info.player_id,
        playerName = player_info.player_name,
        playerLevel = player_info.player_level,
        uid = uid or '',
        chuid = pid or '',
        chUserType = platform or '',
    }
    update_role_info(params)
end

local player_offline_handler = function()
    E.LOG.debug(TAG, "player_offline_handler")
    -- 设置角色公参
    local params = {
        serverId = '',
        serverName = '',
        playerId = '',
        playerName = '',
        playerLevel = '',
        uid = uid or '',
        chuid = pid or '',
        chUserType = platform or '',
    }
    update_role_info(params)
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
        serverId = '',
        serverName = '',
        playerId = '',
        playerName = '',
        playerLevel = ''
    }
    E.LOG.debug(TAG, 'login，clear cached role data and update account data of ConfigCenter')
    update_role_info(params)

    M.acc_info()
    local account_info = acc_info
    account_info.accountId = user_info.uid
    account_info.chuid = user_info.pid
    if user_info.platform ~= nil and user_info.platform ~= '' then
        account_info.chUserType = user_info.platform
    else
        account_info.chUserType = E.get_channel()
    end
    
    if account_info and env_info then
        env_info.accInfo = account_info
    end

end

local function gangplank_logout_handler()
    --登出成功，更新数据
    uid = ''
    pid = ''
    platform = ''
    -- update stat account param
    local params = {
        serverId = '',
        serverName = '',
        playerId = '',
        playerName = '',
        playerLevel = '',
        uid = '',
        chuid = '',
        chUserType = ''
    }
    E.LOG.debug(TAG, 'logout，clear cached account and role data of ConfigCenter')
    update_role_info(params)
end

local function gangplank_exit_handler()
    uid = ''
    pid = ''
    platform = ''
    -- update stat account param
    local params = {
        serverId = '',
        serverName = '',
        playerId = '',
        playerName = '',
        playerLevel = '',
        uid = '',
        chuid = '',
        chUserType = ''
    }
    E.LOG.debug(TAG, 'exit，clear cached account and role data of ConfigCenter')
    update_role_info(params)
end

-- 检查product_code和本地缓存是否匹配
local function check_productcode_change_handler()
    local current_product_code = E.CONFIG.get_config("product")
    current_product_code = current_product_code and current_product_code:lower()

    local _cache_configs_map = load_configs()
    local _cache_product_code
    for _ns, cinfo in pairs(_cache_configs_map) do
        if cinfo and cinfo.product_code then
            _cache_product_code = cinfo.product_code
            break
        end
    end

    _cache_product_code = _cache_product_code and _cache_product_code:lower()
    --_ejoysdk.log(">>>>>>>>>>>>> _cache_product_code:" .. tostring(_cache_product_code) .. ", current_product_code:" .. tostring(current_product_code))
    --E.log(_cache_configs_map)
    if _cache_product_code and current_product_code
            and _cache_product_code ~= ''
            and current_product_code ~= ''
            and _cache_product_code ~= current_product_code then
        E.LOG.warn(TAG, "current startup product_code different with cache product_code, begin remove cache, curp:"
                .. tostring(current_product_code) .. ", cachep:" .. tostring(_cache_product_code))
        -- delete other product_code cache, it maybe review product code cache
        M.delete_config()
    else
        E.LOG.debug(TAG, "cache is nil or current product_code equals cache product_code, keep cache config")
    end
end

-- ======================== 6.unittest ========================
-- 用于单元测试，请勿调用
function M.get_config_for_unittest()
    return load_configs()
end

M._debug_publish = publish

-- ======================== 7.lifecycle ========================
-- 轮询，每 ${LOOP_SEC}s 执行一次
local function loop_request()
    E.Timer.once(LOOP_SEC, function ()
        timer_fire_request_configs()
        loop_request()
    end)
end

-- ======================== 8.ejoysdk内置namespace处理 ========================
local function ns_biz_handler(biz_config)
    if biz_config and biz_config.config then
        local cc_cutout_infos = biz_config.config.cutout_infos
        local model_str = E.Sysinfo.model() or ''
        if cc_cutout_infos and type(model_str) == 'string' and #model_str ~= 0 then
            local cutout_info = cc_cutout_infos[model_str]
            if cutout_info then
                _ejoysdk.log('update cutout from config_center')
                local cut_params = {}
                cut_params['cutout_info'] = { [model_str] = cutout_info } -- 兼容旧版本的格式
                E.Sysinfo.update_cutout(cut_params)
            end
        end
    end
end

-- 增加首次数据状态标记
M.is_data_inited = false

-- init
function M.init()
    if inited then
        E.LOG.debug(TAG, 'already inited, just notify init success and return')
        return
    end
    
    -- 更新公参数据
    ET.subscribe(ET.gangplank.LOGIN, login_handler)
    ET.subscribe(ET.gangplank.LOGOUT, gangplank_logout_handler)
    ET.subscribe(ET.gangplank.EXIT, gangplank_exit_handler)
    ET.subscribe(ET.gangplank.SET_PLAYER_INFO_WITH_TYPE, set_player_info_handler)
    ET.subscribe(ET.gangplank.PLAYER_OFFLINE, player_offline_handler)

    ET.subscribe(ET.gangplank.INITED, function(succ, ...)
        E.LOG.debug(TAG, "need_update_init_namespace is " .. tostring(need_update_init_namespace))
        if succ and need_update_init_namespace then
            -- 多次初始化且未删除过需要更新一下缓存
            get_configs_from_server(INIT_NAMESPACES, CONFIG_CENTER_UPDATE_TYPE.INC, function (_succ, ...)
                if _succ then
                    need_update_init_namespace = false
                end
            end)
        end
    end)

    -- check product_code compatibility
    check_productcode_change_handler()
    -- subscribe and check product_code change
    ET.subscribe(ET.config.CONFIG_CHANGED, check_productcode_change_handler)

    -- 自处理的ns
    M.subscribe(M.NAMESPACE.EJOYSDK_BIZ, ns_biz_handler)

    -- 加载本地存储的config
    load_configs()

    -- 执行一次请求，如果需要卡初始化这里需要改变请求的时机，cb
    -- 这里使用的是初始化的配置
    get_configs_from_server(INIT_NAMESPACES, CONFIG_CENTER_UPDATE_TYPE.INC, function (...)
        M.is_data_inited = true
        ET.publish(ET.config_center.DATA_INITED, ...)

        E.LOG.debug(TAG, 'config_center_init_succ_handler inited')
        local succ = ...
        local ql = require "ejoysdk_lua.ejoysdk_qualitylog"
        if succ then
            ql.commit_action_succ_main("ejoy_config_center_end")
        else
            local _succ, code, msg = ...
            ql.commit_action_fail_main("ejoy_config_center_end", nil, code, msg)
        end
    end)

    -- 开始轮询，首次不会立刻执行，计时完后执行
    loop_request()

    inited = true
end

return M

