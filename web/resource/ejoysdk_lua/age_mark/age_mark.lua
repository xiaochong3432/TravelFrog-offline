local E = require "ejoysdk_lua.ejoysdk"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local V = require "ejoysdk_lua.version"
local UP = require "ejoysdk_lua.user_center.usercenter_protocal"
local util = require "ejoysdk_lua.ejoysdk_utils"
local EM = require "ejoysdk_lua.ejoysdk_module"
local age_log = require 'ejoysdk_lua.ejoysdk_log_mgr'

local M = {}
local TAG = EM.MODULE.AGE_MARK .. 'age_mark'

local module_inited = false
local pre_loaded = false

local cached_resp = {
}

-- 正在请求时，调用方的cb，等请求完成，会执行回调
local wait_cb = {
}

-- 正在请求的类型
local on_request = {
}

local base_url = 'https://res.flysdk.cn'

local function safeCallCb(cb, ...)
    if cb and type(cb) == 'function' then
        cb(...)
    end
end

local function isValidCb(cb)
    return cb and type(cb) == 'function'
end

local function handle_wait_cb(ageInfoFormat, ...)
    local wait_cb_curr_type = wait_cb[ageInfoFormat] or {}
    for _, cb in pairs(wait_cb_curr_type) do
        safeCallCb(cb, ...)
    end
    wait_cb[ageInfoFormat] = nil
end

local function is_overseas ()
    return E.CONFIG.get_config(E.CONFIG.KEY.MULTI_REGIONS_ENABLED)
end

-- 预加载
local function pre_load()
    -- 海外失效
    if is_overseas() or pre_loaded then
        E.LOG.debug(TAG, 'pre load, fail')
        return
    end
    pre_loaded = true
    M.get_age_mark({ignoreCache=true}, function(succ, ...)
        if succ then
            E.LOG.debug(TAG, 'pre load, req succ')
        else
            E.LOG.debug(TAG, 'pre load, req fail')
        end
    end)
end

local function real_http_get_age_mark(aOpts, cb)
    local opts = util.deepcopy(aOpts)

    -- sdk内，自认的参数，不要发到请求中去
    opts['ignoreCache'] = nil
    -- 新版接口，ageInfoFormat参数，不需要传了，即使游戏传了，也把这个ageInfoFormat参数移除
    opts['ageInfoFormat'] = nil

    -- ageInfoFormat:h5 or text
    local params = {
        ['bizId']='ageInfo'
    }
    for k, v in pairs(opts) do
        params[k] = v
    end

    -- 国内域名，这个需求目前不支持海外
    local url = base_url ..'/ejoyclient/'.. UP.SERVICE.GAME_DISPLAY_INFOS .. '?ver=1.0&df=json&gt=ng&cver='..V.LUA_VERSION..'&os='..E.Sysinfo.os()

    E.LOG.debug(TAG, 'http_get_age_mark, url:' .. tostring(url))

    UP.post_to(url, UP.SERVICE.GAME_DISPLAY_INFOS, params, function(succ, ...)
        local ageInfoFormat = ''
        if succ then
            local body = ...
            if body then
                cached_resp[ageInfoFormat] = body
                local copy_resp = util.deepcopy(cached_resp[ageInfoFormat])
                safeCallCb(cb, true, copy_resp)
                handle_wait_cb(ageInfoFormat, true, copy_resp)
            else
                safeCallCb(cb, false, 0, "resp body miss")
                handle_wait_cb(ageInfoFormat, false, 0, "resp body miss")
            end
        else
            local code, msg = ...
            code = code or 0
            msg = msg or 'error'
            safeCallCb(cb, false, code, msg)
            handle_wait_cb(ageInfoFormat, false, code, msg)
        end
        on_request[ageInfoFormat] = nil
    end, {log_level = age_log.LOG_LEVEL.LOW})
end

function M.init()
    if module_inited then
        return
    end

    E.LOG.debug(TAG, 'init')
    ET.subscribe(ET.gangplank.INITED, pre_load)

    ET.publish(ET.age.INITED, true)
    module_inited = true
end

function M.set_base_url(url)
    base_url = url
end

-- opts 保留字段，方便后续扩展参数，传nil 或者 {}
-- cb 成功=>cb(true, data), 失败=>cb(false, code, msg)
function M.get_age_mark(opts, cb)

    -- 海外失效
    if is_overseas() then
        safeCallCb(cb, false, 0, "unsupport overseas")
        return
    end

    opts = opts or {}
    opts.ageInfoFormat = ''

    local ignoreCache = opts.ignoreCache == true
    -- 不忽略缓存，且缓存存在，就返回缓存
    if not ignoreCache  and cached_resp[opts.ageInfoFormat] then
        -- 应该做深拷贝，再返给调用方
        local copy_resp = util.deepcopy(cached_resp[opts.ageInfoFormat])
        E.LOG.debug(TAG, 'resp from cache')
        safeCallCb(cb, true, copy_resp)
        return
    end

    -- 是否处于请求之中？是，并且间隔在3s内，就放进wait_cb里
    if on_request[opts.ageInfoFormat] and (os.time() - on_request[opts.ageInfoFormat]) <= 3 then
        if isValidCb(cb) then
            local wait_cb_curr_type = wait_cb[opts.ageInfoFormat] or {}
            wait_cb[opts.ageInfoFormat] = wait_cb_curr_type
            local key = tostring(os.time()) .. tostring(math.random(1000, 9999))
            wait_cb_curr_type[key] = cb
            E.Timer.once(3, function()
                local wait_cb_curr_type_after = wait_cb[opts.ageInfoFormat] or {}
                if wait_cb_curr_type_after[key] then
                    real_http_get_age_mark(opts, cb)
                    wait_cb_curr_type_after[key] = nil
                end
            end)
        end
        return
    end

    -- 标记正在请求中, 并记录下请求的时间戳
    on_request[opts.ageInfoFormat] = os.time()

    real_http_get_age_mark(opts, cb)
end

local function get_domain(_url)
    local url = E.Utils.trim(_url)

    local domain_name
    local last

    if string.sub(url, 1, 7) == "http://" then
        url = string.sub(url, 8)
    elseif string.sub(url, 1, 8) == "https://" then
        url = string.sub(url, 9)
    end

    last = string.find(url, "/")
    if last then
        url = string.sub(url, 1, last - 1)
    end

    local first_point = string.find(url, "%p")
    if first_point then
        url = string.sub(url, first_point)
    end
    domain_name = url

    return domain_name
end

local function open_webview(url)
    local local_start_up_data = {}
    local domain = get_domain(url)
    E.LOG.debug(TAG, 'open_webview, url=' .. (url or 'null') .. ', domain=' .. (domain or 'null'))
    local host = {
        [domain] = {
            transparent = false,
            startupData = local_start_up_data
        }
    }

    E.WebView.open(url, host, {
        compactMode= true,
        use_fragment = true,
        hide_close_btn = false
    })
end

function M.open_age_mark_page(cb)
    local start_resp = cached_resp['']
    local start_can_open = start_resp and start_resp['ageInfo'] and start_resp['ageInfo']['ageInfoH5'] and #(start_resp['ageInfo']['ageInfoH5']) > 0

    local open_webview_if_can = function(_cb)
        -- 要重新获取一下
        local resp = cached_resp['']

        -- 要重新判断一下
        local can_open = resp and resp['ageInfo'] and resp['ageInfo']['ageInfoH5'] and #(resp['ageInfo']['ageInfoH5']) > 0
        if can_open then
            open_webview(resp['ageInfo']['ageInfoH5'])
            safeCallCb(_cb, true)
        else
            safeCallCb(_cb, false, -1, 'ageInfoH5 data miss')
        end
    end

    -- 不能打开，就尝试重新请求
    if not start_can_open then
        M.get_age_mark({['ignoreCache']=true}, function(succ, ...)
            if succ then
                open_webview_if_can(cb)
            else
                local code, msg = ...
                safeCallCb(cb, code, msg)
            end
        end)
        return
    end

    open_webview_if_can(cb)
end

return M