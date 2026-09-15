local ET = require "ejoysdk_lua.ejoysdk_topic"
local EJOYSDK_CONFIG = require 'ejoysdk_lua.ejoysdk_config'
local EM = require "ejoysdk_lua.ejoysdk_module"

local M = {}

local LANG_KEYSTORE_NAME = 'EJOYSDK_CONFIG_LANG'
local LANG_CONFIG_KEY = 'lang'

local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. "ejoysdk_lang"
local lang_list
local default_lang

local _lang_keystore -- 请通过 get_lang_keystore() 获取

local function get_lang_keystore()
    if _lang_keystore == nil then
        local E = require "ejoysdk_lua.ejoysdk" -- 不能直接 require ejoysdk
        _lang_keystore = E.LazyKeyStore:New(LANG_KEYSTORE_NAME, false, false, false)
    end
    return _lang_keystore
end

-- 语言配置变化监听器
local function lang_config_changed(value)
    if not value or type(value) ~= 'string' then
        return
    end
    if value == get_lang_keystore():get() then
        _ejoysdk.log('lang config changed, but same lang, return')
        return
    end
    _ejoysdk.log('lang config changed, value: ' .. tostring(value))
    get_lang_keystore():set(value:lower())
end

do
    ET.subscribe(ET.config.CONFIG_CHANGED .. '_' .. LANG_CONFIG_KEY, lang_config_changed)
end

-- 获取玩家手机设置语言
local function get_system_lang()
    local E = require "ejoysdk_lua.ejoysdk" -- 不能直接 require ejoysdk
    return E.Sysinfo.language_and_script():lower()
end

-- 寻找适合玩家的语言
local function find_match_lang()
    local system_lang = get_system_lang()
    local match_lang = system_lang
    if lang_list then
        local function escape_lang(lang)
            return lang:gsub('%-', '') -- 过滤掉 '-' 符号，因为它在 lua 里是个正则符号，不方便做后面的匹配
        end

        system_lang = escape_lang(system_lang)

        local longest_len = 0
        local longest_lang

        for _, lang in ipairs(lang_list) do
            local elang = escape_lang(lang)
            local find_result = {system_lang:find(elang)}
            if find_result[1] and find_result[2] then
                longest_len = find_result[2] > longest_len and find_result[2] or longest_len
                longest_lang = lang
            end
        end

        if longest_lang then
            _ejoysdk.log('使用最长匹配语言: ' .. tostring(longest_lang))
            match_lang = longest_lang
        elseif default_lang then
            _ejoysdk.log('使用默认语言: ' .. tostring(longest_lang))
            match_lang = default_lang
        end
    end

    return match_lang
end

-- 获取启动语言，按以下优先级
-- 1.上次存储语言
-- 2. 匹配语言，使用手机设置、游戏语言列表过滤
function M.get_startup_lang()
    local last_lang = get_lang_keystore():get()
    if last_lang then
        _ejoysdk.log('last lang: ' .. tostring(last_lang))
        return last_lang
    else
        local match_lang = find_match_lang()
        _ejoysdk.log('has no last lang, match lang: ' .. tostring(match_lang))
        return match_lang
    end
end

-- lang_list : 游戏包语言列表，CONFIG.get('lang') 的语言只会返回它的其中一项
-- default_lang : 游戏包默认语言，当手机设置不在语言列表时，返回默认语言
function M.set_lang_list(lang_list_param, default_lang_param)
    lang_list = lang_list_param
    default_lang = default_lang_param

    _ejoysdk.log(TAG .."#set_lang_list finished, default_lang_param:" .. tostring(default_lang_param))
end

function M.get()
    return EJOYSDK_CONFIG.get_config(LANG_CONFIG_KEY)
end

function M.set(value)
    _ejoysdk.log(TAG .. "#set with value:" .. tostring(value))
    EJOYSDK_CONFIG.set_config(LANG_CONFIG_KEY, value:lower()) -- 设置后会触发 lang_config_changed
end

return M