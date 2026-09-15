local E = require "ejoysdk_lua.ejoysdk"
local BASE_API = require 'ejoysdk_lua.libs.base_api'
local OSS_API = require 'ejoysdk_lua.ejoysdk_oss'
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local log_collector_api = BASE_API:New('log-collector')

local TAG = 'server_api#log_collector_ex'

local M = {}
M.MAX_SIZE = 50*1024*1024
M.INPUT_TYPE = OSS_API.INPUT_TYPE

-- 协议文档：https://aliyuque.antfin.com/ejoy-platform/user_guide/az0zet
-- 1. 获取凭证，这里获取的是步骤2的oss_params
--[[
    获取上传 OSS 的 policy
    参数说明：
    cb         : function, 回调，如 cb(true, oss_params) 或 cb(false, code, message)

    oss_params 结构参考：
    table: 0x70e2f3a240 {
       ["ticket_id"] => "628b4a3851964a4ff3a2ff97" -- 其中ticket_id是commit接口关心的参数
       ["callback"] => "string" 
       ["accessid"] => "string"
       ["policy"] => "string"
       ["dir"] => "string"
       ["file_name"] => "string"
       ["expire"] => 1653324772
       ["signature"] => "..."
       ["host"] => "plat-holo-oss.oss-cn-shenzhen.aliyuncs.com"
       ["key"] => "string"
       ["success_action_status"] => 200
       ["x-oss-object-acl"] => "private"
    }
]] 
function M.apply_oss_policy(cb)
    local headers = {}
    local opt = {}
    log_collector_api:post('/client_api/apply_oss_policy', headers, nil, opt, function(succ, ...)
        if succ then
            local resp = ...
            cb(true, resp.data)
        else
            E.LOG.debug(TAG,'apply_oss_policy request fail')
            cb(false, ...)
        end
    end)
end

-- 2. 上传oss
--[[
    参数说明：
    oss_params : table, 获取凭证, 步骤一get_oss_policy返回的oss信息
    input_file : string, 资源二进制数据/路径
    input_type : string, file类型，path还是content, 如 LOG_EX_API.INPUT_TYPE.DATA 或 LOG_EX_API.INPUT_TYPE.PATH
    media_type : string, 资源类型支持 image/video/audio/text，如'text'或'image'
    cb         : function, 回调
    cb(true, data) 或 cb(false, code, message)

    返回成功data结构可以不关注，这里的data没有暂时实际使用场景，通常只关心结果即可，针对成功的结果commit关联信息到平台
    ["data"] => table: 0x70cc552bc0{
        ...
    }
]] 
function M.upload_file_to_oss(input_file, input_type, media_type, oss_params, cb)
    OSS_API.upload_file(input_file, input_type, media_type, oss_params, cb)
end

-- 3. commit接口。上传完oss（成功）后，需要将上传结果提交到平台后端
--[[
    参数说明：
    params : table
        通常元素结构参考如下（以最终文档为准）：
        { 
            device_id : string, 设备id
            ext : 透传参数，table
            player_id : player_id, 角色id
            ticket_id : string, 步骤一get_oss_policy返回的oss ticket_id信息
        }
    cb         : function, 回调
    参考 cb(succ, ...)
        cb(true) 或 cb(false, code, message)
]] 
function M.commit(params, cb)
    local body = params or {}
    local opt = {}
    log_collector_api:post('/client_api/commit', {}, body, opt, function(succ, ...)
        if succ then
            if cb then
                cb(true, ...)
            end
        else
            if cb then
                cb(false, ...)
            end
        end
    end)
end

--[[
    SDK 封装了上述3个步骤的通用流程：
    参数说明：
    input_file : string, 资源二进制数据/路径
    input_type : string, file类型，path还是content,
        LOG_EX_API.INPUT_TYPE.DATA 表示input_file为content
        LOG_EX_API.INPUT_TYPE.PATH 表示input_file为path
    media_type : string, 资源类型支持，log这里固定传 application/octet-stream

    cb         : function, 回调
    参考 cb(succ, ...)
        cb(true) 或 cb(false, code, message)

    参考如下
    local LOG_EX_API = require 'ejoysdk_lua.server_api.log_collector_ex'
    local input_file = $file_content

    LOG_EX_API.upload_and_commit({}, input_file, LOG_EX_API.INPUT_TYPE.DATA, 'text', cb)

]]
function M.upload_and_commit(ext_params, input_file, input_type, media_type, cb)

    -- 获取凭证
    M.apply_oss_policy(function (succ, ...)

        if not succ then
            -- Step1 失败 get_oss_policy请求的结果
            cb(false, ...)
            return
        end

        local oss_params = ...
        local ticket_id = oss_params and oss_params.ticket_id
        if not ticket_id then
            cb(false, CONSTANTS.OSS_ERROR.CODE_UPLOAD_FAIL, 'upload fail, oss_policy return nil or ticket_id is nil')
            return
        end

        -- 传入oss
        M.upload_file_to_oss(input_file, input_type, media_type, oss_params, function (oss_succ, ...)
            if not oss_succ then
                -- Step2 失败upload_file请求的结果
                cb(false, ...)
                return
            end

            local GDP = require 'ejoysdk_lua.gangplank_data_provider'
            local player_id = GDP.PLAYER_INFO.get('player_id')
            local device_id = E.Sysinfo.utdid()

            local commit_params = {
                device_id = device_id,
                ext = ext_params or {},
                player_id = player_id,
                ticket_id = oss_params.ticket_id
            }
            M.commit(commit_params, function (commit_suc, ...)
                if commit_suc then
                    local commit_result = ...
                    E.LOG.debug(TAG, commit_result)
                    cb(true, commit_result)
                else
                    -- -- Step3 失败 commit_media请求的结果
                    cb(false, ...)
                end
            end)
        end)
    end)
end


--[[
    SDK 封装了简单上传的接口，通常使用此接口可满足需求：
    参数说明：
    file_path_name : file_path_name, 上传文件路径
    params : string, 透传参数
    cb         : function, 回调
    参考 cb(succ, ...)
        cb(true) 或 cb(false, code, message)

    参考如下
    local LOG_EX_API = require 'ejoysdk_lua.server_api.log_collector_ex'
    local params = {} -- ext透传参数

    LOG_EX_API.upload_client_log(file_path_name, params, cb)

]]
function M.upload_client_log(file_path_name, params, cb)
    
    local err_tips
    if not E.Utils.end_with(file_path_name, ".zip") then
        err_tips = string.format("file_path_name is not a zip file, file_path_name = '%s'", file_path_name)
        E.LOG.error(TAG, err_tips)
        cb(false, CONSTANTS.OSS_ERROR.CODE_UPLOAD_FAIL, err_tips)
        return
    end

    local data
    if E.Sysinfo.os() == 'ios' then
        data = E.sync_call('read_file', file_path_name)
    else
        data = _ejoysdk.lread(file_path_name)
    end

    if not data then
        err_tips = string.format("file no found. file_path_name = '%s'", file_path_name)
        E.LOG.error(TAG, err_tips)
        cb(false, CONSTANTS.OSS_ERROR.CODE_UPLOAD_FAIL, err_tips)
        return
    end

    E.LOG.debug(TAG, "file length:" .. tostring(#data) .. ", max length:" .. tostring(M.MAX_SIZE))

    if #data > M.MAX_SIZE then
        err_tips = "file too large. must less than " .. tostring(M.MAX_SIZE/(1024*1024)) .. 'M'
        E.LOG.error(TAG, err_tips)
        cb(false, CONSTANTS.OSS_ERROR.CODE_UPLOAD_FAIL, err_tips)
        return
    end

    M.upload_and_commit(params, data, M.INPUT_TYPE.DATA, 'application/octet-stream', cb)
end

return M