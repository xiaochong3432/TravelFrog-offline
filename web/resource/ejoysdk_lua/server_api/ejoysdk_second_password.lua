local E = require 'ejoysdk_lua.ejoysdk'
local BASE_API = require 'ejoysdk_lua.libs.base_api'
local sec_psw_api = BASE_API:New('safebox') -- 新建 stake api 模块
local EM = require "ejoysdk_lua.ejoysdk_module"
local _TAG = EM.MODULE.SERVER_API .. 'sec_password'
local M = {}

local password_type = 1

-- RC4 加密密码
local function encrypt_password(password)
    local rc4_init_key = 'rc4_key_ZWxpeGlyaQ=='
    local rc4_key = _ejoysdk_crypt.rc4_key(rc4_init_key)
    local encrypt_key = _ejoysdk_crypt.rc4_encrypt(password, rc4_key)
    return _ejoysdk_crypt.base64encode(encrypt_key)
end

-- 获取二级密码锁当前状态，每次都从服务端获取
-- 服务端接入文档：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/cq7ouw
function M.get_status(cb)
    local headers = {}
    local body = {device_id = E.get_pkg_info().utdid}
    local opt = {use_ejoy_token = true}
    sec_psw_api:post('/sdk_api/secondlock/get_current_status', headers, body, opt, function(succ, ...)
        if succ then
            local result = ...
            local lock_info = result.lock_info
            cb(true, lock_info)
        else
            cb(false, ...)
        end
    end)
end

-- 设置二级密码
-- 使用状态：初始状态，还没有设置密码时
-- 服务度接入文档：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/pusgv0
function M.set_password(password, cb)
    local headers = {}
    local body = {
        password = encrypt_password(password),
        type = password_type,
        device_id = E.get_pkg_info().utdid or ''
    }

    local opt = {use_ejoy_token = true}
    sec_psw_api:post('/sdk_api/password/set_password', headers, body, opt, cb)
end

-- 关闭二级密码校验
-- 使用状态：已上锁或锁被解开
-- 服务端接入文档：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/qzrhtm
function M.close(password, cb)
    local headers = {}
    local body = {
        password = encrypt_password(password),
        device_id = E.get_pkg_info().utdid
    }
    local opt = {use_ejoy_token = true}
    sec_psw_api:post('/sdk_api/secondlock/lock_close', headers, body, opt, cb)
end

-- 打开二级密码校验
-- 使用状态：有锁，但是锁被关闭
-- 服务端接入文档：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/wnxyml
function M.open(cb)
    local headers = {}
    local body = {}
    local opt = {use_ejoy_token = true}
    sec_psw_api:post('/sdk_api/secondlock/lock_open', headers, body, opt, cb)
end

-- 申请移除二级密码锁
-- 使用状态：1.有锁，但是锁被关闭 2.已上锁或锁被解开
-- 服务端接入文档：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/yuz0go
function M.apply_remove(cb)
    local EG = require 'ejoysdk_lua.ejoysdk_gangplank'
    local headers = {}
    local body = {
        ptoken = EG.user_info().ptoken,
        pkg_info = E.get_pkg_info()
    }
    local opt = {use_ejoy_token = true}
    sec_psw_api:post('/sdk_api/password/apply_message', headers, body, opt, cb)
end

-- 移除二级密码锁
-- 使用状态：1.有锁，但是锁被关闭 2.已上锁或锁被解开
-- 服务端接入文档：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/gyzfs2
function M.remove(message_code, cb)
    local EG = require 'ejoysdk_lua.ejoysdk_gangplank'
    local headers = {}
    local body = {
        message = tostring(message_code),
        type = password_type,
        ptoken = EG.user_info().ptoken,
        pkg_info = E.get_pkg_info()
    }
    local opt = {use_ejoy_token = true}
    sec_psw_api:post('/sdk_api/password/remove', headers, body, opt, cb)
end

-- 通过二级密码移除二级密码
-- 使用状态：1.有锁，但是锁被关闭 2.已上锁或锁被解开
-- 服务端接入文档：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/tzt6si
function M.remove_by_password(password, cb)
    local headers = {}
    local body = {
        password = encrypt_password(password),
        type = password_type
    }
    local opt = {use_ejoy_token = true}
    sec_psw_api:post('/sdk_api/password/remove_by_password', headers, body, opt, cb)
end

-- 修改二级密码
-- 服务端接入文档：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/eacpax
function M.change_password(old_password, new_password, cb)
    local headers = {}
    local body = {
        password_old = encrypt_password(old_password),
        password_new = encrypt_password(new_password),
        type = password_type,
        device_id = E.get_pkg_info().utdid or ''
    }
    local opt = {use_ejoy_token = true}
    sec_psw_api:post('/sdk_api/password/change_password', headers, body, opt, cb)
end

-- 校验二级密码，校验成功后，服务端的锁会被解开，直至登录态被刷新
-- 服务端接入文档：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/bfwbzf
function M.verify(password, cb)
    local headers = {}
    local body = {
        password = encrypt_password(password),
        type = password_type
    }
    local opt = {use_ejoy_token = true}
    sec_psw_api:post('/sdk_api/password/verify', headers, body, opt, cb)
end

function M.get_security_mobile(cb)
    local EG = require 'ejoysdk_lua.ejoysdk_gangplank'
    local headers = {}
    local body = {
        ptoken = EG.user_info().ptoken,
        pkg_info = E.get_pkg_info()
    }
    local opt = {use_ejoy_token = true}
    sec_psw_api:post('/sdk_api/password/get_security_mobile', headers, body, opt, function(succ, ...)
        if not succ then
            cb(false, ...)
            return
        end
        local result = ...
        local security_mobile = result.security_mobile
        cb(true, security_mobile)
    end)
end


-- 二级密码一键申诉接口
-- 服务端接入文档：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/xv9guc#dJmB6
function M.password_appeal(cb)
    local EG = require 'ejoysdk_lua.ejoysdk_gangplank'
    local headers = {}
    local _body = {
        device_id = E.get_pkg_info().utdid,
        client = {
            token=EG.user_info().ptoken or '',
            gameId=E.get_pkg_info().game_id or '',
            accountId=EG.user_info().uid or ''
        }
    }

    local opt = {use_ejoy_token = true}
    sec_psw_api:post('/sdk_api/password/appeal', headers, _body, opt, function(succ, ...)

        -- 错误码接口文档 https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/xv9guc#xseoz
        local auto_appeal_failed_code = 10410

        if not succ then
            local code, _msg, body = ...
            if code == auto_appeal_failed_code then
                local url = ''
                if body and body.data and body.data.submitCasePageUrl and type(body.data.submitCasePageUrl) == 'string' and #(body.data.submitCasePageUrl) > 0 then
                    url = body.data.submitCasePageUrl
                end
                if #url > 0 then
                    E.open_webview(url,
                            {'.aligames.cn', '.aligames.com'},
                            {}, nil,
                            nil, nil)
                end
            end
            cb(false, ...)
            return
        end

        cb(true, ...)
    end)
end

-- 取消一键申诉(二级密码)接口
-- 服务端接入文档：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/xv9guc#dJmB6
function M.password_cancel_appeal(cb)
    local headers = {}
    local body = {
        type = password_type
    }

    local opt = {use_ejoy_token = true}
    sec_psw_api:post('/sdk_api/password/cancel_appeal', headers, body, opt, cb)
end

return M