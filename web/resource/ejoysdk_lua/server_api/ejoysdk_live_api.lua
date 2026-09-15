local E = require "ejoysdk_lua.ejoysdk"
local BASE_API = require 'ejoysdk_lua.libs.base_api'
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local holo_api = BASE_API:New('holo') -- 新建 holo api 模块

local TAG = 'live#ejoysdk_live_api'

local M = {}

-- 协议文档：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/ggantl
-- 1. 根据直播主题ID获取直播计划列表
--[[
    参数说明：
    topic_id   : string, 直播主题ID
    cb         : function, 回调，如 cb(true, data) 或 cb(false, code, message)
    返回参数：
    data 结构参考(服务端返回如后续有更新，以最新文档为准)：
    {
       sched_list : {
            id : string, 直播计划ID
            topic_id : string, 直播主题ID
            name : string, 直播间标题
            trend : number, 直播间热度值
            live_platform : string, 直播平台
            live_room_cfg : table, 直播间配置， 包含对应直播平台的直播间ID和资源地址
                room_id  : string
                resource_url : string
            sched_status : string, 直播间当前开启状态: OPENED（已开启）、 CLOSED（已关闭）、 UNOPENED（尚未开启）
            sched_start_time : number, 直播开始时间	UTC时间戳，时间单位为：毫秒
            sched_end_time : number, 直播结束时间 UTC时间戳，时间单位为：毫秒
            sched_latency_ms : number, 当前时间距离直播开始时间还有多少时间 UTC时间戳，时间单位为：毫秒。注意已开启的（OPENED）或者已结束的（OPENED），返回为值-1
            chat_group_broker_id : string, 聊天分线代理ID, 可用于匹配直播间对应的聊天分组ID前缀
            ...
        }
    }
    
    data eg：这里仅列举部分字段，服务端返回如后续有更新，以最新文档为准
    {
        ["sched_list"] => table: 0x282106c80{
            [1] => table: 0x28213b7c0{
                ["live_platform"] => "DOUYU"
                ["id"] => "62bd0c7ca8c93547e4d6027d"
                ["name"] => "zenzen_1"
                ["live_room_cfg"] => table: 0x2821d5000{
                    ["room_id"] => "654321"
                    ["resource_url"] => "https://open.douyu.com/tpl/h5/chain2/aid/98765"
                }
                ["topic_id"] => "62baf903f257229f5e53378d"
                ["trend"] => 783
                ...
            }
        }
    }
]] 
function M.get_topical_scheds(topic_id, cb)

    if not topic_id then
        cb(false, CONSTANTS.BASE_API_COMMON_ERROR.CODE_INVALID_PARAMETER, 'invalid topic_id')
        return
    end

    local params = {
        topic_id = topic_id
    }
    
    M.get_topical_scheds_with_params(params, cb)
end    

-- 预留支持更多参数的接口，当前必传 params = { topic_id = topic_id }
function M.get_topical_scheds_with_params(params, cb)
    local headers = {}
    local query_params = params or {}
    local opt = { use_moment_token = true, use_ejoy_token = true }
    holo_api:get('/live_sched/openapi/get_topical_scheds', headers, query_params, opt, function(succ, ...)
        if succ then
            local resp = ...
            cb(true, resp and resp.data)
        else
            E.LOG.debug(TAG,'get_topical_scheds fail')
            cb(false, ...)
        end
    end)
end

-- 协议文档：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/ggantl
-- 2. 客户端心跳上报
--[[
    参数说明：
    sched_id   : string, 直播计划ID
    cb         : function, 回调，如 cb(true, data) 或 cb(false, code, message)
    返回参数：
    data 结构参考(服务端返回如后续有更新，以最新文档为准)：
    table: 0x70e2f3a240 {
        sched_info : table, 直播计划信息，直播计划ID找不到时返回空
            id : string, 直播计划ID, 
            trend : number, 直播间热度值
            sched_status : string, 直播间当前开启状态: OPENED（已开启）、 CLOSED（已关闭）、 UNOPENED（尚未开启）
            sched_latency_ms : number, 当前时间距离直播开始时间还有多少时间 UTC时间戳，时间单位为：毫秒。注意已开启的（OPENED）或者已结束的（OPENED），返回为值-1
        next_interval : integer, 下次轮询时间间隔(秒); 此设计是为了避免集中请求（例如玩家通过红点触发进入的）,客户端可以设定一个兜底的时间间隔值，只有在某次请求异常时，才可以用默认的兜底值来决定下次轮询时间。
        reload_topical_sched_list : true, 是否需要重载直播主题对应的直播计划列表, 当识别到一个tick周期内，直播列表某个房间开启状态发生变化是，返回为true
        ...
    }

    data eg: 这里仅列举部分字段，服务端返回如后续有更新，以最新文档为准
    {
        ["next_interval"] => 117
        ["sched_info"] => table: 0x282cab040{
            ["trend"] => 783
            ["id"] => "62baf956fdc3b7952fa9efdc"
            ...
        }
        ["reload_topical_sched_list"] => true
    }
]] 
function M.live_sched_tick(sched_id, cb)

    if not sched_id then
        cb(false, CONSTANTS.BASE_API_COMMON_ERROR.CODE_INVALID_PARAMETER, 'invalid sched_id')
        return
    end

    local params = {
        sched_id = sched_id
    }

    M.live_sched_tick_with_params(params, cb)
end    

-- 预留支持更多参数的接口，当前必传 params = { sched_id = sched_id }
function M.live_sched_tick_with_params(params, cb)
    local headers = {}
    local body = params or {}
    local opt = { use_moment_token = true, use_ejoy_token = true }
    holo_api:post('/live_sched/api/tick', headers, body, opt, function(succ, ...)
        if succ then
            local resp = ...
            cb(true, resp and resp.data)
        else
            E.LOG.debug(TAG,'live_sched_tick fail')
            cb(false, ...)
        end
    end)
end

M.default_tick_interval = 180 -- 默认轮询间隔，优先以服务端为准

local current_next_interval = M.default_tick_interval
local current_sched_id
local current_timer_id

-- 3. 开始定时监听获取当前直播间信息，并上报心跳到直播间，如热度等信息
--[[
    首次或切换直播间才会重置tick心跳逻辑，sched_id, tick_handler必须同时设置
    参数说明：
    sched_id   : string, 直播计划ID
    loop_tick_handler         : function, 定时回调live_sched_tick接口成功后回调的数据
        data 结构参考(服务端返回如后续有更新，以最新文档为准)：
        table: 0x70e2f3a240 {
            sched_info : table, 直播计划信息，直播计划ID找不到时返回空
                id : string, 直播计划ID, 
                trend : number, 直播间热度值
                sched_status : string, 直播间当前开启状态: OPENED（已开启）、 CLOSED（已关闭）、 UNOPENED（尚未开启）
                sched_latency_ms : number, 当前时间距离直播开始时间还有多少时间 UTC时间戳，时间单位为：毫秒。注意已开启的（OPENED）或者已结束的（OPENED），返回为值-1
            next_interval : integer, 下次轮询时间间隔(秒); 此设计是为了避免集中请求（例如玩家通过红点触发进入的）,客户端可以设定一个兜底的时间间隔值，只有在某次请求异常时，才可以用默认的兜底值来决定下次轮询时间。
            ...
        }
]]
function M.start_live_sched_loop_tick(sched_id, loop_tick_handler)
    
    if sched_id and current_sched_id ~= sched_id then

        current_sched_id = sched_id
        
        local tick_live_timer
        tick_live_timer = function(loop_tick_sched_id, loop_timer_id)
            if loop_tick_sched_id then
                M.live_sched_tick(loop_tick_sched_id, function (suc, ...)

                    -- 切换过直播间，丢弃上一个直播活动的结果；或请求间隔内回到了直播间，但生成的是新的timer
                    if (loop_tick_sched_id ~= current_sched_id) or (loop_timer_id ~= current_timer_id) then
                        E.LOG.debug(TAG, 'sched_id or timer changed, loop_tick_sched_id:' .. tostring(loop_tick_sched_id) .. ", current_sched_id:" .. tostring(current_sched_id) .. ", loop_timer_id:".. tostring(loop_timer_id) .. ", current_timer_id:".. tostring(current_timer_id))
                        return
                    end

                    if suc then
                        local data = ...
                        if data then
                            if loop_tick_handler then
                                loop_tick_handler(data)
                            end

                            -- 直播间next_interval = -1 表示已归档，不需要继续轮询，退出循环
                            if data.next_interval == -1 then
                                E.LOG.debug(TAG, 'sched_id is not enable(next_interval: -1), stop tick')
                                M.stop_live_sched_loop_tick()
                                return
                            else
                                -- 以下发的间隔为准
                                current_next_interval = data.next_interval or M.default_tick_interval
                                -- 保护一下，服务端理论返回不会这么小的值；最少得10s
                                if current_next_interval < 10 then
                                    current_next_interval = 10
                                end
                            end
                        end
                    end
           
                    -- 确保current_next_interval > 0
                    if current_next_interval > 0 then
                        E.Timer.once(current_next_interval, function ()
                            -- 确保只tick当前的直播活动且只有一个timer
                            if current_sched_id and tick_live_timer and loop_tick_sched_id == current_sched_id and loop_timer_id == current_timer_id then
                                tick_live_timer(loop_tick_sched_id, loop_timer_id)
                            else
                                E.LOG.debug(TAG, 'timer changed, loop_tick_sched_id:' .. tostring(loop_tick_sched_id) .. ", current_sched_id:" .. tostring(current_sched_id) .. ", loop_timer_id:".. tostring(loop_timer_id) .. ", current_timer_id:".. tostring(current_timer_id))
                            end
                        end)
                    end

                end)
            end
            
        end

        -- 每次为timer生成唯一id，用于确保只有一个timer持续运行
        local uuid = require "ejoysdk_lua.ejoysdk_uuid"
        current_timer_id = uuid()

        if tick_live_timer then
            tick_live_timer(current_sched_id, current_timer_id)
        end
    end
end

-- 4. 停止定时监听获取直播间信息
--[[
    把当前根据sched_id获取信息的定时器清空
]]
function M.stop_live_sched_loop_tick()
    current_sched_id = nil
    current_timer_id = nil
end

-- 5. 进入直播间
--[[
    参数说明：
    sched_id   : string, 直播计划ID
    cb         : function, 回调，如 cb(true, data) 或 cb(false, code, message)
    返回参数：
    data 结构参考(服务端返回如后续有更新，以最新文档为准)：
    table: 0x70e2f3a240 {
        sched_info : table, 直播计划信息
            id : string, 直播计划ID,
        ... 
    }

    data eg: 这里仅列举部分字段，服务端返回如后续有更新，以最新文档为准
    {
        ["sched_info"] => table: 0x283610fc0{
            ["id"] => "62be99120aef4b0bc4f617d7"
            ...
        }
    }
]]
function M.enter(sched_id, cb)

    if not sched_id then
        cb(false, CONSTANTS.BASE_API_COMMON_ERROR.CODE_INVALID_PARAMETER, 'invalid sched_id')
        return
    end

    local params = {
        sched_id = sched_id
    }
    
    M.enter_with_params(params, cb)
end    

-- 预留支持更多参数的接口，当前必传 params = { sched_id = sched_id }
function M.enter_with_params(params, cb)
    local headers = {}
    local body = params or {}
    local opt = { use_moment_token = true, use_ejoy_token = true }
    holo_api:post('/live_sched/api/enter', headers, body, opt, function(succ, ...)
        if succ then
            local resp = ...
            cb(true, resp and resp.data)
        else
            E.LOG.debug(TAG,'live_sched enter fail')
            cb(false, ...)
        end
    end)
end


-- 6. 离开直播间
--[[
    参数说明：
    sched_id   : string, 直播计划ID
    cb         : function, 回调，如 cb(true, data) 或 cb(false, code, message)
    返回参数：
    data 结构参考(服务端返回如后续有更新，以最新文档为准)：
    table: 0x70e2f3a240 {
        sched_info : table, 直播计划信息
            id : string, 直播计划ID,
        ... 
    }

    data eg: 这里仅列举部分字段，服务端返回如后续有更新，以最新文档为准
    {
        ["sched_info"] => table: 0x28360a700{
            ["id"] => "62be99120aef4b0bc4f617d7"
            ...
        }
        ...
    }
]]
function M.exit(sched_id, cb)

    if not sched_id then
        cb(false, CONSTANTS.BASE_API_COMMON_ERROR.CODE_INVALID_PARAMETER, 'invalid sched_id')
        return
    end

    local params = {
        sched_id = sched_id
    }
    
    M.exit_with_params(params, cb)
end    

-- 预留支持更多参数的接口，当前必传 params = { sched_id = sched_id }
function M.exit_with_params(params, cb)
    local headers = {}
    local body = params or {}
    local opt = { use_moment_token = true, use_ejoy_token = true }
    holo_api:post('/live_sched/api/exit', headers, body, opt, function(succ, ...)
        if succ then
            local resp = ...
            cb(true, resp and resp.data)
        else
            E.LOG.debug(TAG,'live_sched exit fail')
            cb(false, ...)
        end
    end)
end

return M