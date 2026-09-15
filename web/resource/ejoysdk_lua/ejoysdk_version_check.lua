local E = require "ejoysdk_lua.ejoysdk"
local V = require "ejoysdk_lua.version"
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
local EM = require "ejoysdk_lua.ejoysdk_module"
local split_string = E.Utils.split_string

local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. "ver_check"

--各平台单独依赖的平台常量
local SDK_NAME = {
    EJOYSDK = 'EJOYSDK',
    ANDROID_UNITY_SDK = "UNITYSDK",
    IOS_EJOYSDK_BASE  = 'EJOYSDK_BASE'
}

local M = {}

local function collect_sdk_min_versions(vendors)
    local sdk_min_version_list = {}
    local sdk_name_list = {}

    --所有平台都有ejoysdk
    table.insert(sdk_name_list, SDK_NAME.EJOYSDK)

    local platform_min_versions = {}

    --检查每个平台独有的sdk
    local os = E.Sysinfo.os()
    if os == 'ios' then
        -- set platform min versions
        platform_min_versions = V.IOS_MIN_VER
        -- add iOS  default dependency sdk
        table.insert(sdk_name_list, SDK_NAME.IOS_EJOYSDK_BASE)
    elseif os == 'android' then
        -- set platform min versions
        platform_min_versions = V.ANDROID_MIN_VER
        -- add android default dependency sdk
    elseif os == 'windows' then
        -- set platform min versions
        platform_min_versions = V.WINDOWS_MIN_VER

        --TODO add windows default dependency sdk
    end

    for vendor_name, _ in pairs(vendors) do
        table.insert(sdk_name_list, vendor_name)
    end

    --拼接所有sdk的最低版本信息
    for _i, name in ipairs(sdk_name_list) do
        sdk_min_version_list[name] = platform_min_versions[name]
    end

    return sdk_min_version_list
end

-- 版本比较
-- 1: version1大于version2, 0:version1等于version2, -1:version1小于version2
local function compare_versions(version1, version2)
    if version1 == nil or version1 == '' or version2 == nil or version2 == '' then
        if version1 ~= nil and version1 ~= '' then
            return 1
        elseif version2 ~= nil and version2 ~= '' then
            return -1
        else
            return 0
        end
    end

    local version_arr1 = split_string(version1, '%.')
    local version_arr2 = split_string(version2, '%.')
    local min_len = math.min(#version_arr1, #version_arr2)
    local diff = 0;

    --lua index从1开始
    local idx = 1
    while (idx <= min_len)
    do
        local str1 = version_arr1[idx]
        local str2 = version_arr2[idx]
        diff = string.len(str1) - string.len(str2)
        if diff == 0 then
            if str1 == str2 then
                diff = 0
            elseif str1 > str2 then
                diff = 1
            else
                diff = -1
            end
        end

        if diff ~= 0 then
            break
        else
            idx = idx + 1
        end
    end

    --如果已经分出大小，则直接返回，如果未分出大小，则再比较位数，有子版本的为大；
    if diff ~= 0 then
        if diff > 0 then
            return 1
        else
            return -1
        end
    else
        local len = #version_arr1 - #version_arr2
        if len > 0 then
            return 1
        elseif len == 0 then
            return 0
        else
            return -1
        end
    end
end
M.compare_versions = compare_versions

--检查lua依赖的sdk的最低要求版本
function M.check_sdk_version(vendors)
    local sdk_list = collect_sdk_min_versions(vendors)
    E.log(sdk_list)
    local check_result = {
        result = true
    }

    local stat_table_data = {}
    table.insert(stat_table_data, "lua_ver:"..V.LUA_VERSION)
    for k, v in pairs(sdk_list) do
        local sdk_name = k
        local sdk_min_version = v

        -- if v type is table then traversing the table, and get the sdk name
        if type(sdk_min_version) == "table" then
            for ck, cv in pairs(sdk_min_version) do
                local ch_sdk_min_version = cv
                local ch_sdk_name = ck
                local ch_cur_sdk_version = E.get_sdk_version_name(ch_sdk_name)
                E.log("version>> sdk detail, sdk_name:"..(ch_sdk_name or "")..", min_ver:"..(ch_sdk_min_version or "")..", sdk_ver:"..(ch_cur_sdk_version or ""))
                -- compare_versions
                if ch_cur_sdk_version == nil or ch_cur_sdk_version == '' then
                    --我们只知道游戏接了sdk_name的vendor，但该vendor对应的插件列表为可选接入，所以没有接入我们不强校验
                    E.log("version>> warnning game not integrate sdk_name:"..ch_sdk_name)
                else
                    local ch_compare_result = compare_versions(ch_cur_sdk_version, ch_sdk_min_version)
                    if ch_compare_result < 0 then
                        check_result.result = false
                        check_result.sdk_name = ch_sdk_name
                        check_result.sdk_min_version = ch_sdk_min_version
                        check_result.current_sdk_version = ch_cur_sdk_version
                        break
                    end
                end
            end
        else
            local current_sdk_version = E.get_sdk_version_name(sdk_name)
            local compare_result
            E.log("version>> sdk detail, sdk_name:"..(sdk_name or "")..", min_ver:"..(sdk_min_version or "")..", sdk_ver:"..(current_sdk_version or ""))
            -- if current_sdk_version exists, need check if it's larger than sdk_min_version. If it's lower than sdk_min_version it may cause error
            if current_sdk_version ~= nil and current_sdk_version ~= '' then
                compare_result = compare_versions(current_sdk_version, sdk_min_version)
                if compare_result < 0 then
                    check_result.result = false
                    check_result.sdk_name = sdk_name
                    check_result.sdk_min_version = sdk_min_version
                    check_result.current_sdk_version = current_sdk_version
                end
            else
                -- not integrate native vendor, if lua calls native api, then it do nothing, so it has no problem.
                E.LOG.warn(TAG, "current native sdk version is nil, sdk_name:"..sdk_name)
            end

            local item_stat_data = {}
            table.insert(item_stat_data, sdk_name)
            table.insert(item_stat_data, "min_ver:"..(sdk_min_version or 'nil'))
            table.insert(item_stat_data, "curr_ver:"..(current_sdk_version or 'nil'))
            table.insert(item_stat_data, "result:"..tostring(compare_result))
            local item_stat_str = table.concat(item_stat_data, "-")
            table.insert(stat_table_data, item_stat_str)
        end

        if not check_result.result then
            break
        end
    end

    if check_result.result then
        E.log("version>> version check success!")
        table.insert(stat_table_data, "check_result:true")
    else
        E.log("version>> check error! current version is smaller than min version, sdk_name:"..check_result.sdk_name..", sdk_min_ver:"..(check_result.sdk_min_version or "")..", cur_sdk_ver:"..(check_result.current_sdk_version or ""))
        table.insert(stat_table_data, "check_result:false")
    end

    -- 排序列表，保证每次获取sdk列表顺序是固定的，用于日志统计上报，否则无序的sdk列表影响统计后台难以分析sdk版本分布情况。
    -- 注意：table.sort 适用于只包含字符串的table对象，其他key-value的复杂table对象就不适用。
    table.sort(stat_table_data)
    local comp_ver_stat_str = table.concat(stat_table_data, ",")
    ESTAT.stat_action("version.check", TAG, check_result.result, {comp_ver_stat_result = comp_ver_stat_str})
    E.LOG.debug(TAG, "comp_ver_stat_str:"..comp_ver_stat_str)
    return check_result
end

return M