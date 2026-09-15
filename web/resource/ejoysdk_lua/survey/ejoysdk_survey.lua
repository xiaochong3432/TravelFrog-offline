local E = require "ejoysdk_lua.ejoysdk"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local EH = require "ejoysdk_lua.ejoysdk_holo"
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local EM = require "ejoysdk_lua.ejoysdk_module"

local M = {}
local TAG = EM.MODULE.SURVEY .. 'survey'

local HTTP = E.HTTP

--google 问卷提交成功后会跳转到https://docs.google.com/forms/xxxx/formResponse
local GOOGLE_FORM_PREFIX = 'https://docs.google.com/forms'
local GOOGLE_FORM_SUFFIX = 'formResponse'
--google问卷提交成功后等待多少秒后关闭
local GOOGLE_FORM_CLOSE_DELAY_SEC = 3

--默认问卷状态
local SURVEY_SUBMIT_STATUS_EMPTY = {
    success = false,
    result_code = -1,
    result_msg = 'canceled by user!'
}

local survey_submit_status = {
    success = SURVEY_SUBMIT_STATUS_EMPTY.success,
    result_code = SURVEY_SUBMIT_STATUS_EMPTY.result_code,
    result_msg = SURVEY_SUBMIT_STATUS_EMPTY.result_msg
}

--是否默认开启google问卷自动关闭功能
local google_redirect_close_enable = false

local function _do_post(url, params, body, cb)
    HTTP.post(url, params, HTTP.CT_JSON, body, function(resp)
        if resp.status == 200 then
            if resp.body.code == 0 then
                cb(200, resp.body)
            else
                cb(resp.body.code, resp.body)
            end
        else
            cb(resp.status, resp.body or {})
        end
    end)
end

local function survey_url_base(api, url_base)
    return url_base .. api
end

-- https://aone.alibaba-inc.com/v2/project/770618/req/34939800
-- 问卷的服务已迁移到 game_adapter
local function survey_url(api)
    local url_base = E.CONFIG.get_config('game-adapter')
    if string.sub(api, 1, 1) ~= '/' then
        api = '/' .. api
    end
    return survey_url_base(api, url_base)
end

--获取问卷列表
local function request_get_survey_list(player_token, cb)
    E.LOG.debug(TAG, 'get_survey_list, player_token:' .. tostring(player_token))
    if player_token == nil or player_token == '' then
        local err_msg = "get_survey_list failed, for moment-token is nil, should call this method after set role info!"
        E.LOG.debug(TAG, err_msg)
        cb(false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_PLAYER_TOKEN_INVALID, err_msg)
        return
    end

    local api = "/survey/list"
    local url = survey_url(api)
    E.LOG.debug(TAG, 'get_survey_list, url:'.. tostring(url))
    assert(url, "get_survey_list api: " .. api .. " not found")

    local params = {
        acceptable = E.HTTP.CT_JSON,
        headers = {['Moment-Token']= player_token}
    }

    local temp_body = {
        lang = E.CONFIG.get_config('lang')
    }
    E.LOG.debug(TAG,"post params---")
    E.LOG.debug(TAG, params)
    _do_post(url, params, temp_body, function(status, body)
        if status == 200 then
            cb(true, body.data)
        else
            cb(false, body.code or status, body.message or '')
        end
    end)
end

--获取单个问卷详情
local function request_get_survey_detail(player_token, res_id, cb)
    E.LOG.debug(TAG, 'get_survey_detail')
    if player_token == nil or player_token == '' then
        local err_msg = "get_survey_detail failed. moment-token is nil, should call this method after set role info!"
        E.LOG.debug(TAG, err_msg)
        cb(false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_PLAYER_TOKEN_INVALID, err_msg)
        return;
    end

    local api = "/survey/detail"
    local url = survey_url(api)
    E.LOG.debug(TAG, 'get_survey_detail, url:'.. tostring(url))
    assert(url, "get_survey_detail api: " .. tostring(api) .. " not found")

    local params = {
        acceptable = E.HTTP.CT_JSON,
        headers = {['Moment-Token']= player_token}
    }

    local temp_body = {
        lang = E.CONFIG.get_config('lang'),
        resource_id = res_id
    }

    _do_post(url, params, temp_body, function(status, body)
        if status == 200 then
            cb(true, body)
        else
            --获取问卷详情失败
            cb(false, body.code or status, body.message or '')
        end
    end)
end

--接口描述：获取问卷列表接口
--接入要求：本接口依赖Moment-Token，游戏需要在设置完角色后调用该接口
--接口返回：
-- true:获取成功，返回问卷列表（问卷列表详细参数定义请参考服务器协议：https://yuque.antfin-inc.com/docs/share/15b22d12-376f-4224-9338-6c59e95e852a）
-- false: 获取失败，返回错误码和错误信息
function M.get_survey_list(cb)
    E.LOG.debug(TAG, '开始获取问卷列表')
    local player_token = EH.get_player_token()

    if player_token == nil then
        cb(false, 0, '角色登录游戏后才能获取问卷')
        return
    end
    request_get_survey_list(player_token, function(success, ...)
        if success then
            local survey_list = ...
            E.LOG.debug(TAG, '获取问卷列表成功！')
            E.LOG.debug(TAG, survey_list)
            cb(true, ...)
        else
            local code, msg = ...
            E.LOG.warn(TAG, '获取问卷列表失败, code: ' .. tostring(code)  .. ' ,msg: ' .. tostring(msg))
            cb(false, ...)
        end
    end)
end

--重置问卷的状态
local function reset_survey_submit_status()
    survey_submit_status.success = SURVEY_SUBMIT_STATUS_EMPTY.success
    survey_submit_status.result_code = SURVEY_SUBMIT_STATUS_EMPTY.result_code
    survey_submit_status.result_msg = SURVEY_SUBMIT_STATUS_EMPTY.result_msg
end

local function listen_webview_close_event(_service, cb)
    local function webview_close_callback(_value)
        ET.unsubscribe('webview_close', webview_close_callback)

        if survey_submit_status.success then
            cb(true, survey_submit_status.result_msg)
        else
            cb(false, survey_submit_status.result_code, survey_submit_status.result_msg)
        end

        --重置问卷状态
        reset_survey_submit_status()
    end

    ET.subscribe('webview_close', webview_close_callback)
end

--[[判断str是否以substr开头。是返回true，否返回false，失败返回失败信息]]
local startswith = function(str, substr)
    if str == nil or substr == nil then
        return nil, "the string or the sub-stirng parameter is nil"
    end
    if string.find(str, substr) ~= 1 then
        return false
    else
        return true
    end
end

--[[判断str是否以substr结尾。是返回true，否返回false，失败返回失败信息]]
local endswith = function(str, substr)
    if str == nil or substr == nil then
        return nil, "the string or the sub-string parameter is nil"
    end
    local str_tmp = string.reverse(str)
    local substr_tmp = string.reverse(substr)
    if string.find(str_tmp, substr_tmp) ~= 1 then
        return false
    else
        return true
    end
end

local function update_survey_success(msg)
    survey_submit_status.success = true
    survey_submit_status.result_code = 0
    survey_submit_status.result_msg = msg
end

local function update_survey_fail(code, msg)
    survey_submit_status.success = false
    survey_submit_status.result_code = code
    survey_submit_status.result_msg = msg
end

local function listen_webview_redirect_event(service, _cb)
    --google问卷没有js回调，我们需要监听url跳转来判断问卷是否提交成功
    if service == 'google' then
        local function webview_redirect_callback(_value)
            local redirect_url = _value.url
            if(startswith(redirect_url, GOOGLE_FORM_PREFIX) and
                    endswith(redirect_url, GOOGLE_FORM_SUFFIX)) then
                E.LOG.debug(TAG, 'google 问卷提交成功！')
                --标记google问卷提交成功
                update_survey_success('google survey submit success!')

                --close browser
                E.Timer.once(GOOGLE_FORM_CLOSE_DELAY_SEC, function()
                    E.WebView.close()
                end)
            end
        end
        ET.subscribe('webview_url_redirect', webview_redirect_callback)
    end
end

local function listen_webview_js_event(_cb)
    local function webview_js_callback(_value)
        local args = _value.args
        if args.type == 'survey' then
            if args.status == 'success' then
                update_survey_success('submit success!')
            else
                update_survey_fail(-1, 'submit err!')
            end

            ET.unsubscribe('webview_jsargs', webview_js_callback)

            --close browser
            E.WebView.close()
        end
    end

    ET.subscribe('webview_jsargs', webview_js_callback)
end

local function open_webview(url, screen_orientation)
    local default_hosts = {
        ['.ejoybox.com']= {
        },
        ['survey.alibaba-inc.com'] = {
        },
        ['survey.alibaba.com'] = {
        },
        ['survey.aiyun.com'] = {
        }
    }

    E.WebView.open(url, default_hosts, {
        compactMode= true,
        screen_orientation = screen_orientation or "portrait"
    })
end

--google问卷跳转和提交场景，客户端无法区分，如果游戏的问卷是单页的，则可以设置为true，那么google问卷提交成功后，客户端可以返回成功
function M.enable_close_on_google_redirect(enabled)
    if enabled then
        google_redirect_close_enable = true
    else
        google_redirect_close_enable = false
    end
end

-- 支持all,landscape,portrait三种screen_orientation
function M.show_survey(resource_id, cb, screen_orientation)
    E.LOG.debug(TAG, '开始获取问卷详情')
    local player_token = EH.get_player_token()

    --首先获取问卷url
    request_get_survey_detail(player_token, resource_id, function(success, ...)
        if success then
            local body = ...
            --E.log(body)
            --listen to webview callback
            listen_webview_js_event(cb)
            listen_webview_close_event(body.service, cb)
            if google_redirect_close_enable then
                listen_webview_redirect_event(body.service, cb)
            end
            -- 加载webview
            open_webview(body.url, screen_orientation or body.screen_orientation)
        else
            local code, msg = ...
            --409 代表已填写过，详细见服务器文档：https://yuque.antfin-inc.com/docs/share/15b22d12-376f-4224-9338-6c59e95e852a
            if code == 409 then
                cb(true, msg)
            else
                E.LOG.warn(TAG, '获取问卷详情失败, code: ' .. tostring(code)  .. ' ,msg: ' .. tostring(msg))
                cb(false, ...)
            end
        end

    end)
end

return M