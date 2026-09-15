local E = require 'ejoysdk_lua.ejoysdk'
local BASE_API = require 'ejoysdk_lua.libs.base_api'
local ET = require "ejoysdk_lua.ejoysdk_topic"
local UTILS = require 'ejoysdk_lua.ejoysdk_utils'
local game_adapter_api = BASE_API:New('game-adapter')

local TAG = "EJOYSDK_MAIL"

local M = {}

--邮件缓存数据
local mail_cache = {}

--sdk固定每10分钟请求一次
local MAIL_CLIENT_REFRESH_TIME = 10 * 60

--服务端刷新邮件列表的时间, 每次使用接口拉取数据，及收到推送时，更新该字段。缓存的数据早于该时间的则为无效缓存
local server_refresh_mail_time = 0

--服务端返回的邮件配置
local server_mail_config = {}

--邮件拉取配置
local mail_pull_config = {}

--邮件推送通知
local mail_push_handler

--是否初始化
local mail_inited = false

--定时刷新数据是否已经开启
local refresh_data_timer_enabled = false

--角色是否在线
local player_online = false

--是否中断分批请求
local interrupt_batch_request = false

local OP = {
    READ = '/read',
    DELETE = '/delete',
    FETCH_ATTACHMENT = '/fetch_attachment'
}

-- 合并数据，将table2的数组合并到table1
local function merge_array_data(table1, table2)
    if table2 == nil then
        return
    end
    if table1 == nil then
        table1 = {}
    end
    for _, value in ipairs(table2) do
        table.insert(table1, value)
    end
end

-- 是否是纯数组的table
local function is_array_table(t)
    if type(t) ~= 'table' then
        return false
    end
    local n = #t
    for key, _ in pairs(t) do
        if type(key) ~= "number" then
            return false
        end
        if key > n then
            return false
        end
    end
    return true
end

--合并table, 只支持合并数字和数组
local function merge_table_data(table1, table2)
    if table2 == nil then
        return
    end
    if table1 == nil then
        table1 = {}
    end
    for key, value in pairs(table2) do
        if table1[key] == nil then
            table1[key] = value
        else
            --合并数字
            if type(value) == 'number' then
                table1[key] = table1[key] + value
            elseif is_array_table(value) then
                merge_array_data(table1[key], value)
            else
                E.LOG.debug(TAG, "error merge table data")
            end
        end
    end
end

local function mail_api_path(api)
    api = '/client_api_v2/mail' .. api
    return api
end

--收到聊天通道过来的邮件推送信息
local function mail_update_push(msg)
    E.LOG.debug(TAG, 'try mail_update_push')
    --如果推送时间大于当前最新时间，存储更新服务端邮件列表时间，并发起推送，否则不需要处理
    local now_ms = tonumber(msg.now_ms)
    local server_refresh_mail_time_number = tonumber(server_refresh_mail_time)
    if now_ms and server_refresh_mail_time_number and now_ms > server_refresh_mail_time_number then
        if mail_push_handler then
            E.LOG.debug(TAG, "push msg to game")
            mail_push_handler(msg)
        else
            E.LOG.debug(TAG, 'not set push handler, should not handle push')
        end
    else
        E.LOG.debug(TAG, "current refresh mail time is bigger than msg's now_ms, shouldn't push to game")
    end
    --更新服务端邮件列表刷新时间，单位:毫秒，收到推送或本地拉取时都需要设置最新的值
    server_refresh_mail_time = msg.now_ms
end

--获取数据缓存
local function get_page_cache(page)
    --开启了更新推送的情况下
    local page_cache = mail_cache[page]
    if page_cache and (page_cache.now_ms == server_refresh_mail_time) then
        --和最近一次服务端更新时间一致，则为有效缓存，否则缓存无效
        return page_cache
    end
end

local function inner_get_mails(page, use_cache, cb)
    if use_cache then
        --设置当前页数
        local cache_mails = get_page_cache(page)
        --存在有效缓存，则直接返回
        if cache_mails then
            if cb then
                cb(true, UTILS.deepcopy(cache_mails))
            end
            return
        end
    end
    --无有效缓存，请求数据
    mail_pull_config.page = page
    local opt = { use_moment_token = true }
    E.LOG.debug(TAG, mail_pull_config)
    game_adapter_api:post(mail_api_path('/list'), {}, mail_pull_config, opt, function(succ, ...)
        if succ then
            local res_body = ...
            --服务端返回的邮件操作配置
            server_mail_config = res_body.config or {}
            --缓存数据
            mail_cache[page] = res_body
            --构造推送数据，发起推送
            local msg = {
                --这两个字段兼容旧版本
                now_ms = res_body.now_ms,
                need_concern = res_body.need_concern
            }
            --其余需要给推送的字段，服务端使用concern_info字段包装，sdk透传给项目
            if res_body.concern_info then
                --mails_add,mails_add_count拉取数据一定是没有的，真实的推送由，对齐
                msg.mails_add = {}
                msg.mails_add_count = 0
                for concern_info_key, concern_info_value in pairs(res_body.concern_info) do
                    msg[concern_info_key] = concern_info_value
                end
            end
            mail_update_push(msg)
            if cb then
                cb(true, UTILS.deepcopy(mail_cache[page]))
            end
        else
            if cb then
                cb(false, ...)
            end
        end
    end)
end

--登录后，开启定时器刷新数据，每10分钟轮询请求一次第一页数据
local function start_timer_refresh_data()
    E.LOG.debug(TAG, 'start timer to refresh data')
    local refresh_mail_data
    refresh_mail_data = function()
        --角色在线才需要请求，logout后不需要再请求
        if player_online then
            inner_get_mails(1, false,nil)
        else
            E.LOG.debug(TAG, 'player has logout, skip get mail')
        end
        E.Timer.once(MAIL_CLIENT_REFRESH_TIME, refresh_mail_data)
    end
    --开启定时
    E.Timer.once(MAIL_CLIENT_REFRESH_TIME, refresh_mail_data)
end

local logout_handler = function()
    M.clean_cache()
    --角色下线
    player_online = false
end

--初始化
function M.init()
    if mail_inited then
        E.LOG.debug(TAG, 'already init and return')
        return
    end

    --邮件拉取接口，默认配置，limit: 每页邮件数量50, sort_type: 未读未领>时间近， recv_push: 默认开启推送，push_interval：邮件更新频率，默认更新频率为30秒
    local lang = E.CONFIG.get_config('lang')
    mail_pull_config = {
        limit = 50,
        sort_type = 1,
        recv_push = true,
        lang = lang or 'zh-hans'
    }

    ET.subscribe(ET.gangplank.LOGOUT, function()
        E.LOG.debug(TAG, 'gangplank logout, clean cache')
        --注销账号时，清除缓存
        logout_handler()
    end)

    ET.subscribe(ET.gangplank.PLAYER_OFFLINE, function()
        E.LOG.debug(TAG, 'player offline, clean cache')
        --角色登出时，清除缓存
        logout_handler()
    end)

    --角色登录后，开启刷新数据
    ET.subscribe(ET.gangplank.PLAYER_ONLINE, function()
        M.clean_cache()
        --角色上线
        player_online = true
        --角色登录后，立刻获取一次第一页数据
        inner_get_mails(1, false,nil)
        --定时器只需要一个
        if not refresh_data_timer_enabled then
            refresh_data_timer_enabled = true
            start_timer_refresh_data()
        end
    end)

    --注册监听，监听聊天通道邮件推送
    ET.subscribe('chat_info_mail_update_push', mail_update_push)

    mail_inited = true
end

--[[
设置邮件拉取的配置
@param
    params : table
    支持参数limit限制每页返回的邮件数量, 默认50, -1为不限制（账号邮件最多不超过200封，角色邮件也是）
    支持参数sort_type排序方式，默认1，1为未读未领>时间近，2为时间近
    支持参数recv_push设置是否接收更新推送，默认每60秒推送一次更新
    支持参数lang字符串，用户语言，用于选取邮件对应的文本内容
    参考 { limit = 50, sort_type = 1, recv_push = true }
]]
function M.set_mail_pull_config(params)
    for config_key, config_value in pairs(params) do
        mail_pull_config[config_key] = config_value
    end
end

--[[
获取邮件列表
@param
    params : table
    支持参数page设置拉取的页数，默认1
]]
--拉取邮件，判断是否有有效缓存，如有，则返回，如无，获取邮件返回并缓存
function M.get_mails(page, cb)
    inner_get_mails(page, true, cb)
end

--[[
从服务端获取邮件列表
@param
    params : table
    支持参数page设置拉取的页数
]]
-- 从服务端拉取邮件
function M.get_mails_from_server(page, cb)
    inner_get_mails(page, false, cb)
end

-- 是否需要分批操作
local function is_need_batch(params)
    --return false
    if params and params.mail_ids and server_mail_config.batch_size and #(params.mail_ids) > server_mail_config.batch_size then
        return true
    end
    return false
end

--将邮件数组按batch_size拆分
local function split_mails_array(mail_ids, batch_size)
    local mails_id_array = {}
    if mail_ids and next(mail_ids) then
        --拆分数组返回
        local current_array_index = 0
        local current_array = {}
        table.insert(mails_id_array, current_array)
        for _, mail_id in ipairs(mail_ids) do
            -- 到一批的数量了
            if current_array_index == batch_size then
                current_array = {}
                current_array_index = 0
                --将新的数组插入
                table.insert(mails_id_array, current_array)
            end
            current_array_index = current_array_index + 1
            table.insert(current_array, mail_id)
        end
    end
    return mails_id_array
end

--分批处理邮件
local function batch_op_mails(params, op_fun, merge_result_op_fun, cb, batch_cb)
    --重置中断标志位为false，只有分批请求过程中触发的中断才需要处理
    interrupt_batch_request = false
    cb = cb or function() end
    local batch_size = server_mail_config.batch_size
    local mails_id_array = split_mails_array(params.mail_ids, batch_size)
    --数组非空
    if mails_id_array and next(mails_id_array) then
        local merge_result
        local error_code
        local error_msg
        local batch_inner_cb
        params.mail_ids = mails_id_array[1]
        batch_inner_cb = function(succ, ...)
            E.LOG.debug(TAG, "return op mails batch result")
            --返回当次回调
            if batch_cb then
                batch_cb(succ, ...)
            end
            --合并结果和错误码
            if succ then
                --合并结果
                if merge_result == nil then
                    merge_result = ...
                else
                    local batch_result = ...
                    merge_result_op_fun(merge_result, batch_result)
                end
            else
                error_code, error_msg = ...
                --这里需要打印
                E.LOG.debug(TAG, 'batch op mails fail, code is ' .. tostring(error_code) .. ', msg is ' .. tostring(error_msg))
            end
            --判断当前是否最后一项，不是且没有中断才继续请求
            table.remove(mails_id_array, 1)
            if next(mails_id_array) and interrupt_batch_request == false then
                params.mail_ids = mails_id_array[1]
                op_fun(params, batch_inner_cb)
            else
                --全部执行完了，需要回调总结果
                if merge_result then
                    cb(true, merge_result)
                else
                    cb(false, error_code, error_msg)
                end
            end
        end
        op_fun(params, batch_inner_cb)
    end
end

--处理邮件的请求，统一调用
local function handle_mails(api, params, cb, batch_cb)
    local opt = { use_moment_token = true }
    game_adapter_api:post(mail_api_path(api), {}, params, opt, function(succ, ...)
        if succ then
            local res_body = ...
            --设置已读后，会影响邮件排序，缓存失效
            M.clean_cache()
            if cb then
                cb(true, res_body)
            end
            if batch_cb then
                batch_cb(true, res_body)
            end
        else
            if cb then
                cb(false, ...)
            end
            if batch_cb then
                batch_cb(false, ...)
            end
        end
    end)
end

local function inner_set_mails_read(params, cb)
    handle_mails(OP.READ, params, cb)
end

local function inner_delete_mails(params, cb)
    handle_mails(OP.DELETE, params, cb)
end

local function inner_fetch_attachment(params, cb)
    handle_mails(OP.FETCH_ATTACHMENT, params, cb)
end

--[[
设置邮件已读
@param
    params : table
    支持参数mail_ids，设置已读的邮件id列表
    参考 { "6184f733848e9382d4de3562", "6184f733848e9382d4de3564" }
]]
function M.set_mails_read(params, cb, batch_cb)
    if is_need_batch(params) then
        batch_op_mails(params, inner_set_mails_read, function(merge_result, batch_result)
            merge_array_data(merge_result.succ_ids, batch_result.succ_ids)
        end, cb, batch_cb)
    else
        handle_mails(OP.READ, params, cb, batch_cb)
    end
end

--[[
提取附件
@param
    params: table
    支持参数mail_ids,要提取附件的邮件id列表
    支持参数delete, 领取完后是否删除邮件
]]
function M.fetch_attachment(params, cb, batch_cb)
    if is_need_batch(params) then
        batch_op_mails(params, inner_fetch_attachment, function(merge_result, batch_result)
            merge_array_data(merge_result.succ_list, batch_result.succ_list)
            merge_array_data(merge_result.fail_list, batch_result.fail_list)
        end, cb, batch_cb)
    else
        handle_mails(OP.FETCH_ATTACHMENT, params, cb, batch_cb)
    end
end

--[[
删除邮件
@param
    params : table
    支持参数mail_ids，设置要删除邮件id列表
    参考 { "6184f733848e9382d4de3562", "6184f733848e9382d4de3564" }
]]
function M.delete_mails(params, cb, batch_cb)
    if is_need_batch(params) then
        batch_op_mails(params, inner_delete_mails, function(merge_result, batch_result)
            merge_array_data(merge_result.succ_ids, batch_result.succ_ids)
        end, cb, batch_cb)
    else
        handle_mails(OP.DELETE, params, cb, batch_cb)
    end
end

local function inner_operate_all(params, cb)
    local opt = { use_moment_token = true }
    --新版本lua为true，旧版本lua无该字段，服务端用该字段判断客户端是否支持分批处理邮件，项目无感知
    params.batch_request = true
    game_adapter_api:post(mail_api_path('/operate_all'), {}, params, opt, function(succ, ...)
        if succ then
            local res_body = ...
            --如果数据发生了变化，则需要清掉缓存
            local changed = res_body.changed or false
            if changed then
                M.clean_cache()
            end
            cb(true, res_body)
        else
            cb(false, ...)
        end
    end)
end

--[[
一键操作
@param
    params: table
    支持参数operation,值可以是：
      fetch_attachment 一键提取附件
      fetch_and_delete 一键提取附件且删除
      delete_fetched 一键删除已领取的邮件
      read 一键读取未读取的邮件
]]
function M.operate_all(params, cb, batch_cb)
    --重置中断标志位为false，只有分批过程中触发的中断才需要处理
    interrupt_batch_request = false
    params = params or {}
    -- 首次循环时，避免外部一直持有同一个params(含改变的action)有影响
    params.action = nil
    
    cb = cb or function() end
    local merge_result
    local batch_inner_cb
    batch_inner_cb = function(succ, ...)
        --分批回调
        if batch_cb then
            batch_cb(succ, ...)
        end
        if succ then
            local res_body = ...
            if merge_result == nil then
                merge_result = res_body
            else
                -- 合并数据
                --changed，表示邮件数据变化，只要有一次是true，就应该是true
                merge_result.changed = res_body.changed or merge_result.changed
                --has_more, 是否还有邮件未操作，只要有一次是false，就应该是false，且不再继续获取
                merge_result.has_more = res_body.has_more and merge_result.has_more
                -- 存在结果数据，需要合并
                if res_body.result then
                    merge_table_data(merge_result.result, res_body.result)
                end
            end
            --还需要下一次请求
            if res_body.has_more and interrupt_batch_request == false then
                params = params or {}
                -- 进入下次循环时，action设置为continue
                params.action = "continue"
                E.LOG.debug(TAG, 'operate_all next page, action:continue')
                inner_operate_all(params, batch_inner_cb)
            else
                cb(true, merge_result)
            end
        else
            cb(false, ...)
        end
    end
    inner_operate_all(params, batch_inner_cb)
end

--清理掉所有缓存
function M.clean_cache()
    mail_cache = {}
end

--[[
邮件更新推送监听，可通过设置该监听，获取到邮件列表更新的通知，用于刷新红点操作
@param
    params: function
    eg: set_mail_push_handlers(function(msg)
        ...
    end)
end
]]
function M.set_mail_push_handlers(handler)
    mail_push_handler = handler
end

--[[
中断分批请求，
]]
function M.interrupt()
    interrupt_batch_request = true
end


return M