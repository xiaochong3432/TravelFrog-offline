local md5 = require "ejoysdk_lua.libs.md5"
local E = require "ejoysdk_lua.ejoysdk"
local EM = require "ejoysdk_lua.ejoysdk_module"

local M = {}
local _TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'file'

local function cache_dir()
    local file_path = ''
    if E.Sysinfo.os() == 'ios' then
        local paths = _ejoysdk.sysinfo_paths()
        file_path = paths['document_path']
    elseif E.Sysinfo.os() == 'android' then
        local dir = E.sync_call('GET_EXT_STG_DIR')
        file_path = dir.path
    --else
        --windows链路都还不通，先不考虑
    end

    return file_path
end

local function get_file_data(path)
    local rfile = io.open(path, "r")

    if not rfile then
        return ''
    end

    local current = rfile:read("*all")
    return current, md5.sumhexa(current)
end

-- opts.loadBinData 是否需要二进制数据
-- cb 成功=>cb(true, data), 失败=>cb(false, code, msg)
function M.download_file(url, opts, cb)
    local function safeCallCb(a_cb, ...)
        if a_cb and type(a_cb) == 'function' then
            a_cb(...)
        end
    end

    -- 没有回调，调用方执行该方法就没意义，可以直接return
    if not cb or type(cb) ~= 'function' then
        return
    end

    opts = opts or {}

    -- 判断是否为http链接
    if not url or type(url) ~= 'string' then
        safeCallCb(cb, false, 0, 'url invalid')
        return
    else
        local is_http = string.find(url,"http://") == 1 or
                string.find(url,"https://") == 1
        if not is_http then
            safeCallCb(cb, false, 0, 'not http protocol')
            return
        end
    end

    -- 是否需要二进制data
    local need_bin_data = opts.loadBinData == true

    local is_native_call = opts.isNativeCall == true

    -- 获取url的文件名
    local file_name = url:match( "([^/]+)$")
    local local_save_path = cache_dir() .. '/' .. file_name
    local param = {
        progress = function(_url, _file, _recv, _total)
            --E.LOG.debug(TAG,'文件总大小： ' .. total .. ' ，当前下载大小： ' .. recv)
        end,
        finish_cb = function()
        end,
        file = local_save_path  -- 指定本地路径
    }

    E.HTTP.get(url, param, function(resp)
        if resp.status == 200 then
            local file_data, md5_value = get_file_data(local_save_path)
            local body = {
                fileLocalPath = local_save_path or '',
                md5 = md5_value or ''
            }

            -- 需要二进制，且不是原生调用，才往data里放二进制。tips:原生调用下，放二进制数据，会有问题
            if need_bin_data and is_native_call ~= true and file_data then
                body.fileData = file_data
            end
            safeCallCb(cb, true, body)
        else
            safeCallCb(cb, false, 0, "download fail")
        end
    end)
end

return M