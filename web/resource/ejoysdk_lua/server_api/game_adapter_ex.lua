local BASE_API = require 'ejoysdk_lua.libs.base_api'
local game_adapter_api = BASE_API:New('game-adapter')
-- local E = require 'ejoysdk_lua.ejoysdk'
-- local EM = require "ejoysdk_lua.ejoysdk_module"
-- local TAG = EM.MODULE.SERVER_API .. 'game_adapter_ex'

local M = {}

local function game_adapter_api_path(api, ver)
    
    if ver then
        api = '/v' .. tostring(ver) .. api
    end

    return api
end

----------------  预约服务器接口 ----------------  
-- 接口文档：https://yuque.antfin.com/ejoy-platform/user_guide/iit5ts#ntFf5
--[[ 
--  获取预约服务器列表
    @param
    params : table
        可选参数：lbs_info，表示lbs信息,  eg: { lbs_info = { city_code = "", country_code = "", ... } } ，可以从LBS.get_location接口获取。
        SDK内部接口解耦，不强制该接口触发获取到lbs信息，由业务方选择触发时机。接口是否需要触发定位权限/ip解析lbs的请求可以参考如下：

        1. 如需获取lbs信息，opt传递参考 LBS.get_location 接口，可能涉及opt传递弹窗描述等字段
            if EC.has_vendor_config('LBS') then
                local LBS = require 'ejoysdk_lua.vendors.lbs'
                LBS.get_location(opt, function(succ, ...)
                    if succ then
                        local lbs_info = ...
                        local r_params = { lbs_info = lbs_info }
                        -- 传入lbs信息
                        get_reserve_server_list(r_params, function(succ, ...)
                            if succ then
                                local reserve_server_list = ...
                            end
                        end)
                    end
                end)
            else -- 兼容旧版本和云端
                local EG = require 'ejoysdk_lua.ejoysdk_gangplank'
                EG.get_ip_location_async(function(succ, ...)                 
                    if succ then
                        local lbs_info = ...
                        local r_params = { lbs_info = lbs_info }
                        get_reserve_server_list(r_params, cb)
                    end
                end)
            end
        2. 如不传lbs信息，不启用区域推荐功能

    cb : function
    参考 cb(succ, ...)
        cb(true, reserve_server_list) 或 cb(false, code, message)
        reserve_server_list : table，预约服务器信息
            recomment : 是否是推荐预约服务器
            reserve_begin : 预约开始时间，单位毫秒 假如为 null，表示不限制
            reserve_end : 预约结束时间，单位毫秒 假如为 null，表示不限制
            server_info : 服务器信息。start_timestamp，开服时间，单位毫秒， null 表示未确定开服时间
        eg:
        ["reserve_server_list"] => table: 0x2816c2640{
            [1] => table: 0x2816c2680{
            ["reserve_begin"] => 1646289400443
            ["server_info"] => table: 0x2816c26c0{
                ["server_id"] => "test_interface"
                ["server_name"] => "test_interface"
            }
            ["reserve_end"] => 1646894203196
            ["recomment"] => false
            }
        }
]]

function M.get_reserve_server_list(_params, cb)
    local params = _params or {}
    local opt = { use_ejoy_token = true }

    game_adapter_api:post(game_adapter_api_path('/reserve_server/get_reserve_server_list'), {}, params, opt, function(succ, ...)
        if succ then
            local body = ...
            local list = body.data and body.data.reserve_server_list
            cb(succ, list)
        else
            cb(succ, ...)
        end
    end)
end

--[[ 
-- 获取我的预约服务器列表
    @param
    cb : function
    参考 cb(succ, ...)
        cb(true, data) 或 cb(false, code, message)
        data : table
            limit : 玩家预约上限；
            reserved_servers : 已预约服务器信息; 
            server_id和server_name : 服务器id和名称; 
            status : 预约状态(string), 包含reserved=已预约, notified=预约、开服且未创角
        
        eg:
        data => table: 0x2816c2640{
            ["reserved_servers"] => table: 0x2805d9300{
                [1] => table: 0x2805da8c0{
                    ["server_id"] => "test_interface"
                    ["server_name"] => "test_interface"
                    ["status"] => "reserved"
                }
            }
            ["limit"] => 5
        }
]]
function M.get_account_reserve_info(cb)
    local body = {}
    local opt = { use_ejoy_token = true }
    game_adapter_api:post(game_adapter_api_path('/reserve_server/get_account_reserve_info'), {}, body, opt, function(succ, ...)
        if succ then
        local res_body = ...
            cb(succ, res_body.data)
        else
            cb(succ, ...)
        end
    end)
end

--[[ 
-- 预约服务器
    @param
    params : table，支持参数server_id设置预约服务器id
    参考 { server_id = "123" }

    cb : function
    参考 cb(succ, ...)
        cb(true, data) 或 cb(false, code, message)
]]
function M.do_reserve_server(_params, cb)
    local params = _params or {}
    local opt = { use_ejoy_token = true }
    game_adapter_api:post(game_adapter_api_path('/reserve_server/do_reserve_server'), {}, params, opt,  cb)
end

--[[ 
-- 取消预约服务器
    @param
    params : table，支持参数server_id设置取消预约服务器id
    参考 { server_id = "123" }
    
    cb : function
    参考 cb(succ, ...)
        cb(true, data) 或 cb(false, code, message)
]]
function M.cancel_reserve_server(_params, cb)
    local params = _params or {}
    local opt = { use_ejoy_token = true }
    game_adapter_api:post(game_adapter_api_path('/reserve_server/cancel_reserve_server'), {}, params, opt,  cb)
end

return M
