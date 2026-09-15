local E = require 'ejoysdk_lua.ejoysdk'
local BASE_API = require 'ejoysdk_lua.libs.base_api'
local qabot_api = BASE_API:New('qabot')

local TAG = "EJOYSDK_QABOT"
local M = {}

--云小蜜报错
local ERR_CODE_XIAO_MI_ERROR = 75002001

--最近一次回复里的session_id
local last_session_id = nil

function M.init()

end

--[[
用户输入问题
@param
    params : table
    支持参数content，输入的问题
    支持参数input_type, 用户输入的类型，可选，text表示文本，voice表示语音，默认为text，此字段也可自定义，用于记录log
]]
function M.ask_question(params, cb)
    local opt = { use_moment_token = true }
    local lang = E.CONFIG.get_config('lang')
    local param = {
        content = params.content,
        session_id = last_session_id,
        input_type = params.input_type or 'text',
        language = lang or 'zh-hans'
    }
    qabot_api:get('/chat',{acceptable = E.HTTP.CT_JSON}, param, opt, function(succ, ...)
        if succ then
            local resp = ...
            E.LOG.debug(TAG, 'ask question succ, resp >>')
            E.LOG.debug(TAG, resp)
            local response = resp.response
            if response then
                if response.state == 'fail' then
                    E.LOG.debug(TAG, '云小蜜错误')
                    cb(false, ERR_CODE_XIAO_MI_ERROR, '云小蜜错误')
                    return
                end
                if response.session_id then
                    --存在session_id时，更新下该数据
                    last_session_id = response.session_id
                end
            end
            cb(true, resp)
        else
            E.LOG.debug(TAG, 'ask question fail')
            cb(false, ...)
        end
    end)
end

--[[
用户选择推荐问题
@param
    params : table
    支持参数content，推荐问题的标题
    支持参数knowledge_id, 推荐问题的 knowledge_id 字段
]]
function M.ask_recommend_question(params, cb)
    local opt = { use_moment_token = true }
    local lang = E.CONFIG.get_config('lang')
    local param = {
        content = params.content,
        session_id = last_session_id,
        knowledge_id = params.knowledge_id,
        language = lang or 'zh-hans'
    }
    qabot_api:get('/chat',{acceptable = E.HTTP.CT_JSON}, param, opt, function(succ, ...)
        if succ then
            local resp = ...
            E.LOG.debug(TAG, 'choose_recommend_question succ, resp >>')
            E.LOG.debug(TAG, resp)
            local response = resp.response
            if response and response.state == 'fail' then
                E.LOG.debug(TAG, '云小蜜错误')
                cb(false, ERR_CODE_XIAO_MI_ERROR, '云小蜜错误')
                return
            end
            cb(true, resp)
        else
            E.LOG.debug(TAG, 'choose_recommend_question fail')
            cb(false, ...)
        end
    end)
end

--[[
用户点击标签跳转
@param
    params : table
    支持参数hyper_link_id，对应标签id，与答案中的 msg_id 是同一个概念
    支持参数from_page, 自定义字段，可表示从热点等页面跳转时取值为热点表的 group，分享页面等等,此字段用于记录log
    支持参数from_id, 可选字段，如为答案内点击标签，from_id 为源页面的答案id，热点页等其他跳转不需传送此值,此字段用于记录log
]]
function M.hyper_link(params, cb)
    local opt = { use_moment_token = true }
    local lang = E.CONFIG.get_config('lang')
    local param = {
        hyper_link_id = params.hyper_link_id,
        from_page = params.from_page,
        from_id = params.from_id,
        language = lang or 'zh-hans'
    }
    qabot_api:get('/chat',{acceptable = E.HTTP.CT_JSON}, param, opt, function(succ, ...)
        if succ then
            local resp = ...
            E.LOG.debug(TAG, 'hyper_link succ, resp >>')
            E.LOG.debug(TAG, resp)
            local response = resp.response
            if response and response.state == 'fail' then
                E.LOG.debug(TAG, '云小蜜错误')
                cb(false, ERR_CODE_XIAO_MI_ERROR, '云小蜜错误')
                return
            end
            cb(true, resp)
        else
            E.LOG.debug(TAG, 'hyper_link fail')
            cb(false, ...)
        end
    end)
end

--[[
用户评价答复满意度
@param
    params : table
    支持参数msg_id，答案的id
    支持参数satisfy, 是否满意，值为true/false
    支持参数chat_uid, 回复答案时的chat_uid，该字段用于记录log
]]
function M.comment(params, cb)
    local url = E.CONFIG.get_config('qabot') .. '/chat/comment'
    local param = {
        msg_id = params.msg_id,
        satisfy = params.satisfy,
        chat_uid = params.chat_uid
    }

    local HOLO = require 'ejoysdk_lua.ejoysdk_holo'
    local headers = {}
    headers['moment-Token']= HOLO.get_player_token()

    E.HTTP.post(url, {raw_body = true, headers = headers}, E.HTTP.CT_JSON, param, function(resp)
        if resp.status == 200 then
            if resp.body and resp.body == 'success' then
                cb(true, resp.body)
            else
                cb(false, resp.body)
            end
        else
            cb(false, resp.status, 'http error')
        end
    end)
end

--[[
热门列表
@param
    params : table
    支持参数group，对应热点配置表的group字段
]]
function M.popular(params, cb)
    local opt = { use_moment_token = true }
    local param = {
        group = params.group
    }
    qabot_api:post('/chat/popular', {acceptable = E.HTTP.CT_JSON}, param, opt, function(succ, ...)
        if succ then
            local resp = ...
            E.LOG.debug(TAG, 'get popular succ, resp >>')
            E.LOG.debug(TAG, resp)
            cb(true, resp)
        else
            E.LOG.debug(TAG, 'get popular fail')
            cb(false, ...)
        end
    end)
end



return M
