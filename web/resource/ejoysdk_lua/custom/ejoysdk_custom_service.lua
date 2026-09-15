local CONSTANS = require 'ejoysdk_lua.ejoysdk_constants'
local E = require 'ejoysdk_lua.ejoysdk'
local EM = require "ejoysdk_lua.ejoysdk_module"
local M = {}

local TAG = EM.MODULE.CUSTOM .. "custom_service"

local function get_custom_service_vendor()

    -- 扫码包不支持客服
    if E.is_scan_pkg() then
        return nil
    end

    local EVDS = require 'ejoysdk_lua.ejoysdk_vendors'
    local EV = require 'ejoysdk_lua.vendors.vendor'

    -- 读取 sdkconfig 客服能力 vendor
    local vendor_names = EVDS.get_native_vendors(EV.ABILITY.CUSTOM_SERVICE)
    if vendor_names and #vendor_names > 0 then
        local vendor = EVDS.get(vendor_names[1])
        if vendor and vendor:is_support_ability({EV.ABILITY.CUSTOM_SERVICE}) then
            E.LOG.debug(TAG, "find support custom with native ability:" .. tostring(vendor_names[1]))
            return vendor
        end
    end

    -- 查找支持客服的 vendor
    for _name, vendor in pairs(EVDS.VENDORS) do
        if vendor:is_support_ability({EV.ABILITY.CUSTOM_SERVICE}) then
            E.LOG.debug(TAG, "find support custom with vendor ability:" .. tostring(_name))
            return vendor
        end
    end

    E.LOG.warn(TAG, "get_custom_service_vendor nil, no vendor found")
    --local default_custom_service_vendor = 'XSPACE'
    --return EVDS.get(default_custom_service_vendor)
    return nil
end

-- 是否支持客服
function M.can_show_custom_service()

    -- 扫码包不支持客服
    if E.is_scan_pkg() then
        return false
    end

    local vendor = get_custom_service_vendor()
    if vendor ~= nil then
        return true
    end
    return false
end

local default_orientation = 'portrait'
-- params.orientation : landscape 横屏、portrait 竖屏、sensor 跟随传感器
function M.show_custom_service(params, cb)
    params = params or {}
    params.orientation = params.orientation or default_orientation -- 默认横屏

    local vendor = get_custom_service_vendor()
    if not vendor then
        E.LOG.warn(TAG, "show_custom_service failed, no vendor found")
        if cb then
            cb(false, CONSTANS.CUSTOM_SERVICE.CODE_NOT_SUPPORT, '不支持客服接口')
        end
        return
    else
        E.LOG.debug(TAG, "show_custom_service begin")
        vendor.show_custom_service(params, cb)
    end
end

return M