local JSON = require 'ejoysdk_lua.ejoysdk_json'
local GDP = require 'ejoysdk_lua.gangplank_data_provider'
local E = require "ejoysdk_lua.ejoysdk"
local EM = require "ejoysdk_lua.ejoysdk_module"
local string_len = string.len
local string_sub = string.sub
-- 默认4M
local MAX_SIZE = 4*1024*1024
local M = {}

local _TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'upload_log'

local function string_end_with(str, end_str)
    local st = string_len(str) - string_len(end_str) + 1
    if st < 1 then
        return false
    end
   return string_sub(str, st) == end_str
end

function M.get_max_size()
    return MAX_SIZE
end

-- new_size 单位字节
function M.set_max_size(new_size)
    if new_size and type(new_size) == 'number' then
        MAX_SIZE = new_size
    end
end

--上传客户端运行日志
function M.upload_client_log(file_path_name)
    local url = E.CONFIG.get_config("log-collector") .. '/client_api/upload_log'
    _ejoysdk.log(">>>>>>>>>>>>>>> upload_client_log begin2:" .. tostring(file_path_name))
    if not string_end_with(file_path_name, ".zip") then
        _ejoysdk.log(string.format("file_path_name is not a zip file, file_path_name = '%s'", file_path_name))
        return
    end

    -- 安卓和iOS的_ejoysdk.lread的实现不太一样，所以不能直接用这个函数，iOS之前会去读bundle内的文件，逻辑不对
    -- E.File.readfile函数会在内部指定一个目录来读取，只接收文件名，而不是绝对路径，这里特意改成游戏传递的文件绝对路径
    --local data = E.File.readfile(file_path_name)
    local data
    if E.Sysinfo.os() == 'ios' then
        data = E.sync_call('read_file', file_path_name)
    else
        data = _ejoysdk.lread(file_path_name)
    end

    _ejoysdk.log(">>>>>>>>>>>>>>> upload_client_log begin3:" .. tostring(file_path_name))
    if not data then
        _ejoysdk.log(string.format("file no found. file_path_name = '%s'", file_path_name))
        return
    end

    _ejoysdk.log(">>>>>>>>>>>>>>> upload_client_log begin4:" .. tostring(file_path_name))
    _ejoysdk.log("file length:" .. tostring(#data) .. ", max length:" .. tostring(MAX_SIZE))
    if #data > MAX_SIZE then
        _ejoysdk.log("file too large. must less than " .. tostring(MAX_SIZE/(1024*1024)) .. 'M')
        return
    end

    local player_id = GDP.PLAYER_INFO.get('player_id')

    local json = 
    {
        player_id = player_id,
        device_id = E.Sysinfo.device_id(),
    }

    local formdata = E.HTTP.FormData.New()
    formdata:add_simple_part('_json', JSON.encode(json))
    formdata:add_part('log_file', data, false, false, file_path_name)

    _ejoysdk.log("upload_client_log url "..url)
    E.HTTP.post(url, {acceptable = E.HTTP.CT_JSON}, formdata:content_type(), formdata:build(), function(resp)

        if resp.status ~= 200 then
            E.log({error='send event error', resp=resp})
        else
            local body = resp.body
            if body and (body.code == 0 or body.code == 200) then
                _ejoysdk.log(string.format("upload_client_log ok. file_path_name = '%s'", file_path_name))
            else
                E.log({error='send event error', resp=resp})
            end
        end
    end)
end

-- 文件不能超过4M，同 ip 2分钟内最多允许调用10次此接口
function M.upload_client_log_v2(file_path_name, params, cb)
    local url = E.CONFIG.get_config("log-collector") .. '/client_api/upload_log'

    if not string_end_with(file_path_name, ".zip") then
        _ejoysdk.log(string.format("file_path_name is not a zip file, file_path_name = '%s'", file_path_name))
        return
    end

    -- 安卓和iOS的_ejoysdk.lread的实现不太一样，所以不能直接用这个函数，iOS之前会去读bundle内的文件，逻辑不对
    -- E.File.readfile函数会在内部指定一个目录来读取，只接收文件名，而不是绝对路径，这里特意改成游戏传递的文件绝对路径
    --local data = E.File.readfile(file_path_name)
    local data
    if E.Sysinfo.os() == 'ios' then
        data = E.sync_call('read_file', file_path_name)
    else
        data = _ejoysdk.lread(file_path_name)
    end

    if not data then
        _ejoysdk.log(string.format("file no found. file_path_name = '%s'", file_path_name))
        return
    end

    _ejoysdk.log("file length:" .. tostring(#data) .. ", max length:" .. tostring(MAX_SIZE))
    if #data > MAX_SIZE then
        _ejoysdk.log("file too large. must less than " .. tostring(MAX_SIZE/(1024*1024)) .. 'M')
        return
    end

    local player_id = GDP.PLAYER_INFO.get('player_id')

    -- device_id优先以utdid为准，其次为device_id
    local device_id = E.Sysinfo.utdid() or E.Sysinfo.device_id()
    local json = 
    {
        player_id = player_id,
        device_id = device_id,
        ext = params or {}
    }

    local formdata = E.HTTP.FormData.New()
    formdata:add_simple_part('_json', JSON.encode(json))
    formdata:add_part('log_file', data, false, false, file_path_name)

    _ejoysdk.log("upload_client_log url "..url)
    E.HTTP.post(url, {acceptable = E.HTTP.CT_JSON}, formdata:content_type(), formdata:build(), function(resp)

        if resp.status ~= 200 then
            E.log({error='send event error', resp=resp})
        else
            local body = resp.body
            if body and (body.code == 0 or body.code == 200) then
                _ejoysdk.log(string.format("upload_client_log2 ok. file_path_name = '%s'", file_path_name))
                cb(true)
            else
                E.log({error='send event error', resp=resp})
                cb(false, resp.status or -1, 'request error')
            end
        end
    end)
end

return M