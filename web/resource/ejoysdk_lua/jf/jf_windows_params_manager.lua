local E = require 'ejoysdk_lua.ejoysdk'
local JF_WINDOWS_CONFIG = require 'ejoysdk_lua.jf.jf_windows_config'
--基础参数封装
local M = {}

--角色id
local roleId = ''
--角色名称
local roleName = ''
--服务器id
local serverId = ''
--服务器名称
local serverName = ''

function M.fill_role_info_params(event_log)
    local params = event_log.params or {}
    params.roleId = roleId or ''
    params.roleName = roleName or ''
    params.serverId = serverId or ''
    params.serverName = serverName or ''
    event_log.params = params
end

--经分协议基本参数外的参数封装，对应sdk的特定事件参数进行填充
function M.fill_event_log(event_log)
    --经分上报来源，默认hysdk
    event_log.src = 'hysdk'
    local event_name = event_log.event
    --对主要事件增加参数
    if event_name == JF_WINDOWS_CONFIG.EVENT_NAMES.SDK_START_UP_SUCCESS or event_name == JF_WINDOWS_CONFIG.EVENT_NAMES.SDK_INSTALL or event_name == JF_WINDOWS_CONFIG.EVENT_NAMES.SDK_START_UP then
        M.fill_ext_base_params(event_log)
    end
    return event_log
end

function M.update_role_info(params)
    params = params or {}
    roleId = params.player_id or ''
    roleName = params.player_name or ''
    serverId = params.server_id or ''
    serverName = params.server_name or ''
end

function M.fill_params(event_params, cb)
    local ES = require 'ejoysdk_lua.ejoysdk_stat'
    ES.get_jf_format_data(event_params.event_name, event_params.params, function(event_log)
        M.fill_event_log(event_log)
        cb(event_log)
    end)
end


-- 判断字段是否在隐私白名单内
function M.is_field_in_white_list(target_filed_name)
    local white_privacy_fields = JF_WINDOWS_CONFIG.get_white_privacy_fields()
    -- 没有白名单情况下，默认为true
    if not white_privacy_fields or next(white_privacy_fields) == nil then
        return true
    end
    for _, white_field in pairs(white_privacy_fields) do
        if target_filed_name == white_field then
            return true
        end
    end
end

function M.get_brand()
    if M.is_field_in_white_list('brand') then
        return E.Sysinfo.brand()
    else
        return ''
    end
end

function M.get_model()
    if M.is_field_in_white_list('model') then
        return E.Sysinfo.model()
    else
        return ''
    end
end

function M.get_os_version()
    if M.is_field_in_white_list('fr') then
        return E.Sysinfo.os_version()
    else
        return ''
    end
end

function M.get_cpu_model()
    if M.is_field_in_white_list('cpu') then
        return E.Sysinfo.get_cpu_model()
    else
        return ''
    end
end

--内存
function M.get_memory()
    if M.is_field_in_white_list('ramSize') then
        return E.Sysinfo.memory().Total
    else
        return ''
    end
end

function M.get_country()
    if M.is_field_in_white_list('country') then
        return E.Sysinfo.country()  -- windows用系统
    else
        return ''
    end
end

--分辨率
function M.get_res()
    if E.Sysinfo.screen_width() == -1 or E.Sysinfo.screen_height() == -1 then
        return ''
    else
        return tostring(E.Sysinfo.screen_width()) .. '*' .. tostring(E.Sysinfo.screen_height())
    end
end


--增加事件通用的扩展参数,判断字段白名单
function M.fill_ext_base_params(event_log)
    local devInfo = event_log.envInfo.devInfo
    devInfo.brand = M.get_brand()
    devInfo.model = M.get_model()
    --windows没有，留空
    devInfo.hw_machine = ''
    devInfo.fr = M.get_os_version()
    devInfo.res = M.get_res()
    -- cpu定义为cpu架构，cpuModel才是cpu型号
    devInfo.cpuModel = M.get_cpu_model()
    devInfo.ramSize = M.get_memory()
    --openGL版本号，windows留空
    devInfo.oglVer = ''
    devInfo.net = ''
    devInfo.ip = ''
    devInfo.country = M.get_country()
    devInfo.language = E.Sysinfo.language()
end

return M