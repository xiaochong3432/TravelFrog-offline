local BASE_API = require 'ejoysdk_lua.libs.base_api'
local api = BASE_API:New('report-mailbox')
local EM = require "ejoysdk_lua.ejoysdk_module"

local _TAG = EM.MODULE.SERVER_API .. 'report_mailbox'

local M = {}
-- 获取举报类型
-- https://yuque.antfin.com/ejoy-platform/ejoy-platform/cwbth6#76de6237
function M.get_report_types(cb)
    local body = {}
    local opt = {use_moment_token = true}
    api:post('/get_report_types', {}, body, opt, cb)
end

-- 举报
-- https://yuque.antfin.com/ejoy-platform/ejoy-platform/cwbth6#d80a1d74
function M.report(report_type_id, report_desc, scene, suspect_info, contents, cb)
    local body = {
        report_type_id = report_type_id,
        report_desc = report_desc,
        scene = scene,
        suspect_info = suspect_info,
        contents = contents
    }
    local opt = {use_moment_token = true}
    api:post('/report', {}, body, opt, cb)
end

return M