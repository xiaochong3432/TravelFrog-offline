---
--- Created by pangang.
--- DateTime: 1/17/22 4:24 PM
--- ejoy_res_model_manager: 负责管理不同的Model类型，并根据参数构建和缓存model
---
local E = require "ejoysdk_lua.ejoysdk"
local EU = require "ejoysdk_lua.ejoysdk_utils"
local EC = require "ejoysdk_lua.ejoysdk_constants"
local M = {}

local TAG = "ejoy_res_model_manager"

M.MODEL_TYPE = {
    HTTP_RES = "HTTP_RES", -- http 请求
    HTTP_MULTI_DOWNLOAD = "HTTP_MULTI_DOWNLOAD", -- http 多任务请求
    EJOY_RES_SOURCE = "EJOY_RES_SOURCE", -- ejoy 资源管理系统管理的资源
    IOS_CLOUD_ODR_RES = "IOS_CLOUD_ODR_RES", -- ios cloud odr资源
    ANDROID_CLOUD_CN_OSS = "ANDROID_CLOUD_CN_OSS", -- android国内云游资源管理
    INSTALL_PKG = "INSTALL_PKG" -- 跳转到应用市场下载安装包
}

-- 默认的model名称
local DEFAULT_MODEL_NAME = "default"
local DEFAULT_MULTI_MODEL_NAME = "default_multi"

-- 缓存model实例
local model_cache = {}

local function model_cache_key(model_type, model_name)
    assert(model_type, "model_type should not be nil")
    model_name = model_name or DEFAULT_MODEL_NAME
    return model_type .. "-" .. model_name
end

--[[
获取特定于url下载的model实例，通过该model提供的方法可以创建下载任务和操作一个下载任务
model_name：model别名，用于区分其它自定义model实例。如果不传则使用默认的model实例
--]]
function M.get_http_res_model(model_name)
    local model_key = model_cache_key(M.MODEL_TYPE.HTTP_RES, model_name)
    local cache_model = model_cache[model_key]
    if not cache_model then
        local http_res_model_module = require "ejoysdk_lua.res.model.ejoy_http_download_model"
        cache_model = http_res_model_module:New(model_key)
        model_cache[model_key] = cache_model
    end

    E.LOG.debug(TAG, "get_http_res_model with name:" .. tostring(model_name) .. ", key:" .. model_key ..  ", instance:" .. tostring(cache_model))
    return cache_model
end

--[[
获取多任务下载的model, 效果同get_http_res_model，不同的是创建的是多个下载任务的接口
--]]
function M.get_http_res_multi_model(model_name)
    local model_key = model_cache_key(M.MODEL_TYPE.HTTP_MULTI_DOWNLOAD, model_name or DEFAULT_MULTI_MODEL_NAME)
    local cache_model = model_cache[model_key]
    if not cache_model then
        local http_res_model_module = require "ejoysdk_lua.res.model.ejoy_http_download_multi_model"
        cache_model = http_res_model_module:New(model_key)
        model_cache[model_key] = cache_model
    end

    E.LOG.debug(TAG, "get_http_res_multi_model with name:" .. tostring(model_name) .. ", key:" .. model_key ..  ", instance:" .. tostring(cache_model))
    return cache_model
end

--function M.get_ejoy_res_source_model(model_name, source_adapter)
--
--end

--[[
获取odr资源管理model
--]]
function M.get_ios_cloud_odr_model()
    local model_key = model_cache_key(M.MODEL_TYPE.IOS_CLOUD_ODR_RES)
    local cache_model = model_cache[model_key]
    if not cache_model then
        local odr_res_model_module = require "ejoysdk_lua.res.model.res_src.ios_cloud_odr_model"
        cache_model = odr_res_model_module:New(model_key)
        model_cache[model_key] = cache_model
    end

    E.LOG.debug(TAG, "get_odr_res_model with name, key:" .. tostring(model_key) .. ", instance:" .. tostring(cache_model))
    return cache_model
end

function M.get_android_cloud_cn_oss_model()
    local model_key = model_cache_key(M.MODEL_TYPE.ANDROID_CLOUD_CN_OSS)
    local cache_model = model_cache[model_key]
    if not cache_model then
        local android_cloud_cn_oss_module = require "ejoysdk_lua.res.model.res_src.android_cloud_cn_oss_model"
        cache_model = android_cloud_cn_oss_module:New(model_key)
        model_cache[model_key] = cache_model
    end

    E.LOG.debug(TAG, "get_android_cloud_cn_oss_model key:" .. tostring(model_key) .. ", instance:" .. tostring(cache_model))
    return cache_model
end

function M.get_install_pkg_model()
    local model_key = model_cache_key(M.MODEL_TYPE.INSTALL_PKG)
    local cache_model = model_cache[model_key]
    if not cache_model then
        local install_pkg_model_module = require "ejoysdk_lua.res.model.res_src.ejoy_install_pkg_model"
        cache_model = install_pkg_model_module:New(model_key)
        model_cache[model_key] = cache_model
    end

    E.LOG.debug(TAG, "get_install_pkg_model with name, key:" .. tostring(model_key) .. ", instance:" .. tostring(cache_model))
    return cache_model
end

--[[
接口描述：获取ejoysdk 平台管理的资源模块
--]]
function M.get_ejoy_res_source_model(namespace, res_key, _opts)
    if EU.is_text_empty(namespace) or EU.is_text_empty(res_key) then
        return nil, EC.BASE_API_COMMON_ERROR.CODE_INVALID_PARAMETER, "namespace or res_key invalid"
    end

    local model_name = namespace .. "_" .. res_key
    local model_key = model_cache_key(M.MODEL_TYPE.EJOY_RES_SOURCE, model_name)
    local cache_model = model_cache[model_key]
    if not cache_model then
        local ejoy_res_src_model = require "ejoysdk_lua.res.model.res_src.ejoy_res_source_model"
        cache_model = ejoy_res_src_model:New(model_key, namespace, res_key, _opts)
        model_cache[model_key] = cache_model
    end

    E.LOG.debug(TAG, "get_ejoy_res_source_model key:" .. tostring(model_key) .. ", instance:" .. tostring(cache_model))
    return cache_model
end

-- 通过model_type来构建model 实例，如果缓存有则直接返回
function M.get_model_by_type(model_type, ...)
    E.LOG.debug(TAG, "get_model_by_type:" .. tostring(model_type))

    local model_instance
    if model_type then
        E.LOG.debug(TAG, "has model_type:" .. tostring(model_type) .. ", now use factory method")
        if model_type == M.MODEL_TYPE.HTTP_RES then
            local model_name = ...
            E.LOG.debug(TAG, "model_name for model_type:" .. tostring(model_type) .. ", model_name:" .. tostring(model_name))
            model_instance = M.get_http_res_model(model_name)
        elseif model_type == M.MODEL_TYPE.HTTP_MULTI_DOWNLOAD then
            local model_name = ...
            E.LOG.debug(TAG, "model_name for model_type:" .. tostring(model_type) .. ", model_name:" .. tostring(model_name))
            model_instance = M.get_http_res_multi_model(model_name)
        elseif model_type == M.MODEL_TYPE.EJOY_RES_SOURCE then
            local namespace, res_key = ...
            E.LOG.debug(TAG, "model_name for model_type:" .. tostring(model_type) .. ", namespace:" .. tostring(namespace) .. ", res_key:" .. tostring(res_key))
            model_instance = M.get_ejoy_res_source_model(namespace, res_key)
        elseif model_type == M.MODEL_TYPE.IOS_CLOUD_ODR_RES then
            E.LOG.debug(TAG, "model_name for model_type:" .. tostring(model_type))
            model_instance = M.get_ios_cloud_odr_model()
        elseif model_type == M.MODEL_TYPE.ANDROID_CLOUD_CN_OSS then
            E.LOG.debug(TAG, "model_name for model_type:" .. tostring(model_type))
            model_instance = M.get_android_cloud_cn_oss_model()
        end
    end

    if model_instance then
        E.LOG.debug(TAG, "get_model_by_type succ for type:" .. tostring(model_type))
        return model_instance
    else
        local formatted_model_key = ...
        E.LOG.debug(TAG, "model_type is nil, now try get model instance from cache with name" .. tostring(formatted_model_key))
        if formatted_model_key then
            return model_cache[formatted_model_key]
        else
            return nil
        end
    end
end

return M