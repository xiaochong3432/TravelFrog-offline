local E = require "ejoysdk_lua.ejoysdk"
local cloud_config = require "ejoysdk_lua.cloud_game.cloud_config"
local ejoysdk = require "ejoysdk_lua.ejoysdk"
local EM = require "ejoysdk_lua.ejoysdk_module"
local EC = require "ejoysdk_lua.ejoysdk_constants"
local CSTAT = require "ejoysdk_lua.cloud_game.cloud_stat"
local CIPM = require "ejoysdk_lua.cloud_game.cloud_install_pkg_manager"

local TAG = EM.MODULE.CLOUD_GAME .. 'download_utils'

local M = {}
--单个文件下载失败重试次数
local MAX_RETRY_CNT = 3
--重试延时
local RETRY_TIME_DELAY = 1
M.download_folder = nil
M.temp_folder = nil
local suffix = "_dl_bak_"
--url地址文件
M.URL_CONF = "_cloud_game_url.json"
M.RES_FILE_LIST = "game_resource_files.json"
M.RES_STATE_CACHE = E.LazyKeyStore:New("CLOUD_GAME_RES_STATE_INFO", false, true, false)

local is_download_file_pause = false
local file_recv_bytes = {}
local file_complete_temp_list = {}
local last_calc_recv_bytes = 0
local last_calc_speed_time = 0
local current_download_speed = 0
local remote_res_url_sp = E.SPKeyStore:New('com.ejoy.cloud_config', 'remote_url')

local download_speed_change_listener = nil
-- assets 状态信息
local assets_state_info = {}

local download_pause_listener = nil

local log = function(s)
    E.LOG.debug(TAG, s)
end

M.STATE_KEY = {
    STATE = "state",
    VERSION_NAME = "ver_name"
}

M.CLOUD_RES_STATE = {
    FINISH = "finish", -- 下载完成，可以直接启动游戏
    DOWNLOADING = "downloading", -- 下载中
    UPDATING = "updating", -- 下载完成，但需要升级，升级中
    DISABLE = "disable"
}

function M.check_file_valid(path, file_size)
    local file = io.open(path, "rb")
    if file then
        local len = assert(file:seek("end"))
        file:close()
        --windows没有实现文件下载
        if M.get_os() == "windows" then
            return true
        end
        return len == file_size
    end
end

local function create_dir(dir)
    if E.Sysinfo.os() ~= "windows" then
        return
    end
    --去掉最后的'/'
    dir = string.sub(dir, 1, #dir - 1)
    local file = io.open(dir)
    if not file then
        local cmd
        if M.get_os() == "windows" then
            cmd = "mkdir " .. dir
        else
            cmd = "mkdir -p " .. dir
        end
        os.execute(cmd)
    else
        file:close()
    end
end

function M.get_os()
    return E.Sysinfo.os()
end

local function calc_total_bytes()
    local recv_bytes_count = 0
    for _file_name, file_bytes in pairs(file_recv_bytes) do
        recv_bytes_count = recv_bytes_count + file_bytes
    end

    return recv_bytes_count
end

local function on_download_received_bytes_changed(file, received_bytes, total)
    --E.LOG.debug(TAG, "on_download_received_bytes_changed file >> " .. tostring(file) .. ", received_bytes >> " .. tostring(received_bytes)
    --        .. ", total >> " .. tostring(total))
    if total and total <= 0 then
        E.LOG.error(TAG, 'on_download_received_bytes_changed, total bytes <= 0, return')
        return
    end
    file_recv_bytes[file] = received_bytes
    if received_bytes == total then
        file_complete_temp_list[file] = received_bytes
    end


    local cur_time = E.time()
    if last_calc_speed_time == 0 then
        last_calc_speed_time = cur_time
    end

    -- 一秒计算一次
    local diff_time = cur_time - last_calc_speed_time
    if diff_time >= 1 then
        local total_recv_bytes = calc_total_bytes()
        local diff_bytes = total_recv_bytes - last_calc_recv_bytes
        local speed = math.floor(diff_bytes / diff_time)
        --E.LOG.debug(TAG, "total_recv_bytes:" .. tostring(total_recv_bytes) .. ", last_calc_recv_bytes:" .. tostring(last_calc_recv_bytes) .. ", diff_time:" .. tostring(diff_time) .. ", speed:" .. tostring(speed))
        last_calc_speed_time = cur_time

        if file_complete_temp_list and next(file_complete_temp_list) ~= nil then
            local total_bytes = total_recv_bytes
            for f, f_size in pairs(file_complete_temp_list) do
                total_bytes = total_bytes - f_size
                file_recv_bytes[f] = nil
            end

            last_calc_recv_bytes = total_bytes
        else
            last_calc_recv_bytes = total_recv_bytes
        end

        file_complete_temp_list = {}

        if speed > 0 and current_download_speed ~= speed then
            current_download_speed = speed
            if download_speed_change_listener ~= nil then
                download_speed_change_listener(current_download_speed)
            end
        end
    end
end

local function request_file(url, file, cb, file_size, file_md5, on_download_progress)
    local temp_file = M.temp_folder .. file .. suffix
    --windows不没有实现下载文件
    if M.get_os() ~= "windows" then
        local down_cb = function(ret)
            if ret.status == 200 or ret.status == 0 then
                --log("[cloud game] finish down file2 " .. file .. " " .. ret.status)
                if not file_size or M.check_file_valid(temp_file, file_size) then
                    os.remove(M.download_folder .. file)
                    os.rename(temp_file, M.download_folder .. file)
                    cb(true)
                else
                    log("[cloud game] request_file size error " .. file)
                    cb(false, EC.DOWNLOAD_ERROR_CODES.DOWNFINISH_FILE_INVALID)
                end
            else
                if ret.status == EC.EJOYSDK_ERROR_CODES.RES_DOWNLOAD_MD5_MISMATCH then
                    log("[cloud game] file md5 check mismatch")
                    CSTAT.stat_action_fail("mini_request_file_md5_mismatch", url)
                end
                local message = ret.message or ''
                cb(false, ret.status, message)
            end
        end

        local recv_present = 0
        local progress = function(_, _file, recv, total)
            local p = math.floor(recv / total * 100)
            if p ~= recv_present then
                recv_present = p
                if on_download_progress then
                    on_download_progress(recv_present)
                end
            end

            -- update received bytes
            on_download_received_bytes_changed(_file, recv, total)
        end

        -- todo:目前只实现了android限速
        E.HTTP.get(
            url,
            {
                file = temp_file,
                kps_limit = cloud_config.get_http_kps_limit() or -1,
                interval_limit = cloud_config.HttpIntervalLimit,
                progress = progress,
                checksum = file_md5
            },
            down_cb
        )
    else
        local down_cb_body = function(ret)
            if ret.status == 200 then
                log("[cloud game] finish down body " .. file .. " " .. ret.status)
                local f = io.open(temp_file, "w")
                f:write(ret.body)
                f:close()
                if not file_size or M.check_file_valid(temp_file, file_size) then
                    os.rename(temp_file, M.download_folder .. file)
                    cb(true)
                else
                    log("[cloud game] request_file size error pc" .. file)
                    cb(false, EC.DOWNLOAD_ERROR_CODES.DOWNFINISH_FILE_INVALID)
                end
            else
                cb(false, ret.status)
            end
        end
        E.HTTP.get(url, {}, down_cb_body)
    end
end

-- 在odr的场景中，不需要创建下载目录
function M.init(download_folder)
    log("[cloud game] init download_dir " .. tostring(download_folder))
    M.download_folder = download_folder
    -- 使用下载目录的上层目录，避免游戏把下载目录删除掉
    M.finish_flg_folder = M.get_parent_folder(M.download_folder)
    log("[cloud game] finish_flg_folder " .. M.finish_flg_folder)
    --因为不支持创建目录，则使用后缀来区分
    M.temp_folder = download_folder
    create_dir(M.download_folder)
    create_dir(M.temp_folder)
end

function M.register_download_speed_changed(listener)
    download_speed_change_listener = listener
end

function M.set_donwload_pause(is_pause)
    is_download_file_pause = is_pause
    if download_pause_listener then
        download_pause_listener(is_pause)
    end
    E.LOG.debug(TAG, "[cloud game] set_donwload_pause " .. tostring(is_pause))
end

function M.is_download_paused()
    return is_download_file_pause
end

function M.register_download_pause_listener(listener)
    download_pause_listener = listener
end

-- 下载文件，会重试（如果填了file_size则表示会校验文件大小）
function M.down_file(url, file, ok_cb, fail_cb, file_size, file_md5, on_download_progress)
    --重试次数
    local retry_cnt = 0
    local down_cb
    local down_file_wrap
    down_file_wrap = function()
        --暂停下载
        if is_download_file_pause then
            ejoysdk.Timer.once(1,down_file_wrap)
            return
        end

        E.LOG.debug(TAG, "request_file:  begin:" .. tostring(url) .. ", is_pause:" .. tostring(is_download_file_pause))
        request_file(url, file, down_cb, file_size, file_md5, on_download_progress)
    end

    down_cb = function(is_ok, ...)
        if is_ok then
            E.LOG.debug(TAG, "request_file:  end:" .. tostring(url))
            ok_cb(file)
        else
            retry_cnt = retry_cnt + 1
            if retry_cnt <= MAX_RETRY_CNT then
                E.Timer.once(
                    RETRY_TIME_DELAY,
                    function()
                        log(string.format("[cloud game] down_file fail,retry cnt=%s file=%s",retry_cnt, file))
                        down_file_wrap()
                    end
                )
            else
                local code, msg = ...
                fail_cb(code, msg)
            end
        end
    end
    down_file_wrap()
end

function M.split_url(full_url)
    local temp = string.reverse(full_url)
    local _,i = string.find(temp,"/")
    local offset = string.len(full_url) - i + 1
    return string.sub(full_url,1,offset),string.sub(full_url,offset+1,string.len(full_url))
end


function M.get_parent_folder(path)
    if string.sub(path,string.len(path))=="/" then
        path = string.sub(path,1,string.len(path)-1)
    end
    path = M.split_url(path)
    return path
end

function M.down_file_by_urls(urls,ok_cb, fail_cb)
    local _index = nil
    local get_next = function()
        local id, url = next(urls, _index)
        _index = id
        return url
    end

    local down_cfg_fun
    down_cfg_fun = function(full_url)
        local url,file = M.split_url(full_url)
        E.LOG.debug(TAG, "[cloud game] down cfg from " .. tostring(url) .. tostring(file) )
        E.LOG.debug(TAG, "[cloud game] down cfg from test " .. tostring(url) .. tostring(file) )
        M.down_file(
            full_url,
            file,
            function()
                ok_cb(url,file)
            end,
            function()
                local next_url = get_next()
                if next_url then
                    E.LOG.debug(TAG, "[cloud game] try other url " .. tostring(next_url))
                    down_cfg_fun(next_url)
                else
                    fail_cb("can't find file:" .. file)
                end
            end
        )
    end
    down_cfg_fun(get_next())
end

function M.set_finish_down_assets()
    local app_version_name = E.get_pkg_info().versions.app_version_name
    local state_info = {
        [M.STATE_KEY.STATE] = M.CLOUD_RES_STATE.FINISH,
        [M.STATE_KEY.VERSION_NAME] = app_version_name
    }

    -- save state info
    E.LOG.debug(TAG, "save state info >> " .. tostring(state_info[M.STATE_KEY.STATE]))
    M.RES_STATE_CACHE:set(state_info)
end

function M.set_not_finish_down_assets()
    local app_version_name = E.get_pkg_info().versions.app_version_name
    local state_info = {
        [M.STATE_KEY.STATE] = M.CLOUD_RES_STATE.DOWNLOADING,
        [M.STATE_KEY.VERSION_NAME] = app_version_name
    }

    -- save state info
    E.LOG.debug(TAG, "save state info >> " .. tostring(state_info[M.STATE_KEY.STATE]))
    M.RES_STATE_CACHE:set(state_info)
end

function M.remove_game_res_config_files()
    E.LOG.debug(TAG, "remove_game_res_config_files begin")
    local game_file_list_path = M.download_folder .. M.RES_FILE_LIST
    os.remove(game_file_list_path)

    -- remove cached file list config sp
    remote_res_url_sp:set("")
end

function M.get_file_content(file_path)
    local rfile = io.open(file_path, "r")
    if rfile then
        local content = rfile:read("*all")
        rfile:close()

        local CJSON = require "ejoysdk_lua.ejoysdk_cjson"
        local cfg = CJSON.decode(content)
        --local ok, cfg = pcall(json.decode, content)
        if cfg then
            return cfg, content
        end
    end
    return nil
end

-- 检查本地的资源配置文件是否有效
function M.check_game_res_config_files()
    local res_config_files = {}
    if M.is_file_exist(M.RES_FILE_LIST) then
        res_config_files["res_file_list"] = M.download_folder .. M.RES_FILE_LIST
        res_config_files["remote_res_url"] = remote_res_url_sp:get()
    else
        E.LOG.debug(TAG, "check_game_res_config_files not exists，clear all config files")
        M.remove_game_res_config_files()
    end

    return res_config_files
end

function M.get_backup_file_name(file_name)
    return file_name .. ".bak"
end

-- 如果源文件列表有，则删除bak，重新备份源文件
-- 如果源文件列表没有，则返回
function M.backup_clear_game_res_config_files()
    E.LOG.debug(TAG, "backup_clear_game_res_config_files")
    local game_file_list_path = M.download_folder .. M.RES_FILE_LIST
    local game_file_list_path_bak = M.download_folder .. M.get_backup_file_name(M.RES_FILE_LIST)

    -- 备份源文件
    local origin_file_list = io.open(game_file_list_path, "r")
    if origin_file_list then
        os.remove(game_file_list_path_bak)
        -- 备份源文件
        local content = origin_file_list:read("*all")
        origin_file_list:close()
        -- 重新备份源文件
        local bak_file = io.open(game_file_list_path_bak, "w")
        bak_file:write(content)
        bak_file:close()
    end

    -- 删除源文件
    M.remove_game_res_config_files()
end

-- 获取当前的资源下载状态
function M.current_assets_down_state()
    return assets_state_info or {}
end

function M.check_assets_down_state(cb)
    local state_info = M.RES_STATE_CACHE:get() or {}

    local cur_app_ver_name = E.get_pkg_info().versions.app_version_name
    -- 如果没有状态文件
    if next(state_info) == nil then
        local finish_file = io.open(M.finish_flg_folder .. "__finish_down_asset_.flg", "r")
        --兼容旧代码
        if not finish_file then
            finish_file = io.open(M.download_folder .. "__finish_down_asset_.flg", "r")
        end

        if finish_file then
            E.LOG.debug(TAG,"[cloud game] is_finish_down_assets")
            -- 已经下载完成资源，但是没有__down_asset_state_文件，代表老包被新包覆盖且还未生成该文件。此时属于覆盖安装，状态为{@link M.CLOUD_RES_STATE.UPDATING}
            state_info[M.STATE_KEY.STATE] = M.CLOUD_RES_STATE.UPDATING
            state_info[M.STATE_KEY.VERSION_NAME] = cur_app_ver_name

            -- 删除游戏资源的配置文件，重新检查资源更新
            M.backup_clear_game_res_config_files()
            -- 关闭finish_file
            finish_file:close()
        else
            -- 没有__down_asset_state_.flg文件，是老包覆盖安装了新包。此时老包资源没有下载完。可能是首次安装新包，也需要重新开始检查游戏资源
            state_info[M.STATE_KEY.STATE] = M.CLOUD_RES_STATE.DOWNLOADING
            state_info[M.STATE_KEY.VERSION_NAME] = cur_app_ver_name

            -- 删除游戏资源的配置文件，重新检查资源更新
            M.backup_clear_game_res_config_files()
        end
    else
        local state = state_info["state"]
        local last_ver_name = state_info["ver_name"]
        E.LOG.debug(TAG, "read assets_down_state_file, state:" .. tostring(state) .. ", last_ver_name:" .. tostring(last_ver_name))
        E.LOG.debug(TAG, state_info)
        if last_ver_name ~= cur_app_ver_name then
            -- 覆盖安装
            if state == M.CLOUD_RES_STATE.FINISH then -- 下载完成
                state_info[M.STATE_KEY.STATE] = M.CLOUD_RES_STATE.UPDATING
                state_info[M.STATE_KEY.VERSION_NAME] = cur_app_ver_name
            elseif state == M.CLOUD_RES_STATE.UPDATING then
                -- 升级的过程中再次出现覆盖安装
                state_info[M.STATE_KEY.STATE] = M.CLOUD_RES_STATE.UPDATING
                state_info[M.STATE_KEY.VERSION_NAME] = cur_app_ver_name
            elseif state == M.CLOUD_RES_STATE.DOWNLOADING then
                state_info[M.STATE_KEY.STATE] = M.CLOUD_RES_STATE.DOWNLOADING
                state_info[M.STATE_KEY.VERSION_NAME] = cur_app_ver_name
            else
                state_info[M.STATE_KEY.STATE] = M.CLOUD_RES_STATE.DOWNLOADING
                state_info[M.STATE_KEY.VERSION_NAME] = cur_app_ver_name
            end

            -- 覆盖安装场景，需要删除游戏资源的配置文件，重新检查资源更新
            M.backup_clear_game_res_config_files()
        else
            -- 正常启动游戏，正常读取和恢复之前的状态
            E.LOG.debug(TAG, "not override install, do normal startup")
        end
    end

    E.LOG.debug(TAG, "state_info, after >> ")
    E.LOG.debug(TAG, state_info)

    -- save state info
    M.RES_STATE_CACHE:set(state_info)

    assets_state_info = state_info
    if cb then
        cb(state_info)
    end
end

-- odr检查资源状态直接通过调用odr接口判断资源是否可用
function M.check_assets_down_state_odr(cb)
    local state_info = {}
    local cur_app_ver_name = E.get_pkg_info().versions.app_version_name
    state_info[M.STATE_KEY.VERSION_NAME] = cur_app_ver_name
    local odr_config = cloud_config.ODRConfig or {} --临时修复下lua异常
    local tags = {}
    for _, tag_items in pairs(odr_config) do
        for _, tag in ipairs(tag_items) do
            table.insert(tags, tag[cloud_config.ODR_TAG_CONFIG_KEYS.NAME])
        end
    end
    local demand_res = require "ejoysdk_lua.odr.demand_res_manager"
    demand_res.check_res_available(tags, function(available)
        E.LOG.debug(TAG, "odr res state >> " .. tostring(available))
        if available then
            state_info[M.STATE_KEY.STATE] = M.CLOUD_RES_STATE.FINISH
        else
            -- 通过缓存判断之前是否下载完成过,
            -- 如果是下载完成过，就启动本地游戏，后续更新的资源自行调用odr下载
            if M.check_odr_download_finish() then
                E.LOG.debug(TAG, "odr downloaded finish in the history")
                state_info[M.STATE_KEY.STATE] = M.CLOUD_RES_STATE.FINISH
            else
                state_info[M.STATE_KEY.STATE] = M.CLOUD_RES_STATE.DOWNLOADING
            end
        end
        if cb then
            cb(state_info)
        end
    end)
end

function M.check_pkg_install_state(cb)
    local state_info = {}
    local cur_app_ver_name = E.get_pkg_info().versions.app_version_name
    state_info[M.STATE_KEY.VERSION_NAME] = cur_app_ver_name
    local is_install = CIPM.is_pkg_installed()
    if is_install then
        state_info[M.STATE_KEY.STATE] = M.CLOUD_RES_STATE.FINISH
    else
        state_info[M.STATE_KEY.STATE] = M.CLOUD_RES_STATE.DOWNLOADING
    end
    if cb then
        cb(state_info)
    end
end


M.ODR_DOWNLOAD_STATE = E.LazyKeyStore:New("CLOUD_GAME_ODR_DOWNLOAD_STATE", false, true, false)
M.ODR_DOWNLOAD_STATE_KEY = "cloud_game_odr_download_state"

function M.save_odr_download_finish()
    E.LOG.debug(TAG, "save cloud odr res download finish")
    local state_info = {
        [M.ODR_DOWNLOAD_STATE_KEY] = true
    }
    M.ODR_DOWNLOAD_STATE:set(state_info)
end

function M.check_odr_download_finish()
    local state_info = M.ODR_DOWNLOAD_STATE:get()
    if state_info then
       local state = state_info[M.ODR_DOWNLOAD_STATE_KEY]
        if state then
            return true
        end
    end
    return false
end


function M.is_file_exist(file)
    if not file then
        return
    end
    -- 为了兼容ios没有下载目录的配置
    if not M.download_folder then
        return false
    end
    local f = io.open(M.download_folder .. file, "r")
    if f then
        f:close()
        return true
    end
end

function M.read_file_content(file)
    local f = io.open(M.download_folder .. file, "r")
    if f then
        local content = f:read("*all")
        f:close()
        return content
    end
end

function M.create_empty_file(file)
    local f = io.open(M.download_folder .. file, "w")
    f:close()
end


return M
