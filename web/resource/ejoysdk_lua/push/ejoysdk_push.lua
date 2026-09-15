local E = require 'ejoysdk_lua.ejoysdk'
local ET = require "ejoysdk_lua.ejoysdk_topic"
--local EG = require 'ejoysdk_lua.ejoysdk_gangplank'
local JSON = require "ejoysdk_lua.ejoysdk_json"
local EM = require "ejoysdk_lua.ejoysdk_module"
local TAG = EM.MODULE.PUSH .. 'ejoysdk_push'

local push_event = require 'ejoysdk_lua.push.ejoysdk_push_event'

local push_vendor = nil
local push_handlers = nil

local CALLBACK_LOCAL_NOTIFICATION = 'CALLBACK_LOCAL_NOTIFICATION'
local IVK_LOCAL_NOTIFICATION_INIT = 'LOCAL_NOTIFICATION_INIT'
local IVK_ADD_LOCAL_NOTIFICATION = 'ADD_LOCAL_NOTIFICATION'
local IVK_REMOVE_LOCAL_NOTIFICATION = 'REMOVE_LOCAL_NOTIFICATION'
local IVK_STOP_FOREGROUND_SERVICE = 'STOP_FOREGROUND_SERVICE'

local EVT_ON_LOCAL_NOTIFICATION = "EVT_ON_LOCAL_NOTIFICATION"
local EVT_ON_LOCAL_NOTIFICATION_OPEN = "EVT_ON_LOCAL_NOTIFICATION_OPEN"
local EVT_ON_LOCAL_NOTIFICATION_RECEIVE_INAPP = "EVT_ON_LOCAL_NOTIFICATION_RECEIVE_INAPP"

local IVK_ADD_LOCAL_PROGRESS_NOTIFICATION = 'ADD_LOCAL_PROGRESS_NOTIFICATION'
local IVK_UPDATE_LOCAL_PROGRESS_NOTIFICATION = 'UPDATE_LOCAL_PROGRESS_NOTIFICATION'
local IVK_SETUP_PASSIVE_MODE_PROGRESS_NOTI_PRESENTER_INFO = 'SETUP_PASSIVE_MODE_PROGRESS_NOTI_PRESENTER_INFO'

local M = {}

M.max_local_push_notifyids = 10
local UPDATE_NOTIFICATION_INTERVAL_MILLS = 1000
local UPDATE_NOTIFICATION_INTERVAL_GAMETIME_MILLS = 3000 -- 游戏中为3秒更新一次
local is_foreground_notification_added = false
local last_foreground_notification_update_time = 0

-- notify id 分段
M.NOTIFY_ID_SDK_INNER = {
    NOTIFY_ID_FOREGROUND_SERVICE = 1000
}

local function get_notify_ids_size(notify_ids)
    local size = 0
    for _notify_id, _body in pairs(notify_ids) do
        size = size + 1
    end
    return size
end

local NOTIFY_IDS_MGR = {}
NOTIFY_IDS_MGR.storage= E.LazyKeyStore:New('LOCAL_PUSH_NOTIFYIDS', false, true, false)
NOTIFY_IDS_MGR.add = function(notify_id, calendar)
    if not notify_id or not calendar or M.max_local_push_notifyids == 0 then
        return
    end
    local expired = os.time() + calendar.second + calendar.minute * 60 + calendar.hour * 60 * 60 + calendar.day * 60 * 60 * 24
    E.LOG.debug(TAG, 'expired time: ' .. tostring(expired))
    local notify_ids = NOTIFY_IDS_MGR.storage:get()
    if notify_ids then
        local size = get_notify_ids_size(notify_ids)
        if size >= M.max_local_push_notifyids then
            local oldest_notify_id = nil
            local oldest_time = 20000000000
            for temp_notify_id, body in pairs(notify_ids) do
                if body.expired < oldest_time then
                    oldest_time = body.expired
                    oldest_notify_id = temp_notify_id
                end
            end
            notify_ids[oldest_notify_id] = nil -- delete oldest notify id
        end
    else
        notify_ids = {}
    end
    notify_ids[tostring(notify_id)] = {expired = expired}
    NOTIFY_IDS_MGR.storage:set(notify_ids)
end

NOTIFY_IDS_MGR.remove = function(notify_id)
    local notify_ids = NOTIFY_IDS_MGR.storage:get()
    if notify_ids and notify_ids[notify_id] then
        notify_ids[tostring(notify_id)] = nil
        NOTIFY_IDS_MGR.storage:set(notify_ids)
    end
end

NOTIFY_IDS_MGR.remove_all = function()
    local notify_ids = NOTIFY_IDS_MGR.storage:get()
    if notify_ids then
        for notify_id, _body in pairs(notify_ids) do
            E.LOG.debug(TAG, 'remove notify id: ' .. tostring(notify_id))
            M.remove_local_notification(notify_id)
        end
    end
    NOTIFY_IDS_MGR.storage:set({})
end

NOTIFY_IDS_MGR.self_update = function()
    local notify_ids = NOTIFY_IDS_MGR.storage:get()
    if notify_ids then
        for notify_id, body in pairs(notify_ids) do
            local expired = body.expired
            if expired < os.time() then
                E.LOG.debug(TAG, 'expired notify id: ' .. tostring(notify_id))
                notify_ids[notify_id] = nil
            end
        end
        NOTIFY_IDS_MGR.storage:set(notify_ids)
    end
end

NOTIFY_IDS_MGR.print_all = function()
    local notify_ids = NOTIFY_IDS_MGR.storage:get()
    if notify_ids and get_notify_ids_size(notify_ids) >0 then
        for notify_id, body in pairs(notify_ids) do
            E.LOG.debug(TAG, 'notify id: ' .. tostring(notify_id))
            E.LOG.debug(TAG, body)
        end
    else
        E.LOG.debug(TAG, "not has notify id")
    end
end

local function callback(push_handler_name, ...)
    E.LOG.debug(TAG, 'push callback name: ' .. tostring(push_handler_name))
    if push_handlers then
        if NOTIFY_IDS_MGR[push_handler_name] then
            NOTIFY_IDS_MGR[push_handler_name](...)
        end
        local push_handler = push_handlers[push_handler_name]
        if push_handler then
            push_handler(...)
        end
    end
end

function M.set_push_vendor(vendor)
    push_vendor = vendor
    push_vendor.set_handlers(push_handlers)
end

M.inited = false

function M.init(handlers)
    if M.inited then
        E.LOG.debug(TAG, 'already init and return')
        return
    end

    push_handlers = handlers
    if push_vendor then
        push_vendor.set_handlers(push_handlers)
    end
    ET.publish(ET.push.INITED, true)
    M.inited = true

    _ejoysdk.register_cb(CALLBACK_LOCAL_NOTIFICATION, function(_cbid, js_str)
        E.LOG.debug(TAG, 'js_str:' .. tostring(js_str))
        local result = JSON.decode(js_str)
        local event = result.event
        local value = result.value
        E.LOG.debug(TAG,'lua push callback local notification: ' .. tostring(event))
        local callback_event = nil
        if event == EVT_ON_LOCAL_NOTIFICATION then
            callback_event = push_event.ON_LOCAL_NOTIFICATION
        elseif event == EVT_ON_LOCAL_NOTIFICATION_RECEIVE_INAPP then
            callback_event = push_event.ON_LOCAL_NOTIFICATION_IN_APP
        elseif event == EVT_ON_LOCAL_NOTIFICATION_OPEN then
            callback_event = push_event.ON_LOCAL_NOTIFICATION_OPEN
        end
        if callback_event then
            callback(callback_event, value.title, value.content, value.ext or {})
        end
    end)
    if E.Sysinfo.os() == 'android' then
        E.invoke(IVK_LOCAL_NOTIFICATION_INIT, {})
    elseif E.Sysinfo.os() == 'ios' then
        _ejoysdk[IVK_LOCAL_NOTIFICATION_INIT]()
    end

    NOTIFY_IDS_MGR.self_update()
end

function M.set_push_handlers(handlers)
    push_handlers = handlers
    if push_vendor then
        push_vendor.set_handlers(push_handlers)
    end
end

function M.add_local_notification(title, content, calendar, ext, config)
    assert(calendar and type(calendar) == 'table', 'calendar is not valid')
    calendar.mode = 'delay'
    local params = {title = title, content = content, calendar = calendar, ext = ext or {}, config = config or {}}
    local notify_id = nil
    if E.Sysinfo.os() == 'android' then
        notify_id = tonumber(E.sync_call(IVK_ADD_LOCAL_NOTIFICATION, params).notify_id)
    elseif E.Sysinfo.os() == 'ios' then
        local returnParams = E.sync_call(IVK_ADD_LOCAL_NOTIFICATION, JSON.encode(params))
        local returnDecode = JSON.decode(returnParams)
        notify_id = tonumber(returnDecode.notify_id)
    end
    NOTIFY_IDS_MGR.add(notify_id, calendar)
    return notify_id
end

function M.async_add_local_notification(title, content, calendar, ext, config, cb)
    if cb then
        cb(M.add_local_notification(title, content, calendar, ext, config))
    end
end

function M.remove_local_notification(notify_id)
    if E.Sysinfo.os() == 'android' then
        E.invoke(IVK_REMOVE_LOCAL_NOTIFICATION, {notify_id=tostring(notify_id)})
    elseif E.Sysinfo.os() == 'ios' then
        E.sync_call(IVK_REMOVE_LOCAL_NOTIFICATION, JSON.encode({notify_id=tostring(notify_id)}))
    end
    NOTIFY_IDS_MGR.remove(notify_id)
end

function M.print_all_local_notification()
    NOTIFY_IDS_MGR.print_all()
end

function M.remove_all_local_notification()
    NOTIFY_IDS_MGR.remove_all()
end

-- Android 内置的一些icon
function M.get_noti_icon_with_task(task_status)
    local task_status_icon = 'epn_finish_download'
    if task_status == 0 then
        task_status_icon = 'epn_start_download'
    elseif task_status == 1 then
        task_status_icon = 'epn_stop_download'
    end
    return task_status_icon
end

-- 只有Android支持的接口
-- 通知栏进度条
function M.add_local_progress_notification(task_info, ext, config)
    if E.Sysinfo.os() == 'android' then
        local params = {
            title = task_info.title,
            short_title = task_info.short_title or '',
            task_id = task_info.task_id,
            left_text = task_info.left_text,
            right_text = task_info.right_text,
            task_status = task_info.task_status,
            task_status_icon = task_info.task_status_icon,
            task_action = task_info.task_action,
            progress = task_info.progress or 0,
            progress_visibility = task_info.progress_visibility,
            ext = ext or {},
            config = config or {}
        }
        local notify_id
        local result = E.sync_call(IVK_ADD_LOCAL_PROGRESS_NOTIFICATION, params)
        -- E.log(result)
        notify_id = result and tonumber(result.notify_id)
        -- NOTIFY_IDS_MGR.add(notify_id, calendar)
        return notify_id
    end
    return nil
end

function M.update_local_progress_notification(task_info, ext, config)
    if E.Sysinfo.os() == 'android' then
        
        local params = {
            title = task_info.title,
            task_id = task_info.task_id,
            left_text = task_info.left_text,
            right_text = task_info.right_text,
            progress = task_info.progress or 0,
            progress_visibility = task_info.progress_visibility,
            task_status = task_info.task_status,
            task_status_icon = task_info.task_status_icon,
            task_action = task_info.task_action,
            ext = ext or {},
            config = config or {}
        }
        E.sync_call(IVK_UPDATE_LOCAL_PROGRESS_NOTIFICATION, params)
        return true
    end
    return false
end

function M.update_local_progress_notification_custom(_params)
    if E.Sysinfo.os() == 'android' then
        local params = _params or {}
        params.ext = params.ext or {}
        params.config = params.config or {}
        E.sync_call(IVK_UPDATE_LOCAL_PROGRESS_NOTIFICATION, params)
    end
end

function M.update_foreground_service_notification(task_info, ext, force_notify)
    local config = {
        notify_id = M.NOTIFY_ID_SDK_INNER.NOTIFY_ID_FOREGROUND_SERVICE
    }

    if not is_foreground_notification_added then
        M.add_local_progress_notification(task_info, ext, config)
        is_foreground_notification_added = true
    else
        local current_time = E.system_clock()
        local eg = require "ejoysdk_lua.ejoysdk_gangplank"
        local is_after_sdk_init = eg.is_inited()
        local notification_interval_mills = is_after_sdk_init and UPDATE_NOTIFICATION_INTERVAL_GAMETIME_MILLS or UPDATE_NOTIFICATION_INTERVAL_MILLS
        if force_notify or current_time - last_foreground_notification_update_time > notification_interval_mills then
            --E.LOG.debug(TAG, "do_native_present_notification >>>" .. tostring(task_info.title))
            last_foreground_notification_update_time = current_time
            M.update_local_progress_notification(task_info, ext, config)
        end
    end
end

function M.stop_notification_service_foreground()
    if E.Sysinfo.os() == 'android' then
        E.LOG.debug(TAG, "stop_foreground for android begin")
        E.invoke(IVK_STOP_FOREGROUND_SERVICE, {})
    else
        E.LOG.warn(TAG, "stop_foreground skip ios")
    end
end

function M.setup_passive_mode_progress_presenter_info(progress_presenter_info)
    local os = E.Sysinfo.os()
    if os == 'android' then
        E.LOG.debug(TAG, "setup_passive_mode_progress_presenter_info begin")
        E.sync_call(IVK_SETUP_PASSIVE_MODE_PROGRESS_NOTI_PRESENTER_INFO, progress_presenter_info)
    elseif os == 'ios' and E.is_support_function('setup_notification_present_info') then
        E.sync_call('setup_notification_present_info', JSON.encode(progress_presenter_info))
    else
        E.LOG.debug(TAG, "setup_passive_mode_progress_presenter_info skip for ios and windows")
    end
end

return M