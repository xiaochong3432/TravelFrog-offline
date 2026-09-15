--[[
    聊天会话消息model
    一个实例管理一个会话消息列表
    处理消息的增删查改
    1. 内部同时有字典结构和数组结构。可以在 o(n) 时间复杂度内做合并操作。
    2. 按时间排序，可以高效地索引到 已读，未读 发生变化的消息。
    3. 允许用户将UI资源直接设置至消息结构。若是更新操作，会保留老消息结构的数据，即保留用户自己设置的值。
--]]
local Class = require "ejoysdk_lua.ejoysdk_class"
local E = require "ejoysdk_lua.ejoysdk"
local msg_util = require "ejoysdk_lua.chat.export.ejoysdk_chat_msg_util"
local E_UTILS = require 'ejoysdk_lua.ejoysdk_utils'
local compat = require 'ejoysdk_lua.compat.ejoysdk_compat'
local table_move = compat.table_move

local TAG = 'chat_msg_model'

local M = Class:Inherit('session_msg_model')

--- 初始化函数
--- @param session_id string 会话id
--- @return nil
function M:_init(session_id)
    self.mapped_msg = {}
    self.sorted_msg = {}
    self.session_id = session_id
end

--- 获得会话id
--- @return string session_id
---@example
--      local chat_session_msg_class = require "ejoysdk_lua.chat.export.ejoysdk_chat_session_msg"
--      local chat_session_msg_instance = chat_session_msg_class:New("group_world_1")
--      chat_session_msg_instance:get_session_id() -> "group_world_1" 
function M:get_session_id() return self.session_id end

--- 合并消息
--- @param new_msgs table sdk 回调的消息，要求按时间升序
--- @return table 返回变化(包括新增)的消息结构，按时间升序
---@example
--      msg1 = {msg_id="623dacfaecd7f5ebb0b6c491", content={type=rich_text,data={extend_data={},text="nihaoya1"}}, ...}
--      chat_session_msg_instance:merge_msgs({msg1}) -> {msg1}
function M:merge_msgs(new_msgs)
    -- 将新消息合并至老结构
    local changed_msgs = {}
    local insert_msgs = {}
    for _, v in ipairs(new_msgs) do
        local msg_id = v.msg_id
        local update_key = msg_id
        local msg = nil
        if msg_id ~= nil then
            msg = self.mapped_msg[msg_id]
            -- 先通过msg_id查
            -- 查不到，通过send_id查
            if msg == nil and v.send_id ~= nil then
                self.mapped_msg[msg_id] = self.mapped_msg[v.send_id]
                -- 清理旧的send_id 映射
                self.mapped_msg[v.send_id] = nil
                msg = self.mapped_msg[msg_id]
            end
            -- 还没有消息id，只能通过send_id去更新
        elseif v.send_id ~= nil then
            update_key = v.send_id
            msg = self.mapped_msg[v.send_id]
        else
            E.LOG.e(TAG, "should_not_be_here msg_id and send_id both nil")
        end

        if msg ~= nil then
            msg = self:_update_old_msg(msg, v)
        else
            table.insert(insert_msgs, v)
            msg = v
        end

        table.insert(changed_msgs, msg)
        self.mapped_msg[update_key] = msg
    end

    -- 合并两个有序数组
    local idx1 = #self.sorted_msg
    local idx2 = #insert_msgs
    local idx_right = idx1 + idx2
    while (idx2 > 0) do
        if idx1 <= 0 or
            msg_util.smaller(self.sorted_msg[idx1], insert_msgs[idx2]) then
            self.sorted_msg[idx_right] = insert_msgs[idx2]
            idx2 = idx2 - 1
        else
            self.sorted_msg[idx_right] = self.sorted_msg[idx1]
            idx1 = idx1 - 1
        end
        idx_right = idx_right - 1
    end

    return changed_msgs
end

--- 获得会话消息的数量(模块管理的，所有会话消息的数量)
--- @return integer 会话消息数量
---@example
--      chat_session_msg_instance:count() -> 20
function M:count() return #self.sorted_msg end

--- 获得排序过的消息
--- @return table 排序过的消息
---@example
--      chat_session_msg_instance:get_sorted_msg() -> {msg1, msg2, msg3, ...}
function M:get_sorted_msg() return self.sorted_msg end

--- 获得映射过的消息
--- 有msg_id的，可以用msg_id找到，没有msg_id的假消息，根据send_id映射
--- @return table 映射过的消息
---@example
--      chat_session_msg_instance:get_mapped_msg() -> {[msg_id2]=msg2, [msg_id1]=msg1, [send_id1]=msg3}
function M:get_mapped_msg() return self.mapped_msg end

---查消息的idx
--- @param msg table 消息结构
--- @return integer 下标按lua array
---@example
--      msg1 = {msg_id="623dacfaecd7f5ebb0b6c491", content={type=rich_text,data={extend_data={},text="nihaoya1"}}, ...}
--      chat_session_msg_instance:query_msg_idx(msg1) -> 1
function M:query_msg_idx(msg)
    -- 二分查找，查找到对应的消息
    return self:_find_idx_binary(function(msg2)
        return msg_util._cmp(msg, msg2)
    end)
end

---查从start_idx到end_idx的消息. 超出的范围不会返回
--- @param start_idx integer 开始下标。
--- @param end_idx integer 结束下标。
--- @return table msgs
---@example
--      local chat_session_msg_instance = chat_session_msg_class:New("group_world_1")
--      chat_session_msg_instance:merge_msgs({msg1, msg2, msg3})
--      chat_session_msg_instance:get_msg_by_range(1, 2) -> {msg1, msg2}
--      chat_session_msg_instance:get_msg_by_range(1, 3) -> {msg1, msg2, msg3}
--      chat_session_msg_instance:get_msg_by_range(1, 5) -> {msg1, msg2, msg3}
--      chat_session_msg_instance:get_msg_by_range(nil, 5) -> {msg1, msg2, msg3}
--      chat_session_msg_instance:get_msg_by_range(nil, nil) -> {msg1, msg2, msg3}
--      chat_session_msg_instance:get_msg_by_range(2, nil) -> {msg2, msg3}
function M:get_msg_by_range(start_idx, end_idx)
    local using_start_idx = math.max(1, start_idx or 1)
    local using_end_idx = math.min(#self.sorted_msg, end_idx or #self.sorted_msg)
    local ret = {}
    table_move(self.sorted_msg, using_start_idx, using_end_idx, 1, ret)

    return ret
end

---删除一定范围的消息，并返回这些被删除的消息
--- @param start_idx integer 开始下标。
--- @param end_idx integer 结束下标。
--- @return table msgs
---@example
--      local chat_session_msg_instance = chat_session_msg_class:New("group_world_1")
--      chat_session_msg_instance:merge_msgs({msg1, msg2, msg3})
--      chat_session_msg_instance:delete_msg_by_range(1, 2) -> {msg1, msg2}
--      chat_session_msg_instance:get_msg_by_range(nil, nil) -> {msg3}
function M:delete_msg_by_range(start_idx, end_idx)
    local using_start_idx = math.max(1, start_idx or 1)
    local using_end_idx = math.min(#self.sorted_msg, end_idx or #self.sorted_msg)
    local ret = {}
    for idx = using_start_idx, using_end_idx do table.insert(ret, self.sorted_msg[idx]) end

    -- 将后面的move到前面，并清理这些被删除的消息
    table_move(self.sorted_msg, using_end_idx + 1, #self.sorted_msg, using_start_idx)
    for idx = #self.sorted_msg - (using_end_idx - using_start_idx), #self.sorted_msg do
        self.sorted_msg[idx] = nil
    end
    -- 将哈希表一同删除
    for _, v in ipairs(ret) do
        local key = v.msg_id or v.send_id
        self.mapped_msg[key] = nil
    end

    return ret
end

function M:_find_idx_binary(compare_func)
    local left, right = 1, #self.sorted_msg
    local mid
    while left <= right do
        mid = math.floor((left + right) / 2)
        local cmp_result = compare_func(self.sorted_msg[mid])
        if cmp_result == 0 then
            return mid
            -- 比查找对象小
        elseif cmp_result < 0 then
            right = mid - 1
            -- 比查找对象大
        else
            left = mid + 1
        end
    end
    return nil
end

function M:_find_insert_idx(v)
    return self:_find_idx_from_back(function(msg1)
        local msg2 = v
        return msg_util.greater(msg2, msg1)
    end) + 1
end

-- 从后往前查
function M:_find_idx_from_back(func)
    for idx = #self.sorted_msg, 1, -1 do
        local msg1 = self.sorted_msg[idx]
        if func(msg1) then return idx end
    end
    return 0
end

function M:_update_old_msg(old_msg, new_msg)
    local is_need_bubble = false
    if old_msg.msg_id == nil and new_msg.msg_id ~= nil then
        is_need_bubble = true
    end

    -- table 地址没有改，这样就不用处理时间排序的数组, 也可以保留游戏自己设置的UI相关资源
    for k, v in pairs(new_msg) do old_msg[k] = v end

    -- 如果是一个伪造的消息变为真正有消息id的消息
    -- 那么其排序可能发生变化
    -- 一般这种都会出现在列表尾部。先找到消息的idx, 再使用冒泡排序。
    -- 因为只有SDK伪造的消息才会出现这样的情况，大部分情况冒泡0-1次即可
    if is_need_bubble then
        -- 找到原消息的idx
        local idx = self:_find_idx_from_back(function(msg1)
            local msg2 = old_msg
            return msg1.msg_id == msg2.msg_id
        end)
        -- 执行冒泡, 将大的消息换到后面
        for idx2 = idx - 1, 1, -1 do
            local msg1 = old_msg
            local msg2 = self.sorted_msg[idx2]
            if msg_util.smaller(msg1, msg2) then
                self.sorted_msg[idx], self.sorted_msg[idx2] =
                    self.sorted_msg[idx2], self.sorted_msg[idx]
                idx = idx2
            else
                break
            end
        end
    end

    return old_msg
end

E_UTILS.do_export_wrapping(M)
return M
