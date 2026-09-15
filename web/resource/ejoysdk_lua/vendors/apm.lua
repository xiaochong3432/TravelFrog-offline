local E = require "ejoysdk_lua.ejoysdk"
-- local ET = require "ejoysdk_lua.ejoysdk_topic"
local UNI = require "ejoysdk_lua.vendors.unisdk"
local Vendor = require "ejoysdk_lua.vendors.vendor"
local JSON = require 'ejoysdk_lua.ejoysdk_json'
-- local ejoysdk_init = require 'ejoysdk_lua.ejoysdk_init'
local ET = require 'ejoysdk_lua.ejoysdk_topic'
local ECC = require 'ejoysdk_lua.ejoysdk_config_center'
local EM = require "ejoysdk_lua.ejoysdk_module"
local ETAPUS = require "ejoysdk_lua.ejoysdk_to_apus"
-- require 'ejoysdk_lua.server_api.ejoysdk_bbs'

--APM SDK
local CHANNEL = "APM"
local M = Vendor:Inherit(CHANNEL)
--初始化 apmsdk
-- local CAST_INIT_APM_SDK = "CAST_INIT_APM_SDK"

local CAST_NETWORK_PING = "CAST_NETWORK_PING"
local CAST_NETWORK_TRACEROUTE = "CAST_NETWORK_TRACEROUTE"
local CALLBACK_NETWORK_EVENT = "network_state_change" --网络发生变化

local APM_EVENT_NET = "apm.net.netanalysis"

local TAG = EM.MODULE.VENDORS.APM
local inited = false
local DEFAULT_FREQUNCE_ENABLE = true 
local DEFAULT_FREQUNCE_PER_SEC = 900
local MIN_FREQUNCE_PER_SEC = 300 
local DEFAULT_PRE_NETWORK_CHANGED_DETECT = 5 * 60 
-- 默认需要检测的服务和域名：gangplank/launcher/bbs/pusher/chat, 平台服务都属于同机房，只需要保留一个即可
local DEFAULT_DOMAIN_SERVICES = {
    gangplank = true
}
local default_domains = {}
local frequnce_per_sec = DEFAULT_FREQUNCE_PER_SEC --默认15分钟检测一次
local frequnce_enable = DEFAULT_FREQUNCE_ENABLE --是否开启定时自动网络检测, 默认true
local detect_domains --默认检测域名
local not_enable_domains = {} --未部署服务域名过滤
local nw_namespace_config = {} --配置中心下发配置
local last_dectected_time = 0
local acc_info = {}

local APMEVENT
local function report_apm_event(event_name, _lablels, _trace_id, _msg, _stats)

    if APMEVENT == nil then
        local ok, apm_event = pcall(require, "ejoysdk_lua.apm-sdk-lua.event.event")
        if ok then
            APMEVENT = apm_event
        end
    end 

    if APMEVENT ~= nil then
        local labels = _lablels or {}
        local trace_id = _trace_id or 0
        local stats = _stats or {}
        local msg = _msg or ''
        APMEVENT.post(event_name, labels, trace_id, msg, stats)
    end
end

function M.set_frequnce_enable(_frequnce_enable)
    frequnce_enable = _frequnce_enable
end

function M.set_frequnce_per_sec(_frequnce_per_sec)
    frequnce_per_sec = _frequnce_per_sec
    -- 保护一下，最少需要设置5min
    if frequnce_per_sec < MIN_FREQUNCE_PER_SEC then
        frequnce_per_sec = MIN_FREQUNCE_PER_SEC
    end
end

-- 网络检测相关
-- ping _params 指定域名
-- _params = {'ulr1','url2'}
function M.ping(_params, cb)

    local os_name = _ejoysdk.os()
    local params = _params or {}
    -- windows还没有unisdk
    if os_name =='windows' then
        E.Sysinfo.network_ping(params, cb)
    else
        UNI.async_call(CHANNEL, CAST_NETWORK_PING, { params = params }, nil, function(succ, ...)
            if succ then
                local body = ...
                if body ~= nil then
                    cb(true, body.data)
                end
            else
                local code, body = ...
                E.LOG.debug(TAG, 'ping fail:' .. tostring(code) .. ' ,msg: ' .. tostring(body and body.msg))
                cb(false, tostring(code), tostring(body and body.msg))
            end
        end)
    end
end

-- traceroute _params 指定域名
-- _params = {'ulr1','url2'}
function M.traceroute(_params, cb)

    local os_name = _ejoysdk.os()
    local params = _params or {}
    -- windows还没有unisdk
    if os_name =='windows' then
        E.Sysinfo.network_traceroute(params, cb)
    else
        UNI.async_call(CHANNEL, CAST_NETWORK_TRACEROUTE, { params = params }, nil, function(succ, ...)
            if succ then
                local body = ...
                if body ~= nil then
                    cb(true, body.data)
                end
            else
                local code, body = ...
                E.LOG.debug(TAG, 'traceroute fail:' .. tostring(code) .. ' ,msg: ' .. tostring(body and body.msg))
                cb(false, tostring(code), tostring(body and body.msg))
            end
        end)
    end

end

-- 从配置中心更新网络配置
local function update_network_namespace_config(_config)
    nw_namespace_config = _config or {}

    local unique_domains = {} -- 去重map
    for _, v in pairs(detect_domains) do
        if v then
            unique_domains[v] = true
        end
    end

    local sub_config = nw_namespace_config.config
    if sub_config ~= nil then
        local net_any = sub_config.net_any or {}
        if net_any.domains ~= nil then
            local domains = net_any.domains
            for _, v in pairs(domains) do
                if unique_domains[v] == nil then
                    table.insert(detect_domains, v)
                end
            end
        end

        M.set_frequnce_per_sec(net_any.frequnce_per_sec or DEFAULT_FREQUNCE_PER_SEC)

        if net_any.frequnce_enable ~= nil then
            frequnce_enable = net_any.frequnce_enable
        else
            frequnce_enable = DEFAULT_FREQUNCE_ENABLE
        end
    end    
end

-- 从配置中心更新APM配置
local function update_apm_namespace_config(_config)
    
end

function M.start_detect()

    local filter_domains = {}
    for _, v in pairs(detect_domains) do
        if not_enable_domains[v] == nil then 
            table.insert(filter_domains, v)
        end
    end
    
    if #filter_domains > 0 and frequnce_enable then

        M.ping(filter_domains, function(succ, ...)
            if succ then
                local list = ...
                if list and #list > 0 then
                    for _, v in pairs(list) do
                        local msg_str = tostring(v.status) .. '(' .. tostring(v.code) .. ')'
                        local results = JSON.safe_decode(v.data)
                        local stats = {}
                        local labels = { target = v.target, cmd = 'apm.net.ping'}

                        if results ~= nil and type(results) == 'table'  then
                            stats = {
                                avg_delay = results.avg_delay or -1,
                                loss = results.loss or -1,
                                count = results.count or -1
                            }
                            labels['target_ip'] = results.target_ip or ''
                        end
                        report_apm_event(APM_EVENT_NET, labels, 0, msg_str, stats)

                        -- 5是CMD_STATUS_ERROR_UNKNOW_HOST，没有这个服务就不在检测了
                        if '5' == tostring(v.code) and v.target then
                            not_enable_domains[v.target] = true
                        end
                    end
                end
            end
        end)

        M.traceroute(filter_domains, function(succ, ...)
            if succ then
                local list = ...
                if list and #list > 0 then
                    for _, v in pairs(list) do
                        local labels = { target = v.target, cmd = 'apm.net.traceroute' }
                        local msg_str = tostring(v.status) .. '(' .. tostring(v.code) .. ')'
                        if v.data ~= nil and v.data ~= '' then
                            msg_str = v.data
                        end
                        report_apm_event(APM_EVENT_NET, labels, 0, msg_str, {})

                        -- 5是CMD_STATUS_ERROR_UNKNOW_HOST，没有这个服务就不在检测了
                        if '5' == tostring(v.code) and v.target then 
                            not_enable_domains[v.target] = true
                        end
                    end
                end
            end
        end)
    end
end

local function start_timer_detect()
    if frequnce_enable then 
        E.Timer.once(frequnce_per_sec, start_timer_detect)
    end

    local current_time = os.time()
    if (current_time - last_dectected_time > DEFAULT_PRE_NETWORK_CHANGED_DETECT) or last_dectected_time == 0 then
        last_dectected_time = current_time
        M.start_detect()
    end
end


local first_state_changed = 1
local function start_net_state_changed_detect(state_info)
    if state_info ~= nil and type(state_info) == 'table' and first_state_changed == 1 then
        if state_info.state ~= nil and tostring(state_info.state) ~= '0' then
            local current_time = os.time()
            if current_time - last_dectected_time > DEFAULT_PRE_NETWORK_CHANGED_DETECT then
                last_dectected_time = current_time
                M.start_detect()
            end
        end
        first_state_changed = 0
    end
end

--初始化apmsdk
local function init_apm_sdk(_opt)
    local ok, APM = pcall(require, "ejoysdk_lua.apm-sdk-lua.apm")
    if ok then
        APM.init()
    end
end

local function trim_start_http(str)
    local nstr = str
    if nstr ~= nil then
        if E.Utils.start_with(nstr, 'https://') then
            nstr = E.Utils.trim_start(nstr,'https://')
        elseif E.Utils.start_with(nstr, 'http://') then
            nstr = E.Utils.trim_start(nstr,'http://')
        end
    end
    return nstr
end

local function setup_defaul_domain()
    default_domains = {}

    local unique_domains = {} -- 去重map

    -- 获取预制的domains
    for k, v in pairs(DEFAULT_DOMAIN_SERVICES) do
        if v then
            local url_prefix = E.CONFIG.get_config(k)
            if url_prefix and #url_prefix > 0 then
                local url_domain = trim_start_http(url_prefix)
                table.insert(default_domains, url_domain)
                unique_domains[url_domain] = true
            end
        end
    end

    local ec = require 'ejoysdk_lua.chat.ejoysdk_chat_server'
    if ec ~= nil then
        local chat_server = ec.get_server_addr()
        if chat_server ~= nil then
            local chat_domain = trim_start_http(chat_server)
            table.insert(default_domains, chat_domain)
            unique_domains[chat_domain] = true
        end
    end

    detect_domains = default_domains

    -- 拿首次的配置
    nw_namespace_config = ECC.get_config(ECC.NAMESPACE.NETWORK)

    if nw_namespace_config ~= nil then
        local sub_config = nw_namespace_config.config
        if sub_config ~= nil then
            local net_any = sub_config.net_any or {}
            if net_any.domains ~= nil then
                local domains = net_any.domains
                for _, v in pairs(domains) do
                    if unique_domains[v] == nil then
                        table.insert(detect_domains, v)
                    end
                end
            end

            M.set_frequnce_per_sec(net_any.frequnce_per_sec or DEFAULT_FREQUNCE_PER_SEC)

            if net_any.frequnce_enable ~= nil then
                frequnce_enable = net_any.frequnce_enable
            else
                frequnce_enable = DEFAULT_FREQUNCE_ENABLE
            end
        end
    end

end

local function on_acc_info_change_handler(_acc_info)
    -- E.LOG.debug(TAG, "on_acc_info_change_handler received")
    -- E.log(_acc_info)
    acc_info = _acc_info or {}
end

function M.init(opt, cb)
    E.LOG.debug(TAG, 'apmsdk start init!')

    if inited then 
        E.LOG.debug(TAG,'apmsdk had inited')
        cb(true)
        return
    end

    -- 获取需要检测的配置
    setup_defaul_domain()

    -- 初始化apm sdk
    init_apm_sdk(opt)

    if frequnce_enable then 
        E.Timer.once(5, start_timer_detect) -- 初始化后5s, 先执行一次
    end

    -- 订阅配置中心
    ECC.subscribe(ECC.NAMESPACE.NETWORK, update_network_namespace_config)
    ECC.subscribe(ECC.NAMESPACE.APM, update_apm_namespace_config)

    -- 监听网络变化
    ET.subscribe(CALLBACK_NETWORK_EVENT, start_net_state_changed_detect)

    -- register acc_info change
    local estat = require "ejoysdk_lua.ejoysdk_stat"
    estat.register_acc_info_change_listener(on_acc_info_change_handler)


    --[[
    {
       ["accountCh"] => "998233"
       ["chuid"] => "2b358359c7979279efc740412468028a"
       ["chUserType"] => "998233"
       ["accountId"] => "2b358359c7979279efc740412468028a"
    }
    --]]
    ETAPUS.add_dynamic_label("acc_ch", function()
        return acc_info["accountCh"]
    end)

    ETAPUS.add_dynamic_label("acc_ch_uid", function()
        return acc_info["chuid"]
    end)

    ETAPUS.add_dynamic_label("acc_ch_user_type", function()
        return acc_info["chUserType"]
    end)

    ETAPUS.add_dynamic_label("acc_account_id", function()
        return acc_info["accountId"]
    end)

    cb(true)
end

return M