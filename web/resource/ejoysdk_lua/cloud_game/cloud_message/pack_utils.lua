local pack_config = require "ejoysdk_lua.cloud_game.cloud_message.pack_config"
local pack_msg_data = require "ejoysdk_lua.cloud_game.cloud_message.pack_msg_data"
local pack_udp_data = require "ejoysdk_lua.cloud_game.cloud_message.pack_udp_data"
local EM = require "ejoysdk_lua.ejoysdk_module"

local _TAG = EM.MODULE.CLOUD_GAME .. 'pack_utils'

local M = {}
local msg_sequence_id = 0
local udp_sequence_id = 0

function M.generate_msg_id()
    msg_sequence_id = msg_sequence_id + 1
    if msg_sequence_id == 0xff then
        msg_sequence_id = 1
    end
    return msg_sequence_id
end

function M.generate_udp_id()
    udp_sequence_id = udp_sequence_id + 1
    -- FIXME 这里不是short
    if udp_sequence_id == 0xff then
        udp_sequence_id = 1
    end
    return udp_sequence_id
end

local function _create_udp_data(msg_id, type, data)
    local msg_data = pack_msg_data.pack_data(pack_config.VERSION, msg_id, type, data)
    return pack_udp_data.pack_data(pack_config.VERSION, M.generate_udp_id(), type, pack_config.PKG_NAME, msg_data)
end

function M.create_heatbeat_pack()
    local data = "hi"
    local type = pack_config.TYPE.HEART_BEAT
    return _create_udp_data(M.generate_msg_id(), type, data)
end

function M.create_userdata_pack(data, msg_id)
    local type = pack_config.TYPE.USER_DATA
    if not msg_id then
        msg_id = M.generate_msg_id()
    end
    return _create_udp_data(msg_id, type, data), msg_id
end

function M.create_ack_pack(msg_id)
    local type = pack_config.TYPE.ACK
    local data = ""
    return _create_udp_data(msg_id, type, data)
end

function M.parse_pack(receive_data)
    local udp_pack = pack_udp_data.unpack_data(receive_data)
    local msg_pack = pack_msg_data.unpack_data(udp_pack.data)
    return msg_pack, udp_pack
end

return M
