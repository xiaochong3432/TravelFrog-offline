-- luacheck: ignore
-- 自定义APM指标使用样例，可以在游戏Lua代码中实现APM埋点

local APUS = require "ejoysdk_lua.apm-sdk-lua.apus"

-- 新建stats模块并注册到Collector中
local stats = APUS:new_custom_stats("my-custom-stats")

local function get_mem_size()
    return math.random(100)
end

-- 注册从回调函数自动取值的gauge自定义指标，可指定维度
local mem_size = stats:new_gauge_with_func("mem_size",false, get_mem_size)

-- 注册counter类型的自定义指标，可指定维度
local error_count = {}
error_count["4xx"] = stats:new_counter("error_count", {code="4xx"})
error_count["5xx"] = stats:new_counter("error_count", {code="5xx"})

-- 注册aggregate类型的自定义指标，用于上报统计数据(count/min/max/avg)
local request_duration = stats:new_aggregate("request_duration_ms")

-- 供游戏Lua中调用，更新自定义指标值
local function update_request_metrics(status_code, duration)
    if status_code >= 500 then
        error_count["5xx"].inc()
    elseif status_code >= 400 then
        error_count["4xx"].inc()
    end
    request_duration.update(duration)
end
