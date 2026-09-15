local UNI = require "ejoysdk_lua.vendors.unisdk"
local Vendor = require "ejoysdk_lua.vendors.vendor"
local CHANNEL = "NAVER_GAME"

--展示主页
local CAST_SHOW_CAFE_PAGE = "CAST_SHOW_CAFE_PAGE"
--停用sdk
local CAST_FINISH_SDK = "CAST_FINISH_SDK"
--维护页
local CAST_SHOW_SORRY_PAGE = "CAST_SHOW_SORRY_PAGE"
--公告
local CAST_SHOW_BOARD_PAGE = "CAST_SHOW_BOARD_PAGE"
--留言
local CAST_SHOW_FEED_PAGE = "CAST_SHOW_FEED_PAGE"


local M = Vendor:Inherit(CHANNEL)

function M.show_cafe_page()
    UNI.cast(CHANNEL, CAST_SHOW_CAFE_PAGE, {})
end

function M.finish_sdk()
    UNI.cast(CHANNEL, CAST_FINISH_SDK, {})
end

function M.show_sorry_page()
    UNI.cast(CHANNEL, CAST_SHOW_SORRY_PAGE, {})
end

--board_id公告id
function M.show_board_page(board_id)
    local params = {
        board_id = board_id
    }
    UNI.cast(CHANNEL, CAST_SHOW_BOARD_PAGE, params)
end

--feed_id 留言id
--is_temp_feed_id 是否预留言
function M.show_feed_page(feed_id, is_temp_feed_id)
     local params = {
         feed_id = feed_id,
         is_temp_feed_id = is_temp_feed_id
     }
    UNI.cast(CHANNEL, CAST_SHOW_FEED_PAGE, params)
end

return M