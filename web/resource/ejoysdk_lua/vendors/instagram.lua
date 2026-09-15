local E = require "ejoysdk_lua.ejoysdk"
local Vendor = require "ejoysdk_lua.vendors.vendor"
local CHANNEL = "INSTAGRAM"
local CONTS = require 'ejoysdk_lua.ejoysdk_constants'
local UNI = require "ejoysdk_lua.vendors.unisdk"
local JSON = require 'ejoysdk_lua.ejoysdk_json'
local EM = require "ejoysdk_lua.ejoysdk_module"
local M = Vendor:Inherit(CHANNEL)

local android_package_name = 'com.instagram.android'
local VENDOR_NAME = 'INSTAGRAM'

local TAG = EM.MODULE.VENDORS.INSTAGRAM

function M.init(_opt, cb)
    cb(true)
end

local function can_open_instagram()
    E.LOG.debug(TAG, 'can_open_instagram, os:' .. tostring(E.Sysinfo.os()))
    if E.Sysinfo.os() == 'android' then
        return E.Sysinfo.is_app_install(android_package_name) -- Instagram android 包不支持 schema 判断
    elseif E.Sysinfo.os() == 'ios' then
        return E.Sysinfo.can_open_url('instagram://')
    else
        return false
    end
end

function M.is_share_support()
    return can_open_instagram()
end

function M.share(param, _chunk_data, cb)
    E.LOG.debug(TAG, 'instagram share >>>>')
    E.LOG.debug(TAG, param)
    if param.message or param.content_url then
        cb(false, CONTS.SHARE.CODE_SHARE_TYPE_NOT_SUPPORT, 'share type not support')
        return
    end

    if not can_open_instagram() then
        cb(false, CONTS.SHARE.CODE_PLATFORM_NOT_SUPPORT, 'share platform not support')
        return
    end

    local image_url = param.media[1].data
    if image_url == nil or #image_url == 0 then
        cb(false, CONTS.SHARE.CODE_IMAGE_FILE_EMPTY, 'image file empty')
        return
    end

    local f = io.open(image_url, 'r')
    if f then
        io.close(f)
    else
        cb(false, CONTS.SHARE.CODE_IMAGE_FILE_NOT_EXIST, 'image file not exist')
        return
    end

    if E.Sysinfo.os() == 'android' then
        local share_to_app_params = {
            image_url = image_url,
            package_name = android_package_name,
            type = 'image_url'
            --package_activity_name = 'com.instagram.share.handleractivity.CustomStoryShareHandlerActivity'
            --package_activity_name = 'com.instagram.direct.share.handler.DirectExternalPhotoShareActivityInterop'
            --package_activity_name = 'com.instagram.share.handleractivity.ShareHandlerActivity' -- feed
            --package_activity_name = 'com.instagram.share.handleractivity.StoryShareHandlerActivity' -- stories
            --package_activity_name = 'com.instagram.share.handleractivity.MultiStoryShareHandlerActivity' --stories
            --package_activity_name = 'com.instagram.share.handleractivity.CustomStoryShareHandlerActivity'
            --package_activity_name = 'com.instagram.direct.share.handler.DirectExternalPhotoShareActivity' -- direct
        }

        local SOCIAL = require 'ejoysdk_lua.social.ejoysdk_social'
        if param.platform == SOCIAL.SHARE_PLATFORM.instagram_share_timeline then
            E.LOG.debug(TAG, 'share instagram_share_timeline')
            share_to_app_params.package_activity_name = 'com.instagram.share.handleractivity.ShareHandlerActivity'
        elseif param.platform == SOCIAL.SHARE_PLATFORM.instagram_share_story then
            E.LOG.debug(TAG, 'share instagram_share_story')
            share_to_app_params.package_activity_name = 'com.instagram.share.handleractivity.StoryShareHandlerActivity'
        end

        E.async_call('SHARE_TO_APP', share_to_app_params, nil, function(info)
            if info.succ then
                cb(true)
            else
                cb(false, CONTS.SHARE.CODE_SHARE_OPEN_FAIL, 'share open fail')
            end
        end)
    elseif E.Sysinfo.os() == 'ios' then
        local SOCIAL = require('ejoysdk_lua.social.ejoysdk_social')
        if param.platform == SOCIAL.SHARE_PLATFORM.instagram_share_timeline then
            E.async_call('SHARE_TO_SYSTEM', function(info)
                E.LOG.debug(TAG, 'instagram share to system callback info >>>>')
                E.LOG.debug(TAG, info)
                local result = JSON.decode(info) or {}
                if result.succ then
                    cb(true)
                else
                    cb(false, result.code or CONTS.SHARE.CODE_SHARE_OPEN_FAIL, 'can not open whatsapp')
                end
                cb(JSON.decode(info))
            end , JSON.encode(param))
        else
            UNI.async_call(VENDOR_NAME, 'ASYNC_SHARE_TO_PLATFORM', param, _chunk_data, function(succ, ...)
                if succ then
                    local body = ...
                    cb(true, body)
                else
                    local _, body = ...
                    cb(false, body.error_code, body.error_msg)
                end
            end)
        end

    end
end

M:is_implemented({Vendor.ABILITY.SHARE})

return M