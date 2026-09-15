local UNI = require "ejoysdk_lua.vendors.unisdk"
local E = require 'ejoysdk_lua.ejoysdk'
local Vendor = require "ejoysdk_lua.vendors.vendor"
local LANG = require "ejoysdk_lua.lang.util"
local EG = require "ejoysdk_lua.ejoysdk_gangplank"
local EC = require 'ejoysdk_lua.ejoysdk_config'
local VENDOR_NAME = "LBS"
local HTTP = E.HTTP


local M = Vendor:Inherit(VENDOR_NAME)

--获取定位信息
local ASYNC_GET_LOCATION = 'ASYNC_GET_LOCATION'

--申请定位权限
local ASYNC_REQUEST_LOCATION_PERMISSION = 'ASYNC_REQUEST_LOCATION_PERMISSION'

--检测定位权限ios
local ASYNC_DETECT_LOCATION_PERMISSION = 'ASYNC_DETECT_LOCATION_PERMISSION'

local LBS_PERMISSION_DIALOG_COUNT = E.LazyKeyStore:New('LBS_PERMISSION_DIALOG_COUNT',false,false,false)

--服务器定位接口返回数据无效
local ERR_CODE_SERVER_RESULT_INVALID = 75001001
--无权限导致定位失败
local ERR_CODE_PERMISSION_DENY = 74001002

--lbs数据缓存，内存缓存，当次有效
local lbs_info_cache

local function real_get_location(cb)
    UNI.async_call(VENDOR_NAME,ASYNC_GET_LOCATION,{},nil, function(succ, ...)
        if succ then
            local data = ...
            cb(true, data)
        else
            local _, body = ...
            cb(false, body.error_code, body.error_msg)
        end
    end)
end

local function get_location_info_from_server(location, cb)
    local url = EG.gangplank_url('get_location', '2')
    local params = {
        coordinate = location
    }
    local headers = {}
    HTTP.post(url, headers, HTTP.CT_JSON, params, function(resp)
        if resp.status == 200 then
            local code = resp.body.code
            if code == 0 then
                local result = resp.body.data
                cb(true, result or {})
            else
                cb(false, code, resp.body and resp.body.message or '')
            end
        else
            cb(false, resp.status, resp.body and resp.body.message or '')
        end
    end)
end

--申请定位权限
local function request_location_permission(cb)
    UNI.async_call(VENDOR_NAME, ASYNC_REQUEST_LOCATION_PERMISSION,{},nil, cb)
end

function M.detect_location_permission(cb)
    --判断是否支持LBS
    if not EC.has_vendor_config('LBS') then
        E.LOG.debug(VENDOR_NAME, 'not support detect location permission')
        cb(false, {status = 0})
    end
    if E.Sysinfo.os() == 'android' then
        local permission = 'android.permission.ACCESS_COARSE_LOCATION'
        E.Permission.detect_permission(permission, cb)
    elseif E.Sysinfo.os() == 'ios' then
        UNI.async_call(VENDOR_NAME, ASYNC_DETECT_LOCATION_PERMISSION,{},nil, function(succ, ...)
            if succ then
                cb(true)
            else
                cb(false, {status = 0})
            end
        end)
    end
end

--获取设备经纬度
function M.get_device_location(opt, cb)
    if opt == nil then
        opt = {}
    end
    E.LOG.debug(VENDOR_NAME, 'get device location, opt is ')
    E.log(opt)
    local permission = 'android.permission.ACCESS_COARSE_LOCATION'
    if E.Sysinfo.os() == "ios" then
        permission = 'NSLocationWhenInUseUsageDescription'
    end
    local permission_title, permission_desc_content = E.Permission.permission_default_description({[permission] = {}})
    local force_request_permission = opt.force_request_permission or false
    local max_request_permission_count = opt.max_request_permission_count or 1
    local current_permission_request_count_str = LBS_PERMISSION_DIALOG_COUNT:get() or '0'
    local current_permission_request_count = 0
    if type(current_permission_request_count_str) == 'string' then
        current_permission_request_count = tonumber(current_permission_request_count_str)
    end
    E.LOG.debug(VENDOR_NAME, 'current permission count is ' .. tostring(current_permission_request_count))
    local can_request_permission = true
    if force_request_permission == false and current_permission_request_count >= max_request_permission_count then
        can_request_permission = false
    end

    local title = opt.title or permission_title
    local desc = opt.desc or permission_desc_content
    local setting_guide_title = opt.setting_guide_title or permission_title
    local setting_guide_desc = opt.setting_guide_message or '系统拒绝应用申请此权限。如需使用功能，请前往系统设置内手动打开此权限。\n\n' .. permission_desc_content
    --默认用途弹窗
    local usage_options = {
        buttons = {LANG.getString('confirm',"确定")},
        title = title,
        message = desc,
        permissions = {permission}
    }
    --默认设置弹窗
    local setting_usage_options = {
        title = setting_guide_title,
        message = setting_guide_desc,
        buttons = {'取消', '跳转到设置'},
        permissions = { permission }
    }

    M.detect_location_permission(function(succ,resp)
        if not succ then
            -- 未授权，判断授权弹窗显示次数
            if can_request_permission == false then
                E.LOG.debug(VENDOR_NAME, 'permission deny and request permission is max count, should not request again')
                cb(false, ERR_CODE_PERMISSION_DENY, 'permission deny and request permission is max count, should not request again')
                return
            end
            --显示跳往设置页引导弹窗
            local show_setting_usage_dialog_fun = function()
                local show_setting_usage_dialog_cb = function(ret)
                    LBS_PERMISSION_DIALOG_COUNT:set(tostring(current_permission_request_count + 1))
                    if ret == 1 then
                        E.Permission.openSetting()
                    end
                end
                if opt.show_custom_setting_usage_dialog then
                    opt.show_custom_setting_usage_dialog(show_setting_usage_dialog_cb)
                else
                    E.Permission.show_usage_dialog(setting_usage_options, show_setting_usage_dialog_cb)
                end
            end

            local status = resp.status

            if 0 == status then
                --ios申请权限，拒绝后显示提示，跳往设置页面
                --android, 显示用途，点确定后拉起授权，ok，则拉起，否则
                if E.Sysinfo.os() == 'android' then
                    --显示用途弹窗回调
                    local show_usage_dialog_cb = function()
                        LBS_PERMISSION_DIALOG_COUNT:set(tostring(current_permission_request_count + 1))
                        --权限申请
                        request_location_permission(function(request_permission_succ)
                            E.LOG.debug(VENDOR_NAME, 'permission callback ' .. tostring(request_permission_succ))
                            if request_permission_succ then
                                --用户授权
                                E.LOG.debug(VENDOR_NAME,"check permission succ")
                                real_get_location(cb)
                            else
                                --用户拒绝授权
                                E.LOG.debug(VENDOR_NAME,"check permission fail")
                                cb(false, ERR_CODE_PERMISSION_DENY, 'permission deny')
                            end
                        end)
                    end
                    if opt.show_custom_usage_dialog then
                        opt.show_custom_usage_dialog(show_usage_dialog_cb)
                    else
                        E.Permission.show_usage_dialog(usage_options, show_usage_dialog_cb)
                    end
                elseif E.Sysinfo.os() == 'ios' then
                    request_location_permission(function(request_permission_succ)
                        E.log('request_location_permission result is ' .. tostring(request_permission_succ))
                        if request_permission_succ then
                            --授权成功
                            E.LOG.debug(VENDOR_NAME, 'request permission succ')
                            real_get_location(cb)
                        else
                            show_setting_usage_dialog_fun()
                            cb(false, ERR_CODE_PERMISSION_DENY, 'permission deny')
                        end
                    end)
                end
            elseif -1 == status then
                -- 永久拒绝,显示跳转设置弹窗
                E.LOG.debug(VENDOR_NAME,'permission deny， and never ask' .. permission)
                show_setting_usage_dialog_fun()
                cb(false, ERR_CODE_PERMISSION_DENY, 'permission deny')
            end
        else
            E.LOG.debug(VENDOR_NAME,'permission access, ' .. permission)
            real_get_location(cb)
        end
    end)
end

-- opt.show_custom_usage_dialog, opt支持设置自定义权限说明弹窗，若无设置，则使用默认
-- 使用默认弹窗时,opt.title:权限名称，opt.message:权限描述, 设置自定义文案
-- opt.show_custom_setting_usage_dialog: 设置自定义跳转设置弹窗，若无设置，则使用默认
-- opt.setting_guide_title：引导前往设置的弹窗的title，opt.setting_guide_message: 引导前往设置弹窗的描述文案，若无设置，使用默认
-- opt.force_request_permission: 设置是否强制授权，如果设置为true，则每次都会弹窗授权，默认为false，
-- opt.max_request_permission_count:设置弹窗授权次数（在未设置强制授权，或设置强制授权为false时生效），默认为1，只弹一次。
-- opt.ip_lbs_enable: 设置是否使用ip定位,默认值为true。如果设置为false，则只有能获取到经纬度时才能获取位置信息，否则返回失败
-- opt.force_request_location: 不使用缓存，无论当前是否有定位信息，都重新获取
-- todo 这里后续支持需要考虑云游的场景
function M.get_location(opt, cb)
    local force_request_location = opt.force_request_location or false
    if lbs_info_cache and force_request_location == false then
        E.LOG.debug(VENDOR_NAME,'has location info cache, now return')
        cb(true, lbs_info_cache)
    else
        local ip_location_cb = function(succ, ...)
            if succ then
                local lbs_info = ...
                if lbs_info and lbs_info.city_code then
                    lbs_info_cache = lbs_info
                    E.LOG.debug(VENDOR_NAME, 'get location info succ')
                    E.log(lbs_info_cache)
                    cb(true, ...)
                else
                    --返回错误
                    cb(false, ERR_CODE_SERVER_RESULT_INVALID, 'server result is invalid')
                end
            else
                local status, error_msg = ...
                E.LOG.debug(VENDOR_NAME, 'get location info fail, status is ' .. tostring(status) .. ', msg is ' .. tostring(error_msg))
                cb(false, ...)
            end
        end

        --判断是否支持LBS
        if not EC.has_vendor_config('LBS') then
            get_location_info_from_server({}, ip_location_cb)
            return 
        end

        M.get_device_location(opt, function(succ, ...)
            E.LOG.debug(VENDOR_NAME, 'get_device_location callback')
            if succ then
                E.LOG.debug(VENDOR_NAME, 'get_device_location succ, request location info')
                local params = ...
                if params then
                    E.log(params)
                end
                get_location_info_from_server(params, ip_location_cb)
            else
                local ip_lbs_enable = true
                if opt.ip_lbs_enable ~= nil then
                    ip_lbs_enable = opt.ip_lbs_enable
                end
                if ip_lbs_enable then
                    E.LOG.debug(VENDOR_NAME, 'get_device_location fail, now use ip location')
                    get_location_info_from_server({}, ip_location_cb)
                else
                    cb(false, ...)
                end
            end
        end)
    end
end

return M