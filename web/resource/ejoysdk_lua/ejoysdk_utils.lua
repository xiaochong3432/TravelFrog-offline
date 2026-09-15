local byte = string.byte
local char = string.char
local compat = require 'ejoysdk_lua.compat.ejoysdk_compat'
local bitutil, xpcall = compat.bitutil, compat.xpcall


local EM = require "ejoysdk_lua.ejoysdk_module"
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'

local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'utils'

local M = {}

M.INNER_LOG_LEVEL = {
    INFO = 0,
    DEBUG = 1,
    WARN = 2,
    ERROR = 3
}

-- 一个简单的XOR流加解密器
local XORCipher = {}
XORCipher.__index = XORCipher

function XORCipher.new(key)
    return setmetatable({key=key, now=0}, XORCipher)
end

function XORCipher:encrypt(data)
    local key = self.key
    local key_len = #key
    local now = self.now

    local ret = {}
    for i=1, #data do
        now = now + 1
        ret[i] = char(bitutil.bxor(byte(data, i) ,  byte(key, now)))
        now = now % key_len
    end
    self.now = now
    return table.concat(ret)
end

XORCipher.decrypt = XORCipher.encrypt

M.XORCipher = XORCipher

-- 参考官网推荐做法：http://lua-users.org/wiki/CopyTable
-- 目前拷贝不支持超级大的table(可能引起栈溢出问题), 暂不支持metatable
local function deepcopy(orig, seen)
    local orig_type = type(orig)
    seen = seen or {}
    local copy
    if orig_type == 'table' then
        -- 防止无限递归调用，如果存在则直接返回copy的结果
        if seen[orig] then
            -- _ejoysdk.log('deepcopy repeat orig:' .. tostring(orig))
            copy = seen[orig]
        else
            copy = {}
            -- 记录copy过的table
            seen[orig] = copy

            for orig_key, orig_value in next, orig, nil do
                copy[deepcopy(orig_key, seen)] = deepcopy(orig_value, seen)
            end
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

M.deepcopy = deepcopy

-- 深拷贝标记
local deepcopy_once_record_mt = {__mode = "kv"}
local deepcopy_once_record = {}
setmetatable(deepcopy_once_record, deepcopy_once_record_mt)
local function deepcopy_only_once(orig)
    local orig_type = type(orig)
    local copy

    if orig_type == 'table' then
        local copyed = deepcopy_once_record[orig]
        if type(copyed) == 'table' then
            copy = copyed
        else
            copy = {}
            deepcopy_once_record[orig] = copy
            for orig_key, orig_value in next, orig, nil do
                copy[deepcopy_only_once(orig_key)] = deepcopy_only_once(orig_value)
            end
        end
    else
        copy = orig
    end

    return copy
end

M.deepcopy_only_once = deepcopy_only_once

local function reset_deepcopy_only_once_record()
    deepcopy_once_record = {}
end

M.reset_deepcopy_only_once_record = reset_deepcopy_only_once_record

-- 计算table长度
local function tablelength(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end
M.tablelength = tablelength

function M.safe_call_cb(cb, ...)
    if cb then
        cb(...)
    end
end

function M.safe_get_array_item(tbl, idx)
    if not tbl or next(tbl) == nil then
        return nil
    end

    if idx < 1 or idx > #tbl then
        return nil
    end

    return tbl[idx]
end

-- fsm
local unpack = unpack or table.unpack

-- 各个状态的 event 不能同名，否则无法处理 undo_event 应该分发给哪个状态的问题
local machine = {}
machine.__index = machine

local ASYNC = "async" -- onevent 返回 ASYNC ，需要自己调用 transition 迁移状态
local SYNC = 'sync' -- onevent 返回 SYNC，需要返回迁移到的状态，和返回参数

local function call_handler(handler, ...)
    if handler then
        return handler(...)
    end
end

local machine_log_enable = true
function M.set_global_log_enable(is_enable)
    machine_log_enable = is_enable
end

function machine:log(log_msg)
    if not machine_log_enable then
        return
    end

    _ejoysdk.log(log_msg)
end

function machine:transition(from, to, ...)
    if not self.states[from] then
        return
    end

    if from == self.current and from ~= to then -- 只有在当前状态才可以迁移
        call_handler(self['onleave' .. from], self, to, ...)
        self.current = to
        call_handler(self['onenter' .. to], self, from, ...)
        call_handler(self['onstatechange'], self, from, to, ...)
        local undo_events = self.undo_events[self.current]
        if not undo_events then return end
        self.undo_events[self.current] = {}

        for _, undo_event in ipairs(undo_events) do
            _ejoysdk.log('do undo event: ' .. (undo_event.name or ''))
            self[undo_event.name](self, unpack(undo_event.params))
        end
    else
        --_ejoysdk.log("skip transtion, from:" .. tostring(from) .. ", current:" .. tostring(self.current) .. ", to:" .. tostring(to))
    end
end

-- 事件处理结束
function machine:on_event_finish(event)
    if not event or event == self.current_event then
        self:log("on_event_finish：" .. tostring(event))
        self.current_event = nil
    end

    -- exec next event
    if self.msg_queue and next(self.msg_queue) ~= nil then
        local event_obj
        local can_consume_event
        repeat
            event_obj = table.remove(self.msg_queue, 1)
            if event_obj then
                can_consume_event = self:can(event_obj.name)
                if can_consume_event then
                    self:log("on_event_finish process event:" .. tostring(event_obj.name))
                    self[event_obj.name](self, unpack(event_obj.params))
                else
                    _ejoysdk.log("on_event_finish cannot process event, remove it:" .. tostring(event_obj and event_obj.name))
                end
            else
                -- 没有可处理的事件，消费完成
                can_consume_event = true
            end

        until can_consume_event
    end
end

function machine:notify_async_finish(event)
    self:on_event_finish(event)
end

function machine:on_event_begin(event_name)
    self:log("on_event_begin: " .. tostring(event_name))
    self.current_event = event_name
end

local function create_event_handler(event_name)
    local can, to, from

    local function handle_event(self, ...)
        can = self:can(event_name)
        if not can then
            return
        end
        from = self.current
        -- 标记event begin
        self:on_event_begin(event_name)
        local result = {call_handler(self['on'.. event_name], self, from,  ...)}
        if not result[1] then
            return
        end
        if result[1] == ASYNC then
            -- ASYNC 的 event 考虑存放起来，可以做一个 cancel
            -- wait for event finish callback
            return
        end
        if result[1] == SYNC then
            to = result[2]
            if to then
                table.remove(result, 1)
                table.remove(result, 1)
                self:transition(from, to, unpack(result))
            end

            self:on_event_finish(event_name)
        end
    end

    return handle_event
end

function machine.create(options)
    assert(options.events)

    local fsm = {}
    setmetatable(fsm, machine)

    fsm.initial = options.initial
    fsm.current = options.initial or 'none'
    fsm.undo_events ={}
    fsm.states = {}
    fsm.events = {}

    for _, event in ipairs(options.events or {}) do
        local name = event.name
        local from = event.from
        fsm[name] = fsm[name] or create_event_handler(name)
        fsm.events[name] = from
        fsm.states[from] = fsm.states[from] or {}
        fsm.states[from][name]  = true
    end

    for name, callback in pairs(options.callbacks or {}) do
        fsm[name] = callback
    end

    return fsm
end

function machine:is(state)
    return self.current == state
end

function machine:can(event_name)
    local state = self.states[self.current]
    if not state then
        _ejoysdk.log("can event check false, current:" .. tostring(self.current) .. ", event:" .. tostring(event_name))
        return false
    else
        return state[event_name] ~= nil
    end
end

function machine:cannot(e)
    return not self:can(e)
end

function machine:add_event(event, ...)
    if self:can(event) then
        self[event](self, ...)
    else
        _ejoysdk.log(TAG.. 'not support event: ' .. tostring(event) .. ' ,in current state: ' .. tostring(self.current))
    end
    --if self:can(event) then
    --    self[event](self, ...)
    --else
    --    _ejoysdk.log('undo event: ' .. event)
    --    local state = self.events[event]
    --    self.undo_events[state] = self.undo_events[state] or {}
    --    local undo_event = {
    --        name = event,
    --        params = {...}
    --    }
    --    table.insert(self.undo_events[state], undo_event)
    --end
end

function machine:enqueue_event(event, at_front, ...)
    self:log("enqueue_event, current_event:" .. tostring(self.current_event) .. ", enqueue event:" .. tostring(event))
    self.msg_queue = self.msg_queue or {}
    local event_obj = {
        name = event,
        params = {...}
    }

    if at_front then
        self:log("enqueue_event at queue front:" .. tostring(event))
        table.insert(self.msg_queue, 1, event_obj)
    else
        self:log("enqueue_event at queue tail:" .. tostring(event))
        table.insert(self.msg_queue, event_obj)
    end

    -- 检查无当前运行任务，触发一次
    if not self.current_event then
        self:log("enqueue_event no current event, try pick event from queue head")
        self:on_event_finish()
    else
        self:log("enqueue_event has current event, wait for current event finish:" .. tostring(self.current_event))
    end
end

function machine:reset()
    self.current = self.initial
    self.current_event = nil
    self.undo_events = {}
end

function M.appstore_score()
    if _ejoysdk.os() == 'ios' then
        --_ejoysdk.appstore_score();
        local EJOY_IOS = require("ejoysdk_lua.ejoysdk_ios")
        EJOY_IOS.async_call('appstore_score')
    else
        _ejoysdk.log(TAG .. "appstore_score function only for ios operating system")
    end
end

function M.appstore_write_comment(appId)
    if appId == nil or #appId == 0 then
        _ejoysdk.log(TAG .. "appId can not be null or empty")
        return
    end

    if _ejoysdk.os() == 'ios' then
        local EJOY_IOS = require("ejoysdk_lua.ejoysdk_ios")
        EJOY_IOS.async_call('appstore_write_comment', nil, appId)
    else
        _ejoysdk.log(TAG .. "appstore_write_comment function only for ios operating system")
    end
end

function M.set_file_to_pasteboard(filePath, pasteType)
    if filePath == nil or #filePath == 0 then
        _ejoysdk.log(TAG .. "filePath can not be null or empty")
        return
    end

    if _ejoysdk.os() == 'ios' then
        local EJOY_IOS = require("ejoysdk_lua.ejoysdk_ios")
        local pasteName = EJOY_IOS.sync_call('unisdk_set_file_to_pasteboard', filePath, pasteType)
        return pasteName
    else
        _ejoysdk.log(TAG .. "unisdk_set_file_to_pasteboard function only for ios operating system")
    end
end

machine.ASYNC = ASYNC
machine.SYNC = SYNC

M.fsm = machine

local lang_util = {}

-- 避免大小写问题，统一使用小写，比较时先转小写
lang_util.lang_area_to_script = {
    zh = {
        _ = 'hans',
        cn = 'hans',
        hk = 'hant',
        tw = 'hant'
    }
}

lang_util.get_script = function()
    local E = require "ejoysdk_lua.ejoysdk"
    local area = E.Sysinfo.country() -- 这里都是获取系统的，先不动
    local lang = E.Sysinfo.language()
    if not area or not lang then
        return ''
    end
    local area_to_script = lang_util.lang_area_to_script[lang]
    if area_to_script then
        local script = area_to_script[area:lower()] or area_to_script['_'] or ''
        return script
    else
        return ''
    end
end

M.lang_util = lang_util

local log_util = {}

-- key_to_val_symbol : table 里面 key value 之间的衔接符号
-- log_table_name : 是否打印 table 的名称
log_util.table_tostring = function(table, key_to_val_symbol, log_table_name)
    local _indent = '   '

    key_to_val_symbol = key_to_val_symbol or ' => '

    if log_table_name == nil then
        log_table_name = true
    end

    local function output(t, indent)
        local result_value
        if type(t) == 'table' then
            result_value = (log_table_name and tostring(t) or '') .. '{\n'
            for key, val in pairs(t) do
                local next_indent = indent .. _indent
                result_value = result_value .. indent .. '[' ..output(key, next_indent) .. ']' .. key_to_val_symbol .. output(val, next_indent) .. '\n'
            end
            result_value = result_value .. indent:sub(#_indent + 1) .. '}'
        elseif type(t) == 'string' then
            result_value = '"' .. t .. '"'
        else
            result_value = tostring(t)
        end
        return result_value
    end

    return output(table, _indent)
end


log_util.table_tojson = function(table)
    local _indent = '   '

    local key_to_val_symbol = ':'
    local log_table_name = false

    local function output(t, indent)
        local result_value
        if type(t) == 'table' then
            local is_array = M.is_array_table(t)

            local left_bracket_symbol = '{'
            local right_bracket_symbol = '}'

            if is_array then
                left_bracket_symbol = '['
                right_bracket_symbol = ']'
            end

            result_value = (log_table_name and tostring(t) or '') .. left_bracket_symbol .. '\n'
            for key, val in pairs(t) do
                local next_indent = indent .. _indent
                if not is_array then
                    result_value = result_value .. indent .. output(key, next_indent) .. key_to_val_symbol .. output(val, next_indent) .. '\n'
                else
                    result_value = result_value .. indent .. output(val, next_indent) .. '\n'
                end
            end
            result_value = result_value .. indent:sub(#_indent + 1) .. right_bracket_symbol
        elseif type(t) == 'string' then
            result_value = '\"' .. t .. '\"'
        else
            result_value = '\"' .. tostring(t) .. '\"'
        end
        return result_value
    end

    return output(table, _indent)
end

M.log_util = log_util

function M.get_user_ip_info(cb)
    (require 'ejoysdk_lua.user_center.usercenter_api').get_user_ip_info(cb)
end


local function is_array_table(t)
    if type(t) ~= "table" then
        return false
    end

    local n = #t
    for i, _ in pairs(t) do
        if type(i) ~= "number" then
            return false
        end

        if i > n or i < 1 or (math.floor(i) < i) then
            return false
        end
    end

    return true
end

M.is_array_table = is_array_table

function M.version_compare(v1, v2)
    v1 = v1 or ''
    v2 = v2 or ''

    local v1_length = #v1
    local v2_length = #v2

    if ('' == v1 or '' == v2) then
        if (v1_length < v2_length) then
            return -1
        elseif (v1_length > v2_length) then
            return 1
        else
            return 0
        end
    end

    local asc_dot = string.byte('.')
    local asc_nine = string.byte('9')
    local asc_zero = string.byte('0')

    local calc = function(params)
        local c1 = asc_zero
        local x = 0
        while (params.index <= params.length and c1 ~= asc_dot) do
            c1 = string.byte(params.str, params.index)
            if c1 >= asc_zero and c1 <= asc_nine then
                x = x * 10 + c1 - asc_zero
            end
            params.index = params.index + 1
        end
        return x
    end

    local v1_params = { str = v1, index = 1, length = v1_length }
    local v2_params = { str = v2, index = 1, length = v2_length }
    while (v1_params.index <= v1_length or v2_params.index <= v2_length) do
        local x = calc(v1_params)
        local y = calc(v2_params)

        if (x < y) then
            return -1
        elseif (x > y) then
            return 1
        end
    end
    return 0
end


--- 遍历raw_string, 遇到非法utf-8字符, 替换成?
function M.verify_utf_char(raw_string)
    if type(raw_string) ~= 'string' then
        return raw_string
    end
    local len = string.len(raw_string)
    if nil == raw_string or len == 0 then
        return raw_string
    end
    local new_string = {}
    local index_of_raw_string = 1
    while index_of_raw_string <= len do
        local count_1_of_byte = M.get_continuous_1_count_of_byte(string.byte(raw_string, index_of_raw_string))
        if count_1_of_byte < 0 then
            return raw_string
        end
        if count_1_of_byte <= 3 then
            local sub_char = string.sub(raw_string, index_of_raw_string, index_of_raw_string + count_1_of_byte - 1)
            local is_valid_utf8_char = M.is_valid_utf8_char(sub_char, count_1_of_byte)
            if is_valid_utf8_char then
                table.insert(new_string, sub_char)
            else
                table.insert(new_string, '?')
            end
        else
            table.insert(new_string, '?')
        end
        index_of_raw_string = index_of_raw_string + count_1_of_byte
    end
    return table.concat(new_string)
end


----
--- 按照utf-8的编码规则, 第一个字节的最高位连续1的个数，表示这个字符占用的字节数
--- 参考：https://blog.csdn.net/SKY453589103/article/details/76337557?locationNum=9&fps=1
--- num：字符的第一个字节
function  M.get_continuous_1_count_of_byte(num)
    if nil == num then
        return -1
    end

    local count = 0
    while (bitutil.band(num, 0x80) ~= 0) do
        count = count + 1
        num = bitutil.lshift(num, 1)
    end
    -- 一个字节的字符，最高位是0
    if count == 0 then
        count = 1
    end
    return count
end


---- 判断char是否是合法的utf-8编码
--- char 需要判断的字符
--- len 字节数
--- 0000 0000-0000 007F   0xxxxxxx
--- 0000 0080-0000 07FF   110xxxxx 10xxxxxx
--- 0000 0800-0000 FFFF   1110xxxx 10xxxxxx 10xxxxxx
--- 0001 0000-001F FFFF   11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
--- 0020 0000-03FF FFFF   111110xx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
--- 0400 0000-7FFF FFFF   1111110x 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
function M.is_valid_utf8_char(sub_char, len)
    if string.len(sub_char) ~= len then
        return false
    end
    local first_byte = string.byte(sub_char, 1)
    if len == 1 then
        if bitutil.band(first_byte, 0x80) ~= 0 then
            return false
        end
    end
    if len >= 2 then
        if len == 2 and bitutil.band(first_byte, 0xE0) ~= 0xC0 then
            return false
        end
        if len == 3 and bitutil.band(first_byte, 0xF0) ~= 0xE0 then
            return false
        end
        if len == 4 and bitutil.band(first_byte, 0xF8) ~= 0xF0 then
            return false
        end
        if len == 5 and bitutil.band(first_byte, 0xFC) ~= 0xF8 then
            return false
        end
        if len == 6 and bitutil.band(first_byte, 0xFE) ~= 0xFC then
            return false
        end
        for i = 2, len do
            local follow_byte = string.byte(sub_char, i)
            if bitutil.band(follow_byte, 0xC0) ~= 0x80 then
                return false
            end
        end
    end
    return true
end

function M.do_export_wrapping(target)
    if type(target) ~= "table" then
        return
    end

    local E = require "ejoysdk_lua.ejoysdk"

    for k,v in pairs(target) do
        -- _开头的方法 表达的含义是 私有方法
        if type(v) == 'function' and not E.Utils.start_with(k, '_') then
            local func_wraper = function(...)
                return M.ejoysdk_call(v, ...)
            end
            target[k] = func_wraper
        end
    end
end

local _ejoysdk_call

function M.ejoysdk_call(func, ...)
    local E = require "ejoysdk_lua.ejoysdk"

    local function print_stack()
        -- 不打印堆栈了，太耗性能，debug阶段需要打印，可以在这里自行添加
    end
    if _ejoysdk_call == nil then
        _ejoysdk_call = true
        local ms_start = E.system_ms()
        local ok, msg = xpcall(func, print_stack, ...)
        local ms_end = E.system_ms()
        local diff = ms_end - ms_start

        if diff > 5 then
            E.LOG.warn(TAG, 'exe method spend too long, spend time=' .. tostring(diff) .. ' ms')
        end

        _ejoysdk_call = nil
        if ok then
            return msg
        else
            return {code= CONSTANTS.EJOYSDK_ERROR_CODES.LUA_ERROR, message="sdk_inner_error"}
        end
    else
        return func(...)
    end

end

-- 合并两个table，将 new_table 的数据覆盖到 old_table，返回 old_table
function M.merge_table(old_table, new_table)

    assert(type(old_table) == 'table', 'param old_table must be table type')
    assert(type(new_table) == 'table', 'param new_table must be table type')

    for k, v in pairs(new_table) do

        if type(v) ~= type(old_table[k]) then
            old_table[k] = v
        else
            if type(v) == 'table' then
                old_table[k] = M.merge_table(old_table[k],  v)
            else
                old_table[k] = v
            end
        end
    end

    return old_table
end

-- local table3 = {a={[1]=1, a1={}}, b={}, c={[1]=1}}
function M.replace_empty_table(orig_table, new_value, seen)
    seen = seen or {}

    if not orig_table or type(orig_table) ~= 'table' then
        return
    end

    -- 防止无限递归调用
    if seen[orig_table] then
        return
    end

    seen[orig_table] = true
    for k, v in pairs(orig_table) do
        if type(v) == 'table' then
            if next(v) ~= nil then
                M.replace_empty_table(v, new_value, seen)
            else
                orig_table[k] = new_value
            end
        end
    end
end

function M.is_text_empty(text)
    return text == nil or text == ""
end

function M.table_maxn(t)
    local mn = 0
    for k, _ in pairs(t) do
        if mn < k then
            mn = k
        end
    end
    return mn
end

-- 比较两个table是否相等
function M.compareTable(t1, t2)
    if type(t1) ~= 'table' or type(t2) ~= 'table' then
        return false
    end
    local mt1 = getmetatable(t1)
    local mt2 = getmetatable(t2)
    if mt1 and mt1.__eq then
        return mt1.__eq(t1, t2)
    end
    if mt2 and mt2.__eq then
        return mt2.__eq(t1, t2)
    end
    if #t1 ~= #t2 then
        return false
    end
    for k, v in pairs(t1) do
        if type(v) == 'table' then
            if not M.compareTable(v, t2[k]) then
                return false
            end
        else
            if v ~= t2[k] then
                return false
            end
        end
    end
    for k, v in pairs(t2) do
        if type(v) == 'table' then
            if not M.compareTable(t1[k], v) then
                return false
            end
        else
            if t1[k] ~= v then
                return false
            end
        end
    end
    return true
end

return M
