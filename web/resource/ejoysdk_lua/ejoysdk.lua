local JSON = require "ejoysdk_lua.ejoysdk_json"
local CONFIG = require "ejoysdk_lua.ejoysdk_config"
local Class = require "ejoysdk_lua.ejoysdk_class"
local COMPAT = require 'ejoysdk_lua.compat.ejoysdk_compat'
local BitUtil = COMPAT.bitutil
--local string_unpack = COMPAT.string.unpack

--local V = require "ejoysdk_lua.version"
local E_UTILS = require 'ejoysdk_lua.ejoysdk_utils'
local ELOG = require "ejoysdk_lua.ejoysdk_log"
local UIM = require 'ejoysdk_lua.user_info_manager'
local LANG = require "ejoysdk_lua.lang.util"
local ET = require 'ejoysdk_lua.ejoysdk_topic'
local EM = require "ejoysdk_lua.ejoysdk_module"
local ECC = require "ejoysdk_lua.ejoysdk_constants"

local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'ejoysdk'

local M
if _ejoysdk.os and _ejoysdk.os() == 'android' then
    M = require 'ejoysdk_lua.ejoysdk_android'
    CONFIG.set_config('os', 'android')
elseif _ejoysdk.os and _ejoysdk.os() == 'windows' then
    M = require 'ejoysdk_lua.ejoysdk_windows'
    CONFIG.set_config('os', 'windows')
else
    M = require 'ejoysdk_lua.ejoysdk_ios'
    CONFIG.set_config('os', 'ios')
end

local ejoysdk_log = _ejoysdk.log
local log_with_tag = function(s)
    ejoysdk_log('[l]' .. tostring(s))
end
_ejoysdk.log = log_with_tag

-- 老版本没这个函数报错了
if _ejoysdk.bin_version then
    CONFIG.set_config('bin_version', _ejoysdk.bin_version())
else
    CONFIG.set_config('bin_version', 1)
end

M.CONFIG = CONFIG

local HTTP = M.HTTP
local HttpDns = {}
M.HttpDns = HttpDns

local file_delegate = function()
    return require "ejoysdk_lua.libs.file"
end

local path_delegate = function()
    return require "ejoysdk_lua.libs.path"
end

local Path = {}
M.Path = Path

--[[
根据不同平台的sep, 将base_path和多个path部分join到一起
--]]
Path.join = function(base_path, ...)
    return path_delegate().join(base_path, ...)
end

Path.uniform_sep = function(path)
    return path_delegate().uniform_sep(path)
end

Path.trim_end_separator = function(path)
    return path_delegate().trim_end_separator(path)
end

Path.trim_separators = function(path)
    return path_delegate().trim_separators(path)
end

Path.trim_begin_separator = function(path)
    return path_delegate().trim_begin_separator(path)
end

Path.get_ext_file_dir = function()
    return path_delegate().get_ext_file_dir()
end

--[[
返回路径的父目录(支持windows和linux两种文件分隔符)，有以下两个场景：
1. 文件路径：/aaa/b.txt，则父目录为/aaa/
2. 目录路径：/aaa/bbb/ 则父目录为/aaa/
3. 无父目录场景：/aaa 则父目录为空串
@return 父目录，路径最后一级的名称（可能是文件或者目录名）
--]]
Path.parent_dir = function(path)
    return path_delegate().parent_dir(path)
end

--[[
检查路径path的父目录是否存在，不存在则尝试创建
--]]
Path.ensure_parent_dir = function(path)
    return path_delegate().ensure_parent_dir(path)
end

local File = M.File
--[[
重命名文件或者目录，
以下场景会rename失败：
1. 如果目标目录存在且不为空

@param src: string, 必传，源文件相对路径, 相对路径见E.File.get_ext_file_dir()
@param dst：string, 必传，目标文件相对路径
@param opts: table, 可选，可选项, 包含以下内容：
    @param is_fullpath: bool, 默认为false, true：当前src和dst为绝对路径

@return bool true rename成功； nil rename 失败，同时第二个参数为code, msg
--]]
File.rename = function(src, dst, opts)
    return file_delegate().rename(src, dst, opts)
end

File.rename_fullpath = function(src_full_path, dst_full_path)
    return file_delegate().rename_fullpath(src_full_path, dst_full_path)
end

--[[
批量重命名文件或者目录
@param map: table, 必传，文件列表，key-value为源路径和目标路径键值对，具体如下
    key: string, 必传，默认为源文件相对路径, 可以通过opts的is_fullpath修改
    value string, 必传，默认为目标文件相对路径, 可以通过opts的is_fullpath修改
@param cb: function，返回结果，返回内容如下：
    @param succ: bool, true：全部rename成功；false: 部分失败或全部失败，此时code, msg, result_ext不为空
    @param code: number, 错误码
    @param msg: string, 错误信息
    @param result_ext: table, 失败的路径信息，包含以下key-value值
        key string，源文件路径
        value table, 错误信息，包含以下key-value
            @param code number 错误码
            @param msg string 错误信息
@param opts: table, 可选，可选项, 包含以下内容：
    @param is_fullpath: bool, 默认为false, true：当前src和dst为绝对路径
--]]
File.batch_rename = function(map, cb, opts)
    file_delegate().batch_rename(map, cb, opts)
end

--[[
复制一个文件或目录
@param src: string, 必传，源文件相对路径, 相对路径见E.File.get_ext_file_dir()
@param dst：string, 必传，目标文件相对路径
@param cb：function, 可选，结果回调，返回内容如下：
    @param succ bool, true: 成功，false: 失败，失败时下面code和msg有值
    @param code number, 错误码
    @param msg string, 错误信息
@param opts: table, 可选，可选项, 包含以下内容：
    @param is_fullpath: bool, 默认为false, true：当前src和dst为绝对路径
    @param override: bool, 默认为false, true: 覆盖目标目录，false:不覆盖，如果目标文件存在则会报错
@return
    @param succ bool, true: 成功，false: 失败，失败时下面code和msg有值
    @param code number, 错误码
    @param msg string, 错误信息
--]]
File.copy = function(src, dst, opts)
    return file_delegate().copy(src, dst, opts)
end

--[[
复制一个文件或目录
@param src: string, 必传，源文件绝对路径
@param dst：string, 必传，目标文件绝对路径
@param cb：function, 可选，结果回调，返回内容如下：
    @param succ bool, true: 成功，false: 失败，失败时下面code和msg有值
    @param code number, 错误码
    @param msg string, 错误信息
@param opts: table, 可选，可选项, 包含以下内容：
    @param override: bool, 默认为false, true: 覆盖目标目录，false:不覆盖，如果目标文件存在则会报错
--]]
File.copy_fullpath = function(src, dst, cb, opts)
    return file_delegate().copy_fullpath(src, dst, cb, opts)
end

--[[
批量复制文件或者目录
@param map: table, 必传，文件列表，key-value为源路径和目标路径键值对，具体如下
    key: string, 必传，源文件路径, 默认为相对路径，可以通过opts的is_fullpath修改该路径属性
    value string, 必传，目标文件路径
@param cb: function，返回结果，返回内容如下：
    @param succ: bool, true：全部rename成功；false: 部分失败或全部失败，此时code, msg, result_ext不为空
    @param code: number, 错误码
    @param msg: string, 错误信息
    @param result_ext: table, 失败的路径信息，包含以下key-value值
        key string，源文件路径
        value table, 错误信息，包含以下key-value
            @param code number 错误码
            @param msg string 错误信息
@param opts: table, 可选，可选项, 包含以下内容：
    @param is_fullpath: bool, 默认为false, true：当前src和dst为绝对路径
    @param override: bool, 默认为false, true: 覆盖目标目录，false:不覆盖，如果目标文件存在则会报错
--]]
File.batch_copy = function(map, cb, opts)
    file_delegate().batch_copy(map, cb, opts)
end

--[[
删除一个文件或目录
@param path：string, 必传，源文件相对路径, 相对路径见E.File.get_ext_file_dir()
@return bool true remove成功； nil remove 失败，同时第二个参数为code, msg
--]]
File.remove = function(path)
    return file_delegate().remove(path)
end

--[[
@deprecate 已废弃，建议使用remove_fullpath，统一函数命名格式。这里为了可能外部的调用而保留
--]]
M.remove_full_path = function(path)
    return File.remove_fullpath(path)
end

--[[
删除一个文件或目录
@param path：string, 必传，源文件绝对路径
@return bool true remove成功； nil： remove 失败，同时第二个参数为code, msg
--]]
File.remove_fullpath = function(path)
    return file_delegate().remove_fullpath(path)
end

--[[
批量删除文件或者目录
@param list: table, 文件或目录字符串列表
@param cb: function, 结果回调，返回内容如下：
    @param succ: bool, true：全部删除成功；false: 部分失败或全部失败，此时code, msg, result_ext不为空
    @param code: number, 错误码
    @param msg: string, 错误信息
    @param result_ext: table, 失败的路径信息，包含以下key-value值
        key string，源文件路径
        value table, 错误信息，包含以下key-value
            @param code number 错误码
            @param msg string 错误信息
@param opts: table, 可选，可选项, 包含以下内容：
    @param is_fullpath: bool, 默认为false, true：当前src和dst为绝对路径
--]]
File.batch_remove = function(list, cb, opts)
    file_delegate().batch_remove(list, cb, opts)
end

--[[
判断路径是否存在
@param path：string，文件路径或者目录路径，相对路径见E.File.get_ext_file_dir()
@param is_full_path: bool, 是否是完整路径，默认为false
@return bool, true: 存在，false: 不存在
--]]
File.exists = function(path, is_full_path)
    return file_delegate().exists(path, is_full_path)
end

File.exists_fullpath = function(path)
    return file_delegate().exists_fullpath(path)
end

--[[
创建目录
@param path string，目录路径
--]]
File.make_dirs = function(path)
    return file_delegate().make_dirs(path)
end

--[[
返回文件的md5值
@param file_path 文件路径，相对路径见E.File.get_ext_file_dir()
@param is_full_path: bool, 是否是完整路径，默认为false
@return
    @param md5_data: string, md5值, 如果md5值为空，则后面返回的为错误码和错误信息
    @param code: number, 错误码
    @param msg: string，错误信息
--]]
File.md5 = function(file_path, is_full_path)
    return file_delegate().md5(file_path, is_full_path)
end

File.md5_fullpath = function(file_path)
    return file_delegate().md5_fullpath(file_path)
end

--[[
批量返回文件的md5值
@param file_list：table, 为文件路径数组，相对路径见E.File.get_ext_file_dir()
@param cb: function, 结果回调，包含以下返回值
    @param succ, bool, true：成功，false: 单个或全部失败，此时后面参数分别为code, msg, succ_data, fail_data
    @param code number，错误码
    @param msg string, 错误信息
    @param succ_data table, 多个文件md5值，k-v格式，对应内容如下：
            key: 文件路径
            value: md5值
    @param fail_data table, 多个路径对应的错误信息
@param is_full_path: bool, 是否是完整路径，默认为false
--]]
File.batch_md5 = function(file_list, cb, is_full_path)
    file_delegate().batch_md5(file_list, cb, is_full_path)
end

--[[
批量检查文件状态
@param file_list：table, 为文件路径数组，相对路径见E.File.get_ext_file_dir()
@param cb: function, 结果回调，包含以下返回值
    @param succ_data table, 多个文件的状态信息，k-v格式，对应内容如下：
            key: 文件路径
            value: table, 包含的信息和opts配置相关，包含以下内容：
                @param exists: bool, 是否存在，true: 存在，false: 不存在
                @param size: number, 文件大小
@param opts: table, 可选项信息，包含以下信息
    @param is_full_path: bool，是否完整路径，默认为false, 相对路径见E.File.get_ext_file_dir()。true: 为绝对路径
    @param check_size: bool, 是否返回size， 默认为false, 不返回，如果设置为true会返回size
    @param base_path: string, 根路径，根路径+file_list里面的item=完整路径
--]]
File.batch_info = function(file_list, cb, opts)
    file_delegate().batch_info(file_list, cb, opts)
end

--[[
检查路径是否是目录
@param file_path 文件路径，相对路径见E.File.get_ext_file_dir()
@param is_full_path: bool, 是否是完整路径，默认为false
@return succ，bool, true: 是目录，false: 不是目录
--]]
File.is_directory = function(file_path, is_full_path)
    return file_delegate().is_directory(file_path, is_full_path)
end

File.is_directory_fullpath = function(file_path)
    return file_delegate().is_directory_fullpath(file_path)
end

--[[
枚举目录下面的所有文件
@param dir_path: string, 目录路径，默认为相对路径（相对路径见E.File.get_ext_file_dir()）。可以通过is_full_path设置为传入绝对路径
@param recursive: bool, 是否递归遍历，默认为false，false: 非递归，仅遍历第一级目录；true: 递归遍历
@param is_full_path: bool, dir_path是否为完整路径，true: 为完整路径；false: 为相对路径
@param cb: function, 异步结果返回，返回内容：
    @param ret: table, 为文件数组信息，每一项的类型为table, 包含字段如下：
        @param is_dir: bool, true: 是目录，false: 非目录
        @param path: string, 文件路径，相对于当前的dir_path。注意：该path第一个字符不为路径分隔符
--]]
File.list_directory = function(dir_path, recursive, is_full_path, cb)
    file_delegate().list_directory(dir_path, recursive, is_full_path, cb)
end

--[[
枚举包体内目录下面的所有文件
@param bundle_dir_path: string, bundle目录路径，android为assets下面目录
@param recursive: bool, 是否递归遍历，默认为false，false: 非递归，仅遍历第一级目录；true: 递归遍历
@param cb: function, 异步结果返回，返回内容：
    @param ret: table, 为文件数组信息，每一项的类型为talble, 包含字段如下：
        @param is_dir: bool, true: 是目录，false: 非目录
        @param path: string, 文件路径，相对于当前的dir_path。注意：该path第一个字符不为路径分隔符
--]]
File.list_bundle = function(bundle_dir_path, recursive, cb)
    file_delegate().list_bundle(bundle_dir_path, recursive, cb)
end

M.META_CONFIG_KEY = {
    GAME_ID = "game_id", -- 游戏ID
    OVERSEAS = "overseas", -- 海外开关
    PUBLISH_AREA = "publish_area", -- 发行地区
    GAME_LANG = "game_lang", -- 游戏语言
    DISTRICT = "district", -- 游戏语言
    PRODUCT_CODE = "product_code", -- 平台ID
    SERVER_DOMAIN = "server_domain", -- 期望替换的服务域名，例如：
    PARENT_PKG_ID = "parent_pkg_id", -- 母包ID
    PARENT_PKG_RECORD_ID = "parent_pkg_record_id", -- 母包记录ID
    APP_REVIEW_VERSION = "app_review_version" -- 游戏提审版本号
}

-- sdkconfig meta value cache
local meta_values_cache = {}

-- 此代码用于信任一个自签名的证书，而非CA签发的证书，以前A2项目会用到，目前用不到了先注释。
--function M.get_cert_info()
--    local ejoy_cert_base64 =
--        'MIIF/DCCA+SgAwIBAgIJALsg/W/4U7gzMA0GCSqGSIb3DQEBCwUAMIGSMQswCQYDVQQGEwJDTjESMBAGA1UECAwJR3Vhbmdkb25nMRIwEAYDVQQHDAlHdWFuZ3pob3UxETAPBgNVBAoMCEVqb3kgSW5jMQ0wCwYDVQQLDARHYW1lMREwDwYDVQQDDAhlam95LmNvbTEmMCQGCSqGSIb3DQEJARYXZ2FtZS5iZEBhbGliYWJhLWluYy5jb20wHhcNMTgxMTE2MTI1NDI1WhcNMjgxMTEzMTI1NDI1WjCBkjELMAkGA1UEBhMCQ04xEjAQBgNVBAgMCUd1YW5nZG9uZzESMBAGA1UEBwwJR3Vhbmd6aG91MREwDwYDVQQKDAhFam95IEluYzENMAsGA1UECwwER2FtZTERMA8GA1UEAwwIZWpveS5jb20xJjAkBgkqhkiG9w0BCQEWF2dhbWUuYmRAYWxpYmFiYS1pbmMuY29tMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA6x1/ieDc2pIOleHdi9xnQSZpDG2bHE6dBX75JTBIIoraykNQySFOGFUboGFyYT8hu6GL4PtsBidJOfBVqgnnO1w3J9gFxFAJQf3tB0qnMIkwVReOa8CfBfqm2CcPVM1a5cUnQ74mOM2TfIMzxBU7C+xGDW344mJqs5NvBKyWBZbTEYgfvu/mlqQtB/QLtmceQoW95mD6GDn+NDQLnCTXn0UbAlnS02Jr+ORXYOdCwaKlBP3JF3wUgwodo54P6Xcb1FDvvKvXvrpxxwPtKIj3CeppPGXgAIf9VlZsEIUIkoJZnQ1hL/5++Ge8VIgt11pdIHtkdr0Zgg+rxoSXnMzOyWfFx9SJo+V+ZvcciEjsRknGk4ga3UX1In4+7220vhEAQu/UhREbzJyJHG1UTNs1E6TtiWv+IO+5CEP6Pomp9pUBmojcfWyDGpxYGw5ZAVNdN2JFhDDd1oUsbVltcqUFCiva5vNVt+4fdqtct77GHvIIL09H/xEmCkyekQurEwPhh4bfrGTEVZiV8Io3AfiSS3JoD9T/tLavSqcZxd6AKwqLM43htorW4pcwLDJfmcWmSgs19bZwG6JQPgSbl4fRkPFWo3JR5zh5lELWq/Qjo1/nXVkLSpjgv118XW++9Q1Zpqu+w6PZ8Yf56cZoauRM18UvUHFDM+J4FtXnaH0p6U0CAwEAAaNTMFEwHQYDVR0OBBYEFMgIfK/SBQdQaJNYZeohAeBxJUNAMB8GA1UdIwQYMBaAFMgIfK/SBQdQaJNYZeohAeBxJUNAMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggIBAH47JGlEme4lR88Xz7+OyEKO2N83W3aEWxIxYrwD28718g+xfVQ6UlEY8/K9X34uNkwHy4VywFYgsAghWFPU6oYNq/3D+Gc/fqlx1ZvfnFjQqVxUuI5OqCJVyaPZwBRhzBUvNn5uLciFokcZakh1WMKEMhLYdlQ7+qYb3ZsvsXSXiC6/bdJd+G6yO/N6QcVI0Ee4nwaDf5OkBnSLjeIwbJHyCvRy972Y/nUM6Hbyy8YjkMVhE5IYbT3SbaWKHkjwAaAwucCwpNDS77r5LYHeAZqAFQdzJyeKLUntM1gXUymDUANAX0UyZzZcMa8YZ2+oImaw2lPu5SfQ027nnS0vSFT4B6M7jjIiQjIQkSPe9nUVdLvgQWZwhExosqRdrwkhyF7F3gZx1J109y7Tfp4mb7dAyMtQS7r6hRQJrO/rIu+KlZsPHG5bA7ox2N6dWjjgOYrh+PNfd6j9FJVI1d8NK1wJrOv4r/tjv9QNtMEhmpmG8qCe9FHTii8PyantAGsuHZIcXHPeb1XZsqdEyEDgZPOnJVwah52R5yF1Ske5TntuLULDfyp0iVzGHGZyvBJecmeO4viAnfBQU2b3uuuWDGuf2lPUzHW6IWCp4uLF3EmlNZ8halQWG/prK7+tdCJlXk/ZP5Wew3Ud2j9KT5ymjjwTgbsm3l5S2HEwamb45UKC'
--    local ejoy_cert_raw = _ejoysdk_crypt.base64decode(ejoy_cert_base64)
--    local cert_info = {
--        cert_raw = ejoy_cert_raw,
--        cert_name = 'ejoy_cert',
--        cert_base64 = ejoy_cert_base64
--    }
--    return cert_info
--end

do
    --local cert_info = M.get_cert_info()
    --if cert_info.cert_raw then
    --    HTTP.add_cert(
    --        cert_info.cert_name,
    --        cert_info.cert_raw,
    --        function(succ)
    --            if not succ then
    --                _ejoysdk.log('add ejoy cert fail')
    --            end
    --        end
    --    )
    --end

    -- 登陆时设置账号所在的渠道号，补充到pkg_info里
    local pkg_fill_params_function = function(user_info)
        local pkg_info = M.get_pkg_info() -- 正常会拿到user_info_manager里的一个全局变量
        local multi_regions_enabled = M.CONFIG.get_config(M.CONFIG.KEY.MULTI_REGIONS_ENABLED)
        if multi_regions_enabled then
            -- 海外的账号渠道号，三个端保持一致，都是固定值
            pkg_info.accountCh = '998236' --E.get_channel()
        else
            -- 国内三个端的账号渠道号，可以读取platform字段
            pkg_info.accountCh = user_info.platform or ''
        end
    end

    ET.subscribe(ET.gangplank.ACQUIRE, function(user_info)
        pkg_fill_params_function(user_info)
        M.log('acquire success---')
        M.log(M.get_pkg_info())
    end)

    ET.subscribe(ET.gangplank.SCAN_LOGIN, function(user_info)
        pkg_fill_params_function(user_info)
        M.log('scan_login success---')
        M.log(M.get_pkg_info())
    end)


    ET.subscribe(ET.gangplank.LOGOUT, function()
        -- 退出登陆时清除该字段
        local pkg_info = M.get_pkg_info()
        pkg_info.accountCh = ''
    end)

end

local function split_string(str, sep_opt)
    local sep, fields = sep_opt or ' ', {}
    local pattern = string.format('([^%s]+)', sep)
    string.gsub(
        str,
        pattern,
        function(c)
            fields[#fields + 1] = c
        end
    )
    return fields
end

local function insert_string(src,opt,pos)
    src = src or ''
    opt = opt or ''
    if not pos or pos <= 0 or pos > #src then
        pos = #src + 1
    end

    return src:sub(1,pos-1)..opt..src:sub(pos)
end

-- FIXME 这里没有做 encode，ejoysdk_popup_handler.lua里面有同样的方法，合并一下？
local function url_append(url,key,value)
    local append_params = '?'
    if string.find(url, '?') then
        append_params = '&'
    end

    append_params = append_params .. key .. '=' .. value

    local shell_pos = string.find(url,'#')
    return M.Utils.string_insert(url, append_params, shell_pos)
end

local function url_clipping(url)
    if not url then
        return nil
    end

    local temp = url
    if M.Utils.start_with(url, 'http://') or M.Utils.start_with(url,'file://') then
        temp = string.sub(url, 8)
    elseif M.Utils.start_with(url, 'https://') then
        temp = string.sub(url, 9)
    end

    M.LOG.debug(TAG, ', origin url = '..url)
    M.LOG.debug(TAG, ',  temp = '..temp)

    local query_index = string.find(temp, '?')
    if query_index and query_index > 0 then
        temp = string.sub(temp, 1, query_index-1)
    end

    local fragment_index = string.find(temp, '#')
    if fragment_index and fragment_index > 0 then
        temp = string.sub(temp, 1, fragment_index-1)
    end

    -- 去掉尾部的斜杆
    --if E.Utils.end_with(temp, '/') then
    --    temp = string.sub(temp, 1,-2)
    --end

    M.LOG.debug(TAG, ', origin url = '..url..', code = '..temp)

    return temp
end

local function start_with(str, start)
    return str:sub(1, #start) == start
end

local function end_with(str, suffix)
    if not str or not suffix then
        return false
    end

    return str:sub(-string.len(suffix)) == suffix
end

local function trim_start(str, start)
    if type(str) == 'string' and type(start) == 'string' then
        if #str >= #start and start_with(str, start) then
            return str:sub(#start + 1)
        end
    end

    return str
end

local function trim_end(str, end_str)
    if not end_str or not str then
        return str
    end

    local result_str = str
    if end_with(str, end_str) then
        result_str = str:sub(1, -string.len(end_str) - 1)
    end

    return result_str
end

local function trim(s)
    if type(s) == 'string' then
        return (s:gsub("^%s*(.-)%s*$", "%1"))
    else
        return s
    end
end

local function trim_chars(s, ch)
    if ch == nil then
        return s
    end

    if type(s) == 'string' then
        if ch == "." or ch == "%" then
            ch = "%" .. ch
        end

        local pattern = "^" .. tostring(ch) .. "*(.-)" .. tostring(ch).. "*$"
        return (s:gsub(pattern, "%1"))
    else
        return s
    end
end

local function table_size(data)
    local count = 0
    for _, _ in pairs(data) do
        count = count + 1
    end
    return count
end

HTTP.Header = {
    New = function(headers)
        local obj = {}
        if headers then
            for k, v in pairs(headers) do
                if type(v) == 'boolean' then
                    v = tostring(v)
                elseif type(v) ~= 'string' and type(v) ~= 'number' then
                    _ejoysdk.log('http#headers value error, type:' .. type(v) .. ', key:' .. tostring(k))
                end
                obj[k:lower()] = v
            end
        end
        return setmetatable(obj, HTTP.Header)
    end,
    __index = function(self, key)
        if key==0 or key==1 then
            return
        end
        return rawget(self, key:lower())
    end,
    __newindex = function(self, key, value)
        local v = value
        if type(v) == 'boolean' then
            v = tostring(v)
        elseif type(v) ~= 'string' and type(v) ~= 'number' then
            _ejoysdk.log('http#headers value error, type:' .. type(v) .. ', key:' .. tostring(key))
        end
        rawset(self, key:lower(), v)
    end
}

-- ejoy 现在暂时获取不了网络类型名称，例如：4g,3g等，所以这里先通过Sysinfo.network_type来猜测
--• 0 : 网络不可达，断网状态
--• 1 : Wifi网络
--• 2 : 移动数据网络
--• 3 : 未知网络状态
local function guess_network_type_name()
    local network_type = M.Sysinfo.network_type_cache()
    local network_type_name = 'unknown'
    if network_type == 1 then
        network_type_name = 'wifi'
    elseif network_type == 2 then
        network_type_name = '4g'
    end

    --M.LOG.debug(TAG, 'guess_network_type_name:'..network_type_name)
    return network_type_name
end

function HTTP.check_and_update_headers(headers)
    local ret = HTTP.Header.New(headers)

    ret['User-Agent'] = ret['User-Agent'] or M.PLATFORM.HTTP_UA
    ret['Accept-Charset'] = ret['Accept-Charset'] or 'UTF-8'
    ret['Net-Type'] = guess_network_type_name()
    ret['trace-id'] = M.get_pkg_info().utdid ..'-' .. tostring(os.time())

    --M.LOG.debug(TAG, 'check_and_update_headers headers >')
    --M.log(ret)
    return ret
end







local escape = function(str)
    str = string.gsub(str, '\n', '\r\n')
    str =
        string.gsub(
        str,
        '([^A-Za-z0-9%_%.%-%~])', -- locale independent
        function(c)
            return string.format('%%%02X', string.byte(c))
        end
    )
    str = string.gsub(str, ' ', '+')
    return str
end
HTTP.escape = escape

local function escape_pattern(text)
    return text:gsub('([^%w])', '%%%1')
end

local decode = function(str)
    str = str:gsub('+', ' ')
    return (str:gsub(
        '%%(%x%x)',
        function(c)
            return string.char(tonumber(c, 16))
        end
    ))
end


local function sort_less(a, b)
    return tostring(a) < tostring(b)
end

-- urlencode、urlencode2，以table的字段Key降序排序方式进行拼接
local urlencode2 = function(query)
    local ret = {}
    local queryKey = {}
    for k in pairs(query) do
        table.insert(queryKey, k)
    end
    table.sort(queryKey, sort_less)
    for _, k in pairs(queryKey) do
        local v = query[k]
        if type(v) == 'table' then
            -- 按照约定，二级table是数组即直接排序
            table.sort(v)
            local v_arr_str = table.concat(v, ",")
            v = v_arr_str
        end

        local val_type = type(v)
        if val_type == 'number' or val_type == 'boolean' then
            v = tostring(v)
        end
        ret[#ret + 1] = escape(k) .. '=' .. escape(v)
    end

    return table.concat(ret, '&')
end

-- urlendocde 只支持1层嵌套数组
local urlencode = function(query)
    -- 注意：table.sort 对于key-value结构的table对象没有排序作用，所以需要写自定义排序逻辑
    local ret = {}
    local queryKey = {}
    for k in pairs(query) do
        table.insert(queryKey, k)
    end
    table.sort(queryKey, sort_less)
    for _, k in pairs(queryKey) do
        local v = query[k]
        if type(v) ~= 'table' then
            v = {v}
        end
        -- 按照约定，二级table是数组即直接排序
        table.sort(v)

        for _, val in ipairs(v) do
            local val_type = type(val)
            assert(val_type ~= 'table')
            if val_type == 'number' or val_type == 'boolean' then
                val = tostring(val)
            end
            ret[#ret + 1] = escape(k) .. '=' .. escape(val)
        end
    end

    return table.concat(ret, '&')
end

HTTP.urlencode = urlencode
HTTP.urlencode2 = urlencode2

local char_to_hex = function(c)
    return string.format("%%%02X", string.byte(c))
end

local hex_to_char = function(x)
    return string.char(tonumber(x, 16))
end

local function encode_uri(uri)
    if uri == nil then
        return nil
    end
    uri = uri:gsub("([^%w%-%.%_%~%!%*%'%(%)%;%/%?%:%@%&%=%+%$%,%#])", char_to_hex)
    uri = uri:gsub(" ", "+")
    return uri
end

local function decode_uri(uri)
    if uri == nil then
        return nil
    end
    uri = uri:gsub("+", " ")
    uri = uri:gsub("%%(%x%x)", hex_to_char)
    return uri
end

--[[
参考js的encodeURI方法, encodeURI() escapes 所有的字符除了:
A–Z a–z 0–9 - _ . ! ~ * ' ( )
; / ? : @ & = + $ , #
--]]
HTTP.encode_uri = encode_uri
HTTP.decode_uri = decode_uri

-- from https://github.com/golgote/neturl
function HTTP.parse_query(str, sep)
    sep = sep or '&'

    local values = {}
    for key_str, val in str:gmatch(string.format('([^%q=]+)(=*[^%q=]*)', sep, sep)) do
        local key = decode(key_str)
        local keys = {}
        key =
            key:gsub(
            '%[([^%]]*)%]',
            function(v)
                -- extract keys between balanced brackets
                if string.find(v, '^-?%d+$') then
                    v = tonumber(v)
                else
                    v = decode(v)
                end
                table.insert(keys, v)
                return '='
            end
        )
        key = key:gsub('=+.*$', '')
        key = key:gsub('%s', '_') -- remove spaces in parameter name
        val = val:gsub('^=+', '')

        if not values[key] then
            values[key] = {}
        end
        if #keys > 0 and type(values[key]) ~= 'table' then
            values[key] = {}
        elseif #keys == 0 and type(values[key]) == 'table' then
            values[key] = decode(val)
        end

        local t = values[key]
        for i, k in ipairs(keys) do
            if type(t) ~= 'table' then
                t = {}
            end
            if k == '' then
                k = #t + 1
            end
            if not t[k] then
                t[k] = {}
            end
            if i == #keys then
                t[k] = decode(val)
            end
            t = t[k]
        end
    end
    setmetatable(values, {__tostring = HTTP.urlencode})
    return values
end

local function setAuthority(comp, authority)
    comp.authority = authority
    comp.port = nil
    comp.host = nil
    comp.userinfo = nil
    comp.user = nil
    comp.password = nil

    authority =
        authority:gsub(
        '^([^@]*)@',
        function(v)
            comp.userinfo = v
            return ''
        end
    )
    authority =
        authority:gsub(
        '^%[[^%]]+%]',
        function(v)
            -- ipv6
            comp.host = v
            return ''
        end
    )
    authority =
        authority:gsub(
        ':([^:]*)$',
        function(v)
            comp.port = tonumber(v)
            return ''
        end
    )
    if authority ~= '' and not comp.host then
        comp.host = authority:lower()
    end
    if comp.userinfo then
        local userinfo = comp.userinfo
        userinfo =
            userinfo:gsub(
            ':([^:]*)$',
            function(v)
                comp.password = v
                return ''
            end
        )
        comp.user = userinfo
    end
    return authority
end

local function setQuery(comp, query)
    comp.query = HTTP.parse_query(query)
    comp.query_ori_str = query or ''
    return query
end

function HTTP.parse(url)
    local comp = {}
    setAuthority(comp, '')
    setQuery(comp, '')

    url = tostring(url or '')
    url =
        url:gsub(
        '#(.*)$',
        function(v)
            comp.fragment = v
            return ''
        end
    )
    url =
        url:gsub(
        '^([%w][%w%+%-%.]*)%:',
        function(v)
            comp.scheme = v:lower()
            return ''
        end
    )
    url =
        url:gsub(
        '%?(.*)',
        function(v)
            setQuery(comp, v)
            return ''
        end
    )
    url =
        url:gsub(
        '^//([^/]*)',
        function(v)
            setAuthority(comp, v)
            return ''
        end
    )
    comp.path = decode(url)

    return comp
end

function HTTP.url_query(url, query)
    return url .. '?' .. urlencode(query)
end

function HTTP.uri_join(...)
    return table.concat({...}, '/')
end

local FormData = {}
FormData.__index = FormData
HTTP.FormData = FormData

function FormData.New()
    local boundary = FormData.gen_boundary()
    return setmetatable(
        {
            params = {},
            boundary = boundary
        },
        FormData
    )
end

function FormData:add_part(key, data, content_type, content_encoding, filename)
    content_type = content_type or 'application/octet-stream'

    local data_type = type(data)
    if data_type == 'table' then
        if content_type == HTTP.CT_JSON then
            data = JSON.encode(data)
        elseif content_type == HTTP.CT_URLENCODED then
            data = urlencode(data)
        end
    end
    data = tostring(data)
    content_encoding = content_encoding or 'binary'

    local params = self.params
    params[#params + 1] = {
        key = key,
        filename = filename,
        content_type = content_type,
        content_encoding = content_encoding,
        data = data
    }
end

function FormData:add_simple_part(key, data)
    local params = self.params
    params[#params + 1] = {key = key, data = data}
end

function FormData:add_file(_key, _file)
    -- 实现一个高效的文件传输方式
end

local function encode_part(r, entry)
    r[#r + 1] = string.format('content-disposition: form-data; name="%s"', entry.key)

    if entry.filename then
        r[#r + 1] = string.format('; filename="%s"', entry.filename)
    end

    if entry.content_type then
        r[#r + 1] = '\r\ncontent-type: '
        r[#r + 1] = entry.content_type
    end

    if entry.content_encoding then
        r[#r + 1] = '\r\ncontent-transfer-encoding: %s'
        r[#r + 1] = entry.content_encoding
    end
    r[#r + 1] = '\r\n\r\n'
    r[#r + 1] = entry.data
    r[#r + 1] = '\r\n'
end

function FormData:content_type()
    return 'multipart/form-data; boundary=' .. self.boundary
end

function FormData:build()
    local boundary = self.boundary
    local part = '--' .. boundary .. '\r\n'
    local r = {}

    for _, v in ipairs(self.params) do
        r[#r + 1] = part
        encode_part(r, v)
    end
    r[#r + 1] = '--' .. boundary .. '--'

    return table.concat(r)
end

function FormData.gen_boundary()
    local t = {'BOUNDARY-'}
    for i = 2, 17 do
        t[i] = string.char(math.random(65, 90))
    end
    t[18] = '-BOUNDARY'
    return table.concat(t)
end

HTTP.CT_URLENCODED = 'application/x-www-form-urlencoded'
HTTP.CT_JSON = 'application/json'
HTTP.CT_FORMDATA = 'multipart/form-data'

function HTTP.smart_content(body, content_type)
    if type(body) == 'string' then
        return body
    elseif body == nil then
        return ''
    end

    assert(type(body) == 'table')

    if content_type == HTTP.CT_JSON then
        return JSON.encode(body)
    elseif content_type == HTTP.CT_URLENCODED then
        return urlencode(body)
    --这个留着
    --[[
    elseif content_type == 'text/xml'  then
        return
    ]]
    end
    assert(false, content_type)
end



local OPENTRACING = {}
local TracerHttp
local TracerTags
local TracerContext
local TracerLink = {}
function OPENTRACING.get_tracer()
    if TracerHttp == nil then
        local ETRACER = require 'ejoysdk_lua.opentracing.ejoysdk_tracer'
        local TracerBuilder = ETRACER.TracerBuilder
        TracerHttp = TracerBuilder:New(nil, nil, 'ejoysdk'):build()
    end
    return TracerHttp
end

function OPENTRACING.get_tags()
    if TracerTags == nil then
        TracerTags = require 'ejoysdk_lua.opentracing.ejoysdk_tags'
    end
    return TracerTags
end

function OPENTRACING.get_context()
    return TracerContext
end

function OPENTRACING.set_context(context)
    TracerContext = context
end

-- 调用链上下文
function HTTP.get_span_dep(span_buz)
    return TracerLink[span_buz]
end

function HTTP.set_span_dep(span, span_buz)
    TracerLink[span_buz] = span
end

-- opentracing
-- opentracing 增加APM Vendor控制
local l_opentracing_enable
function HTTP.opentracing_enable()

    if l_opentracing_enable == nil then
        if CONFIG.has_vendor_config('APM') then
            l_opentracing_enable = true
        else
            l_opentracing_enable = false
        end
    end

    return l_opentracing_enable
end

-- 暴露是否包含apus的入口，使用缓存结果
M.has_apus_vendor = HTTP.opentracing_enable

-- opentracing 分以下步骤：
--  1. params.opentracing 启用tracing的开关 opentracing = {parent_span=parent_span, reference=reference}
--  2. request start span 
function HTTP.start_http_span(method, url, params)

    if not HTTP.opentracing_enable() then
        return nil
    end 

    local opentracing = params.opentracing
    local net_span = nil
    if opentracing and type(opentracing) == 'table' then
        -- local tracer = OPENTRACING.get_tracer_builder():New(nil, nil, 'ejoysdk'):build()
        
        -- 找到同业务span_buz的reference并加入
        if opentracing.span_buz ~= nil and opentracing.reference ~= nil then 
            local parent_span = HTTP.get_span_dep(opentracing.span_buz)
            if parent_span ~= nil and type(parent_span) == 'table' then
                net_span = OPENTRACING.get_tracer():build_span(opentracing.span_buz or method):as_child_of_span(parent_span):start()
            end
        end

        if net_span == nil then 
            -- 新增一个tracer
            net_span = OPENTRACING.get_tracer():build_span(opentracing.span_buz or method):start()
        end

        net_span:set_tag(OPENTRACING.get_tags().HTTP_URL, url)
        net_span:set_tag(OPENTRACING.get_tags().HTTP_METHOD, method)
        net_span:set_tag(OPENTRACING.get_tags().SPAN_KIND, OPENTRACING.get_tags().SPAN_KIND_CLIENT)
        
    end

    return net_span
end

HTTP.CONST_TRACE_ID_KEY = '_http_trace_id'

-- opentracing
--  3. 对Header做inject
function HTTP.inject_tracing_header(span, params)
    -- tracing header
    if not HTTP.opentracing_enable() then
        return
    end 

    if span ~= nil then
        local context = span:context()
        if context ~= nil then
            local trace_id = tostring(context:get_trace_id())

            local context_string = trace_id .. ':' .. tostring(context:get_span_id()) .. ':' .. tostring(context:get_parent_id()) ..':1'
            if params.headers ~= nil then
                params.headers[OPENTRACING.get_tags().INJECT_HTTP_HEADER] = context_string
            else 
                params.headers = {[OPENTRACING.get_tags().INJECT_HTTP_HEADER] = context_string}
            end
            params.headers[HTTP.CONST_TRACE_ID_KEY] = trace_id

            -- _ejoysdk.log("[ejoysdk]http#post#header: opentracing context_string = "..context_string)
        end
    end
    -- 还原params
    params.opentracing = nil
    return params
end

-- opentracing
--  4. response finish span
function HTTP.stop_http_span(opentracing, span, info)

    if not HTTP.opentracing_enable() then
        return
    end 

    if span ~= nil then
        span:set_tag(OPENTRACING.get_tags().HTTP_STATUS, tostring((info and info.status)) or "-1")
        span:finish_now()
        if opentracing.span_buz then
            -- 跟随关系不用覆盖dep，root和父子需要覆盖
            if opentracing.reference and opentracing.reference == OPENTRACING.get_tags().FOLLOWS_FROM then
                return
            end

            HTTP.set_span_dep(span, opentracing.span_buz)
        end
    end
end

function HTTP.http_send(http_type, url, params, content_type, _body, cb)
    _ejoysdk.log("http#" .. tostring(http_type) ..  ": url = " .. tostring(url))
    --[[
        _log_config.log_level 表示业务方希望修改日志级别
        _log_config.disable 表示业务方，不需要默认打印，业务方自己会打印，适用于resp很长的请求
    --]]

    params = params or {}

    local _log_config = params._log_config
    params._log_config = nil


    if _log_config and _log_config.disable then
        return false
    end

    local trace_id
    if params.headers and params.headers[HTTP.CONST_TRACE_ID_KEY] then
        trace_id = params.headers[HTTP.CONST_TRACE_ID_KEY]
        params.headers[HTTP.CONST_TRACE_ID_KEY] = nil
    end
    if not trace_id then
        -- 和opentracing的trace_id生成规则一致
        local guuid = require "ejoysdk_lua.ejoysdk_uuid"
        trace_id = guuid.random_i64() .. guuid.random_i64()
    end

    local content_data = {}
    content_data.url = url or ''
    content_data.trace_id = trace_id
    content_data.http_type = http_type or ''
    content_data.content_type = content_type or ''
    --content_data.params = params or {}
    --content_data.body = body or {}
    content_data.cb = cb or '_nil_cb'

    -- 日志级别，默认是debug，最低级别
    local ejoy_log = require 'ejoysdk_lua.ejoysdk_log_mgr'
    local log_level = ejoy_log.LOG_LEVEL.LOW
    if  _log_config and type(_log_config) == 'table' then
        log_level = _log_config.log_level or ejoy_log.LOG_LEVEL.LOW
    end
    -- http发送的日志，debug是肯定要打的，部分请求，可能会打info的，所以会从open_log信息里取
    ejoy_log.http_send({}, TAG, log_level, content_data, {})

    return true, trace_id, log_level
end

function HTTP.http_receive(_log_trace_id, _log_level, _url, _info)
    -- 这里的日志是多余重复的，先注释处理
    -- local content_data = {}
    -- content_data.log_trace_id = log_trace_id
    -- --content_data.info = info
    -- if _info then
    --     content_data.status = _info.status
    -- end
    -- content_data.url = url

    -- local ejoy_log = require 'ejoysdk_lua.ejoysdk_log_mgr'
    -- ejoy_log.http_receive({}, TAG, log_level, content_data, {})
end


--设置网络错误时，重新请求的域名映射
--[[
    案例：
    local params = {
        ios = {
            {
                status = -1007,
                host_map = {
                    {
                        original = 'https://p10719-user-info.qookkagames.com',
                        new = 'https://p10719-user-info-a.qookkagames.com'
                    }
                }
            }
        },
        android = {}

    }
]]
local host_map_config
function HTTP.set_http_retry_list(params)
    M.LOG.debug(TAG, 'set_http_retry_list >> ')
    M.LOG.debug(TAG, params)
    host_map_config = params
end

local function get_http_retry_url(url, status)
    local os = M.Sysinfo.os()
    if host_map_config[os] and next(host_map_config[os]) then
        for _, host_config in ipairs(host_map_config[os]) do
            local config_status = host_config.status
            local config_host_map = host_config.host_map
            if config_status == status and config_host_map then
                for _, config_host in ipairs(config_host_map) do
                    if start_with(url, config_host.original) then
                        local original_host = config_host.original
                        local retry_url = config_host.new .. string.sub(url, #original_host + 1)
                        M.LOG.debug(TAG, 'old url is '.. tostring(url) .. ', status is ' .. tostring(status) .. ', new url is ' .. tostring(retry_url))
                        return retry_url
                    end
                end
            end
        end
    end
end

-- return enable state list
local function check_http_func_enable_states(params, opts)
    opts = opts or {}
    local enable_states = {}
    -- check opentracing enable
    -- 没有opentracing信息，且enable_opentracing没有设置，则兼容之前的开启配置；如果enable_opentracing为false，则禁用
    if params.opentracing ~= nil and (opts.enable_opentracing == nil or opts.enable_opentracing == true) then
        enable_states.enable_opentracing = true
    else
        enable_states.enable_opentracing = opts.enable_opentracing
    end

    -- 检查日志开关
    if params._log_config and params._log_config.disable ~= nil then
        enable_states.disable_http_log = params._log_config.disable
    else
        enable_states.disable_http_log = opts.disable_http_log
    end

    -- 是否禁用统计打点
    enable_states.disable_http_stat = opts.disable_http_stat

    -- 是否启用断点续传
    if params.enable_download_range ~= nil then
        enable_states.enable_download_range = params.enable_download_range
    else
        enable_states.enable_download_range = opts.enable_download_range
    end

    -- 检查是否开启http dns
    if params.httpdns ~= nil then
        enable_states.enable_http_dns = params.httpdns
    elseif CONFIG.get_config('http_dns') ~= nil then
        enable_states.enable_http_dns = CONFIG.get_config('http_dns')
    else
        enable_states.enable_http_dns = opts.enable_http_dns
    end

    return enable_states
end

--[[
GET method的http 网络请求
@param url: 必传，http url
@param params: 可选，附加参数，详细描述如下：
    @param progress: 可选，function类型，进度回调，只有params.file有值时该progress才有返回。返回内容如下：
        @param url: string，链接地址
        @param file: string，文件路径，当前下载文件的路径
        @param received: number，接收到的字节数，单位字节
        @param total: number，文件总大小，单位字节

    @param finish_cb：可选，function类型，下载完成回调。只有params.file有值时该finish_cb才有回调。该回调无参数返回
    @param header_cb: 可选，function类型，接收到服务端响应的header的回调。只有params.file有值时该header_cb才有回调。返回table类型的headers 对象
    @param enable_download_range：可选，bool类型，是否启用断点续传，true: 启用断点续传，false: 不启用断点续传
    @param headers: 可选，table类型，key-value格式。http 请求的header信息
    @param checksum: 可选，字符串类型，md5校验信息
    @param file：可选，字符串类型，下载文件路径。如果设置此值则代表下载内容到该文件路径
    @param connectionTimeout 可选，整型，连接超时时间，单位毫秒，默认为20000
    @param dataRetrievalTimeout 可选，整型，读数据超时时间，单位毫秒，默认为20000
@param cb: 必传，请求回调，返回参数如下：
    @param resp，请求结果内容，包含如下字段：
        @param status http状态码，整型
        @param body http body内容，如果params.file有值（代表下载到文件），则body为空；如果params.file 为空，则body会返回内容（可用于下载到内存的场景，此时建议enable_download_range设置为false）
        @param headers json结构，服务端响应的headers
@param opts: 可选，用于控制get请求的功能
    @param enable_opentracing bool, 默认关闭，true: 开启, false: 关闭
    @param disable_http_log bool, 默认开启，true: 关闭, false: 开启
    @param disable_http_stat bool, 默认开启，true: 关闭, false: 开启
    @param enable_download_range bool, 默认关闭，true: 开启, false: 关闭
    @param enable_http_dns bool, 默认关闭，true: 开启, false: 关闭
--]]
function HTTP.get(url, params, cb, opts)
    params = params or {}

    -- retrive http functions switch states
    local switch_states = check_http_func_enable_states(params, opts)

    -- opentracing
    local net_span
    if switch_states.enable_opentracing then
        net_span = HTTP.start_http_span('GET', url, params)
        if net_span then
            HTTP.inject_tracing_header(net_span, params)
        end
    end

    -- 日志打印
    local can_log, log_trace_id, log_level
    if not switch_states.disable_http_log then
        can_log, log_trace_id, log_level = HTTP.http_send('GET', url, params, nil, nil, cb)
    end

    -- 断点续传的处理
    if switch_states.enable_download_range and params.file then
        local range_fun_name
        local _os = _ejoysdk.os()
        if _os == 'android' then
            range_fun_name = M.NATIVE_SUPPORT_FUNCTION_NAMES.HTTP_DOWNLOAD_RANGE
        elseif _os == 'ios' then
            range_fun_name = M.NATIVE_SUPPORT_FUNCTION_NAMES.HTTP_DOWNLOAD_RANGE
        else
            range_fun_name = M.NATIVE_SUPPORT_FUNCTION_NAMES.HTTP_DOWNLOAD_RANGE_V1
        end

        if M.is_support_function(range_fun_name) then
            local util = require "ejoysdk_lua.res.ejoy_http_res_utils"
            local is_exist, size = util.is_file_exists(params.file)
            _ejoysdk.log("is_file_exists is_exist:" .. tostring(is_exist) .. ", size:" .. tostring(size))
            size = tonumber(size) or 0
            if is_exist and size > 0 then
                params.headers = params.headers or {}
                params.headers['Range'] = 'bytes=' .. tostring(size) .. '-'
                -- check_and_update_headers change Range to lower case
                M.LOG.debug("process_get",' range download continue, start with size:'.. tostring(size))
            else
                M.LOG.debug("process_get",' start download new file')
            end
        end
    end

    local http_retry_callback_wrapper = function(...)
        local resp = ...
        -- 规避status非数字的情况
        local status = tonumber((resp or {}).status)
        --200到300为正常响应，不需要处理, ios旧native在网络出错情况的status可能为空
        if status == nil or (status >= 200 and status < 300) or host_map_config == nil then
            return cb(...)
        end
        local retry_url = get_http_retry_url(url, status)
        if retry_url then
            M.HTTP.get(retry_url, params, cb)
        else
            cb(...)
        end
    end

    -- 放到局部，避免循环require
    local cb_inner = http_retry_callback_wrapper
    if not switch_states.disable_http_stat then
        local QL = require "ejoysdk_lua.ejoysdk_qualitylog"
        cb_inner = QL.make_log_http_callback(url, false, params, http_retry_callback_wrapper, M.system_clock(), HTTP.opentracing_enable())
    end

    local cb_inner_log_wrapper=function(...)
        local info=...
        _ejoysdk.log("[ejoysdk]http#get#resp: url = "..url..", status = "..((info and info.status) or "-1"))

        -- opentracing finish
        if params.opentracing and net_span then
            --local info=...
            HTTP.stop_http_span(params.opentracing, net_span, info)
        end

        if can_log then
            --local info=...
            HTTP.http_receive(log_trace_id, log_level, url, info)
        end

        cb_inner(...)
    end

    -- _ejoysdk.log("[ejoysdk]http#get: url = "..url)
    if switch_states.enable_http_dns then
        return HttpDns.get(url, params, cb_inner_log_wrapper)
    else
        local HTTP_Adapter = require 'ejoysdk_lua.ejoysdk_http_adapter'
        return HTTP_Adapter.http_get_adapter_security(url, params, cb_inner_log_wrapper)
    end
end

function M.HTTP.simple_get(url, params, cb)
    local HTTP_Adapter = require 'ejoysdk_lua.ejoysdk_http_adapter'
    return HTTP_Adapter.http_get_adapter_security(url, params, cb)
end

--[[
POST method 的http请求
@param url 必传，http url
@param params 可选，附加参数信息
    @param acceptable SDK接受的content-type, 例如application/json，则cb返回的body为table类型，否则返回原始的响应内容
    @param headers 可选，table类型，key-value格式存放header信息
@param content_type 必传，字符串，同HTTP CONTENT-TYPE
@param body 可选，字节数组（对应lua的字符串类型），请求的body内容
@param cb 必传，function类型。返回table类型的object，包含信息如下：
        @param status http状态码，整型
        @param body http body内容
@param opts: 可选，用于控制get请求的功能
    @param enable_opentracing bool, 默认关闭，true: 开启, false: 关闭
    @param disable_http_log bool, 默认开启，true: 关闭, false: 开启
    @param disable_http_stat bool, 默认开启，true: 关闭, false: 开启
    @param enable_download_range bool, 默认关闭，true: 开启, false: 关闭
    @param enable_http_dns bool, 默认关闭，true: 开启, false: 关闭
--]]
function HTTP.post(url, params, content_type, body, cb, opts)
    params = params or {}

    -- retrive http functions switch states
    local switch_states = check_http_func_enable_states(params, opts)

    local opentracing
    local net_span
    if switch_states.enable_opentracing then
        opentracing = params.opentracing
        net_span = HTTP.start_http_span('POST', url, params)
        if opentracing and net_span then
            HTTP.inject_tracing_header(net_span, params)
        end
    end

    local can_log, log_trace_id, log_level
    if not switch_states.disable_http_log then
        can_log, log_trace_id, log_level = HTTP.http_send('POST', url, params, content_type, body, cb)
    end

    local http_retry_callback_wrapper = function(...)
        local resp = ...
        -- 规避status非数字的情况
        local status = tonumber((resp or {}).status)
        --200到300为正常响应，不需要处理, ios旧native在网络出错情况的status可能为空
        if status == nil or (status >= 200 and status < 300) or host_map_config == nil then
            return cb(...)
        end
        local retry_url = get_http_retry_url(url, status)
        if retry_url then
            M.HTTP.post(retry_url, params, content_type, body, cb)
        else
            cb(...)
        end
    end

    local cb_inner = http_retry_callback_wrapper
    if not switch_states.disable_http_stat then
        local QL = require "ejoysdk_lua.ejoysdk_qualitylog"
        cb_inner = QL.make_log_http_callback(url, true, params, http_retry_callback_wrapper, M.system_clock(), HTTP.opentracing_enable())
    end

    local cb_inner_log_wrapper=function(...)
        local info=...
        _ejoysdk.log("http#post#resp: url = "..url..", status = "..((info and info.status) or "-1"))

        -- opentracing finish
        if opentracing and net_span then
            -- local info=...
            HTTP.stop_http_span(opentracing, net_span, info)
        end

        if can_log then
            --local info=...
            HTTP.http_receive(log_trace_id, log_level, url, info)
        end

        cb_inner(...)
    end
    -- _ejoysdk.log("[ejoysdk]http#post: url = "..url)
    if switch_states.enable_http_dns then
        return HttpDns.post(url, params, content_type, body, cb_inner_log_wrapper)
    else
        local HTTP_Adapter = require 'ejoysdk_lua.ejoysdk_http_adapter'
        return HTTP_Adapter.http_post_adapter_security(url, params, content_type, body, cb_inner_log_wrapper)
    end
end

function M.HTTP.simple_post(url, params, content_type, body, cb, _opts)
    local HTTP_Adapter = require 'ejoysdk_lua.ejoysdk_http_adapter'
    return HTTP_Adapter.http_post_adapter_security(url, params, content_type, body, cb)
end

function HTTP.stop(_task_id_arr, params, cb)
    params = params or {}
    HTTP.process_stop(_task_id_arr, params, cb)
end


-- 使用NativeBuildFormData，确保post 存在safe_formdata字段
local NativeBuildFormData = {}
NativeBuildFormData.__index = NativeBuildFormData
function NativeBuildFormData.New()
    return setmetatable(
        {
            params = {}
        },
        NativeBuildFormData
    )
end

function NativeBuildFormData:add_file(name, file_path, content_type, filename)
    content_type = content_type or 'application/octet-stream'

    local params = self.params
    params[#params + 1] = {
        name = name,
        file_name = filename,
        content_type = content_type,
        file_path = file_path,
        type = 'file'
    }
end

function NativeBuildFormData:add_part(name, data)
    local params = self.params
    params[#params + 1] = { name = name, data = data, type = 'data' }
end

function NativeBuildFormData:get_part()
    return self.params
end

-- 传递到native的时候，不需要关心，由native实现
function NativeBuildFormData:content_type()
    return HTTP.CT_JSON
end

function NativeBuildFormData:empty_body()
    return {}
end

HTTP.NativeBuildFormData = NativeBuildFormData

local DnsCache = {}

local HttpDnsAdapter = {
    Adapter = 'Dnspod',
    Dnspod = {
        ttl = nil, -- 需要ttl改成1
        api = 'http://119.29.29.29/d'
    },
    Ejoy = {
        ttl = nil, -- 需要ttl改成1
        api = 'http://119.29.29.29'
    }
}

local function dnspod_read(data, ttl)
    local ret = {}
    local expires = nil
    if ttl then
        local entry = split_string(data, ',')
        data = entry[1]
        expires = tonumber(entry[2]) + os.time()
    end

    string.gsub(
        data,
        '[^;]+',
        function(c)
            if ttl then
                ret[#ret + 1] = {c, expires}
            else
                ret[#ret + 1] = c
            end
        end
    )

    if #ret == 0 then
        return
    end

    return ret
end

-- 这里不是很高效，因为其实很少需要这样搞的
local function dns_iterator(ips)
    if not ips then
        return function()
        end
    end

    local f, t, s = ipairs(ips)
    local now = os.time()
    local itr = function(t1, k_)
        local k, v = f(t1, k_)
        while k do
            local ip = nil
            if type(v) == 'string' then
                ip = v
            elseif v[2] <= now then
                ip = v[1]
            end
            if ip then
                return k, ip
            else
                k, v = f(t1, k)
            end
        end
    end
    return itr, t, s
end

local function make_dns_resp(ips, array)
    if array then
        local ret = {}
        for _, ip in dns_iterator(ips) do
            ret[#ret + 1] = ip
        end
        if #ret ~= 0 then
            return ret
        end
    else
        for _, ip in dns_iterator(ips) do -- luacheck: ignore
            return ip
        end
    end
    return
end

local function httpdns_update_params(params, parsed_url)
    if not params.headers then
        params.headers = {}
    end
    local host = parsed_url.host
    if parsed_url.port then
        host = host .. ':' .. parsed_url.port
    end
    params.headers['Host'] = host
end

function HttpDnsAdapter.Dnspod:gethostbyname(domain, cb)
    local params = {
        dn = domain,
        ttl = self.ttl
    }
    local url = HTTP.url_query(self.api, params)

    local HTTP_Adapter = require 'ejoysdk_lua.ejoysdk_http_adapter'
    HTTP_Adapter.http_get_adapter_security(
        url,
        {},
        function(resp)
            if resp.status == 200 then
                if resp.body and #resp.body ~= 0 then
                    return cb(dnspod_read(resp.body, self.ttl))
                end
            end
            return cb()
        end
    )
end

function HttpDnsAdapter.Dnspod:preload(domains, cb)
    local loop
    loop = function(rest, acc)
        local domain = table.remove(rest)
        if domain then
            self:gethostbyname(
                domain,
                function(ips)
                    if ips then
                        acc[domain] = ips
                    end
                    loop(rest, acc)
                end
            )
        else
            return cb(acc)
        end
    end
    loop(domains, {})
end

function HttpDnsAdapter.Ejoy:gethostbyname(domain, cb)
    local params = {
        dn = domain,
        ttl = self.ttl
    }
    local url = HTTP.url_query(self.api .. '/d', params)
    local HTTP_Adapter = require 'ejoysdk_lua.ejoysdk_http_adapter'
    HTTP_Adapter.http_get_adapter_security(
        url,
        {},
        function(resp)
            if resp.status == 200 then
                if resp.body and #resp.body ~= 0 then
                    return cb(dnspod_read(resp.body, self.ttl))
                end
            end
            return cb({})
        end
    )
end

local function ejoy_preload_read(data, _ttl)
    local ret = {}
    string.gsub(
        data,
        '[^\n]+',
        function(c)
            local entry = split_string(c, ':')
            local domain = entry[1]
            ret[domain] = dnspod_read(entry[2])
        end
    )
    return ret
end

function HttpDnsAdapter.Ejoy:preload(domains, cb)
    local params = {
        dn = domains:concat(','),
        ttl = self.ttl
    }
    local url = HTTP.url_query(self.api .. '/q', params)
    local HTTP_Adapter = require 'ejoysdk_lua.ejoysdk_http_adapter'
    HTTP_Adapter.http_get_adapter_security(
        url,
        {},
        function(resp)
            if resp.status == 200 then
                if resp.body and #resp.body ~= 0 then
                    return cb(ejoy_preload_read(resp.body, self.ttl))
                end
            end
            return cb()
        end
    )
end

function HttpDns.is_numeric(domain)
    return string.find(domain, '^%d+%.%d+%.%d+%.%d+$')
end

function HttpDns.gethostbyname(domain, cb, return_array)
    if HttpDns.is_numeric(domain) then
        return cb(domain)
    end

    local cache = make_dns_resp(DnsCache[domain], return_array)
    if cache then
        return cb(cache)
    end

    local adapter = HttpDnsAdapter[HttpDnsAdapter.Adapter]
    adapter:gethostbyname(
        domain,
        function(ips)
            if ips then
                DnsCache[domain] = ips
                return cb(make_dns_resp(ips, return_array))
            else
                return cb()
            end
        end
    )
end

function HttpDns.prepare(url, params, cb)
    params.httpdns = nil
    local parsed_url = HTTP.parse(url)
    local host = parsed_url.host
    HttpDns.gethostbyname(
        host,
        function(ip)
            if ip then
                httpdns_update_params(params, parsed_url)
                url = url:gsub(escape_pattern(host), ip, 1)
            end
            cb(url, params)
        end
    )
end

function HttpDns.get(url, params, cb)
    HttpDns.prepare(
        url,
        params,
        function(new_url, new_params)
            local HTTP_Adapter = require 'ejoysdk_lua.ejoysdk_http_adapter'
            HTTP_Adapter.http_get_adapter_security(new_url, new_params, cb)
        end
    )
end

function HttpDns.post(url, params, content_type, body, cb)
    HttpDns.prepare(
        url,
        params,
        function(new_url, new_params)
            local HTTP_Adapter = require 'ejoysdk_lua.ejoysdk_http_adapter'
            HTTP_Adapter.http_post_adapter_security(new_url, new_params, content_type, body, cb)
            --HTTP.process_post(new_url, new_params, content_type, body, cb)
        end
    )
end

function HttpDns.preload(domains, cb)
    local adapter = HttpDnsAdapter[HttpDnsAdapter.Adapter]
    adapter:preload(
        domains,
        function(ret)
            for domain, ips in pairs(ret) do
                DnsCache[domain] = ips
            end
            if cb then
                cb()
            end
        end
    )
end

-- 判断native 功能是否支持
M.NATIVE_SUPPORT_FUNCTION_NAMES = ECC.NATIVE_SUPPORT_FUNCTION_NAMES

M.Utils = {}
M.Utils.split_string = split_string
M.Utils.start_with = start_with
M.Utils.end_with = end_with
M.Utils.trim_start = trim_start
M.Utils.trim_end = trim_end
M.Utils.string_insert = insert_string
M.Utils.url_append_params = url_append
M.Utils.url_clipping = url_clipping
M.Utils.trim = trim
M.Utils.trim_chars = trim_chars
M.Utils.table_size = table_size

function M.Sysinfo.os()
    return _ejoysdk.os()
end

function M.Sysinfo.bin_version()
    if _ejoysdk.bin_version then
        return _ejoysdk.bin_version()
    else
        return '1.0.0'
    end
end

function M.Sysinfo.language_and_script()
    local lang = M.Sysinfo.language() or ''
    local script = M.Sysinfo.language_script()
    if not script or #script == 0 then
        script = E_UTILS.lang_util.get_script()
    end
    local lang_and_script
    if script and #script > 0 then
        lang_and_script = lang .. '-' .. script
    else
        lang_and_script = lang
    end
    return lang_and_script:lower()
end

local LazyKeyStore = Class:Inherit('LazyKeyStore')

function LazyKeyStore:_init(key, no_auto_save, is_json, permanent)
    self.is_json = is_json
    self.key = key
    self.value = nil
    self.auto_save = (not no_auto_save)
    if permanent == nil or permanent == true then
        self.keystore = M.KeyStore
    else
        self.keystore = M.UnRecoverKeyStore
    end
end

function LazyKeyStore:set(value)
    self.value = value
    if self.auto_save then
        self:save()
    end
end

function LazyKeyStore:save()
    local value = self.value
    if self.is_json then
        value = JSON.encode(value)
    end
    self.keystore.set(self.key, value)
end

function LazyKeyStore:get()
    if not self.value then
        self.value = self.keystore.get(self.key)
        if self.is_json and self.value then
            self.value = JSON.decode(self.value)
        end
    end
    return self.value
end

function LazyKeyStore:delete()
    self.value = nil
    self.keystore.delete(self.key)
end

M.LazyKeyStore = LazyKeyStore

-- Android : sharedpreferences, iOS : NSUserDefaults
local SPKeyStore = Class:Inherit('SPKeyStore')
-- name 参数暂时只有 Android 用到
function SPKeyStore:_init(name, key)
    self.name = name
    self.key = key
    self.keystore = M.SPRawKeyStore
end

-- set 方法可能 return false，因为依赖 native 版本支持，比如 iOS 旧的 native 版本不兼容会 return false
-- async_apply: 是否异步写入keystore, 默认为false，为写入到文件后返回。该值对应android的keystore apply，加入写队列后会立即返回，不会等待内容写入成功；
function SPKeyStore:set(value, async_apply)
    return self.keystore.set(self.name, self.key, value, async_apply)
end

function SPKeyStore:get()
    return self.keystore.get(self.name, self.key)
end

function SPKeyStore:delete()
    self.keystore.delete(self.name, self.key)
end

function SPKeyStore:is_empty()
    local value = self:get()
    if not value or #value == 0 then
        return true
    else
        return false
    end
end

M.SPKeyStore = SPKeyStore

function M.get_env_info()
    local ejoysdk_stat = require 'ejoysdk_lua.ejoysdk_stat'
    return ejoysdk_stat.env_info()
end

function M.get_pkg_info()
    return UIM.get_pkg_info()
end

-- 新增一个异步接口给PC使用
function M.async_get_pkg_info(cb)
    local result = M.get_pkg_info()
    if cb then
        cb(result)
    end
end

local function _channel_encode(channel)
    local int_arr = {}
    local channel_len = string.len(channel)
    for i = 1, channel_len do
        --获取字符ascii码值
        table.insert(int_arr, i, channel:byte(i))
    end

    local result = ''
    for i = 1, #int_arr do
        local val = int_arr[i]
        local hex_val = string.format("0x%02x", val)
        local num_hex_var = tonumber(hex_val)
        local revert_result = BitUtil.bxor(num_hex_var ,  0xFF)
        result = result .. string.format("%x", revert_result)
    end
    ejoysdk_log('channel encode origin:' .. channel .. ', result:' .. result)
    return result
end

local function _channel_decode(encode_channel)
    if encode_channel == nil or encode_channel == '' then
        ejoysdk_log("invalid encode channel, it's empty")
        return ''
    end

    local len = string.len(encode_channel)
    if (len % 2 ~= 0) then
        ejoysdk_log('invalid encode channel length')
        return ''
    end

    local decode_result = ''
    for i=1, len, 2 do
        local hex_revert_char = '0x'..string.sub(encode_channel, i, i+1)
        local num_hex_char = tonumber(hex_revert_char)
        local number_char = string.char(BitUtil.bxor(num_hex_char ,  0xFF))
        decode_result = decode_result .. number_char
    end
    ejoysdk_log('channel decode origin:' .. encode_channel .. ', result:' .. decode_result)
    return decode_result
end

local channel = nil
function M.get_channel()
    local meta_data = M.CONFIG.get_config('unisdk_meta')
    if meta_data == nil then
        -- 加载一下unisdk_meta
        local _load = require "ejoysdk_lua.vendors.unisdk"
        meta_data = M.CONFIG.get_config('unisdk_meta')
    end
    if not channel then
        channel = _channel_decode(meta_data.channel)
    end
    if not channel or '' == channel then
        local multi_regions_enabled = M.CONFIG.get_config(M.CONFIG.KEY.MULTI_REGIONS_ENABLED)
        if multi_regions_enabled then
            -- 海外的三个端(含PC)默认都是这个渠道号
            channel = '998236' -- 海外默认渠道 qookkagames
        elseif (_ejoysdk.os() == 'windows' and meta_data.channel_id) then
            -- 国内且是PC且sdkconfig里有配置，读取sdkconfig.json里的渠道号（旧版本则没有配置）
            channel = tostring(meta_data.channel_id)
        elseif (M.Sysinfo.ds_channel_id) then
            -- 取默认的
            channel = M.Sysinfo.ds_channel_id()
        end
    end


    return channel
end

local apk_build_seq = nil
function M.get_apk_build_seq()
    if not apk_build_seq then
        local meta_data = M.CONFIG.get_config('unisdk_meta')
        if meta_data ~= nil then 
            apk_build_seq = meta_data.apk_build_seq
        else 
            M.LOG.debug(TAG, "meta_data is nil")
        end
    end
    return apk_build_seq or ''
end

-- 阶段ID,代表游戏所属阶段(如pbt1, pbt2, cbt1)的ID值,由数据基础平台维护
local ptid = nil
function M.get_ptid()
    if not ptid then
        local meta_data = M.CONFIG.get_config('unisdk_meta')
        if meta_data ~= nil then
            ptid = meta_data.ptid
        else
            M.LOG.debug(TAG, 'meta_data is nil')
        end
    end
    return ptid or ""
end

function M.get_meta_config(key)
    if key == nil or key == '' then
        M.LOG.debug(TAG, "get_meta_config failed for key is nil")
        return nil
    end

    local cache_value = meta_values_cache[key]
    if cache_value ~= nil then
        return cache_value
    end

    local meta_data = M.CONFIG.get_config('unisdk_meta')
    local value = meta_data[key]
    if value ~= nil then
        meta_data[key] = value
        meta_values_cache[key] = value
    end

    return value
end

function M.get_game_id()
    local game_id = M.get_meta_config(M.META_CONFIG_KEY.GAME_ID)

    if game_id ~= nil then
        M.log('get_game_id:' .. game_id)
    else
        ejoysdk_log('get_game_id return nil!')
    end
    return game_id
end

function M.get_parent_pkg_id()
    local parent_pkg_id = M.get_meta_config(M.META_CONFIG_KEY.PARENT_PKG_ID)

    if parent_pkg_id ~= nil then
        ejoysdk_log('get_parent_pkg_id:' .. parent_pkg_id)
    else
        ejoysdk_log('get_parent_pkg_id return nil!')
    end
    return parent_pkg_id
end

function M.get_parent_pkg_record_id()
    local parent_pkg_record_id = M.get_meta_config(M.META_CONFIG_KEY.PARENT_PKG_RECORD_ID)

    if parent_pkg_record_id ~= nil then
        ejoysdk_log('get_parent_pkg_record_id:' .. parent_pkg_record_id)
    else
        ejoysdk_log('get_parent_pkg_record_id return nil!')
    end
    return parent_pkg_record_id
end

local sdk_version_name_cache = {}
function M.get_sdk_version_name(sdk_name)
    if sdk_version_name_cache[sdk_name] == nil then
        sdk_version_name_cache[sdk_name] = M.Sdkinfo.getSDKVersionName(sdk_name)
    end
    -- ejoysdk_log('ejoysdk>> get_sdk_version_name sdkname:' .. sdk_name .. ', ver:' .. sdk_version_name_cache[sdk_name])
    return sdk_version_name_cache[sdk_name]
end

local cn_channel_version = nil
function M.get_cn_channel_version()
    if not cn_channel_version then
        cn_channel_version = tostring(M.Sysinfo.manifest_meta_data('string', 'cn.gosdk.channelVer'))
    end
    ejoysdk_log('cn_channel_version: ' .. tostring(cn_channel_version))
    return cn_channel_version
end

local display_sdk_infos = nil
function M.get_display_sdk_infos()
    if not display_sdk_infos then
        local uni = require "ejoysdk_lua.vendors.unisdk"
        display_sdk_infos = uni.get_sdk_infos() or {}
    end
    return E_UTILS.deepcopy(display_sdk_infos)
end

-- 这里有个坑， 现在没法获得毫秒信息，等支持了再做高精度
-- set_time_diff 不要随便调用
local time_diff = 0
function M.set_time_diff(diff)
    _ejoysdk.log('update time diff: ' .. tostring(diff))
    diff = diff - diff % 1
    time_diff = diff
end

-- 获取当前服务器时间
function M.time()
    return os.time() + time_diff
end

local sync_server_ms = 0
local sync_clock = 0
local _flag_sync_sever_time = false
function M.set_server_ms(server_ms)
    -- _ejoysdk.log('update sync_server_ms: ' .. tostring(server_ms))
    sync_server_ms = server_ms
    -- windows的system_clock实现有问题，实现是获取时间戳，不是获取cpu clock，如果改了本地时间，计算的就不准了
    if _ejoysdk.os() == 'windows' then
        local active_time_clock = os.clock()
        if active_time_clock > 0 then
            sync_clock = active_time_clock
        end
    else
        sync_clock = M.system_clock()
    end
    _flag_sync_sever_time = true
end
-- 是否同步过服务器时间标记
function M.did_sync_sever_time()
    return _flag_sync_sever_time
end

-- 精确到millisecond的服务器时间，10^-3
function M.time_ms()
    if sync_server_ms == 0 or sync_clock == 0 then
        return 0
    end
    -- windows的system_clock实现问题兼容
    if _ejoysdk.os() == 'windows' then
        local active_time_clock = os.clock()
        if active_time_clock > 0 and sync_clock > 0 then
            return math.floor(sync_server_ms + (active_time_clock - sync_clock) * 1000)
        else
            return 0
        end 
    end
    
    return math.floor(sync_server_ms + M.system_clock() - sync_clock)
end

-- 获取一个进程相关的相对时间,单位毫秒
-- 注意：这里system_clock下方会被兼容做替换
function M.system_clock()
    return os.time() * 1000
end

function M.system_ms()
    if _ejoysdk.system_ms then 
        return math.floor(_ejoysdk.system_ms())
    else 
        -- 旧版system_ms没实现的使用系统秒级时间兼容
        return os.time() * 1000
    end
end

-- 日志
-- 保证调用方入口一致
M.LOG = ELOG.LOG
M.LOG_LEVEL = ELOG.LOG_LEVEL
M.LOG_STYLE = ELOG.LOG_STYLE
M.open_log = ELOG.open_log
M.is_log_open = ELOG.is_log_open
M.set_log_level = ELOG.set_log_level
M.get_log_level = ELOG.get_log_level
-- Tag 过滤器
M.open_log_block = ELOG.open_log_block
M.is_block_tag = ELOG.is_block_tag
M.add_block_tags = ELOG.add_block_tags
M.del_block_tags = ELOG.del_block_tags
M.get_block_tags = ELOG.get_block_tags
M.open_log_with_config = ELOG.open_log_with_config
M.open_log_from_cc = ELOG.open_log_from_cc
M.set_white_modules = ELOG.set_white_modules
M.get_white_modules = ELOG.get_white_modules
-- 打印日志长度限制
M.set_log_length_limit = ELOG.set_log_length_limit
M.set_log_max_length = ELOG.set_log_max_length

M.log = ELOG.log

if _ejoysdk.os() == "ios" then
    -- NOTICE: ios 2.0.20 至 2.0.22 版本的 system_clock native 实现，在 ios 9.x 及以前的版本会崩溃
    -- 为了保持代码兼容，ios 修复后的方法改名为 system_clock2
    if _ejoysdk.system_clock2 then
        M.system_clock = _ejoysdk.system_clock2
    end
else
    if _ejoysdk.system_clock then
        M.system_clock = _ejoysdk.system_clock
    end
end

-- 接口描述：简单的open webview封装，startup data包含pkg_info，ejoysdk版本等基本信息
-- 参数描述：
-- @param url, string类型，网页地址
-- @param hosts, string数组，域名白名单，默认包含:.aligames.com, .lingxigames.com, .ejoy.com
-- @param params, table, startupData参数，JS可以通过getStartupData获取;
-- @param screen_orientation, string, 屏幕方向设置，默认不传跟随游戏屏幕方向. 可选值：sensor: 重力感应(旧版是 all)，landscape: 强制横屏，portrait: 强制竖屏，不传：跟随应用程序的朝向
-- @param on_js_callback, function, js调用响应函数
-- @param on_close_callback, function, webview关闭回调
function M.open_webview(url, hosts, params, screen_orientation, on_js_callback, on_close_callback)
    M.LOG.debug(TAG, 'open_webview, url:'..(url or 'nil'))
    local WEB = require "ejoysdk_lua.ejoysdk_web"
    WEB.open_webview(url, hosts, params, screen_orientation, on_js_callback, on_close_callback)
end

-- 接口描述：简单的open webview封装，startup data包含pkg_info，ejoysdk版本等基本信息
-- 参数描述：
-- @param url, string类型，网页地址
-- @param hosts, string数组，域名白名单，默认包含:.aligames.com, .lingxigames.com, .ejoy.com
-- @param params, table, startupData参数，JS可以通过getStartupData获取;
-- @param options, table, options可选参数如下
--[[
● compactMode: bool，是否显示Webview 边框，默认为true
● closeEventData: string, 当这个Webview关闭时，会把这个字符串透传回lua
● screen_orientation: string, 指定 Webview 的朝向
    ■ sensor: 重力感应(旧版是 all)
    ■ landscape: 强制横屏
    ■ portrait: 强制竖屏
    ■ 不传：跟随应用程序的朝向
● use_fragment：bool，默认为true. Android平台属性，是否使用Fragment容器，默认false使用Activity容器满足横竖屏需求。注：这种情况js无法调用lua接口，因为触发Activity导致游戏Lua主线程暂停。
● hide_close_btn: 默认为展示关闭按钮。是否不显示关闭按钮，默认为false（显示），如果页面5秒内打不开，则还是会显示关闭按钮
● enable_toolbar: bool, 是否启用工具栏
● toolbar_theme: string, 工具栏样式主题，sdk内置light和dark两套主题
]]
-- @param on_js_callback, function, js调用响应函数
-- @param on_close_callback, function, webview关闭回调
function M.open_webview_with_options(url, hosts, params, options, on_js_callback, on_close_callback)
    M.LOG.debug(TAG, 'open_webview, url:'..(url or 'nil'))
    local WEB = require "ejoysdk_lua.ejoysdk_web"
    WEB.open_webview_with_options(url, hosts, params, options, on_js_callback, on_close_callback)
end

function M.capture_webview(callback)
    local WEB = require "ejoysdk_lua.ejoysdk_web"
    WEB.capture_webview(callback)
end

function M.loadstring(lua_script)
    if lua_script and ''~=lua_script then
        M.log("doscript: "..lua_script)
        local func, syntaxError = load(lua_script, 'ejoysdk.loadstring', 'bt')
        if(func)then
            local status,err=pcall(func)
            if not status then
                M.LOG.debug(TAG,"run script status: "..tostring(status)..", err: "..(err or ''))
            end
        else
            M.LOG.debug(TAG,"loadstring fail: "..(syntaxError or 'nil'))
        end
    end
end

-- 杀掉当前游戏进程
function M.kill_game_process()
    -- exit crashsdk
    local crash_sdk = require "ejoysdk_lua.vendors.crashsdk"
    crash_sdk.exit()

    -- exit process
    M.kill_app()

end

function M.Permission.permission_default_description(permission_list)
    local default_desc = M.Permission.get_default_desc()
    local title = ''
    local desc = ''
    local i = 1
    local util = require 'ejoysdk_lua.ejoysdk_utils'
    local length = util.tablelength(permission_list)

    for p,d in pairs(permission_list) do
        local p_info = d
        if not p_info or not next(p_info) then
            p_info = default_desc[p or '']
        end

        if p_info then
            if title and #title>0 then title=title..'、' end -- TODO 多语言时需要考虑分隔符
            title = title .. (p_info[1] or '')
            if p_info[2] and ''~=p_info[2] then
                if length > 1 then
                    desc = desc .. i..'. '
                end
                desc = desc .. (p_info[2] or '') .. '\n'

                i = i + 1
            end
        end
    end
    return title,desc
end

--多语言文案获取规则
--1、根据游戏设置的lang获取
--2、1获取不到，则根据publish_area获取对应的lang获取
--3、使用zh-hans兜底
function M.Permission.get_default_desc()
    if _ejoysdk.os then
        local os =  _ejoysdk.os()
        local default_lang = 'zh-hans'

        local langKey = M.CONFIG.get_config('lang'):lower() or ""
        local succ, desc_consts = pcall(function()
            return require('ejoysdk_lua.consts.permissions.'..langKey)
        end)

        if not succ or not desc_consts then
            local area_lang = require "ejoysdk_lua.lang.area_default_lang"
            local publish_area = M.CONFIG.get_config(M.CONFIG.KEY.PUBLISH_AREA) or ""
            local area_lang_key = area_lang[publish_area] or ''
            succ, desc_consts = pcall(function()
                return require('ejoysdk_lua.consts.permissions.'..area_lang_key)
            end)
        end

        if not succ or not desc_consts then
            desc_consts = require('ejoysdk_lua.consts.permissions.'..default_lang)
        end

        return desc_consts[os or '']
    end
    return {}
end

function M.Permission.get_desc(permission)
    if not permission or '' == permission then
        return {}
    end

    local permission_list = M.Permission.get_default_desc()
    if permission_list then
        return permission_list[permission] or {}
    end

    return {}
end

function M.Permission.async_get_desc(permission, cb)
    if cb then
        cb(M.Permission.get_desc(permission))
    end
end

-- 撤消授权弹窗,可以在options下设置permissions,格式如下
-- options={permissions={["权限名1"]={类型,用途说明},["权限名2"]={类别,用途说明},...}}
-- 有三种设置方法:
-- 1. permissions为空：SDK会自动读取当前包里包含的权限声明，并展示SDK定义的权限用途说明
-- 2. permissions权限不为空，用途说明为空：SDK会匹配内部定义的权限用途说明展示
-- 3. permissions权限名与用途都不为空：按传入内容显示 -- TODO 两个权限是同一类别的
function M.Permission.setting_dialog(title,options)
    options = options or {}

    local permission_list = options.permissions

    local default_desc = M.Permission.get_default_desc()
    if permission_list then
        -- 兼容情况2
        for k,v in pairs(permission_list) do
            if k and not v and default_desc[k] then
                permission_list[k] = default_desc[k]
            end
        end
    elseif not permission_list or #permission_list<=0 then
        -- 没传入列表,使用包声明列表
        permission_list = {}
        local requested_permissions = M.Permission.get_requested_permissions()
        if requested_permissions and requested_permissions.value and #(requested_permissions.value)>0 then
            for _,req_permission in pairs(requested_permissions.value) do
                permission_list[req_permission] = default_desc[req_permission]
            end
        else
            permission_list = default_desc
        end
    end

    local category_list = {}
    for req_permission,desc_array in pairs(permission_list) do
        if desc_array and #desc_array >=2 then
            local category = desc_array[1]
            local description = desc_array[2]

            local permission_info = category_list[category or ''] or {}
            local desc = permission_info['desc']
            if desc and '' ~= desc then desc=desc..'\n' end
            permission_info['desc'] = (desc or '') .. description
            permission_info['category'] = category
            permission_info['permissions'] = permission_info['permissions'] or {}
            table.insert(permission_info['permissions'],req_permission)
            category_list[category]= permission_info
        end
    end

    permission_list = {}
    for _, v in pairs(category_list) do
        table.insert(permission_list,v)
    end

    options.permissions = permission_list
    options['style']='setting'
    options['text']={
        authorized = LANG.getString("has_authorized","已授权"),
        unauthorized = LANG.getString("to_settings_page","前往设置>")
    }

    M.Modal.open(title,options)
end

-- 自动保存, 保存的是一个版本号, 且该值清除数据和卸载会消失
local LAST_APP_VERSION_NAME = M.LazyKeyStore:New("EJOY_LAST_APP_VERSION_NAME", false, false, false)
local is_override_install = nil
-- 是否是覆盖安装启动
function M.is_override_install_startup()
    if is_override_install ~= nil then
        _ejoysdk.log(TAG .. "#is_override_install_startup cached: " .. tostring(is_override_install))
        return is_override_install
    end

    -- current app version_name
    local app_version_name = M.Sysinfo.app_version_name()
    local last_app_version_name = LAST_APP_VERSION_NAME:get()
    -- update current app_version_name
    LAST_APP_VERSION_NAME:set(app_version_name)
    if last_app_version_name ~= app_version_name then
        _ejoysdk.log(TAG .. "#is_override_install result true, last_app_version_name:" .. tostring(last_app_version_name) .. ", cur app_version_name:" .. tostring(app_version_name))
        is_override_install = true
    else
        _ejoysdk.log(TAG .. "#app_version_name is same")
        is_override_install = false
    end

    _ejoysdk.log(TAG .. "#is_override_install_startup: " .. tostring(is_override_install))
    return is_override_install
end

-- 是否扫码包标识
local ej_scan_pkg
function M.is_scan_pkg()
    -- 从sdkconfig获取扫码包标识
    if ej_scan_pkg == nil then
        ej_scan_pkg = CONFIG.has_vendor_config('EJOY_SCAN') or false
    end
    
    return ej_scan_pkg
end

-- 存储多vm情况的native回调urldata数据
local SDK_URL_OPEN_DATAS
function M.get_url_data_keystore()
    if SDK_URL_OPEN_DATAS == nil then
        SDK_URL_OPEN_DATAS = M.LazyKeyStore:New("SDK_URL_OPEN_DATAS", false, true, false)
    end
    return SDK_URL_OPEN_DATAS
end


local PRE_ORDER_ITEMS = M.LazyKeyStore:New("EJOY_PRE_ORDER_ITEMS", false, true, false)
function M.get_pre_order_status(cb)
    cb = cb or function()  end

    local request_pre_order_status = function(platform,items,cb2)
        local USER = require 'ejoysdk_lua.user_center.usercenter_api'
        USER.get_pre_order_status(platform,items, function(succ2,...)
            if succ2 == true then
                local data = ...
                cb2(true, data and next(data) and data.isReserveUser or false)
            else
                --请求失败，下次再来
                cb2(false)
            end
        end)
    end

    local save_items = PRE_ORDER_ITEMS:get()
    if save_items and next(save_items) then
        request_pre_order_status(save_items.platform,save_items.items,cb)
    else
        M.get_pre_order_items(function(succ, platform, ...)
            if succ == true then
                local items = ...
                local item_cache = {
                    platform = platform,
                    items = items
                }
                if  not items or not next(items) then
                    -- 获取成功，但列表为空，不请求服务器,非预约用户
                    item_cache.items = {}
                    M.LOG.debug(TAG,"get pre-order status succ: purchase items empty")
                    cb(true, false)
                else
                    request_pre_order_status(platform,items,cb)
                end
                -- 缓存商品列表或票据，防止请求失败
                PRE_ORDER_ITEMS:set(item_cache)
            else
                local code,msg = ...
                M.LOG.debug(TAG,"get pre-order status fail: "..tostring(code or '-1')..', msg: '..(msg or ''))
                -- 当请求失败处理
                cb(false)
            end
        end)
    end
end

function M.save_image_to_album(params,cb)
    params = params or {}

    local callback = function(succ,code,msg)
        if not cb then return end

        if succ == true then
            cb(succ)
        else
            cb(succ,{code = code ,msg = msg})
        end
    end

    if _ejoysdk.os() == 'windows' then
        callback(false,{code = -1, msg = 'not support'})
        return
    end

    if (params.type ~= 'url' and params.type ~= 'base64') or type(params.data) ~= 'string' or params.data == '' then
        callback(false,{code = -2, msg = 'invalid params'})
        return
    end

    local save_to_album = function(image_path)
        if type(image_path)=='string' and image_path ~= '' then
            M.save_to_album(image_path,true,function(ret)
                if ret and ret.code == 1 then
                    callback(true)
                else
                    callback(false,-8,'save albums failed')
                end
            end)
        else
            callback (false,-4, "save file failed,invalid file path")
        end
    end

    local image_file_name = (os.time() * 1000 + math.random(1, 1000))
    if (params.type == 'url') then
        local EMM = require "ejoysdk_lua.res.ejoy_res_model_factory"
        local http_image_download = EMM.get_http_res_model("image_downloader")

        local file_ext = {
            name = image_file_name
        }

        local DM = require "ejoysdk_lua.res.model.ejoy_http_download_model"
        local task ,err_code,err_msg = http_image_download:create_task(params.data,file_ext,nil,function(_state,_state_obj)
            if _state == DM.DOWNLOAD_STATE.COMPLETE then
                --下载成功
                save_to_album(_state_obj.file_path)
            elseif(_state ~= DM.DOWNLOAD_STATE.DOWNLOADING)then
                -- 下载失败
                callback (false,-4, "download fail, code:"..tostring(_state_obj.err_code)..',msg:'..tostring(_state_obj.err_msg))
            end
        end)

        if task then
            task:start_download()
        else
            callback (false,-4, "download fail, code:"..tostring(err_code)..',msg:'..tostring(err_msg))
        end
    elseif (params.type == 'base64') then
        -- local save_path = M.File.get_ext_file_dir() .. '/' .. image_file_name
        local succ, save_path = M.File.writefile(image_file_name,params.data,false,true)
        if succ == true then
            -- 写出成功
            save_to_album(save_path)
        else
            callback (false,-4, "save file failed")
        end
    end
end

-- 静态的系统参数
-- 该接口平台内部使用，项目组勿接
-- 是系统参数里，一些恒定不变的参数，调用1次即可
function M.Sysinfo.async_get_static_params(cb)
    local env_info = M.get_env_info()

    local ret = {}

    ret.res = env_info.devInfo.res or ""  -- 分辨率
    ret.os = M.Sysinfo.os()
    ret.os_ver = M.Sysinfo.os_version()
    ret.cpu_model = M.Sysinfo.get_cpu_model() or ""
    ret.device = M.Sysinfo.brand() .. " " .. M.Sysinfo.model()  -- 机型

    local HOLO = require 'ejoysdk_lua.ejoysdk_holo'
    HOLO.get_device_score(function(succ, ...)
        if succ then
            local score = ...
            ret.cpu_score = score.cpu
            ret.gpu_score = score.gpu
        else
            ret.cpu_score = ""
            ret.gpu_score = ""
        end

        if cb then
            cb(ret)
        end
    end)
end

-- 动态的系统参数
-- 该接口平台内部使用，项目组勿接
-- 每次调用，会动态计算，调用频率不宜过高
function M.Sysinfo.async_get_dynamic_params(cb)

    local cpu = nil
    local cpu_total = nil
    local memory = nil
    local rss_mem = nil
    local temperature = nil  -- 电池温度
    local voltage = nil  -- 电压
    local run_time = nil -- 程序运行时间
    local total_phys = nil
    if M.Sysinfo.memory_info().TotalPhys then
        total_phys = M.Sysinfo.memory_info().TotalPhys / 1024  -- 这个应该是静态参数，但内存相关的参数，都放这了，方便查看
    end
    local total_virtual = nil
    if M.Sysinfo.memory_info().TotalVirtual then
        total_virtual = M.Sysinfo.memory_info().TotalVirtual / 1024 -- 这个应该是静态参数，但内存相关的参数，都放这了，方便查看
    end
    local avail_phys = nil
    if M.Sysinfo.memory_info().AvailPhys then
        avail_phys = M.Sysinfo.memory_info().AvailPhys / 1024
    end
    local avail_virtual = nil
    if M.Sysinfo.memory_info().AvailVirtual then
        avail_virtual = M.Sysinfo.memory_info().AvailVirtual / 1024
    end
    local total_page_file = nil
    if M.Sysinfo.memory_info().TotalPageFile then
        total_page_file = M.Sysinfo.memory_info().TotalPageFile / 1024 -- 这个应该是静态参数，但内存相关的参数，都放这了，方便查看
    end
    local avail_page_file = nil
    if M.Sysinfo.memory_info().AvailPageFile then
        avail_page_file = M.Sysinfo.memory_info().AvailPageFile / 1024
    end
    local avail_extended_virtual = nil
    if M.Sysinfo.memory_info().AvailExtendedVirtual then
        avail_extended_virtual = M.Sysinfo.memory_info().AvailExtendedVirtual / 1024
    end

    local gpu_infos = {}  -- 数组
    local storage_info = nil -- 移动端的存储信息
    local disk_info_list= nil -- PC端的存储信息
    local network = nil

    local device_info_filter = {"cpu", "memory"}
    local battery_ext_filter = {"temperature", "voltage"}

    local async_return_count = 0
    local total_async_return_count
    if M.Sysinfo.os() == 'android' then
        total_async_return_count = 6     -- 安卓端有6项:电池、CPU+内存(一起)、运行时间、GPU、get_storage_info、网络类型
    elseif M.Sysinfo.os() == 'ios' then
        total_async_return_count = 4     -- ios端有4项:CPU+内存(一起)、运行时间、get_storage_info、网络类型
    else
        total_async_return_count = 5     -- PC端有5项:CPU+内存(一起)、运行时间、GPU、disk_info、网络类型
    end

    local network_name
    if M.Sysinfo.os() == 'windows' then
        network_name = {
            [-1] = "unsupport",
            [0] = "default",
            [1] = "unknown", --无网络或者未知网络类型
            [2] = "wifi",  -- 无线网络
            [3] = "wired"  -- 有线网络
        }
    else
        network_name = {
            [0] = "default",
            [1] = "unknown", --未知网络类型，例如6G出来，老版本SDK不识别
            [2] = "wifi",
            [3] = "2G",
            [4] = "3G",
            [5] = "4G",
            [6] = "5G"
        }
    end

    local function final_exe_callback()
        if async_return_count < total_async_return_count then
            return
        end

        if cb then
            local ret = {
                cpu = cpu,
                cpu_total = cpu_total,
                mem = memory,
                rss_mem = rss_mem,
                lua_mem = math.floor(collectgarbage("count") / 1024 + 0.5), -- MB
                temperature = temperature or '',
                voltage = voltage or '',
                runtime = run_time,
                mem_total_phys = total_phys or "",
                mem_total_virtual = total_virtual or "",
                mem_avail_phys = avail_phys or "",
                mem_avail_virtual = avail_virtual or "",
                mem_total_page_file = total_page_file or "",
                mem_avail_page_file = avail_page_file or "",
                mem_avail_extended_virtual = avail_extended_virtual or ""
            }

            if network then
                ret.network = network_name[network] or ""
            else
                ret.network = ""
            end

            local index = 1
            for _, gpu_info in pairs(gpu_infos) do
                ret['gpu' .. tostring(index)] = tostring(gpu_info.vendor) .. ' ' .. tostring(gpu_info.model)
                if gpu_info.memory then
                    ret['gpu' .. tostring(index) .. '_memory'] = gpu_info.memory / 1024
                else
                    ret['gpu' .. tostring(index) .. '_memory'] = ''
                end
                ret['gpu' .. tostring(index) .. '_driver_version'] = gpu_info.driver_version or ''
                ret['gpu' .. tostring(index) .. '_availability'] = gpu_info.availability or ''
            end

            if M.Sysinfo.os() == 'windows' then
                if disk_info_list then
                    for _, v in pairs(disk_info_list) do
                        if v.total_size then
                            ret['storage_info_' .. tostring(v.disk_symbol) .. '_total_size'] = v.total_size / 1024
                        else
                            ret['storage_info_' .. tostring(v.disk_symbol) .. '_total_size'] = ''
                        end

                        if v.free_size then
                            ret['storage_info_' .. tostring(v.disk_symbol) .. '_available_size'] = v.free_size / 1024
                        else
                            ret['storage_info_' .. tostring(v.disk_symbol) .. '_available_size'] = ''
                        end

                        if v.free_to_caller_size then
                            ret['storage_info_' .. tostring(v.disk_symbol) .. '_available_to_caller_size'] = v.free_to_caller_size / 1024
                        else
                            ret['storage_info_' .. tostring(v.disk_symbol) .. '_available_to_caller_size'] = ''
                        end
                    end
                end
            else
                if storage_info and storage_info.internal_total_storage_size  then
                    ret['storage_info_internal_total_size'] = storage_info.internal_total_storage_size / 1024
                else
                    ret['storage_info_internal_total_size'] = ''
                end

                if storage_info and storage_info.internal_available_storage_size then
                    ret['storage_info_internal_available_size'] = storage_info.internal_available_storage_size / 1024
                else
                    ret['storage_info_internal_available_size'] = ''
                end

                if storage_info and storage_info.external_total_storage_size then
                    ret['storage_info_external_total_size'] = storage_info.external_total_storage_size / 1024
                else
                    ret['storage_info_external_total_size'] = ''
                end

                if storage_info and storage_info.external_available_storage_size then
                    ret['storage_info_external_available_size'] = storage_info.external_available_storage_size / 1024
                else
                    ret['storage_info_external_available_size'] = ''
                end
            end

            cb(ret)
        end
    end

    -- 这是一个异步调用，执行完时已经完成了stats收集，因此只是记录上次异步执行的结果
    -- 如果要优化，需要Stats提供异步接口，改动稍大
    M.Sysinfo.device_info(
            device_info_filter,
            function(ok, result)
                if ok and type(result) == "table" then
                    -- 电量信息需要结合充电状态，没想好怎么使用，暂不上报
                    -- battery = result.battery.level
                    -- E.LOG.debug("apm_test", result)
                    if type(result.cpu) == "table" then
                        cpu = result.cpu.usage_solaris_mode -- 归一的cpu使用率
                        cpu_total = result.cpu.usage -- 多核的总cpu使用率
                    end
                    -- 某些情况下result.memory 是一个number类型， 做一下保护
                    if type(result.memory) ~= "table" then
                        async_return_count = async_return_count + 1
                        final_exe_callback()
                        return
                    end
                    -- android提供进程的PSS（非共享内存+分摊的共享内存），ios目前只能提供系统的内存占用（TODO）
                    -- 某些低端机型或低系统版本获取不到 result.memory.appPSS, 或者存在溢出的情况，都需要过滤掉
                    if result.memory.appPSS and result.memory.appPSS > 0 then
                        memory = result.memory.appPSS / 1024 -- 转 kB
                    end

                    if result.memory.VmRSS and result.memory.VmRSS > 0 then
                        rss_mem = result.memory.VmRSS / 1024 -- 转 kB
                    end

                    async_return_count = async_return_count + 1
                    final_exe_callback()
                else
                    cpu = nil
                    cpu_total = nil
                    memory = nil
                    rss_mem = nil

                    async_return_count = async_return_count + 1
                    final_exe_callback()
                end
            end
    )

    if M.Sysinfo.os() == 'android' then
        -- 异步获取当前电池额外的信息
        M.Sysinfo.battery_ext(
                battery_ext_filter,
                function(ret)
                    if not ret then
                        async_return_count = async_return_count + 1
                        final_exe_callback()
                        return
                    end
                    if ret.temperature and ret.temperature >= 0 then
                        temperature = ret.temperature
                    end
                    if ret.voltage and ret.voltage >= 0 then
                        voltage = ret.voltage
                    end

                    async_return_count = async_return_count + 1
                    final_exe_callback()
                end
        )
    end

    local function get_run_time()
        -- 非windows系统 直接用同步获取的方式
        if M.Sysinfo.os() ~= 'windows' then
            run_time = math.floor(M.Sysinfo.run_time() / 1000) -- app运行时间，单位为秒

            async_return_count = async_return_count + 1
            final_exe_callback()
            return
        end

        -- windows系统 使用异步获取的方式
        M.Sysinfo.run_time_async(
                function(ret)
                    if ret and ret.succ then
                        -- run_time是运行时长，单位毫秒
                        run_time = math.floor(ret.run_time / 1000)
                    end

                    async_return_count = async_return_count + 1
                    final_exe_callback()
                end
        )
    end

    get_run_time()

    local function get_gpu_info()
        if M.Sysinfo.os() == 'ios' then
            return
        end

        M.Sysinfo.get_gpu_info(function (ret)
            if M.Sysinfo.os() == 'android' then
                local gpu_info = {
                    ['model']=ret.model,
                    ['vendor']=ret.vendor,
                    ['driver_version']=ret.version,
                    ['memory']=0,
                    ['availability']=''
                }
                table.insert(gpu_infos, gpu_info)
            elseif M.Sysinfo.os() == 'windows' then
                if ret and ret.succ and ret.gpus then
                    for _, item in pairs(ret.gpus) do
                        local gpu_info = {
                            ['model']=item.model,
                            ['vendor']=item.vendor,
                            ['driver_version']=item.driver_version,
                            ['memory']=item.memory / 1024,  -- kB
                            ['availability']=item.availability
                        }
                        table.insert(gpu_infos, gpu_info)
                    end
                end
            end

            async_return_count = async_return_count + 1
            final_exe_callback()
        end)
    end

    get_gpu_info()

    local function get_storage_info()
        if M.Sysinfo.os() == 'android' then
            storage_info = M.Sysinfo.get_storage_info()
            async_return_count = async_return_count + 1
            final_exe_callback()
        elseif M.Sysinfo.os() == 'ios' then
            storage_info = M.Sysinfo.get_storage_info()
            async_return_count = async_return_count + 1
            final_exe_callback()
        else
            M.Sysinfo.get_disk_info_async(function (succ, ...)
                if succ then
                    disk_info_list = ...
                else
                    local _code, _msg = ...
                    disk_info_list = nil
                end
                async_return_count = async_return_count + 1
                final_exe_callback()
            end)
        end
    end

    get_storage_info()

    local function get_network_type()
        M.Sysinfo.network_current_state_async(function (ret)
            if ret.succ then
                network = ret.state
            else
                network = nil
            end

            async_return_count = async_return_count + 1
            final_exe_callback()
        end)
    end

    get_network_type()
end

return M
