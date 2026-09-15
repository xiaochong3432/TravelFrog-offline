local E = require "ejoysdk_lua.ejoysdk"
local Vendor = require "ejoysdk_lua.vendors.vendor"
local CHANNEL = "WHATSAPP"
local CONTS = require 'ejoysdk_lua.ejoysdk_constants'
local JSON = require 'ejoysdk_lua.ejoysdk_json'
local EM = require "ejoysdk_lua.ejoysdk_module"

local TAG = EM.MODULE.VENDORS.WHATS_APP

local M = Vendor:Inherit(CHANNEL)

local android_package_name = 'com.whatsapp'

function M.init(_opt, cb)
    cb(true)
end

local function can_open_whatsapp()
    E.LOG.debug(TAG, 'can_open_whatsapp, os=' .. tostring(E.Sysinfo.os()))
    if E.Sysinfo.os() == 'android' then
        return E.Sysinfo.is_app_install(android_package_name) -- Instagram android 包不支持 schema 判断
    elseif E.Sysinfo.os() == 'ios' then
        return E.Sysinfo.can_open_url('whatsapp://')
    else
        return false
    end
end

local function make_text_url_scheme(text)
    return 'whatsapp://send?text=' .. E.HTTP.escape(tostring(text)) -- url_encode
end

local function share_text(param, cb)
    if param.message == nil or #param.message == 0 then
        -- 文本内容传入空值，会提示LINE非最新版本
        cb(false, CONTS.SHARE.CODE_SHARE_TEXT_EMPTY, 'share text empty')
        return
    end
    local trim = string.gsub(param.message, "%s+", "")
    if trim and #trim == 0 then
        cb(false, CONTS.SHARE.CODE_SHARE_TEXT_EMPTY, 'share text empty')
        return
    end

    if E.Sysinfo.os() == 'android' then
        local share_to_app_params = {
            message = param.message,
            package_name = android_package_name,
        }
        E.async_call('SHARE_TO_APP', share_to_app_params, nil, function(info)
            if info.succ then
                cb(true)
            else
                cb(false, CONTS.SHARE.CODE_SHARE_OPEN_FAIL, 'share open fail')
            end
        end)
    elseif E.Sysinfo.os() == 'ios' then
        local url_scheme = make_text_url_scheme(param.message)
        E.LOG.debug(TAG, 'Whatsapp 分享文本: ' .. tostring(url_scheme))
        E.Sysinfo.open_url(url_scheme)
    else
        cb(false, CONTS.SHARE.CODE_PLATFORM_NOT_SUPPORT, 'os platform not support')
    end
end

local function share_image(param, cb)
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
            message = param.message,
            package_name = android_package_name,
            type = 'image_url'
        }
        E.async_call('SHARE_TO_APP', share_to_app_params, nil, function(info)
            if info.succ then
                cb(true)
            else
                cb(false, CONTS.SHARE.CODE_SHARE_OPEN_FAIL, 'share open fail')
            end
        end)
    elseif E.Sysinfo.os() == 'ios' then
        E.async_call('SHARE_TO_SYSTEM', function(info)
            E.LOG.debug(TAG, 'whatsapp share to system callback info >>')
            E.LOG.debug(TAG, info)
            local result = JSON.decode(info) or {}
            if result.succ then
                cb(true)
            else
                cb(false, result.code or CONTS.SHARE.CODE_SHARE_OPEN_FAIL, 'can not open whatsapp')
            end
            
        end , JSON.encode(param))
    else
        cb(false, CONTS.SHARE.CODE_PLATFORM_NOT_SUPPORT, 'os platform not support')
    end
end

function M.is_share_support()
    return can_open_whatsapp()
end

function M.share(param, _chunk_data, cb)
    E.LOG.debug(TAG, 'whatsapp share >>')
    E.LOG.debug(TAG, param)
    if param.content_url then
        cb(false, CONTS.SHARE.CODE_SHARE_TYPE_NOT_SUPPORT, 'share type not support')
        return
    end

    if not can_open_whatsapp() then
        cb(false, CONTS.SHARE.CODE_PLATFORM_NOT_SUPPORT, 'share platform not support')
        return
    end

    -- 分享图片、或图片+文本
    if param.media and #param.media > 0 and param.media[1].type == 'image_url' then -- 分享图片
        share_image(param, cb)
        return
    end
    -- 分享文本
    if param.message then
        share_text(param, cb)
        return
    end
end

M:is_implemented({Vendor.ABILITY.SHARE})

return M