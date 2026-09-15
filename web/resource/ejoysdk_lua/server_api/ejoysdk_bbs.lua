local BASE_API = require 'ejoysdk_lua.libs.base_api'
local bbs_api = BASE_API:New('bbs') -- 新建 stake api 模块
local EM = require "ejoysdk_lua.ejoysdk_module"

local _TAG = EM.MODULE.SERVER_API .. 'bbs'

local M = {}

-- 获取生成二维码数据接口
-- https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/ri634k
function M.get_qrcode(cb)
    bbs_api:post('/api/passport/qrcode/acquire', {}, {}, {}, cb)
end

-- 扫码登录状态查询接口
-- https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/fbn6dw
function M.qrcode_query_status(uuid, cb)
    local body = {u = uuid}
    bbs_api:post('/api/passport/qrcode/query_status', {}, body, {}, cb)
end

-- 扫码登录验证接口
-- https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/xnvgkl
function M.qrcode_login(uuid, cb)
    local body = {u = uuid}
    local opt = {use_ejoy_token = true}
    bbs_api:post('/api/passport/qrcode/login', {}, body, opt, cb)
end

--[[ 获取场景下所有配置
    scene_ids: string array, 场景id 必填, eg: {[1]='id1',[2]='id2'}
    cb: function
         cb(true, body)
            directors: table, eg: {[1]={scene_id='',key='',value={}}}
         cb(false, code, msg)
--]]
function M.get_director_by_scene(scene_ids, cb)
    local body = { scene_ids = scene_ids }
    local opt = { use_moment_token = true }
    bbs_api:post('/api/outer_director/get_director_by_scene', {}, body, opt, cb)
end

--[[ 获取场景下的单个配置
    scene_id: string, 场景id。必填, eg: 'game_report'
    keys: table，string array, key值。必填, eg: {[1]='key1',[2]='key2'}
    cb: function
         cb(true, body)
            directors: table, eg: {[1]={scene_id='',key='',value={}}}
         cb(false, code, msg)
--]]
function M.get_director_by_key(scene_id, keys, cb)
    local body = { scene_id = scene_id, keys = keys }
    local opt = { use_moment_token = true }
    bbs_api:post('/api/outer_director/get_director_by_key', {}, body, opt, cb)
end

return M