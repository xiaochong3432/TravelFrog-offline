local E = require "ejoysdk_lua.ejoysdk"
local JSON = require "ejoysdk_lua.ejoysdk_json"
local EM = require "ejoysdk_lua.ejoysdk_module"

local UNISDK_EVENT = "UNISDK_EVENT"

local ACT_UNISDK_ASYNC_CALL = "UNISDK_ASYNC_CALL"

local IVK_UNISDK_INIT = "UNISDK_INIT"
local IVK_UNISDK_LOGIN = "UNISDK_LOGIN"
local IVK_UNISDK_LOGOUT = "UNISDK_LOGOUT"
local IVK_UNISDK_PAY = "UNISDK_PAY"
local IVK_UNISDK_CAST = "UNISDK_CAST"
local IVK_UNISDK_SET_PLAYER_INFO = 'UNISDK_SET_PLAYER_INFO'
local IVK_UNISDK_EXIT = "UNISDK_EXIT"

local CT_UNISDK_GET_ABILITY = "UNISDK_GET_ABILITY"
local CT_UNISDK_SYNC_CALL = "UNISDK_SYNC_CALL"

local GET_SDK_INFOS = "GET_SDK_INFOS"

-- 这些值耦合native 代码，并不能乱修改
local EVT_LOGIN = 1
local EVT_LOGOUT = 2
local EVT_PAY = 3
local EVT_EVENT = 4
local EVT_INIT = 5
local EVT_EXIT = 6

local TAG = EM.MODULE.VENDORS.UNI_SDK

local M = {}

local nop = function(key)
    E.LOG.debug(TAG, "unisdk nop function called " .. tostring(key))
end

local cb_mt = {
    __index = function()
        return nop
    end
}

local init_cb_tbl = setmetatable({}, cb_mt)
local login_info = {}
local login_cb_tbl = setmetatable({}, cb_mt)
local logout_cb_tbl = setmetatable({}, cb_mt)
local pay_cb_tbl = setmetatable({}, cb_mt)
local event_cb_tbl = setmetatable({}, cb_mt)
local exit_cb_tbl = setmetatable({}, cb_mt)

local function on_init(succ, chn, msg)
    local init_result
    if succ then
        init_result = 'unisdk on_init init success'
    else
        init_result = 'unisdk on_init init failed: '.. msg
    end
    E.LOG.debug(TAG, init_result)
    init_cb_tbl[chn](succ, msg)
end

local function on_login(succ, chn, info, ext_params)
    if succ then
        E.LOG.debug(TAG, '记录登录成功信息表')
        E.LOG.debug(TAG, {
            succ = succ,
            chn = chn,
            info = info,
            ext_params = ext_params
        })
        login_info[chn] = {info = info, ext = ext_params}
    end

    -- mock 代码。
    --local ext_params = {}
    --ext_params.channel_id = "1234"
    --ext_params.data = "233234234"
    --ext_params.opcode = "wqweqweqwe"
    login_cb_tbl[chn](succ, info, ext_params)
end

local function on_logout(chn, ext_params)
    login_info[chn] = nil
    logout_cb_tbl[chn](ext_params)
end

local function on_pay_result(succ, chn, order_id, ext)
    pay_cb_tbl[chn](succ, order_id, ext)
end

local function on_event(chn, type_, body)
    event_cb_tbl[chn](type_, body)
end

local function on_exit(chn, succ)
    exit_cb_tbl[chn](succ)
end

local function load_sdkconfig()
    local unisdk_config, data
    local os_config = E.CONFIG.get_config("os")
    if os_config == "android" then
        unisdk_config = "unisdk/sdkconfig.json"
        data = _ejoysdk.lread(unisdk_config)
    elseif os_config == 'ios' then
        unisdk_config = "ejoysdk/sdkconfig.json"
        data = _ejoysdk.lread(unisdk_config)
    elseif os_config == 'windows' then
        if _ejoysdk.get_sdkconfig_path and #(_ejoysdk.get_sdkconfig_path()) > 0 then -- pc 自定义的 sdkconfig 路径
            unisdk_config = _ejoysdk.get_sdkconfig_path()
            E.LOG.debug(TAG, 'has custom sdkconfig_path: ' .. tostring(unisdk_config))
            local f, error = io.open(unisdk_config, 'r')
            if f ~= nil then
                data = f:read("*all")
                f:close()
            else
                if _ejoysdk.utf8_to_acp then
                    E.LOG.debug(TAG, 'use utf8_to_acp function to convert this path')
                    local temp_path = _ejoysdk.utf8_to_acp(unisdk_config)
                    f, error = io.open(temp_path, 'r')
                    if f ~= nil then
                        data = f:read("*all")
                        f:close()
                    else
                        E.LOG.warn(TAG, 'utf8_to_acp method to open sdkconfig.json fail: ' .. tostring(error))
                        E.LOG.debug(TAG, 'try lread to read file')
                        -- 需要新的native版本才能生效，因为修改了lread的实现
                        data = _ejoysdk.lread(unisdk_config)
                    end
                else
                    E.LOG.debug(TAG, 'do not have utf8_to_acp function, last error: '..tostring(error))
                end


            end
        else
            E.LOG.debug(TAG, 'no custom sdkconfig_path')
            unisdk_config = "sdkconfig.json"
            data = _ejoysdk.lread(unisdk_config)
        end
    end

    assert(data and data ~= "", "Read sdkconfig.json fail!!!")
    E.LOG.debug(TAG, 'data is ===')
    E.log(data)
    local unisdk_meta = JSON.decode(data)
    if os_config == 'ios' and unisdk_meta and unisdk_meta.sdks then
        local sdk_infos = unisdk_meta.sdks
        for _, sdk_info in pairs(sdk_infos) do
            if sdk_info and sdk_info.meta_data then -- Android 叫 meta，iOS 做转换，保持统一
                sdk_info.meta = sdk_info.meta_data
            end
        end
    end

    if unisdk_meta == nil then
        _ejoysdk.log("[error]!!!!!!!!!!!!Read sdkconfig.json fail!!!, pls check sdkconfig.json first!!!!!!!!!!!!")
    end

    E.CONFIG.set_config('unisdk_meta', unisdk_meta or {})
end

local API = {}
do
    load_sdkconfig()

    local os_config = E.CONFIG.get_config("os")
    if os_config == "android" then
        function API.init(chn, params)
            E.invoke(IVK_UNISDK_INIT, {channel = chn, params = params})
        end

        function API.login(chn, params)
            E.invoke(IVK_UNISDK_LOGIN, {channel = chn, params = params})
        end

        function API.logout(chn, params)
            E.invoke(IVK_UNISDK_LOGOUT, {channel = chn, params = params})
        end

        function API.pay(chn, order_id, params)
            E.invoke(
                    IVK_UNISDK_PAY,
                    {
                        channel = chn,
                        orderId = order_id,
                        params = params
                    }
            )
        end

        function API.set_player_info(chn, params, type)
            E.invoke(IVK_UNISDK_SET_PLAYER_INFO, {channel = chn, params = params, type = type})
        end

        function API.get_sdk(ability)
            return E.sync_call(CT_UNISDK_GET_ABILITY, {ability = ability})
        end

        function API.exit(chn)
            E.invoke(IVK_UNISDK_EXIT, {channel = chn})
        end

        function API.get_sdk_infos()
            return E.sync_call(GET_SDK_INFOS, {}) or {}
        end

        function API.async_call(channel, type_, params, chunk, cb)
            params["channel"] = channel
            params["type"] = type_
            E.async_call(
                    ACT_UNISDK_ASYNC_CALL,
                    params,
                    chunk,
                    function(body, resp_chunk)
                        if body.code == 0 then
                            cb(true, body.body, resp_chunk)
                        else
                            cb(false, body.code, body.body, resp_chunk)
                        end
                    end
            )
        end

        function API.sync_call(channel, type_, params, chunk)
            params["channel"] = channel
            params["type"] = type_
            return E.sync_call(CT_UNISDK_SYNC_CALL, params, chunk)
        end

        function API.cast(channel, type_, params, chunk)
            params["channel"] = channel
            params["type"] = type_
            E.invoke(IVK_UNISDK_CAST, params, chunk)
        end

        local event_dispatch = {
            [EVT_LOGIN] = function(value)
                E.log(value)
                if value.succ then
                    local info = {
                        channel = value.channel,
                        channel_product_code = value.channel_product_code,
                        token = value.token,
                        pid = value.user_id
                    }
                    on_login(true, value.channel, info, value.ext_params)
                else
                    local ext_params = value.ext_params or {}
                    local info = {
                        code = ext_params.code or value.code,
                        msg = ext_params.msg or value.msg
                    }
                    on_login(false, value.channel, info, ext_params)
                end
            end,
            [EVT_LOGOUT] = function(value)
                on_logout(value.channel, value.ext_params)
            end,
            [EVT_PAY] = function(value)
                if value.succ then
                    on_pay_result(true, value.channel, value.order_id, value.ext)
                else
                    on_pay_result(false, value.channel, value.order_id, value)
                end
            end,
            [EVT_EVENT] = function(value)
                local chn = value.channel
                local type_ = value.type
                local body = value.body
                on_event(chn, type_, body)
            end,
            [EVT_INIT] = function(value)
                if value.succ then
                    on_init(true, value.channel, '')
                else
                    on_init(false, value.channel, value.msg)
                end
            end,
            [EVT_EXIT] = function(value)
                on_exit(value.channel, value.succ)
            end
        }

        _ejoysdk.register_cb(
                UNISDK_EVENT,
                function(cbid, js_str, chunk)
                    local handler = event_dispatch[cbid]
                    if handler then
                        local value = JSON.decode(js_str)
                        handler(value, chunk)
                    end
                end
        )
    elseif os_config == 'ios' then
        -- iOS
        API.init = function(chn, params)
            _ejoysdk.unisdk_init(chn, JSON.encode(params))
        end

        API.login = function(chn, params)
            _ejoysdk.unisdk_login(chn, JSON.encode(params))
        end

        API.logout = function(chn, params)
            _ejoysdk.unisdk_logout(chn, JSON.encode(params))
        end

        API.pay = function(chn, order_id, params)
            _ejoysdk.unisdk_pay(chn, order_id, JSON.encode(params))
        end

        API.set_player_info = function(chn, params, type)
            _ejoysdk.unisdk_set_player_info(chn, JSON.encode(params), type)
        end

        API.exit = function(chn)
            if _ejoysdk.exit then
                -- NOTICE: ios 的 ejoysdk framework 2.0.19 版本及以前的版本，没有 exit 方法，这里要做一层保护
                _ejoysdk.exit(chn)
            else
                _ejoysdk.log("_ejoysdk.exit() is not implemented")
            end
        end

        API.get_sdk_infos = function()
            local sdk_infos = JSON.decode(_ejoysdk.get_sdk_infos and _ejoysdk.get_sdk_infos() or '{}')
            for _, sdk_info in pairs(sdk_infos) do
                if sdk_info and sdk_info.meta_data then -- Android 叫 meta，iOS 做转换，保持统一
                    sdk_info.meta = sdk_info.meta_data
                end
            end
            return sdk_infos
        end

        function API.get_sdk(ability)
            local sdk_infos = API.get_sdk_infos()
            local ret = {sdks={}}
            for sdk_name, sdk_info in pairs(sdk_infos) do
                if sdk_info.ability then
                    for __, _ability in ipairs(sdk_info.ability) do
                        if _ability == ability then
                             table.insert(ret.sdks, sdk_name)
                        end
                    end
                end
            end
            return ret
        end

        function API.async_call(channel, type_, params, chunk, cb)
            chunk = chunk or ""
            E.async_call(
                    "unisdk_async_call",
                    function(body, resp_chunk)
                        body = body or '{}'
                        body = JSON.decode(body)
                        if body.code == 0 then
                            cb(true, body.body, resp_chunk)
                        else
                            cb(false, body.code, body.body, resp_chunk)
                        end
                    end,
                    channel,
                    type_,
                    JSON.encode(params),
                    chunk
            )
        end

        API.sync_call = function(chn, type_, params, chunk)
            chunk = chunk or ""
            local ret = _ejoysdk.unisdk_sync_call(chn, type_, JSON.encode(params), chunk)
            return JSON.decode(ret)
        end

        API.cast = function(chn, type_, params, chunk)
            chunk = chunk or ""
            _ejoysdk.unisdk_cast(chn, type_, JSON.encode(params), chunk)
        end

        local event_dispatch = {
            [EVT_LOGIN] = function(chn, status_code, body)
                local value = JSON.decode(body)
                if status_code == 0 then
                    local info = {
                        channel = chn,
                        channel_product_code = value.channel_product_code,
                        token = value.token,
                        pid = value.pid
                    }
                    on_login(true, chn, info, value.ext_params)
                else
                    local info = {
                        code = value.code,
                        msg = value.msg
                    }
                    on_login(false, chn, info, value.ext_params)
                end
            end,
            [EVT_LOGOUT] = function(chn, _status_code, body)
                if not body or body == '' then
                    body = '{}'
                end
                local value = JSON.decode(body)
                on_logout(chn, value.ext_params)
            end,
            [EVT_PAY] = function(chn, status_code, body)
                local value = JSON.decode(body) or {}
                local order_id = value.order_id or ''
                status_code = tostring(status_code)
                if status_code == '0' then
                    on_pay_result(true, chn, order_id, value)
                else
                    local default_msg = ''
                    if status_code == '1' then
                        default_msg = "PAY_FAILED"
                    elseif status_code == '2' then
                        default_msg = "PAY_CANEL"
                    end
                    local ret = {}
                    ret.code = status_code
                    ret.msg = default_msg
                    ret.ext = value
                    on_pay_result(false, chn, order_id, ret)
                end
            end,
            [EVT_EVENT] = function(chn, type_, body)
                on_event(chn, type_, JSON.decode(body))
            end,
            [EVT_INIT] = function(chn, status_code, body)
                local value = JSON.decode(body)
                if status_code == 0 then
                    --on_init(true, chn, {}, {})
                    on_init(true, chn, '')
                else
                    --local info = {
                    --    code = value.code,
                    --    msg = value.msg
                    --}
                    --on_init(false, chn, info, value.ext_params)
                    on_init(false, chn, value.msg)
                end
            end,
            [EVT_EXIT] = function(chn, body)
                local value = JSON.decode(body)
                on_exit(chn, value.succ)
            end
        }

        _ejoysdk.register_cb(
                UNISDK_EVENT,
                function(cbid, ...)
                    local handler = event_dispatch[cbid]
                    if handler then
                        handler(...)
                    end
                end
        )
    elseif os_config == 'windows' then
        API.init = function(chn, _params)
            -- 从native获取初始化参数
            if _ejoysdk.sdkinfo then
                local sdkinfo = _ejoysdk.sdkinfo()
                if sdkinfo and sdkinfo.init_args then
                    E.CONFIG.set_config(E.CONFIG.KEY.INIT_ARGS, JSON.decode(sdkinfo.init_args))
                end
            end
            on_init(true, chn, '')
        end

        API.cast = function(chn, type_, params, chunk)
            chunk = chunk or ""
            _ejoysdk.unisdk_cast(chn, type_, JSON.encode(params), chunk)
        end

        API.sync_call = function(chn, type_, params, chunk)
            chunk = chunk or ""
            local ret = _ejoysdk.unisdk_sync_call(chn, type_, JSON.encode(params), chunk)
            return JSON.decode(ret)
        end

        API.set_player_info = function(_chn, _params, _type)
            --TODO windows sdk 接口实现
        end

        API.get_sdk = function(ability)
            local sdk_infos = API.get_sdk_infos()
            local ret = {sdks={}}
            for sdk_name, sdk_info in pairs(sdk_infos) do
                if sdk_info.ability then
                    for __, _ability in ipairs(sdk_info.ability) do
                        if _ability == ability then
                            table.insert(ret.sdks, sdk_name)
                        end
                    end
                end
            end
            return ret
        end

        API.get_sdk_infos = function()
            local sdk_infos = JSON.decode(_ejoysdk.get_sdk_infos and _ejoysdk.get_sdk_infos() or '{}')
            return sdk_infos
        end

        API.exit = function(chn)
            -- do nothing here
        end

        API.logout = function()
            -- do nothing here
        end

        API.async_call = function()
            -- do nothing here
        end

    end
end

function M.init(chn, params)
    params = params or {}
    API.init(chn, params)
end

function M.login(chn, params)
    params = params or {}
    API.login(chn, params)
end

function M.logout(chn, params)
    params = params or {}
    login_info[chn] = nil
    API.logout(chn, params)
end

function M.get_info(chn)
    return login_info[chn]
end

function M.register_init_listener(channel, cb)
    init_cb_tbl[channel] = cb
end

function M.register_login_listener(channel, cb)
    login_cb_tbl[channel] = cb
end

function M.register_logout_listener(channel, cb)
    logout_cb_tbl[channel] = cb
end

function M.register_pay_listener(channel, cb)
    pay_cb_tbl[channel] = cb
end

function M.register_event_cb(channel, cb)
    event_cb_tbl[channel] = cb
end

function M.register_exit_cb(channel, cb)
    exit_cb_tbl[channel] = cb
end

function M.pay(chn, order_id, params)
    API.pay(chn, order_id, params)
end

function M.get_sdk(ability)
    return API.get_sdk(ability)
end

-- 针对sdk_infos做个缓存，避免每次调用读取sdkconfig文件decode的耗时
local cache_sdk_infos
function M.get_sdk_info(name)
    local sdk_infos = M.get_sdk_infos()

    for sdk_name, sdk_info in pairs(sdk_infos) do
        if name == sdk_name then
            return sdk_info
        end
    end
    return nil
end

function M.set_player_info(channel, player_info, type)
    return API.set_player_info(channel, player_info, type)
end

function M.exit(chn)
    return API.exit(chn)
end

function M.get_sdk_infos()
    -- 如果native没准备好，cache_sdk_infos为空table，则不缓存
    if cache_sdk_infos == nil or (cache_sdk_infos and next(cache_sdk_infos) == nil) then
        cache_sdk_infos = API.get_sdk_infos()
    end
    local utils = require "ejoysdk_lua.ejoysdk_utils"
    return utils.deepcopy(cache_sdk_infos)
end

M.async_call = API.async_call
M.sync_call = API.sync_call
M.cast = API.cast

return M
