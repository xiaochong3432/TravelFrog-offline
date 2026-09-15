local E = require "ejoysdk_lua.ejoysdk"

--账号历史
local ACCOUNT_HISTORY = E.LazyKeyStore:New("EJOYSDK_NOONE_ACCOUNT_HISTORY", false, true, false)
--最近一次登录的数据
local LAST_LOGIN_INFO = E.LazyKeyStore:New('EJOYSDK_NOONE_LAST_LOGIN_INFO', false, true, false)

local account_histories = {}

local M = {}

local TAG = "NOONE_HISTORY"

local function is_empty(str)
    return not str or '' == str or type(str)~='string'
end

function M.init()
    account_histories = ACCOUNT_HISTORY:get() or {}
end

function M.update(user_info)
    E.LOG.debug(TAG, 'noone update user_info')
    E.log(user_info)
    if not user_info or  is_empty(user_info.uid) then
        E.LOG.debug(TAG ..' update function return now....')
        return
    end

    local history = account_histories[user_info.uid] or {
        uid = user_info.uid,
    }
    --更新登录时间
    history['login_time'] = E.time()
    account_histories[history.uid] = history
    ACCOUNT_HISTORY:set(account_histories)
    LAST_LOGIN_INFO:set(user_info)
end

function M.get_last_login_info()
    local user_info = LAST_LOGIN_INFO:get()
    return user_info
end

function M.delete(uid)
    E.LOG.debug(TAG, 'noone delete account ' .. tostring(uid))
    if is_empty(uid) then
        return
    end
    account_histories[uid] = nil
    ACCOUNT_HISTORY:set(account_histories)
end

function M.get_list()
    E.LOG.debug(TAG, 'get noone history list')
    local list = {}
    for _, value in pairs(account_histories) do
        table.insert(list, value)
    end
    --按登录事件排序
    table.sort(list, function(account1, account2)
        return account1.login_time > account2.login_time
    end)
    E.LOG.debug(TAG,list)
    return list
end

function M.delete_last_login_info()
    E.LOG.debug(TAG, "NOONE clean last login info")
    LAST_LOGIN_INFO:delete()
end

return M


