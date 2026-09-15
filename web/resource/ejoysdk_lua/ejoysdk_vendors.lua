local E = require 'ejoysdk_lua.ejoysdk'
local EM = require "ejoysdk_lua.ejoysdk_module"
local EVV = require 'ejoysdk_lua.vendors.vendor'
local EUS = require 'ejoysdk_lua.vendors.unisdk'

local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'vendors'

local M = {}

M.VENDORS_NAME = {
    EJOY = 'ejoysdk_lua.vendors.ejoy',
    APPLE = 'ejoysdk_lua.vendors.apple',
    APPLE_LOGIN = 'ejoysdk_lua.vendors.apple_login',
    ALIGAMES = 'ejoysdk_lua.vendors.aligames',
    AIRLINE_V2 = 'ejoysdk_lua.vendors.airline_v2',
    ASA = 'ejoysdk_lua.vendors.asa_info',
    CBA = 'ejoysdk_lua.vendors.cba_info',
    AGORA = 'ejoysdk_lua.vendors.agora',
    PUSH = 'ejoysdk_lua.vendors.push',
    ONE = 'ejoysdk_lua.vendors.one_ios',
    BBG = 'ejoysdk_lua.vendors.bbgame',
    BBG_LOGIN = "ejoysdk_lua.vendors.bbg_login",
    HW_LOGIN = "ejoysdk_lua.vendors.hw_login",
    JF = 'ejoysdk_lua.vendors.jf',
    APPSFLYER = 'ejoysdk_lua.vendors.appsflyer',
    GOOGLE = 'ejoysdk_lua.vendors.google',
    GOOGLE_PLAY = 'ejoysdk_lua.vendors.google',
    FB = 'ejoysdk_lua.vendors.facebook',
    FIREBASE = 'ejoysdk_lua.vendors.firebase',
    HELPSHIFT = 'ejoysdk_lua.vendors.helpshift',
    CRASH_SDK = 'ejoysdk_lua.vendors.crashsdk',
    NOONE = 'ejoysdk_lua.vendors.noone',
    APPLOG = 'ejoysdk_lua.vendors.applog',
    OFFICIAL = 'ejoysdk_lua.vendors.official',
    OFFICIALPAY = 'ejoysdk_lua.vendors.official_pay',
    REYUN = 'ejoysdk_lua.vendors.reyun',
    SECURITY = 'ejoysdk_lua.vendors.security',
    SENTRY = 'ejoysdk_lua.sentry.ejoysdk_sentry_log_upload',
    EJOYADS = 'ejoysdk_lua.vendors.ejoyads',
    AIRLINE = 'ejoysdk_lua.vendors.airline_account',
    QR_LOGIN = 'ejoysdk_lua.vendors.qrcode_account',
    AGST = 'ejoysdk_lua.vendors.agst_account',
    XSPACE = 'ejoysdk_lua.vendors.xspace',
    CLOUD_GAME = 'ejoysdk_lua.vendors.cloud_game',
    LINE = 'ejoysdk_lua.vendors.line',
    INSTAGRAM = 'ejoysdk_lua.vendors.instagram',
    WHATSAPP = 'ejoysdk_lua.vendors.whatsapp',
    TWITTER_LOGIN = 'ejoysdk_lua.vendors.twitter',
    CITA_LOGIN = 'ejoysdk_lua.vendors.cita_account',
    TRAVLETPAY = 'ejoysdk_lua.vendors.travlet_pay',
    ST_LOGIN = 'ejoysdk_lua.vendors.st_account',
    EJOY_ODR = 'ejoysdk_lua.vendors.odr',
    WIN_OFFICIAL_PAY = 'ejoysdk_lua.vendors.win_official_pay',
    WIN_OVERSEAS_PAY = 'ejoysdk_lua.vendors.h5_overseas_pay',
    H5_OVERSEAS_PAY = 'ejoysdk_lua.vendors.h5_overseas_pay',
    PGA_LOGIN = 'ejoysdk_lua.vendors.playgames',
    APM = 'ejoysdk_lua.vendors.apm',
    NAVER_GAME = 'ejoysdk_lua.vendors.naver_game',
    EJOY_SCAN = 'ejoysdk_lua.vendors.ejoy_scan',
    ALIGAMES_WHITE_BRAND = 'ejoysdk_lua.vendors.aligames_white_brand',
    GAMEBOX = 'ejoysdk_lua.vendors.gamebox',
    TAOBAO_AUTH = 'ejoysdk_lua.vendors.taobao',
    ANT = 'ejoysdk_lua.vendors.ant', -- 以后会包括支付
    ALI_DATA_PKG = 'ejoysdk_lua.vendors.ali_datapkg',
    ZALO = 'ejoysdk_lua.vendors.zalo',
    SHORTCUT = 'ejoysdk_lua.vendors.shortcut',
    PREDOWNLOAD = 'ejoysdk_lua.vendors.predownload',
    DMM_LOGIN = 'ejoysdk_lua.vendors.dmm_account'
}

M.UMBRELLA_VENDORS = { OFFICIAL = true }

M.VENDORS = {}

local inited_vendors = {}

local has_inject_umbrella = false

function M.init(vendors, listeners, cb)
    if not has_inject_umbrella then
        for umbrella, _ in pairs(M.UMBRELLA_VENDORS) do
            if vendors[umbrella] then
                M.inject_umbrella(umbrella, vendors)
            end
        end
        has_inject_umbrella = true
    end

    local vendor_name_arr = {}
    local vendor_param_arr = {}
    local n = 0

    for k, v in pairs(vendors) do
        n = n + 1
        vendor_name_arr[n] = k
        vendor_param_arr[n] = v
    end

    local len = n
    local index = 1

    local function init_vendor(vendor_name, vendor_param)
        E.LOG.debug(TAG, 'init_vendor begin:' .. (vendor_name or 'nil') .. ', total_len:' .. len .. ', current_index:' .. index)
        local function init_next_vendor()
            index = index + 1
            E.LOG.debug(TAG, 'start init_next_vendor index:' .. index)
            if index <= len then
                local name = vendor_name_arr[index]
                local param = vendor_param_arr[index]
                init_vendor(name, param)
            else
                E.LOG.debug(TAG, 'init_next_vendor not has next, all is complete, callback success!')
                -- cb success
                if cb then
                    cb(true)
                end
            end
        end

        -- check not init vendors
        if inited_vendors[vendor_name] then
            E.LOG.debug(TAG, 'init_vendor, vendor:' .. (vendor_name or 'nil') .. ' already initted, now skip')
            init_next_vendor()
            return
        end

        local vendor = M.get(vendor_name)
        if vendor and vendor.init then
            E.LOG.debug(TAG, 'init_vendor, vendor:' .. (vendor_name or 'nil') .. ' exist and has init method, start call vendor init!')
            local auth_listener = function(...)
                listeners.auth_listener(vendor_name, ...)
            end
            local pay_listener = function(...)
                listeners.pay_listener(vendor_name, ...)
            end
            local switch_listener = function(...)
                listeners.switch_listener(vendor_name, ...)
            end
            local logout_listener = function(...)
                listeners.logout_listener(vendor_name, ...)
            end
            local exit_listener = function(...)
                listeners.exit_listener(vendor_name, ...)
            end

            local vopt = {}
            vopt.auth_listener = auth_listener
            vopt.pay_listener = pay_listener
            vopt.switch_listener = switch_listener
            vopt.logout_listener = logout_listener
            vopt.exit_listener = exit_listener
            for k, v in pairs(vendor_param) do
                vopt[k] = v
            end

            vendor.init(vopt, function(succ, ...)
                if succ then
                    E.LOG.debug(TAG, 'vendor init succ, vendor_name:' .. vendor_name)
                    -- 更新初始化成功的vendors
                    inited_vendors[vendor_name] = true
                    --初始化下一个vendor
                    init_next_vendor()
                else
                    -- cb failed
                    local code, msg = ...
                    E.LOG.warn(TAG, 'vendor init failed, vendor_name:' .. vendor_name .. ', code:' .. tostring(code) .. ', msg:' .. tostring(msg))
                    if cb then
                        cb(false, code, msg)
                    end

                    E.LOG.warn(TAG, 'vendor inited failed, vendor_name:' .. vendor_name .. ', and return failed')
                    return
                end
            end)
        else
            E.LOG.warn(TAG, 'init_vendor, vendor:' .. (vendor_name or 'nil') .. ' NOT exist or does not have init method, skip and init next vendor')
            init_next_vendor()
        end
    end

    local vendor_name = vendor_name_arr[index]
    local vendor_param = vendor_param_arr[index]
    init_vendor(vendor_name, vendor_param)
end

function M.get_vendor_name(outoutsource)
    if outoutsource.with and not M.UMBRELLA_VENDORS[outoutsource.with] then
        return outoutsource.with
    end
    return outoutsource.platform
end

function M.get(vendor)
    if not M.VENDORS[vendor] then
        local vendor_name = M.VENDORS_NAME[vendor]
        if vendor_name then
            M.VENDORS[vendor] = require(vendor_name)
        end
    end
    return M.VENDORS[vendor]
end

function M.has_vendor(vendor_name)
    return M.VENDORS[vendor_name]
end

M.ABILITY = EVV.ABILITY

--[
-- 获取当前包支持的渠道列表
-- 这个接口以前只会返回 native sdk，现在 lua vendor 也可以通过 sdkconfig 配置，所以 lua vendor 配置也会一起返回。
--@params ability:  ACCOUNT, PAY ...
--]
function M.get_native_vendors(ability)
    assert(M.ABILITY[ability], tostring(ability) .. ' not found')
    local sdkAbility = EUS.get_sdk(ability)
    if sdkAbility then
        return sdkAbility.sdks or {}
    end
    return {}
end

function M.get_vendors(ability)
    local base = M.get_native_vendors(ability)
    local os = E.CONFIG.get_config('os')

    if os == 'ios' then
        table.insert(base, 'APPLE')
    end

    if ability == M.ABILITY.ACCOUNT then
        table.insert(base, 'EJOY')
    end

    return base
end

function M.inject_umbrella(umbrella_vendor, vendors)
    local vendor = M.get(umbrella_vendor)
    local supported_vendors = vendor.get_umbrella_vendors(vendors)
    for vendor_name, sub_vendor in pairs(supported_vendors) do
        M.VENDORS[vendor_name] = sub_vendor
    end
end

return M
