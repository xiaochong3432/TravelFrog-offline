local E = require "ejoysdk_lua.ejoysdk"
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'

local M = {}

local surfix = '.ejoyold'

function M.get_backup_dirs()
    local pdir = E.File.get_sys_dirs()['program_dir']
    return E.File.join({pdir, surfix})
end

--[[
    file_list: table, 
        key: 新文件的存放地址，绝对路径
        value: 要覆盖的文件路径，相对路径，相对于可执行文件目录。 路径指向的文件可以不存在，表示新增加一个文件。
]]
function M.update(file_list)
    local succ, code, msg = M.install_update(file_list)
    if succ then
        E.log('install_update finish, restart_process')
        if _ejoysdk.restart_process then
            _ejoysdk.restart_process()
        else
            E.log('restart_process is nil')
        end
    end
    return succ, code, msg
end

function M.install_update(file_list)

    if _ejoysdk.os() ~= 'windows' then
        return false, CONSTANTS.WINDOWS_UPDATER.CODE_NOT_SUPPORT, 'os is not support(not windows)'
    end

    E.log('install_update file_list=')
    E.log(file_list)
    -- 确保更新文件都存在
    for from, _to in pairs(file_list) do -- luacheck: ignore
        -- assert(_ejoysdk.is_file_exists(from), "update file not found: " .. from)
        if not _ejoysdk.is_file_exists(from) then
            local msg = "update file not found: " .. from
            E.log(msg)
            return false, CONSTANTS.WINDOWS_UPDATER.CODE_NOT_EXISTS, tostring(msg)
        end
    end
    local pdir = E.File.get_sys_dirs()['program_dir']
    local backup = M.get_backup_dirs()
    E.File.make_dirs(backup)
    for from, to in pairs(file_list) do
        local abs_to = E.File.join({pdir, to})
        if _ejoysdk.is_file_exists(abs_to) then
            local new_name = to:gsub("\\", '_') -- 被覆盖的文件可能是在子目录里，不要创建那么多目录
            local path = E.File.join({backup, new_name})
            -- backup目录存在相同文件先就删除处理再做移动文件处理。
            if _ejoysdk.is_file_exists(path) then
                E.log('remove file first:' .. tostring(path))
                E.File.remove_fullpath(path)
            end
            _ejoysdk.log('install_update is_file_exists rename=' .. path)
            -- assert(E.File.rename(abs_to, path))

            local succ, msg = E.File.rename(abs_to, path)
            if not succ then
                _ejoysdk.log('[backup]install_update false, msg = ' .. tostring(msg) .. ', from = ' .. tostring(abs_to) .. ', to = ' .. tostring(path))
                return false, CONSTANTS.WINDOWS_UPDATER.CODE_RENAME_FAIL, tostring(msg)
            end
        end
        E.log('rename from ' .. tostring(from) .. ', to = ' .. tostring(abs_to))
        local dir = E.File.dirname(abs_to)
        E.File.make_dirs(dir)
        -- assert(E.File.rename(from, abs_to))
        local succ, msg = E.File.rename(from, abs_to)
        if not succ then
            _ejoysdk.log('install_update false, msg = ' .. tostring(msg) .. ', from = ' .. tostring(from) .. ', to = ' .. tostring(abs_to))
            return false, CONSTANTS.WINDOWS_UPDATER.CODE_RENAME_FAIL, tostring(msg)
        end
    end

    return true
end

-- 返回迭代器，每迭代一次替换固定的数量的文件，防止卡死游戏逻辑进程。
-- 可以这样执行 
-- local itr = update_iterator(file_list, 10)
-- function on_update()
--     itr()
-- end 
-- 当 itr() 迭代完成，程序会重启

function M.update_iterator(file_list, batch)

    if _ejoysdk.os() ~= 'windows' then
        E.LOG.e('windows_updater', 'os is not support(not windows)')
        return function() end
    end

    if _ejoysdk.restart_process == nil then
        return false, CONSTANTS.WINDOWS_UPDATER.CODE_NOT_SUPPORT, 'windows sdk is lower'
    end

    local itr, v
    return function()
        local batch_file_list = {}
        local count = 0
        for _i = 1, batch do
            itr, v = next(file_list, itr)
            if itr == nil then
                local succ, code, msg = M.install_update(batch_file_list)
                if succ then
                    E.log('install_update finish, restart_process')
                    if _ejoysdk.restart_process then
                        _ejoysdk.restart_process()
                    end
                    return succ, count
                end
                return succ, code, msg
            end
            batch_file_list[itr] = v
            count = count + 1
        end
        local succ, code, msg = M.install_update(batch_file_list)
        if succ then
            return succ, count
        end
        return succ, code, msg
    end
end

function M.cleanup()

    if _ejoysdk.os() ~= 'windows' then
        return false, CONSTANTS.WINDOWS_UPDATER.CODE_NOT_SUPPORT, 'os is not support(not windows)'
    end

    if _ejoysdk.listdir == nil or _ejoysdk.restart_process == nil then -- 低版本不做处理
        return false, CONSTANTS.WINDOWS_UPDATER.CODE_NOT_SUPPORT, 'windows sdk is lower, ignore'
    end

    local dir = M.get_backup_dirs()
    local files = _ejoysdk.listdir(dir .. E.File.sep .. "*")
    E.log('[begin]cleanup dir' .. dir .. 'files=')
    E.log(files)
    for _, v in ipairs(files) do
        local abs_path = E.File.join({dir, v})
        E.File.remove_fullpath(abs_path)
    end
    E.log('[end]cleanup dir' .. dir)

    return true
end

return M
