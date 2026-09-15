local M = {}
local ER = require 'ejoysdk_lua.res.ejoysdk_res'
local RTM = require "ejoysdk_lua.res.model.ejoy_res_type_model"
local E = require "ejoysdk_lua.ejoysdk"
local TAG = "ejoysdk_res_base_facade"
local END = require "ejoysdk_lua.res.ejoy_namespace_dispatcher"

M.RES_INFO_KEY = RTM.USING_RES_INFO_PARAM_KEY
M.DOWNLOAD_STATE = RTM.PUBLIC_DOWNLOAD_STATE
M.RES_DOWNLOAD_STATE_KEY = RTM.RES_STATE_INFO_KEY
M.PROGRESS_INFO_KEY = RTM.PROGRESS_INFO_KEY
M.RES_STATE_INFOS = RTM.INFO_TYPE_KEY
M.UPDATE_INFO_KEY = RTM.UPDATE_INFO_KEY
M.USING_RES_INFO_KEY = RTM.USING_RES_STATE_INFO_KEY
M.FILE_LIST_ITEM_KEY = RTM.FILE_LIST_ITEM_KEY
M.NAMESPACE_UPDATE_OPTIONS = END.NAMESPACE_UPDATE_OPTIONS
M.STORAGE_TYPE = RTM.STORAGE_TYPE

--[[
检查资源更新接口，根据本地在使用的资源信息，下载中的资源信息，以及服务端发布的更新信息，找到一份待更新的资源信息
@param namespace string, 由具体业务决定
@param res_key string, 资源标识
@param params table, 传递参数信息，包含参数如下：
    @param using_res_info table, 当前使用的资源信息，包含字段如下：
        @param version string, 版本号，例如：1.2.3
@param opts table, 可选参数, {@link #M.NAMESPACE_RES_UPDATE_OPTIONS}
@param update_cb function, 更新结果回调，包含以下信息
    @param succ, boolean, true:成功， false:失败
        true: 此时第4个参数是资源状态信息，table类型，参考{@link M.RES_STATE_INFOS}
        false: 此时第2, 3个参数分为code, msg
    @param is_update_info_exists，服务端是否有发布更新信息。true: 有，false: 无
    @param has_update，是否需要更新，true: 需要，false: 不需要
    @param state_obj, table, 参考{@link M.RES_STATE_INFOS}
--]]
function M.check_namespace_res_update(namespace, res_key, params, opts, update_cb)
    _ejoysdk.log("check_namespace_res_update")
    ER.check_namespace_res_update(namespace, res_key, params, opts, update_cb)
end

--[[
检查资源更新接口，根据本地在使用的资源信息，下载中的资源信息，以及服务端发布的更新信息，找到一份待更新的文件列表，下载和通知状态更新
@param namespace string, 由具体业务决定
@param res_key string, 资源标识
@param res_ver string, 资源版本
@param params table, 暂无使用
@param opts, table, 可选参数, {@link #M.NAMESPACE_UPDATE_OPTIONS}
    @param listeners
    1. on_request_file_list 游戏如果需要根据更新信息自己生成文件下载清单，可以提供该回调。
       如果有该回调则SDK只会使用该回调来生成文件清单，不会做兜底处理。如果没有该回调则SDK自己生成文件清单。
       @param res_key 资源标识
       @file_list_cb 资源清单回调，游戏通过该接口返回清单信息。该回调对应的参数信息如下：
            @param succ 获取文件列表结果，true: 成功；false：失败
            @param ... 可变参数，
                如果succ为true，则该变参为 file_list（文件清单列表）和 list_desc
                > file_list 文件清单列表，是一个数组。里面每个item的字段信息参考：{@link M.FILE_LIST_ITEM_KEY}
                > list_desc 文件清单的附加信息，例如这些清单里面的文件的父目录相对于服务端basePath的相对路径, 可以添加'folder'设置该内容
                如果succ为false, 则该变参为 code 和 msg
@param complete_cb function, 更新结果回调
    @param succ, boolean, true: 成功， false: 失败
        true: 第2个参数为资源信息，table类型，参考{@link M.RES_STATE_INFOS}
        false: 第2，3个参数为code，msg

@param on_res_state_change_listener function, 资源下载状态变更通知，返回参数如下：
   @param res_key 资源标识
   @param state 资源下载状态，状态信息参考：{@link M.DOWNLOAD_STATE}
   @param state_obj 详细状态信息，字段参考：{@link M.RES_DOWNLOAD_STATE_KEY}

@param on_res_progress_change_listener function, 资源下载进度信息，返回参数如下：
   @param res_key 资源标识
   @param progress_info 进度信息，详细见 {@link M.PROGRESS_INFO_KEY}

--]]
function M.confirm_update_namespace_res(namespace, res_key, res_ver, params, opts, complete_cb, on_res_state_change_listener, on_res_progress_change_listener)
    ER.confirm_update_namespace_res(namespace, res_key, res_ver, params, opts, complete_cb, on_res_state_change_listener, on_res_progress_change_listener)
end

--[[
@param namespace string 命名空间，由具体业务决定
@param res_info table，资源信息，包含参数如下：
    @param res_key string, 资源标识
    @param engine_handler table， 资源处理器，实现以下接口
        1、on_res_apply：资源应用接口，在该接口实现patch合并/拷贝资源到指定目录
        @param res_key 资源标识
        @param res_location 资源路径
        @param res_state_infos  资源信息
        @param cb function类型，资源应用回调，包含以下回调信息：
            @param succ: bool, 是否成功
	        @param ... : 可变参数，对于succ的关系如下：
		        true: ... 为1个返回数据，为remove_download_dir, 是否删除下载目录，true: 删除，false: 不删除
		        false: ... 为2个返回数据，分别为code, msg
       2、on_request_file_list 游戏如果需要根据更新信息自己生成文件下载清单，可以提供该回调。
           如果有该回调则SDK只会使用该回调来生成文件清单，不会做兜底处理。如果没有该回调则SDK自己生成文件清单。
           @param res_key 资源标识
           @file_list_cb 资源清单回调，游戏通过该接口返回清单信息。该回调对应的参数信息如下：
               @param succ 获取文件列表结果，true: 成功；false：失败
               @param ... 可变参数，
                   如果succ为true，则该变参为 file_list（文件清单列表）和 list_desc
                   > file_list 文件清单列表，是一个数组。里面每个item的字段信息参考：{@link M.FILE_LIST_ITEM_KEY}
                   > list_desc 文件清单的附加信息，例如这些清单里面的文件的父目录相对于服务端basePath的相对路径, 可以添加'folder'设置该内容
                   如果succ为false, 则该变参为 code 和 msg
opts table, 可选参数, {@link #M.NAMESPACE_RES_UPDATE_OPTIONS}
listeners table，资源更新回调接口，需要实现如下接口
    @param on_confirm_res_update 启动过程和游戏中监听到资源更新信息变更确认回调，游戏需要在回调中确认是否更新该资源版本。
        该回调函数返回的参数如下：
        @param res_key 资源标识
        @param res_state_info 资源信息，同{@link M.get_res_state}返回。包含更新信息和当前下载状态
        @param confirm_update_cb 确认是否下载回调，业务方需要对res_update_info是否更新通知该回调，该回调的参数如下：
            @param confirmed true: 确认更新；false: 跳过该更新
    @param on_res_update_complete 资源更新完成回调，该回调返回两个参数
        @param succ 是否成功，true: 成功， false：失败
        @param ... 可变参数. 如果succ为true，则该可变参数为空；如果succ 为false，则可变参数为code, msg
    @param on_res_download_state_change_listener 资源下载状态变更通知，返回参数如下：
        @param res_key 资源标识
        @param state 资源下载状态，状态信息参考：{@link M.DOWNLOAD_STATE}
        @param state_obj 详细状态信息，字段参考：{@link M.RES_DOWNLOAD_STATE_KEY}
    @param on_res_download_progress_change_listener 资源下载进度信息，返回参数如下：
        @param res_key 资源标识
        @param progress_info 进度信息，详细见 {@link M.PROGRESS_INFO_KEY}
--]]
function M.check_and_update(namespace, res_info, opts, listeners)


    local res_key = res_info.res_key
    local engine_handler = res_info.engine_handler or {}
    listeners = listeners or {}

    local local_res_state = RTM.static_get_local_res_state(namespace, res_key) or {}
    local using_res_info = local_res_state[RTM.NAMESPACE_RES_CONFIG_KEY.TYPE_USING_RES_INFO] or {}
    --如果本地没有版本，则把版本设置为nil
    local local_res_version = res_info.version or using_res_info.version

    local params = {
        using_res_info = {
            version = local_res_version
        }
    }

    local on_confirm_res_update = listeners.on_confirm_res_update
    local on_res_download_state_change_listener = listeners.on_res_download_state_change_listener or function() end
    local on_res_download_progress_change_listener = listeners.on_res_download_progress_change_listener or function() end
    local on_res_update_complete = listeners.on_res_update_complete or function() end
    local on_res_apply = engine_handler.on_res_apply
    local on_request_file_list = engine_handler.on_request_file_list

    opts.listeners = {
        on_request_file_list = on_request_file_list
    }

    -- 设置下载保存路径，如果有传，设置给opts
    opts[M.NAMESPACE_UPDATE_OPTIONS.RES_SAVE_BASE_PATH] = res_info.res_save_base_path
    opts[M.NAMESPACE_UPDATE_OPTIONS.RES_SAVE_STORAGE_TYPE] = res_info.res_save_storage_type


    -- on_confirm_res_update非必须，默认为true
    if on_confirm_res_update == nil then
        on_confirm_res_update = function(_res_key, _res_info, confirm_cb)
            confirm_cb(true)
        end
    end

    -- apply非必须
    if on_res_apply == nil then
        on_res_apply = function(_res_key, _res_location, _res_state_infos, apply_cb)
            apply_cb(true)
        end
    end

    ER.check_namespace_res_update(namespace, res_key, params, opts, function(succ, ...)
        if succ then
            local is_update_info_exists, has_update, update_res_info = ...
            if is_update_info_exists and has_update then
                on_confirm_res_update(res_key, update_res_info, function(confirm_download)
                    E.LOG.debug(TAG, "on_confirm_res_update result:" .. tostring(confirm_download) .. ", res_key:" .. tostring(res_key))
                    if confirm_download then
                        local update_info = update_res_info[M.RES_STATE_INFOS.TYPE_RES_UPDATE_STATE] or {}
                        local update_ver = update_info[M.UPDATE_INFO_KEY.VERSION_NAME]
                        E.LOG.debug(TAG, "confirm update version:" .. tostring(update_ver))
                        M.confirm_update_namespace_res(namespace, res_key, update_ver, params, opts, function(confirm_succ, ...)
                            if confirm_succ then
                                local res_state_infos = ...
                                local res_location = res_state_infos.res_downloading_info.res_location
                                on_res_apply(res_key, res_location, res_state_infos, function(apply_result, ...)
                                    if apply_result then
                                        ER.publish_using_res_version(namespace, res_key, update_ver)
                                        on_res_update_complete(true, true)
                                    else
                                        --apply fail
                                        local code, msg = ...
                                        on_res_update_complete(false, code, msg)
                                    end
                                end)
                            else
                                -- 下载失败，回调失败
                                local confirm_res_update_err_code, confirm_res_update_err_msg = ...
                                on_res_update_complete(false, confirm_res_update_err_code, confirm_res_update_err_msg)
                            end
                        end, function(_ns, rk, state, state_obj)
                            on_res_download_state_change_listener(rk, state, state_obj)
                        end, function(_ns, rk, progress_info)
                            on_res_download_progress_change_listener(rk, progress_info)
                        end)
                    else
                        --跳过更新直接回调complete
                        on_res_update_complete(true, false)
                    end
                end)
            else
                --无版本更新信息，回调complete succ
                --无更新信息，无需处理
                on_confirm_res_update(res_key, {}, function() end)
                on_res_update_complete(true, false)
            end
        else
            local check_res_update_err_code, check_res_update_err_msg = ...
            on_res_update_complete(false, check_res_update_err_code, check_res_update_err_msg)
        end
    end)
end

--[[
获取指定namespace下所有资源标识的资源状态信息
@param namespace 资源名称空间
@return table类型map，返回游戏namespace下所有资源标识对应的状态信息。为key-value结构。key为资源标识，value为资源状态信息
资源状态信息的详细信息参考方法{@link M.get_res_state} 的返回
--]]
function M.get_res_state(_namespace, _res_key)
    return ER.get_res_state(_namespace, _res_key)
end


return M