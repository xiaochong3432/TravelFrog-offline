local E = require "ejoysdk_lua.ejoysdk"
local BASE_API = require 'ejoysdk_lua.libs.base_api'
local OSS_API = require 'ejoysdk_lua.ejoysdk_oss'
local holo_api = BASE_API:New('holo') -- 新建 holo api 模块
local EGC = require 'ejoysdk_lua.ejoysdk_gangplank_config'

local TAG = 'album#ejoysdk_album_api'

local M = {}

M.INPUT_TYPE = OSS_API.INPUT_TYPE

M.ERR_TYPE = {
    --上传失败，需要重传oss
    UPLOAD = "upload",
    --commit失败，oss资源已经上传成功
    COMMIT = "commit"
}

local function get_oss_policy(group_id, media_type, cb)
    E.LOG.debug(TAG, 'start get_oss_policy')
    local opt = {use_moment_token = true}
    local body = {
        group_id = group_id,
        media_type = media_type
    }
    holo_api:post('/photo_album/apply_upload_policy', {}, body, opt, function(succ, ...)
        if succ then
            local resp = ...
            cb(true, resp.data)
        else
            E.LOG.debug(TAG,'get_oss_policy request http fail')
            cb(false, ...)
        end
    end)
end

--上传oss，批量，只有批量上传成功/批量上传失败。失败了就需要批量重新传
function M.upload_oss(media_content_arr, cb)
    local size = #media_content_arr
    --上传结束个数，包含成功和失败
    local upload_over_count = 0
    --oss上传成功后返回的结果
    local upload_result = {
        --上传后的结果
        result_list = {},
        --总体上传的成功/失败
        all_succ = true
    }
    for index, media in pairs(media_content_arr) do
        --创建数组存储结果
        --上传结果的基本字段，无论成功和失败都会带
        local media_item_upload_result = {
            data = {
                name = media.name,
                media_type = media.media_type,
                group_id = media.group_id,
                --预留字段
                info = media.info
            }
        }
        table.insert(upload_result.result_list, index, media_item_upload_result)


        --每一项item的上传结果回调,该方法会回调多次
        local item_upload_callback = function(upload_media_result)

            upload_over_count = upload_over_count + 1

            --资源上传失败
            if upload_media_result.code ~= 0 then
                --归属于upload失败
                upload_media_result.err_type = M.ERR_TYPE.UPLOAD
                upload_result.all_succ = false
            end

            --全部上传结束，返回结果
            if upload_over_count == size then
                E.LOG.debug(TAG, 'all photo upload succ')
                E.log(upload_result)
                cb(upload_result)
            end
        end

        get_oss_policy(media.group_id, media.media_type,function(succ, ...)
            if succ then
                local oss_params = ...
                media_item_upload_result.data.ticket_id = oss_params.ticket_id
                OSS_API.upload_file(media.media, media.media_input_type,  OSS_API.FILE_TYPE[media.media_type], oss_params, function(upload_succ, ...)
                    if upload_succ then
                        media_item_upload_result.code = 0
                    else
                        local code, msg = ...
                        media_item_upload_result.code = code
                        media_item_upload_result.message = msg
                    end
                    item_upload_callback(media_item_upload_result)
                end)
            else
                local code, msg = ...
                media_item_upload_result.code = code
                media_item_upload_result.message = msg
                item_upload_callback(media_item_upload_result)
            end
        end)
    end
end

function M.commit_media_infos(upload_result, cb)
    local result_list = upload_result.result_list
    local upload_succ_list = {}
    local ticket_index_map = {}
    for index, item_upload_result in pairs(result_list) do
        local ticket_id = item_upload_result.data.ticket_id
        --ticket_id可能为空
        if ticket_id then
            ticket_index_map[ticket_id] = index
        end
        if item_upload_result.code == 0 then
            table.insert(upload_succ_list, item_upload_result.data)
        end
    end

    if next(upload_succ_list) then
        local body = {
            photos = upload_succ_list
        }

        local opt = {use_moment_token = true}
        holo_api:post('/photo_album/commit', {}, body, opt, function(succ, ...)
            if succ then
                local commit_result = ...
                local commit_result_list = commit_result.result_list
                if commit_result_list ~= nil then
                    for _, commit_item_result in pairs(commit_result_list) do

                        local code = commit_item_result.code
                        local commit_photo = commit_item_result.data
                        local commit_ticket = commit_photo.ticket_id
                        local origin_index = ticket_index_map[commit_ticket]

                        --使用commit的返回值
                        result_list[origin_index] = commit_item_result

                        if code ~= 0 then
                            --如果有commit失败的情况，all_succ标志为false
                            commit_item_result.err_type = M.ERR_TYPE.COMMIT
                            upload_result.all_succ = false
                        end
                    end
                end
                cb(upload_result)
            else
                local code, msg = ...
                upload_result.all_succ = false
                --这里还需要给所有commit的数据都加上commit失败
                for _, item_upload_result in pairs(upload_succ_list) do
                    item_upload_result.code = code
                    item_upload_result.message = msg
                    item_upload_result.err_type = M.ERR_TYPE.COMMIT
                end
                --commit正常情况不会返回false，如果返回false，是接口出非业务异常了
                cb(upload_result)
            end
        end)
    else
        -- 没有成功的情况，直接返回
        cb(upload_result)
    end
end


--批量上传接口,包含oss上传和提交数据
function M.upload_medias(media_content_arr, cb)
    E.LOG.debug(TAG, 'start upload_and_commit_media')
    M.upload_oss(media_content_arr, function(upload_result)
        M.commit_media_infos(upload_result, cb)
    end)
end

--单张图片的上传及回调封装
function M.upload_single_media(media, cb)
    local media_arr = {media}
    M.upload_medias(media_arr, function(upload_result)
        if upload_result and upload_result.result_list and next(upload_result.result_list) then
            local upload_item_result = upload_result.result_list[1]
            if upload_item_result.code == 0 then
                cb(true, upload_item_result.data)
            else
                local code  = upload_item_result.code
                local msg = upload_item_result.message
                cb(false, code, msg)
            end
        else
            cb(false, -1, 'upload error')
        end
    end)
end

function M.delete_media_infos(media_ids, cb)
    local body = {
        photo_ids = media_ids
    }
    local opt = {use_moment_token = true}
    holo_api:post('/photo_album/delete', {}, body, opt, function(succ, ...)
        if succ then
            local resp = ...
            cb(true, resp.data)
        else
            E.LOG.debug(TAG,'delete album request fail')
            cb(false, ...)
        end
    end)
end

function M.get_album_group(cb)
    local opt = {use_moment_token = true}
    holo_api:post('/photo_album/get_photo_group', {}, {}, opt, function(succ, ...)
        if succ then
            local resp = ...
            cb(true, resp.data)
        else
            E.LOG.debug(TAG, 'get photo group request fail')
            cb(false, ...)
        end
    end)
end

local function get_media_base_url()
    local base_url = EGC.get_base_url_for_service('media-cdn')
    return base_url
end

--cursor，首次获取不需要传，翻页时传入本接口上一次返回的next_cursor
--thumb_config 缩略图配置
function M.get_media_infos(group_id, size, cursor, thumb_config, cb)
    local base_url = get_media_base_url() .. '/'
    local body = {
        size = size,
        group_id = group_id,
        cursor = cursor
    }
    local opt = {use_moment_token = true}
    holo_api:post('/photo_album/get_photo_list', {}, body, opt, function(succ, ...)
        if succ then
            local resp = ...
            --缩略图处理
            if thumb_config and resp.data and resp.data.list and next(resp.data.list) then
                for _, media_item in pairs(resp.data.list) do
                    --图片资源才需要加缩略图
                    if media_item.media_data then
                        -- 加host前缀
                        local key = base_url ..  media_item.media_data.key
                        media_item.media_data.key = key
                        -- 图片加缩略图
                        if E.Utils.start_with(media_item.media_data.mimeType, 'image')  then
                            local thumb_key = OSS_API.get_thumb_url(key, thumb_config)
                            media_item.media_data.thumb_key = thumb_key
                        end
                    end
                end
            end
            cb(true, resp.data)
        else
            E.LOG.debug(TAG,'delete album request fail')
            cb(false, ...)
        end
    end)
end

--更新相册信息，只支持一张
function M.update_media_info(media_info, cb)
    local opt = {use_moment_token = true}
    local body = {
        name = media_info.name,
        info = media_info.info,
        id = media_info.id
    }
    holo_api:post('/photo_album/update', {}, body, opt, function(succ, ...)
        if succ then
            cb(true)
        else
            cb(false, ...)
        end
    end)
end

--根据传入的相册id，获取审核信息
function M.get_media_status(photo_ids, cb)
    local opt = {use_moment_token = true}
    local body = {
        photo_ids= photo_ids
    }
    holo_api:post('/photo_album/get_photos_status', {}, body, opt, function (succ, ...)
        if succ then
            local resp = ...
            cb(true, resp)
        else
            E.LOG.debug(TAG, 'get album status request fail')
            cb(false, ...)
        end
    end)
end

return M