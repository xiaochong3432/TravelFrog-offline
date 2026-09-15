local ET = require "ejoysdk_lua.ejoysdk_topic"
local EM = require "ejoysdk_lua.ejoysdk_module"
local unpack = unpack or table.unpack

local EJOYSDK_CONFIG = {
    zone = 'CN',
    default_lang = 'CN',
    os = 'ios',
    id = 'https://id.ejoy.com',
    region = nil,
    http_dns = false
}

setmetatable(EJOYSDK_CONFIG, {__index = function(self, key)
    if key == 'lang' then
        -- 首次启动，获取 LANG 的 startup 语言
        local LANG = require 'ejoysdk_lua.ejoysdk_lang'
        local startup_lang = LANG.get_startup_lang()
        rawset(EJOYSDK_CONFIG, 'lang', startup_lang)
        return startup_lang
    elseif key == 'district' then
        local ejoy = require("ejoysdk_lua.ejoysdk")
        local country =  ejoy.Sysinfo.country()
        rawset(EJOYSDK_CONFIG,'district',country)
        return country
    else
        return nil
    end
end})

local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'config'

local M = {}

M.KEY = {
    REGION = 'region',
    PUBLISH_AREA = 'publish_area', -- ISO 3166 alpha-2国家代码
    SERVER_DOMAIN = 'server_domain',
    LOCAL_GANGPLANK_REGION = 'local_gangplank_region',
    LOCAL_GANGPLANK_URL_BASE = 'local_gangplank_url_base',
    GLOBAL_GANGPLANK_ENABLED = 'global_gangplank_enabled',
    MULTI_REGIONS_ENABLED = 'multi_regions_enabled',
    APP_VERSION_UPDATE_CHECK = 'app_version_update_check',
    DOMAIN_ACCOUNT_CENTER = 'domain_account_center',
    INIT_ARGS = ' initialized_arguments',
    APP_REVIEW_VERSION = "app_review_version" -- 游戏提审版本号
}

M.RULE_KEY = {
    -- 服务拼接规则
    RULE_SERVICE = 'service_splice_rule',
    -- region拼接规则
    RULE_REGION = 'region_splice_rule'
}

-- url service 拼接规则
M.URL_SERVICE_SPLICE_RULE = {
    -- 默认拼接规则为把服务名（service）拼接在domain里
    -- 例如：scheme .. '://' .. prefix .. '-' .. service .. domain
    RULE_DEFAULT = 'rule_service_splice_in_domain',

    -- 将服务名（service）拼接在url path部分
    RULE_SERVICE_SPLICE_IN_PATH = 'rule_service_splice_in_path',

    -- 将服务名（service）拼接在url path部分，域名部分完整替换为domain
    RULE_FULL_DOMAIN_SPLICE = 'rule_service_splice_full_domain'
}

M.URL_REGION_SPLICE_RULE = {
    -- region 拼接在domain中
    RULE_DEFAULT = 'rule_region_splice_in_domain',
    -- region 不拼接
    RULE_NO_REGION = 'rule_region_none'
}

M.DOMAIN_EJOY = '.ejoy.com'

M.DOMAIN_CONFIG = {
    -- 国内的PC端，国内的移动端都会使用这个域名，不设置则使用该默认值，设置了就使用设置的值
    USER_CENTER = 'https://res.flysdk.cn'
}

local domain = M.DOMAIN_EJOY
local cdn_domain = nil

local DEFAULT_URL_COMBINE_RULES = {
    [M.RULE_KEY.RULE_SERVICE] = M.URL_SERVICE_SPLICE_RULE.RULE_DEFAULT,
    [M.RULE_KEY.RULE_REGION] = M.URL_REGION_SPLICE_RULE.RULE_DEFAULT
}

local current_url_combine_rules = DEFAULT_URL_COMBINE_RULES

function M.set_domain(domain_name)
    if domain_name == nil or domain_name == '' then
        _ejoysdk.log(TAG .. 'set_domain failed, domain is nil')
        return
    end

    domain = domain_name
    _ejoysdk.log(TAG .. 'set_domain success: ' .. domain)
end

function M.reset_domain()
    domain = M.DOMAIN_EJOY
    _ejoysdk.log(TAG .. 'reset_domain success: ' .. domain)
end

function M.reset_splice_rules()
    current_url_combine_rules = DEFAULT_URL_COMBINE_RULES
    _ejoysdk.log(TAG .. 'reset_splice_rules success, service rule:'..(current_url_combine_rules[M.RULE_KEY.RULE_SERVICE])..', region rule:'..(current_url_combine_rules[M.RULE_KEY.RULE_REGION]))
end

function M.set_splice_rules(splice_rules)
    if not splice_rules then
        return
    end

    local rules = {}
    rules.service_splice_rule = splice_rules.service_splice_rule or M.URL_SERVICE_SPLICE_RULE.RULE_DEFAULT
    rules.region_splice_rule = splice_rules.region_splice_rule or M.URL_REGION_SPLICE_RULE.RULE_DEFAULT
    current_url_combine_rules = rules
end

function M.get_splice_rules()
    return current_url_combine_rules
end

function M.get_domain()
    return domain
end

function M.set_cdn_domain(domain_name)
    cdn_domain = domain_name
end

local all_service_normal = {
    {'launcher', 'https'},
    {'trace', 'https'},
    {'gangplank', 'https'},
    {'holo', 'https'},
    {'cs', 'https'},
    {'holo-cdn', 'http'},
    {'friend', 'https'},
    {'pusher', 'https'},
    {'log-collector', 'https'},
    {'search', 'https'},
    {'user-info', 'https'},
    {'ad-server','https'},
    {'qabot', 'https'},
    {'favor', 'https'},
    {'game-adapter','https'}
}

local all_service_backup = {
    {'launcher', 'http'},
    {'trace', 'http'},
    {'gangplank', 'http'},
    {'holo', 'http'},
    {'cs', 'http'},
    {'holo-cdn', 'http'},
    {'friend', 'http'},
    {'pusher', 'https'},
    {'log-collector', 'http'},
    {'search', 'http'},
    {'user-info', 'http'},
    {'ad-server','http'},
    {'qabot', 'http'},
    {'favor', 'https'},
    {'game-adapter','http'}
}

local all_service = all_service_normal

function M.set_service_backup()
    all_service = all_service_backup
end

local function url_base(scheme, prefix, service)
    local result
    local service_splice_rule = current_url_combine_rules.service_splice_rule
    if service_splice_rule == M.URL_SERVICE_SPLICE_RULE.RULE_SERVICE_SPLICE_IN_PATH then
        result = scheme .. '://' .. prefix .. '-platform' .. domain .. '/' .. service
    elseif service_splice_rule == M.URL_SERVICE_SPLICE_RULE.RULE_FULL_DOMAIN_SPLICE then
        result = scheme .. '://' .. domain .. '/' .. service
    else
        result = scheme .. '://' .. prefix .. '-' .. service .. domain
    end

    -- _ejoysdk.log(TAG .. 'url_base result, url:' .. result:lower() .. ', splice_rule:' .. service_splice_rule)
    return result
end

local function get_prefix_for_region(region)
    local product = EJOYSDK_CONFIG.product
    local prefix
    if EJOYSDK_CONFIG.env == 'product' then
        prefix = product
    else
        prefix = tostring(EJOYSDK_CONFIG.env) .. tostring(product)
    end

    if region and current_url_combine_rules.region_splice_rule == M.URL_REGION_SPLICE_RULE.RULE_DEFAULT then
        prefix = tostring(prefix) .. '-' .. tostring(region)
    end

    return prefix
end

local function get_url_base(scheme, prefix, service)
    local url = url_base(scheme, prefix, service)
    url = url:lower()
    return url
end

-- 根据传入的service 拼接平台域名获取url_base
function M.get_url_base_for_service(service)
    _ejoysdk.log(TAG..'get_url_base_for_service, service:' .. tostring(service))
    if not service or service == '' then
        _ejoysdk.log(TAG..'get_url_base_for_service failed, service is nil')
        return nil
    end

    local gangplank_region_prefix = get_prefix_for_region(EJOYSDK_CONFIG.region)
    local url = get_url_base('https', gangplank_region_prefix, service)

    _ejoysdk.log(TAG..'get_url_base_for_service, service:'..service..', url:'..tostring(url))
    return url
end

--更新ejoysdk service url
function M.update_ejoysdk_service()
    -- _ejoysdk.log(TAG..'update_ejoysdk_service begin!')
    local gangplank_region_prefix = get_prefix_for_region(EJOYSDK_CONFIG.region)

    for _, v in ipairs(all_service) do
        local service, scheme = unpack(v)
        EJOYSDK_CONFIG[service] = get_url_base(scheme, gangplank_region_prefix, service)
        -- _ejoysdk.log(TAG..'update_ejoysdk_service, service:'..service..', url:'..(EJOYSDK_CONFIG[service] or 'nil'))
    end
end

local function update_local_gangplank_url(local_gangplank_region)
    if not local_gangplank_region then
        _ejoysdk.log(TAG..'update_local_gangplank_url failed, region is nil!')
        return
    end

    for _, v in ipairs(all_service) do
        local service, scheme = unpack(v)
        -- 如果设置了本地的地区信息，也需要更新本地的gangplank地址
        if service == 'gangplank' then
            local local_gangplank_region_prefix = get_prefix_for_region(local_gangplank_region)
            EJOYSDK_CONFIG[M.KEY.LOCAL_GANGPLANK_URL_BASE] = get_url_base(scheme, local_gangplank_region_prefix, service)
            break
        end
    end
end

function M.autoconfig(env, product)
    if type(env) == 'string' and type(product) == 'string' then
        EJOYSDK_CONFIG.product = product
        EJOYSDK_CONFIG.env = env
    elseif type(env) == 'table' and product == nil then
        local opt = env
        --env = opt.env
        --product = opt.product
        for k, v in pairs(opt) do
            EJOYSDK_CONFIG[k] = v
        end
    else
        assert(nil, 'error config option')
    end

    --更新 ejoysdk service url
    M.update_ejoysdk_service()

    if cdn_domain then
        EJOYSDK_CONFIG['holo-cdn'] = 'http://' .. cdn_domain
    end

    -- 通知config变更
    ET.publish(ET.config.CONFIG_CHANGED)
end

local function hook_config_value(key, value)
    if value == nil then
        return nil
    end
    if key == 'lang' then
        return value:lower()
    end
    return value
end

function M.set_config(key, value)
    local old_value = EJOYSDK_CONFIG[key]
    value = hook_config_value(key, value)
    EJOYSDK_CONFIG[key] = value

    local data_changed = old_value ~= value
    if data_changed then
        _ejoysdk.log(TAG..'set_config data changed, key:'..(key or 'nil'))
    end

    if data_changed then
        -- _ejoysdk.log(TAG..'data changed, now update ejoysdk service url')
        --if region changed then update ejoysdk service url
        if key == 'region' then
            M.update_ejoysdk_service()
        elseif key == M.KEY.LOCAL_GANGPLANK_REGION then
            update_local_gangplank_url(value)
        end

        -- 通知config变更
        ET.publish(ET.config.CONFIG_CHANGED .. '_' .. key, value)
        ET.publish(ET.config.CONFIG_CHANGED)
    end
end

function M.get_config(key)
    return EJOYSDK_CONFIG[key]
end

function M.get_vendor_config(name)
    local meta = M.get_config('unisdk_meta')
    if not meta or not meta.sdks then
        return
    end
    for _, i in ipairs(meta.sdks) do
        if i.name == name then
            return i.meta
        end
    end
end

-- iOS 里没有name的字段，使用的是vendor的字段;
-- 同时两端大小写实现有所不同，需要抹平
function M.get_vendor_config_v2(name)

    if not name then return nil end

    local UNI = require "ejoysdk_lua.vendors.unisdk"
    local sdk_infos = UNI.get_sdk_infos()
    if not sdk_infos then
        return
    end

    if _ejoysdk.os() =='ios' then
        for _, i in pairs(sdk_infos) do
            if i.vendor then
                if i.vendor:lower() == name:lower() then
                    return i.meta
                end
            end
        end
    elseif _ejoysdk.os() =='android' or _ejoysdk.os() == 'windows' then
        for _, i in pairs(sdk_infos) do
            if i.name then
                if i.name:lower() == name:lower() then
                    return i.meta
                end
            end
        end
    end
end

function M.has_vendor_config(name)

    if not name then return nil end

    local UNI = require "ejoysdk_lua.vendors.unisdk"
    local sdk_infos = UNI.get_sdk_infos()
    if not sdk_infos then
        return false
    end

    local os_name = _ejoysdk.os()

    if os_name =='ios' then
        for _, i in pairs(sdk_infos) do
            if i.vendor then
                if i.vendor:lower() == name:lower() then
                    return true
                end
            end
        end
    elseif os_name =='android' or os_name == 'windows' then
        for _, i in pairs(sdk_infos) do
            if i.name then
                if i.name:lower() == name:lower() then
                    return true
                end
            end
        end
    end

    return false
end

function M.register_service(service)
    table.insert(all_service_normal, {service, 'https'})
    table.insert(all_service_backup, {service, 'http'})
    M.update_ejoysdk_service()
end

return M
