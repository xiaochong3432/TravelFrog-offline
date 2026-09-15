local E = require "ejoysdk_lua.ejoysdk"
local BASE_API = require 'ejoysdk_lua.libs.base_api'
local OSS_API = require 'ejoysdk_lua.ejoysdk_oss'
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local holo_api = BASE_API:New('holo') -- 新建 holo api 模块

local TAG = 'album#ejoysdk_media_api'

local M = {}

M.INPUT_TYPE = OSS_API.INPUT_TYPE

-- 协议文档：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/xvyfqd
-- 1. 获取凭证，这里获取的是步骤2的oss_params
--[[
    获取上传 OSS 的 policy，其中的限制会根据 resource 的类型及分组的配置的限制而定
    使用moment_token鉴权，需要角色登录后使用
    参数说明：
    media_group: string, 后台对应的oss资源分组
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
function M.get_oss_policy(media_group, cb)
    local headers = {}
    local body = {
        media_group = media_group
    }
    local opt = { use_moment_token = true }
    holo_api:post('/media/apply_oss_policy', headers, body, opt, function(succ, ...)
        if succ then
            local resp = ...
            cb(true, resp.data)
        else
            E.LOG.debug(TAG,'get_oss_policy request http fail')
            cb(false, ...)
        end
    end)
end

-- 2. 上传oss
--[[
    参数说明：同接口 upload_oss_with_group
    oss_params : table, 获取凭证, 步骤一get_oss_policy返回的oss信息
    input_file : string, 资源二进制数据/路径
    input_type : string, file类型，path还是content, 如 MEDIA_API.INPUT_TYPE.DATA 或 MEDIA_API.INPUT_TYPE.PATH
    media_type : string, 资源类型支持 image/video/audio/text，如'text'或'image'
    cb         : function, 回调
    cb(true, data) 或 cb(false, code, message)

    返回成功data结构可以不关注，这里的data没有暂时实际使用场景，通常只关心结果即可，针对成功的结果commit关联信息到平台
    ["data"] => table: 0x70cc552bc0{
        ...
    }
]] 
function M.upload_file(input_file, input_type, media_type, oss_params, cb)
    OSS_API.upload_file(input_file, input_type, media_type, oss_params, cb)
end

-- 3. commit接口。上传完oss（成功）后，需要将上传结果提交到平台后端
--[[
    参数说明：
    media_list : array，步骤2的上传成功结果;
        通常media_list的元素结构参考如下（以最终文档为准）：
        [
            media_group : string, 分组名
            media_name : string, 资源名称
            ticket_id : string, 步骤一get_oss_policy返回的oss ticket_id信息
        ]
    cb         : function, 回调
    参考 cb(succ, ...)
        cb(true, result_list) 或 cb(false, code, message)
        result_list : table，结果信息
            code : number, 每个ticket_id的成功与否信息
            data : table, oss存储信息
            message : string
            ticket_id : string
        eg:
        ["result_list"] => table: 0x70c8fd3740{
          [1] => table: 0x70c8fd3780{
             ["ticket_id"] => "628b6ea75eff2b9f102f15c4"
             ["message"] => "ok"
             ["code"] => 0
             ["data"] => table: 0x70c8fd3800{
                ["id"] => "628b6ea910aa2a1d5f817d78"
                ["media_data"] => table: 0x70c8fd3840{
                   ["vaild"] => false
                   ["mimeType"] => "text"
                   ["key"] => "P10119/media/formal/test_sdk_upload_text/text/628b6ea75eff2b9f102f15c3"
                   ["bucket"] => "plat-holo-oss"
                   ["size"] => 8
                }
                ["media_type"] => "text"
                ["status"] => 0
                ["create_time"] => 1653305001558
                ["update_time"] => 1653305001558
                ["user_type"] => "player"
                ["group_id"] => "test_sdk_upload_text"
                ["media_name"] => "oss_test_file_data_name"
                ["user_id"] => "0EACFDA30B57D81B49C2CADB32D90224"
             }
          }
       }
]] 
function M.commit_media(media_list, cb)
    local body = {
        media_list = media_list
    }
    local opt = { use_moment_token = true }
    holo_api:post('/media/commit_media', {}, body, opt, function(succ, ...)
        if succ then
            if cb then
                local resp = ...
                cb(true, resp and resp.result_list)
            end
        else
            if cb then
                cb(false, ...)
            end
        end
    end)
end

--[[
    SDK 封装了上述3个步骤的通用流程，通常使用upload_oss_with_group即可满足需求：
    * 整合步骤 1 + 2 + 3 ， 上传文件到指定oss media_group;
        如果期望多个文件上传整合一次性同步结果，可以由业务方管理同步，分开调用步骤1、2、3的请求，最后commit_media
    参数说明：
    media_name : string, 资源名称
    media_group: string, 后台对应的oss资源分组, 如
    input_file : string, 资源二进制数据/路径
    input_type : string, file类型，path还是content,
        MEDIA_API.INPUT_TYPE.DATA 表示input_file为content
        MEDIA_API.INPUT_TYPE.PATH 表示input_file为path
    media_type : string, 资源类型支持 image/video/audio/text，如'text'或'image'

    cb         : function, 回调
    参考 cb(succ, ...)
        cb(true, media_data) 或 cb(false, code, message)
        media_data ==> table: 0x70c8fd3780{
             ["ticket_id"] => "628b6ea75eff2b9f102f15c4"
             ["message"] => "ok"
             ["code"] => 0
             ["data"] => table: 0x70c8fd3800{
                ["id"] => "628b6ea910aa2a1d5f817d78"
                ["media_data"] => table: 0x70c8fd3840{
                   ["vaild"] => false
                   ["mimeType"] => "text"
                   ["key"] => "P10119/media/formal/test_sdk_upload_text/text/628b6ea75eff2b9f102f15c3"
                   ["bucket"] => "plat-holo-oss"
                   ["size"] => 8
                }
                ["media_type"] => "text"
                ["status"] => 0
                ["create_time"] => 1653305001558
                ["update_time"] => 1653305001558
                ["user_type"] => "player"
                ["group_id"] => "test_sdk_upload_text"
                ["media_name"] => "oss_test_file_data_name"
                ["user_id"] => "0EACFDA30B57D81B49C2CADB32D90224"
             }
          }
    这里的 media_data.data.id 即为平台后台的文件id

    参考如下
    local MEDIA_API = require 'ejoysdk_lua.album.ejoysdk_media_api'
    local input_file = $file_content

    MEDIA_API.upload_oss_with_group('my_file_name', 'test_group', input_file, MEDIA_API.INPUT_TYPE.DATA, 'text', cb)

    注意：上传接口从lua传递文件内容，不建议上传大文件
]]
function M.upload_oss_with_group(media_name, media_group, input_file, input_type, media_type, cb)

    if media_name == nil or media_group == nil then
        cb(false, CONSTANTS.OSS_ERROR.CODE_UPLOAD_FAIL, 'upload fail, media_name or media_group should not be nil')
        return
    end

    -- 获取凭证
    M.get_oss_policy(media_group, function (succ, ...)

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
        OSS_API.upload_file(input_file, input_type, media_type, oss_params, function (oss_succ, ...)
            if not oss_succ then
                -- Step2 失败upload_file请求的结果
                cb(false, ...)
                return
            end

            local resp = ...
            if resp then
                local u_media_list = {}
                local media_item_upload_result = {
                    media_name = media_name,
                    ticket_id = oss_params.ticket_id,
                    media_group = media_group
                }
                table.insert(u_media_list, media_item_upload_result)
                M.commit_media(u_media_list, function (commit_suc, ...)
                    if commit_suc then
                        local result_list = ...
                        if result_list and #result_list > 0 then
                            local first_result = result_list[1]
                            if first_result and (first_result.code == 0) then
                                cb(true, first_result)
                            else
                                cb(false, first_result and first_result.code or -1, first_result and first_result.message or '')
                            end
                        else
                            cb(false, CONSTANTS.OSS_ERROR.CODE_UPLOAD_FAIL, 'upload fail, result_list is nil')
                        end
                    else
                        -- -- Step3 失败 commit_media请求的结果
                        cb(false, ...)
                    end
                end)
            else 
                cb(false, CONSTANTS.OSS_ERROR.CODE_UPLOAD_FAIL, 'upload fail, oss_result is nil')
            end
        end)
    end)
end

return M