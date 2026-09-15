local E = require 'ejoysdk_lua.ejoysdk'
local EM = require "ejoysdk_lua.ejoysdk_module"

local DEFAULT_EXPIRE_TIME = 300 -- 默认过期时间，单位： 秒

local tree_cache = {}

local M = {}

local TAG = EM.MODULE.BADGE .. 'tree_cache'

--由于一个项目可以有多个app_id,因此使用app_id/tree_id作为缓存key
function M.cal_key(app_id, tree_id)
    local key = app_id .. "/" .. tree_id
    return key
end

--每次从接口获取后缓存下来
function M.add_badge_tree(app_id, tree_id, tree_info, deactivate_mode, src_cache_ttl)
    local cache_key = M.cal_key(app_id, tree_id)
    --清除旧数据
    tree_cache[cache_key] = nil
    --新数据加入缓存
    local now = os.time()
    local cache_ttl = src_cache_ttl or DEFAULT_EXPIRE_TIME
    local new_entity = {
        tree_info = tree_info,
        deactivate_mode = deactivate_mode,
        create_ts = now,
        cache_ttl = cache_ttl
    }
    tree_cache[cache_key] = new_entity
    E.LOG.debug(TAG, "badge: 新增/刷新缓存，key: " .. tostring(cache_key) .. ", 缓存时长(分钟): " .. tostring(cache_ttl))
end

-- 根据app_id, tree_id 获取缓存, 如果缓存过期，则清理缓存并返回nil，否则返回缓存数据
function M.get_cache_tree(app_id, tree_id)
    local cache_key = M.cal_key(app_id, tree_id)
    local entity = tree_cache[cache_key]
    if entity then
        --判断缓存是否过期
        local now = os.time()
        local diff = now - entity.create_ts
        -- cache的entity会默认会有cache_ttl
        if diff > entity.cache_ttl then
            --缓存过期了，清除缓存
            tree_cache[cache_key] = nil
            entity = nil
            E.LOG.debug(TAG, "badge: key: " .. tostring(cache_key) .. " 存在缓存, 但已过期, 清除该缓存")
        end
    end
    --没有缓存，返回nil
    return entity
end

return M


