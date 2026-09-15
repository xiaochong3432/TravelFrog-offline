--[[
    聊天model层实现

建议的使用范式：
1. 尽量不通过callback，只通过handler. 给出数据变更，建议用户写MVVM式的代码，针对数据变更更新UI显示。
2. 用户主动触发的请求，有 result callback，不建议用户处理成功的callback，某些场景可能需要处理错误callback。给予用户提示。
3. 需要精确针对特定请求callback的场景，可以按照下面的方式使用：
```
    local task_id = chat_model:send_rich_text(current_session_msg:get_session_id(), {
        text = input_text.text,
        extend_data = {}
    })
    chat_model:add_callback(task_id, function(task_id, task_name, rpc_result) 
        CS.UnityEditor.EditorUtility.DisplayDialog(task_name, "发送的内容是:" .. input_text.text
         .. "\n 发送结果：" .. rpc_result.code, "ok")
    end)
```
--]]

local Class = require "ejoysdk_lua.ejoysdk_class"
local ImplClass = require "ejoysdk_lua.chat.ejoysdk_chat_model_impl"
local E_UTILS = require 'ejoysdk_lua.ejoysdk_utils'
local M = Class:Inherit('chat_model')

--- 初始化
-- 模块初始化接口，创建model层需要的数据结构。
--- @param handler table 回调的module
--- @param init_param table  初始化参数
-- init_param.user_type string 用户类型，player/account
-- init_param.old_chat_handler 出于兼容性保留，后面要拿掉
--- @return nil
---@example
--    chat_model_class:New(chat_handler_instance, {user_type='player'})  ->  chat_model
function M:_init(handler, init_param)
    self.impl = ImplClass:New(handler, init_param)
end

--- tick
-- 在tick中会尝试保持数据同步，修复链接等。
--- @return nil
---@example
--    chat_model:tick()
function M:tick()
    self.impl:tick()
end

--- 增加callback
--- @param task_id string 任务id
--- @param func function 参数参考 info_chat_rpc_result
--- @return boolean
-- 如果传入非法的 参数（如task_id 不是callback 刚返回的），会返回false
-- 非必须情况下，不建议用add_callback方式。比如，如果希望通过闭包携带封装upvalue时，才使用callback。
---@example
--    local session_id = '1000001:1000002'
--    local data = "balabala"
--    local task_id = chat_model:send_rich_text(session_id, {
--        text = 'hello world',
--        extend_data = {}
--    })
--    chat_model:add_callback(task_id, function(task_id, task_name, rpc_result) 
--        if rpc_result.code == 0 then
--            print('发送成功', data)
--        else
--            print('发送失败')
--        end
--    end)
function M:add_callback(task_id, func)
    self.impl:add_callback(task_id, func)
end

--- 获得会话消息
--- @param iter_data table 迭代器数据
--      iter_data.session_id 会话id
--      iter_data.ts 在本地有消息数据之前的第一次查询，只能用时间作为迭代器查询
--      iter_data.msg_id 按消息id查询，可以精确地查询不包含该 msg_id 的上N条，或下N条
--- @param search_direction integer 查询方向
--      1:通过迭代器向后（查更新的消息）查
--      -1:通过迭代器向前查, 一般是从当前时间往前，查最近的消息
--- @param max_msg_count integer 最大返回消息数量。一次不能超过50个
--- @return string task_id 用于callback
---@example
--    local to_player_id = '1000002'
--    local session_id = chat_model:get_to_user_session_id(to_player_id)
--    chat_model:get_session_msg({ts=os.time(), session_id=session_id}, 1, 50) -> '164854145000000004'
function M:get_session_msg(iter_data, search_direction, max_msg_count)
    return self.impl:get_session_msg(iter_data, search_direction, max_msg_count)
end


--- 获得自身对用户的会话id
--- @param user_id string 目标用户id
--- @return string 会话id
---@example
--    chat_model:get_to_user_session_id('1000002')  -> '1000001:1000002'
function M:get_to_user_session_id(user_id)
    return self.impl:get_to_user_session_id(user_id)
end

--- 发送消息
-- 发送富文本接口。不提供文本接口，推荐使用富文本。
--- @param session_id string 会话id
--- @param data table 发送数据
--      data.text 发送原始富文本
--      data.extend_data 拓展数据，平台不进行检测
--      data.plain_text 消息的纯文本化展示。
-- 不传会通过去掉html标签获得消息纯文本展示，如果希望自己控制，可以传入此参数。
-- 可用于系统推送等场景。
--- @param at_list table at的用户ID列表
--- @return string task_id 用于callback
---@example
--    local session_id = chat_model:get_to_user_session_id('1000002')
--    chat_model:send_rich_text(session_id, {
--        text="<img name=zb_2141232></img><span>看看我的<item id=1001, link_id=1>三叉戟</item></span>",
--        extend_data={[1]={attack=100}}},
--        []
--    )  ->  '164854145000000005'
function M:send_rich_text(session_id, data, at_list)
    return self.impl:send_rich_text(session_id, data, at_list)
end

--- 发送消息
-- 发送接口，提供对服务器发送接口的封装。具体参考服务器发送接口文档。
--- @param session_id string 会话id
--- @param content table 发送内容数据,具体看服务器的send接口
--- @return string task_id 用于callback
---@example
--    local session_id = chat_model:get_to_user_session_id('1000002')
--    chat_model:send(session_id, {type="res",data={res_type="audio", res_id="5fa268884afaad1374a69c62"}}, [])  -> '164854145000000006'
function M:send(session_id, content, at_list)
    return self.impl:send("send", session_id, content, at_list)
end

--- 重发消息
--- @param send_id string 如果有消息更新通知中，消息的状态为发送失败。可用此接口幂等重发。建议在消息对应的UI上。做重试按钮。
--- @return string task_id 用于callback
---@example
--    local task_id = chat_model:send_rich_text(current_session_msg:get_session_id(), {
--        text = input_text.text,
--        extend_data = {}
--    })
--    收到消息状态更新，消息处于发送失败状态如下:
--    msg1 = {msg_id="623dacfaecd7f5ebb0b6c491", reader_status=msg_util.msg_status().failed,
--      send_id="1648209148d71aa61344398f3202645265",
--      content={type=rich_text,data={extend_data={},text="nihaoya1"}}, ...}
--    消息显示重发按钮。用户点击重发按钮时，调用：
--    chat_model:resend('1648209148d71aa61344398f3202645265')  -> '164854145000000007'
function M:resend(send_id)
    return self.impl:resend(send_id)
end

--- 创建会话
-- 创建会话，本地存在，则返回本地的，没有则新建
--- @param to_id string 用户id
--- @return string task_id 用于callback
---@example
--      chat_model:create_to_user_session('1000002') -> '164854145000000008'
--      会触发回调：
--      user_chat_handler:info_chat_session_change(...)
function M:create_to_user_session(to_id)
    return self.impl:create_to_user_session(to_id)
end

--- 设置消息已收
--- @param session_id string 会话id
--- @param received_ts integer 大于这个时间戳的消息被设置为已读，可以不传，会使用服务器的时间戳，不传的语义为，设置所有当前会话消息为已读
--- @return string task_id 用于callback
---@example
--      chat_model:set_msg_received('1000001:1000002') -> '164854145000000009'
function M:set_msg_received(session_id, received_ts)
    return self.impl:set_msg_received(session_id, received_ts)
end

--- 创建群组
--- @param members table 邀请的成员id数组
--- @param invite_msg string 邀请语
--- @param info table 群组信息
--      info.name 群组名称
--- @return string task_id 用于callback
---@example
--     chat_model:create_group(
--         ["1000002","1000001"],
--         "快来我的高手闲聊群",
--         {"name":"高手吹水群"})  -> '164854145000000010'
function M:create_group(members, invite_msg, info)
    return self.impl:create_group(members, invite_msg, info)
end

--- 添加群成员
--- @param adds table 邀请的成员id数组
--- @param invite_msg string 邀请语
--- @param group_id string 群组id
--- @return string task_id 用于callback
---@example
--    chat_model:add_group_member(
--        ["1000003","1000004"],
--        '欢迎高手进群',
--        'group_23423523423324')  -> '164854145000000011'
function M:add_group_member(adds, invite_msg, group_id)
    return self.impl:add_group_member(adds, invite_msg, group_id)
end

--- 处理群邀请
--- @param reply_msg string 回复语
--- @param is_agree boolean 同意or拒绝
--- @param group_id string 群组id
--- @return string task_id 用于callback
---@example
--      chat_model:reply_add_group_member(
--          '谢谢，暂时不进群了',
--          false,
--          'group_234325324234'
--      )  ->  '164854145000000012'
function M:reply_add_group_member(reply_msg, is_agree, group_id)
    return self.impl:reply_add_group_member(reply_msg, is_agree, group_id)
end

--- 移除群成员
--- @param removes table 需要移除的成员id数组
--- @param remove_msg string 移除语
--- @param group_id string 群组id
--- @return string task_id 用于callback
---@example
--      chat_model:remove_group_member(
--          ["1000001"],
--          '本群不欢迎',
--          'group_231412312312'
--      )  -> '164854145000000013'
function M:remove_group_member(removes, remove_msg, group_id)
    return self.impl:remove_group_member(removes, remove_msg, group_id)
end

--- 更新群资料
--- @param info table 群资料
--      info.name 群名称
--- @param group_id string 群组id
--- @return string task_id 用于callback
---@example
--      chat_model:update_group(
--          {"name":"群组新名字"},
--          'group_231412312312'
--      )  -> '164854145000000014'
function M:update_group(info, group_id)
    return self.impl:update_group(info, group_id)
end

--- 解散群
--- @param group_id string 群组id
--- @return string task_id 用于callback
---@example
--      chat_model:delete_group(
--          'group_231412312312'
--      )  -> '164854145000000015'
function M:delete_group(group_id)
    return self.impl:delete_group(group_id)
end

--- 退出群
--- @param group_id string 群组id
--- @return string task_id 用于callback
---@example
--      chat_model:exit_group(
--          'group_231412312312'
--      )  -> '164854145000000016'
function M:exit_group(group_id)
    return self.impl:exit_group(group_id)
end

--- 获取自己被邀请的历史
--- @return string task_id 用于callback
---@example
--      local task_id = chat_model:get_group_be_invited_history()
--      通过 info_chat_rpc_result 显示群组邀请历史
function M:get_group_be_invited_history()
    return self.impl:get_group_be_invited_history()
end

--- 举报消息
--- @param report_type_id string 举报类型id
--- @param report_desc string 举报描述
--- @param session_id string 会话id
--- @param msg_id string 消息id
--- @return string task_id 用于callback
---@example
--      chat_model:report_msg(
--          'chat_1',
--          '有人骂我',
--          '1000001:1000002',
--          '6238727f85117540efda2083')  -> '164854145000000017'
function M:report_msg(report_type_id, report_desc, session_id, msg_id)
    return self.impl:report_msg(report_type_id, report_desc, session_id, msg_id)
end

--- 获取聊天配置
--- @return string task_id 用于callback
---@example
--      chat_model:get_chat_config()
--      通过 info_chat_rpc_result 显示聊天配置
function M:get_chat_config()
    return self.impl:get_chat_config()
end

--- 设置聊天配置
--- @param chat_config table 聊天配置
--      chat_config.push 聊天推送配置
--      chat_config.push.push_on_offline 开启离线推送
--      chat_config.push.push_on_system_session 开启系统推送
--      chat_config.push.push_on_player_session 开启角色聊天推送
--      chat_config.push.push_on_cs_session 开启客服聊天推送
--      chat_config.push.push_on_group_types 开启群组聊天的群组类型
--- @return string task_id 用于callback
---@example
--      chat_model:set_chat_config({
--          push={
--              push_on_offline=true,
--              push_on_system_session=true,
--              push_on_player_session=true,
--              push_on_cs_session=true,
--              push_on_group_types=["client_group", "world"]
--          }
--      })
function M:set_chat_config(chat_config)
    return self.impl:set_chat_config(chat_config)
end

function M:destroy()
    self.impl:destroy()
end

E_UTILS.do_export_wrapping(M)

return M
