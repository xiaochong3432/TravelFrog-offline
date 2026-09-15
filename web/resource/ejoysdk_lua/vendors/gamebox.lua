local E = require 'ejoysdk_lua.ejoysdk'
local UNI = require "ejoysdk_lua.vendors.unisdk"
local Vendor = require "ejoysdk_lua.vendors.vendor"
local ECC = require 'ejoysdk_lua.ejoysdk_config_center'
local EW = require 'ejoysdk_lua.ejoysdk_web'
local EG = require 'ejoysdk_lua.ejoysdk_gangplank'
local EM = require "ejoysdk_lua.ejoysdk_module"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local AEGIS_DATA = require 'ejoysdk_lua.aegis.aegis_collect_data'
local BADGE_MGR = require 'ejoysdk_lua.badge.ejoysdk_badge_manager'
local BADGE_ANN = require 'ejoysdk_lua.badge.ejoysdk_badge_anns'
local V2_HISTORY = require 'ejoysdk_lua.airline_v2.airline_v2_history'

local CHANNEL = "GAMEBOX"
local native_vendor = CHANNEL
local TAG = EM.MODULE.VENDORS.GAMEBOX .. CHANNEL
local inited = false

local STATE = {
    NOT_INIT = 0,
    INITED = 1,
    ACCOUNT_LOGINED = 2,
    PLAYER_LOGINED = 3,
}
local state = STATE.NOT_INIT -- 0: 未初始化 1： 已初始化 2：账号已登录 3：角色已设置

-- ======================== 1.native call ========================
--初始化
-- local CAST_INIT = "CAST_INIT"
--展示主页
local SYNC_SHOW_GAMEBOX = "SYNC_SHOW_GAMEBOX"
--隐藏主页
local SYNC_HIDE_GAMEBOX = "SYNC_HIDE_GAMEBOX"
--展示浮标
local SYNC_SHOW_FLOATER = "SYNC_SHOW_FLOATER"
--隐藏浮标
local SYNC_HIDE_FLOATER = "SYNC_HIDE_FLOATER"
--更新配置
local CAST_UPDATE_GAMEBOX = "CAST_UPDATE_GAMEBOX"
--更新红点
local CAST_UPDATE_BADGE = "CAST_UPDATE_BADGE"
--是否显示gamebox
local SYNC_ISSHOWING_GAMEBOX = "SYNC_ISSHOWING_GAMEBOX"
--是否显示浮球
local SYNC_ISSHOWING_FLOATER = "SYNC_ISSHOWING_FLOATER"

local floater_config

local M = Vendor:Inherit(CHANNEL)

M.SYSCODE = {
    ANNOUNCEMENT = "announcement",
    ACCOUNT = "account",
    ACTIVITY = "activity",
    BBS = "bbs",
    EXCHANGE = "exchange",
    CUSTOMER = "customer"
}

-- ======================== 1.mark ========================
local function is_empty(str)
    return not str or '' == str;
end

local function has_inited()
    return inited
end

local function has_login()
    local user_info = EG.user_info()
    local ret = user_info and user_info.uid and user_info.token and '' ~= user_info.uid and '' ~= user_info.token
    return ret
end

local function has_player_info()
    local player_info = EG.player_info()
    local ret = player_info and player_info.player_id and '' ~= player_info.player_id
    return ret
end

local function get_scene()
    local scene = 0
    if has_inited() then
        scene = 0
    end
    if has_login() then
        scene = scene + 1
    end
    if has_player_info() then
        scene = scene + 1
    end
    -- _ejoysdk.log("scene=" .. scene)
    return scene
end


-- ======================== 2.config ========================
local function get_config_from_cc()
    local usercenter_config
    local is_overseas = E.CONFIG.get_config(E.CONFIG.KEY.MULTI_REGIONS_ENABLED)
    if is_overseas then
        usercenter_config = ECC.get_config(ECC.NAMESPACE.USERCENTER_OVERSEA)
    else
        usercenter_config = ECC.get_config(ECC.NAMESPACE.USERCENTER_CN)
    end

    if usercenter_config and usercenter_config.config then
        return usercenter_config.config
    end

    return nil
end

-- 配置处理部分
-- 配置中心获取数据处理
local function usercenter_config_handler(_config)
    local uc_namespace_config = _config or {}
    local ucc_config = uc_namespace_config.config
    if ucc_config ~= nil then
        M.update_gamebox_config(ucc_config, {})
    end
end

--[[
-- 更新列表配置信息，通知native
-- ucc_config 配置中心获取数据处理
    sysCode : "account",
    name : "客服", 显示title
    url : "https://general.aligames.com/lx_customer_relay_page", 需要拼接from_scene=box
    appId : "ieu-account",
    treeId : 红点树id
    showScene : 展示场景：0登录前展示; 1登录后展示; 2进入游戏后展示;
    "ext":{
        "jump":0, -- 为0表示不跳出，jump为1表示跳出浮窗并打开webview
    }
]]
function M.update_gamebox_config(ucc_config, params)
    local had_config_data = false
    local total_config = {}
    if ucc_config and ucc_config.game_box_tab then
        local _params = params or {}
        local auth_info = V2_HISTORY.get_auth_info()
        local local_start_up_data = {
            init_params = _params,
            airlineToken = (auth_info or {}).airlineToken,
            accountId = (auth_info or {}).accountId,
            aegis_data = AEGIS_DATA.get_encrypt_data()
        }

        --local_start_up_data = EW.get_startup_data(local_start_up_data)

        local options = EW.get_fill_default_options({})

        -- 历史问题兼容，避免浮窗出现适配条
        if _ejoysdk.os() == "ios" then
            options.use_cutout = true
        end

        local injection = {}

        local game_box_i18n = ucc_config.game_box_i18n or {}

        local scene = get_scene()
        local game_box_tab = {}
        local badge_tree = {}
        for _, info in ipairs(ucc_config.game_box_tab) do
            -- showScene : 展示场景：0登录前展示; 1登录后展示; 2进入游戏后展示;
            if info.showScene <= scene then
                -- 生成injection，自动白名单
                local url = info["url"]
                if url and type(url) == "string" then
                    local host = string.match(url, "[%w%-%.]*%(.[%w%-]+%.%w+)%/([^?#]*)")
                    if host then
                        injection[host] = {
                            startupData = local_start_up_data,
                            transparent = options.transparent
                        }
                    end
                    -- url
                end

                -- 替换一下i18n name
                local map_name_key = tostring(info["sysCode"]) .. "." .. tostring(info["name"])
                if game_box_i18n and game_box_i18n[map_name_key] then
                    info["name"] = game_box_i18n[map_name_key]
                end

                -- 触发红点
                if not is_empty(info.badgeAppId) then
                    local tree = {
                        app_id = info.badgeAppId,
                        tree_id = info.badgeTreeId or ''
                    }
                    if info.sysCode == M.SYSCODE.ANNOUNCEMENT then
                        -- 公告和特殊处理
                        tree.app_id = BADGE_ANN.APP.announcement
                        tree.ann_type = info.ext.ann_type

                        info.badgeAppId = BADGE_ANN.APP.announcement
                        info.badgeTreeId = BADGE_ANN.TYPE.GAMEBOX
                    end
                    table.insert(badge_tree, tree)
                end

                table.insert(game_box_tab, info)
            end
        end

        E.LOG.debug(TAG, badge_tree)
        BADGE_MGR.batch_get_tree(badge_tree)

        EW.fill_injection_with_common_params(injection, options)

        -- 列表配置
        total_config.gamebox_config = {
            -- 列表配置
            game_box_tab = game_box_tab,
            -- webview配置
            webview_config = { injection = injection, options = options },
            -- 复制等描述配置，复制：copied.label，复制toast: copied.toast
            game_box_i18n = game_box_i18n
        }
        --total_config.pkg_info = E.get_pkg_info()
        total_config.user_info = EG.user_info() or {}
        -- 浮球初始化配置
        if floater_config then
            total_config.floater_config = floater_config
        end

        E.LOG.debug(TAG, total_config)

        UNI.cast(CHANNEL, CAST_UPDATE_GAMEBOX, total_config)

        had_config_data = true
    else
        E.LOG.debug(CHANNEL, 'configcenter game_box_tab config is nil')
    end

    return had_config_data
end

-- ======================== 3.publlic ========================
-- 对外暴露接口
-- 显示gamebox
-- gamebox和floater的联动在native层处理
function M.show_gamebox()
    UNI.sync_call(native_vendor, SYNC_SHOW_GAMEBOX, {})
end

-- 隐藏gamebox
function M.hide_gamebox()
    UNI.sync_call(native_vendor, SYNC_HIDE_GAMEBOX, {})
end

-- 显示浮标
function M.show_floater()
    UNI.sync_call(native_vendor, SYNC_SHOW_FLOATER, {})
end

-- 隐藏浮标
function M.hide_floater()
    UNI.sync_call(native_vendor, SYNC_HIDE_FLOATER, {})
end

-- 更新红点数据
function M.update_badge(_config)
    local config = _config or {}

    UNI.cast(CHANNEL, CAST_UPDATE_BADGE, config)
end

-- 是否显示gamebox
function M.is_showing_gamebox()
    local ret = UNI.sync_call(CHANNEL, SYNC_ISSHOWING_GAMEBOX, {}) or {}
    return ret.value or false
end

-- 是否显示浮标
function M.is_showing_floater()
    local ret = UNI.sync_call(CHANNEL, SYNC_ISSHOWING_FLOATER, {}) or {}
    return ret.value or false
end

-- ======================== 4.handler ========================

local scene_handler = function()
    E.LOG.debug(TAG, "scene update")
    local ucc_config = get_config_from_cc()
    M.update_gamebox_config(ucc_config, {})
end

-- ======================== 5.life cycle ========================
function M.init(opt, cb)

    (require "ejoysdk_lua.ejoysdk_js_bridge").init() -- 注册全局事件监听

    ET.subscribe(ET.gangplank.INITED, function()
        inited = true
        state = STATE.INITED
        scene_handler()
    end)

    ET.subscribe(ET.gangplank.ACQUIRE, function()
        --E.log("scene_update acquire state="..tostring(state))
        if state >= STATE.INITED then
            scene_handler()
        end
        state = STATE.ACCOUNT_LOGINED
    end) -- 账号登录
    ET.subscribe(ET.gangplank.LOGOUT, function()
        --E.log("scene_update logout state="..tostring(state))
        if state >= STATE.INITED then
            scene_handler()
        end
        state = STATE.INITED
    end)
    ET.subscribe(ET.gangplank.PLAYER_OFFLINE, function()
        --E.log("scene_update logout state="..tostring(state))
        if state >= STATE.INITED then
            scene_handler()
        end
        state = STATE.ACCOUNT_LOGINED
    end)
    ET.subscribe(ET.gangplank.PLAYER_ONLINE, function()
        --E.log("scene_update login state="..tostring(state))
        -- 有一些外部调用方可能会直接调publish通知到这里，造成重复通知
        if state <= STATE.ACCOUNT_LOGINED then
            scene_handler()
        end
        state = STATE.PLAYER_LOGINED
    end)

    if opt and opt.position and opt.align then
        floater_config = {
            position = opt.position,
            align = opt.align
        }
    end

    -- 配置中心订阅配置变更
    local is_overseas = E.CONFIG.get_config(E.CONFIG.KEY.MULTI_REGIONS_ENABLED)
    if is_overseas then
        ECC.subscribe(ECC.NAMESPACE.USERCENTER_OVERSEA, usercenter_config_handler)
    else
        ECC.subscribe(ECC.NAMESPACE.USERCENTER_CN, usercenter_config_handler)
    end

    local init_config = get_config_from_cc()

    local had_config_data = M.update_gamebox_config(init_config, {})

    -- 初始化红点服务
    BADGE_MGR.init()

    -- 配置中心初始化完成后，保证外部在回调里面调用show_floater时已有数据
    if not had_config_data and not ECC.is_data_inited then
        local wait4_cc_handler = function(...)
            E.LOG.debug(CHANNEL, 'configcenter getdata inited')
            local ucc_config = get_config_from_cc()
            M.update_gamebox_config(ucc_config, {})
        end
        ET.subscribe(ET.config_center.DATA_INITED, wait4_cc_handler)
    end

    if cb then
        cb(true)
    end
    -- E.LOG.debug(CHANNEL, 'inited')
end

return M