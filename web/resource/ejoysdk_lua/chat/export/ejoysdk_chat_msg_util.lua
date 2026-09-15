--[[
    聊天消息工具类
--]]
local M = {}
local E_UTILS = require 'ejoysdk_lua.ejoysdk_utils'
local msg_status = {
    server_received = 0,
    user_received = 1,
    recall = 5,
    sending = 6,
    failed = 7
}

--- 返回消息状态定义
--- @return table
---@example
--      msg_util.msg_status() -> {recall=5, ...}
function M.msg_status() 
    return msg_status 
end

--- 比较消息大小，是否小于
-- 消息可以按msg_id做全序排序，但这不意味着一定按时间排序。可能一个新消息到来，插入到一个老消息前面。
-- 消息未到达服务器之前，就会构造假的消息, 消息可能没有msg_id。这种情况下根据send_id排序。
-- 假消息一定排在新消息后面。
-- 假设有两个消息，第一个消息发送时失败，重发才成功。
-- 可能会有第二个消息先排在消息一后，在消息二成功返回后，排在消息一前的情况。
-- 上述两种情况，消息的排序都可能发生变更。
--- @param msg1 table 消息1
--- @param msg2 table 消息2
--- @return boolean 消息1 是否小于 消息2
---@example
--      msg1 = {msg_id="623dacfaecd7f5ebb0b6c491", content={type=rich_text,data={extend_data={},text="nihaoya1"}}, ...}
--      msg2 = {msg_id="623dacfaecd7f5ebb0b6c492", content={type=rich_text,data={extend_data={},text="nihaoya2"}}, ...}
--      msg_util.smaller(msg1, msg2) -> true
function M.smaller(msg1, msg2)
    local res = M._cmp(msg1, msg2)
    if res < 0 then
        return true
    else
        return false
    end
end

---参考比较消息大小，msg1是否大于msg2
--- @param msg1 table 消息1
--- @param msg2 table 消息2
--- @return boolean 消息1 是否大于 消息2
---@example
--      msg1 = {msg_id="623dacfaecd7f5ebb0b6c491", content={type=rich_text,data={extend_data={},text="nihaoya1"}}, ...}
--      msg2 = {msg_id="623dacfaecd7f5ebb0b6c492", content={type=rich_text,data={extend_data={},text="nihaoya2"}}, ...}
--      msg_util.greater(msg1, msg2) -> false
function M.greater(msg1, msg2)
    local res = M._cmp(msg1, msg2)
    if res > 0 then
        return true
    else
        return false
    end
end

---是否同一个消息。
--- @param msg1 table 消息1
--- @param msg2 table 消息2
--- @return boolean
---@example
--      msg1 = {msg_id="623dacfaecd7f5ebb0b6c491", content={type=rich_text,data={extend_data={},text="nihaoya1"}}, ...}
--      msg2 = {msg_id="623dacfaecd7f5ebb0b6c492", content={type=rich_text,data={extend_data={},text="nihaoya2"}}, ...}
--      msg_util.is_the_same(msg1, msg2) -> false
function M.is_the_same(msg1, msg2)
    if M._cmp(msg1, msg2) == 0 then
        return true
    else
        return false
    end
end

function M._cmp(msg1, msg2)
    local msg_id1 = msg1.msg_id
    local msg_id2 = msg2.msg_id
    -- 11 10 01 00
    -- bit位代表有无msg_id
    -- 11
    if msg_id1 ~= nil and msg_id2 ~= nil then
        return M._cmp_to_int(msg_id1, msg_id2)
        -- 00
    elseif msg_id1 == nil and msg_id2 == nil then
        return M._cmp_to_int(msg1.send_id, msg2.send_id)
        -- 01 新消息应该更大
    elseif msg_id1 == nil then
        return 1
        -- 其它，即10，msg1 有msg_id, msg2 没有，那么msg1 更小(老)
    else
        return -1
    end
end

function M._cmp_to_int(val1, val2)
    if val1 == val2 then
        return 0
    elseif val1 < val2 then
        return -1
    else
        return 1
    end
end

E_UTILS.do_export_wrapping(M)
return M
