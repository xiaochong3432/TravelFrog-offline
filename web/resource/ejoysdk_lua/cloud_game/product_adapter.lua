local init_sdk_fun = require "ejoysdk_lua.cloud_game.cloud_sdk_init"
local CC = require "ejoysdk_lua.cloud_game.cloud_config"
-- local EM = require "ejoysdk_lua.ejoysdk_module"

-- local TAG = EM.MODULE.CLOUD_GAME .. 'product_adapter'

local M = {}

function M.init_sdk(...)
    _ejoysdk.log("init_sdk in product adapter")
    if CC.SelfStart then
        init_sdk_fun(...)
    else
        local cb = ...
        if cb then
            cb(true)
        end
    end
end

local os = _ejoysdk.os()
if os == 'android' then
    M.asset_download = require "ejoysdk_lua.cloud_game.asset_download_default"
elseif os == 'ios' then
    M.asset_download = require "ejoysdk_lua.cloud_game.asset_download_odr"
end

return M
