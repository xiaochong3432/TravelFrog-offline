-------------------------------------------------------------------------------
-- 限流器 基于token bucket算法实现
-- inspired by https://pkg.go.dev/golang.org/x/time/rate#Limiter
-- Created Date: 2021.10.20
-- Author: 三傻
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------
local apm_stats = require "ejoysdk_lua.apm-sdk-lua.stats.apm_stats"
local Time = require "ejoysdk_lua.apm-sdk-lua.common.time.init"


local M = {}

local limiter = {
    scene = "", -- 限流的使用场景 如event trace
    rate = 0, -- 速率 rate / s , 代表每1000ms可以产生 rate 个token
    burst = 0, -- 令牌桶总容量
    remain_tokens = 0, -- 剩余token
    last = 0, -- 上次请求访问的时间戳 ms 单位
    token_exceed_counter = nil -- 请求被限累加器
}

limiter.__index = limiter

local scene_list = {}

function limiter.new(rate, burst, scene)
    if type(rate) ~= "number" or type(burst) ~= "number" then
        return nil, "illegal param,expect numbers"
    end
    if burst < 0 then
        return nil, "illegal param,expect positive burst"
    end
    if type(scene) ~= "string" or scene == "" then
        return nil, "illegal param,scene expect a not nil string"
    end
    if scene_list[scene] ~= nil then
        return nil, "scene:" .. scene .. " has already registered"
    end
    scene_list[scene] = 0
    local obj = {
        burst = burst,
        rate = rate,
        token_exceed_counter = apm_stats:new_counter(scene .. "_throttled", true)
    }
    return setmetatable(obj, limiter), nil
end

function limiter:allow()
    return self:allow_n(Time.now_ms(), 1)
end

function limiter:allow_n(now, n)
    -- rate 小于0 说明调用方要关闭限流器了 返回不限流
    if self.rate < 0 then
        return true
    end
    local last
    local tokens
    last, tokens = self:advance(now)
    local ok = tokens >= n
    tokens = tokens - n
    if ok then
        self.last = now
        self.remain_tokens = tokens
    else
        self.last = last
        -- 被限次数记录到指标
        self.token_exceed_counter:inc(n)
    end
    return ok
end

function limiter:advance(now)
    local last = self.last
    if now < last then
        last = now
    end
    local elapsed = now - last -- ms级别的时间差
    local delta = elapsed * self.rate / 1000
    local tokens = self.remain_tokens + delta
    if tokens > self.burst then
        tokens = self.burst
    end
    return last, tokens
end

function limiter:set_burst(burst)
    if burst > 0 then
        self.burst = burst
    end
end

function limiter:set_rate(rate)
    if rate >= -1 then
        self.rate = rate
    end
end

-- new_limiter 创建一个限流器
--    limit 速率 limit / s , 代表每1000ms可以产生 limit 个token
--    burst 允许的最大突发数量
--    scene 限流的使用场景 如event trace
function M.new_limiter(limit, burst, scene)
    return limiter.new(limit, burst, scene)
end

return M
