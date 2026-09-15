-------------------------------------------------------------------------------
-- Created Date: 2021.11.04
-- Author: 三傻
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local M = {}
M.__index = M

local file_name_pattern = "^.+[/\\](.+)$"

-- 获取文件名
function M.get_file_name(file_full_path)
    if type(file_full_path) ~= "string" then
        return
    end
    return file_full_path:match(file_name_pattern)
end

return M
