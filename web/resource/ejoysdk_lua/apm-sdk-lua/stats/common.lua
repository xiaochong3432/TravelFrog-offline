-------------------------------------------------------------------------------
-- 收集平台服务、游戏服务API性能指标数据的公共模块

-- Created Date: 2021.12.16
-- Author: 三傻
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------


local Global = require "ejoysdk_lua.apm-sdk-lua.global"
local Cfg = require "ejoysdk_lua.apm-sdk-lua.config.configurator"
local StringUtils = require "ejoysdk_lua.apm-sdk-lua.common.string_utils"


-- SLS_FIELD_MAX_SIZE SLS单个字段可设置的最大长度 详见 https://yuque.antfin.com/gserver/ieg-monitor/pgimkp#w0C44
local SLS_FIELD_MAX_SIZE = 16384 -- 16k

local M = {}

local function jsonify(k)
    k = k:gsub(Global.labels_kv_concate_str, '":"')
    k = k:gsub(Global.labels_kvpair_concate_str, '","')
    k = '{"' .. k .. '"' -- 后面还要拼json 所以这里先不加 }
    return k
end

-- c1:min_cost
-- c2:avg_cost
-- c3:max_cost
local metric_template = [[,"c1":%.2f,"c3":%.2f,"c2":%.2f,"qps":%.2f,"cnt":%.0f}]]

local function get_vector_size(vector)
    local vector_size = 0
    for k, v in pairs(vector) do
        if #k > 1 and v.count > 0 then
            vector_size = vector_size + 1
        end
    end
    return vector_size
end

-- 是否快到达SLS字段最大长度的限制
local function nearly_reach_sls_field_size_limit(stats_content_size)
    return stats_content_size + 1024 > SLS_FIELD_MAX_SIZE
end

local function complete_json(stats_content)
    -- 有可能字符串尾部存在 , 需要去掉
    if string.sub(stats_content, #stats_content) == "," then
        stats_content = string.sub(stats_content, 1, #stats_content - 1)
    end
    return stats_content .. "]"
end

-- agg_group: aggregate_group引用对象
-- 返回值数据结构为 {metric_group={"json数组字符串1","json数组字符串2", ... }}
-- 每满16k 会产生出新的一个 json数组字符串
function M.get_stats(agg_group)
    if agg_group == nil then
        return nil
    end
    local vector = agg_group:get_all()
    local vector_size = get_vector_size(vector)
    if vector_size == 0 then
        -- 清理agg_group
        agg_group:clear()
        return nil
    end
    local output = {}
    local interval = Cfg.get(Cfg.CATEGORY_STATS, "collect_interval", 60)
    local counter = 0
    local sb = StringUtils.new_string_buffer()
    sb:append("[")
    local stats_content_size = 1
    for k, v in pairs(vector) do
        if #k > 1 and v.count > 0 then -- aggregate里面有一些待清理的对象 此类对象不纳入上报
            counter = counter + 1
            k = jsonify(k)
            stats_content_size = stats_content_size + #k
            sb:append(k)
            local qps = v:get_count() / interval
            local metric_str = string.format(metric_template, v:get_min(), v:get_max(), v:get_avg(), qps, v:get_count())
            sb:append(metric_str)
            stats_content_size = stats_content_size + #metric_str
            if counter < vector_size then
                sb:append(",")
                stats_content_size = stats_content_size + 1
            end
            -- 已收集满SLS单个字段可设置的最大长度 并且不是最后一条 需要滚动出一条记录
            if nearly_reach_sls_field_size_limit(stats_content_size) and counter < vector_size then
                table.insert(output, complete_json(sb:to_string()))
                sb = StringUtils.new_string_buffer()
                sb:append("[")
                stats_content_size = 1
            end
        end
    end

    table.insert(output, complete_json(sb:to_string()))

    local result = {
        metric_group = output
    }

    -- 清理agg_group
    agg_group:clear()
    return result
end


function M.apply_pattern(api)
    local index = string.find(api, "?", 1)
    if index == 1 then
        return api, "invalid api, api begins with '?'"
    end
    if index and index > 1 then
        api = string.sub(api, 1, index - 1)
    end
    local patterns = Cfg.get_api_pattern()
    if patterns == nil then
        return api, nil
    end
    for _, pattern in ipairs(patterns) do
        for k, v in pairs(pattern) do
            -- string.match benchmark 性能数据为 > 75W/s  测试用例为6个pattern 最后一次才匹配中
            if string.match(api, k) then
                return v, nil
            end
        end
    end
    return api, nil
end

return M