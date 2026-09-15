-- 仅for iOS，安卓的one登录在大圣SDK内部
local E = require 'ejoysdk_lua.ejoysdk'
local Vendor = require "ejoysdk_lua.vendors.vendor"
local UNI = require "ejoysdk_lua.vendors.unisdk"
local EM = require "ejoysdk_lua.ejoysdk_module"

local VENDOR_NAME = 'ONE'
local VENDOR_NAME_ALIGMES = 'ALIGAMES'
local M = Vendor:Inherit(VENDOR_NAME)

local is_quick_login = false
local logout_listener = nil
local ONE_ACCESS_TOKEN = E.LazyKeyStore:New('ONE_ACCESS_TOKEN', false, false, false)
local ONE_PID = E.LazyKeyStore:New('ONE_PID', false, false, false)
local ONE_EXPIRE_TIME = E.LazyKeyStore:New('ONE_EXPIRE_TIME', false, false, false)

local TAG = EM.MODULE.VENDORS.ONE_IOS

local ds_login_function = nil
local auth_listener = nil

function M.set_ds_login_function(cb)
    if tostring(type(cb))  ~= 'function' then
        E.LOG.warn(TAG, 'set_ds_login_function, cb的类型不对')
        return
    end

    ds_login_function = cb
end

function M.set_auth_listener(cb)
    if tostring(type(cb)) ~= 'function' then
        E.LOG.warn(TAG,'set_auth_listener, cb的类型不对')
        return
    end
    
    auth_listener = cb
end

function M.channel_id()
    return 998244
end

local function set_store(access_token, pid, expire_time)
    ONE_ACCESS_TOKEN:set(access_token)
    ONE_PID:set(pid)
    ONE_EXPIRE_TIME:set(expire_time)
end

local function get_store()
    return ONE_ACCESS_TOKEN:get(), ONE_PID:get(), ONE_EXPIRE_TIME:get()
end

local function delete_store()
    ONE_ACCESS_TOKEN:delete()
    ONE_PID:delete()
    ONE_EXPIRE_TIME:delete()
end

function M.init(opt, cb)
    auth_listener = opt.auth_listener
    logout_listener = function( ... )
        delete_store()
        local fun = opt.logout_listener
        if fun then
            fun()
        end
    end
    UNI.register_login_listener(VENDOR_NAME, function(succ, info, _ext_params)
        if succ then

            if ds_login_function then
                -- 走大圣登录的协议
                local account_params = {
                    channelId = M.channel_id(), -- one的渠道号
                    ex = {
                        loginType = "ding",
                        authCode = info.token or '',
                    }
                }


                ds_login_function(account_params, function(ds_succ, body)
                    E.LOG.debug(TAG, 'ds_login_function finish >>')
                    E.LOG.debug(TAG, body)
                    if ds_succ then
                        local outsource = {
                            platform = tostring(M.channel_id()),
                            with = VENDOR_NAME_ALIGMES,
                            ptoken = body.token,
                            pid = info.pid,
                            guest = false,
                            ext = {}
                        }

                        if body.ex and body.ex.accessToken and body.ex.expireTime then
                            set_store(body.ex.accessToken, info.pid, body.ex.expireTime)
                            E.LOG.debug(TAG,"[one] set ds token")
                        else
                            E.LOG.debug(TAG,'not has accessToken, something is wrong!!!')
                        end


                        if auth_listener then
                            E.LOG.debug(TAG,' star call auth_listener_callback_function')
                            auth_listener(ds_succ, outsource, {})
                        else
                            E.LOG.debug(TAG,' not has auth_listener_callback_function')
                        end

                    else

                        if auth_listener then
                            E.LOG.debug(TAG, ' star call auth_listener_callback_function')
                            local outsource = {
                                code = body.code,
                                msg = body.message or ''
                            }
                            auth_listener(ds_succ, outsource, {})
                        else
                            E.LOG.debug(TAG, ' not has auth_listener_callback_function')
                        end

                    end
                end)
            else
                E.LOG.debug(TAG, '走原来的one登录协议，出问题啦-------')
                -- 走原来的协议
            end

        else
            delete_store()
            local outsource = {
                code = info.code,
                msg = info.msg or ''
            }
            auth_listener(false, outsource, {})
            E.LOG.warn(TAG, 'lua ding auth fail')
        end
    end)

    -- callback init success
    cb(true)
end

function M.login()

    is_quick_login = false
    local save_access_token, pid, expire_time = get_store()
    expire_time = tonumber(expire_time) -- 转换类型用来做比较
    local time_now = tonumber(os.time())

    if save_access_token and expire_time and expire_time > time_now then

        is_quick_login = true

        E.LOG.debug(TAG,'one quick login')

        local account_params = {
            channelId = M.channel_id(), -- one的渠道号
            ex = {
                loginType = "ding",
                accessToken = save_access_token
            }
        }

        if ds_login_function then
            -- 走大圣登录的协议
            ds_login_function(account_params, function(ds_succ, body)
                E.LOG.debug(TAG, 'login action, ds_login_function >>')
                E.LOG.debug(TAG, body)
                if ds_succ then
                    local outsource = {
                        platform = tostring(M.channel_id()),
                        with = VENDOR_NAME_ALIGMES,
                        ptoken = body.token,
                        pid = pid,
                        guest = false,
                        ext = {}
                    }

                    if auth_listener then
                        E.LOG.debug(TAG, ' star call auth_listener_callback_function')
                        auth_listener(ds_succ, outsource, {})
                    else
                        E.LOG.debug(TAG, ' not has auth_listener_callback_function')
                    end

                elseif (body.code == 4001002) then
                    E.LOG.debug(TAG, 'accessToken invalid, pleader retry login')
                    delete_store()
                    if is_quick_login then
                        E.LOG.debug(TAG, 'one quick login 4001002')
                        M.login()
                        is_quick_login = false
                    end

                else

                    if auth_listener then
                        E.LOG.debug(TAG, ' star call auth_listener_callback_function')
                        local outsource = {
                            code = body.code,
                            msg = body.message or ''
                        }
                        auth_listener(ds_succ, outsource, {})
                    else
                        E.LOG.debug(TAG, ' not has auth_listener_callback_function')
                    end

                end
            end)
        else

            E.LOG.debug(TAG, ' not is auto login, but not has ds_login_function')
        end


        return
    end

    UNI.login(VENDOR_NAME, {})
end

function M.merge_info(info, pinfo)
    return M.merge_helper(info, pinfo)
end

function M.simple_token()
    return false
end

function M.check_token(_outsource, _info)
    M.login()
end

function M.logout()
    logout_listener({})
end

function M.login_fail(status, _last_login_params, _login_listener)
    -- 这里的流程不会再执行了
    if status == 406 then
        delete_store()
        if is_quick_login then
            E.LOG.debug(TAG, 'one quick login 406')
            M.login()
            is_quick_login = false
        end
    end
    return false
end


function M.open_user_center()
    E.log('ONE not support user center page')
end

M:is_implemented({"ACCOUNT"})

return M
