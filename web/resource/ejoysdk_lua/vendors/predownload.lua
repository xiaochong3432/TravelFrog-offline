-------------------------------------------------------------------------------
-- 预约下载Vendor https://yuque.antfin.com/ejoy-platform/user_guide/predownload
--
-- Created Date: 2023.02.16
-- Author: 四境
--
-- Copyright (c) 2023 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local EI = require 'ejoysdk_lua.ejoysdk_init'
local Vendor = require "ejoysdk_lua.vendors.vendor"
local EM = require "ejoysdk_lua.ejoysdk_module"
local UNI = require "ejoysdk_lua.vendors.unisdk"
local UIM = require "ejoysdk_lua.user_info_manager"
local VENDOR_NAME = "PREDOWNLOAD"
local M = Vendor:Inherit(VENDOR_NAME)

local TAG = EM.MODULE.VENDORS.PREDOWNLOAD
local inited

-- 启动游戏activity
local SYNC_START_GAME = "SYNC_START_GAME"
local LUA_KEY_DIRECT_START_GAME_ACTIVITY = "direct_start_game_activity"

local login_handler = function(_user_info)

end

local function gangplank_logout_handler()

end

local is_gangplank_inited = false
function M.start_game_activity(direct_start_game_activity)
    local params = {
        [LUA_KEY_DIRECT_START_GAME_ACTIVITY] = direct_start_game_activity
    }

    -- 由于lua和native并行初始化，可能lua调用的时候native还没有初始化完成
    if is_gangplank_inited then
        E.LOG.debug(TAG, "gangplank initted, now start_game_activity")
        UNI.sync_call(VENDOR_NAME, SYNC_START_GAME, params, nil)
    else
        -- 此时会覆盖gangplank的init回调监听，不过此时已经要切换游戏activity了，切游戏时当前的lua虚拟机会关闭，改为游戏的activity, 所以不影响
        local ALL_CHANNEL = 'ALL'
        UNI.register_init_listener(ALL_CHANNEL, function(succ2, msg)
            if succ2 then
                E.LOG.debug(TAG, "native init succ, now start game activity")
                UNI.sync_call(VENDOR_NAME, SYNC_START_GAME, params, nil)
            else
                E.LOG.warn(TAG, "native init failed")
            end
        end)

        local _params = {}
        UNI.init(ALL_CHANNEL, _params)
    end
end

local function gangplank_inited_handler()
    E.LOG.debug(TAG, "recev gangplank inited")
    is_gangplank_inited = true
end

-- ======================== 3.public ========================
function M.init(_opt, cb)
    if inited then
        E.LOG.debug(TAG, 'predownload had inited')
        return
    end
    inited = true
    
    local EPRD = require 'ejoysdk_lua.predownload.ejoysdk_predownload'
    if EPRD.is_finish_predownload() then
        -- 判断是否下载完成 + 切换过大包
        local predownload_game_info = {
            [UIM.PKG_INFO_KEY.KEY_PREDOWNLOAD_GAME_RUN_MODE] = 'predownload_finish',
            [UIM.PKG_INFO_KEY.KEY_PKG_GAME_RUN_MODE_TYPE] = 'predownload_finish'
        }
        UIM.set_predownload_game_mode(predownload_game_info)
        EPRD.stat_finish()
    end

    E.LOG.debug(TAG, 'predownload vendor start init!')
    
    ET.subscribe(EI.SUBSCRIBE_GANGPLANK_INITED, gangplank_inited_handler)
    ET.subscribe(ET.gangplank.LOGIN, login_handler)
    ET.subscribe(ET.gangplank.LOGOUT, gangplank_logout_handler)

    cb(true)
end

return M