---
--- Created by pangang.
--- DateTime: 2019/2/23 下午3:14
---
---
local E = require 'ejoysdk_lua.ejoysdk'
local Vendor = require "ejoysdk_lua.vendors.vendor"
local UNI = require "ejoysdk_lua.vendors.unisdk"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local EM = require "ejoysdk_lua.ejoysdk_module"
local CHANNEL = "HELPSHIFT"
local M = Vendor:Inherit(CHANNEL)

local TAG = EM.MODULE.VENDORS.HELP_SHIFT

local CAST_SHOW_FAQ = "CAST_SHOW_FAQ"
local CAST_LOGIN_SUCCESS = "CAST_LOGIN_SUCCESS"
local CAST_LOGOUT_SUCCESS = "CAST_LOGOUT_SUCCESS"

--显示客服页面
--tags: 过滤FAQ的tag标签，tag值需要预先在helpshift配置，配置地址：https://aligames.helpshift.com/admin/settings/workflows/tags/
--custom_issue_fields: 问题关键字段，最大数量为50，用于后台流程控制，需要在helpshift后台配置，配置地址：https://aligames.helpshift.com/admin/settings/workflows/custom-issue-fields/
--meta_data: 其它字段, 用于为客服提供用户的其它数据，如果想要用issue fields填充，请在添加issue fields时做映射
function M.show_faq(tags, custom_issue_fields, meta_data)
    local params = {
        tags = tags,
        custom_issue_fields = custom_issue_fields,
        meta_data = meta_data
    }
    UNI.cast(CHANNEL, CAST_SHOW_FAQ, params)
end

local login_handler = function(user_info)
    -- update param
    local params = {
        uid = user_info.uid
    }
    UNI.cast(CHANNEL, CAST_LOGIN_SUCCESS, params)
end

local logout_handler = function()
    UNI.cast(CHANNEL, CAST_LOGOUT_SUCCESS, {})
end

function M.init(_opt, cb)
    E.LOG.debug(TAG, 'helpshift start init!')

    -- 账号级的状态缓存，所以只需要ET.gangplank.LOGIN、ET.gangplank.LOGOUT
    ET.subscribe(ET.gangplank.LOGIN, login_handler)
    ET.subscribe(ET.gangplank.LOGOUT, logout_handler)

    -- callback init success
    cb(true)
end

function M.show_custom_service(params, cb)
    params = params or {}
    M.show_faq(params.tags, params.custom_issue_fields, params.meta_data)
    cb(true)
end

return M