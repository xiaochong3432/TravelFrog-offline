local compat = require "ejoysdk_lua.compat.ejoysdk_compat"
local compat_string = compat.string
local pack_config = require "ejoysdk_lua.cloud_game.cloud_message.pack_config"
local EM = require "ejoysdk_lua.ejoysdk_module"

local _TAG = EM.MODULE.CLOUD_GAME .. 'pack_udp_data'

local M = {}

--[[
short version; //协议版本号，2字节
unsigned short id; //消息流水号，2字节，从0递增到0xFE然后回到0不断循环，注意0xFF保留不用
short type; //消息类型，0：心跳包；1：数据包
            云端初始化完成后要立即发送一次心跳包给CGS进程，此后每8秒发送一次。
            CGS收到心跳包后会将包的完整数据如数回复回来，数据包则不会回复
char pkg_name[64]; //游戏包的包名，用于CGS进程做区分，不得多于64字节字符串，少于64字节则补0
short length; //数据段的长度，2字节，所以业务数据不要超过4kB（2的16次方）
char* data; //数据段，长度由length指定
所有2字节字段数据在传输的时候都使用大端序
--]]
function M.pack_data(version, id, type, pkg_name, data)
    if pack_config.IS_USE_BASE64 then
        data = _ejoysdk_crypt.base64encode(data)
    end
    local data_tb = {}
    table.insert(data_tb, compat_string.pack(">i2", version))
    table.insert(data_tb, compat_string.pack(">I2", id))
    table.insert(data_tb, compat_string.pack(">i2", type))
    table.insert(data_tb, compat_string.pack("c64", pkg_name))
    table.insert(data_tb, compat_string.pack(">s2", data))
    return table.concat(data_tb)
end

--lua51和53的实现不一样，这里就不用string.pack了
function M._pack_cn(len,str)
    if #str>len then
        print("_pack_cn too long",str)
        str = string.sub(str,1,len)
    end
    local tb = {str}
    for _=#str+1,len,1 do
        table.insert(tb,'\0')
    end
    return table.concat(tb)
end

function M.unpack_data(receive_data)
    local tb = {}
    local pos = 1
    tb.version, pos = compat_string.unpack(">i2", receive_data, pos)
    tb.id, pos = compat_string.unpack(">I2", receive_data, pos)
    tb.type, pos = compat_string.unpack(">i2", receive_data, pos)
    tb.pkg_name, pos = compat_string.unpack("c64", receive_data, pos)
    tb.data = compat_string.unpack(">s2", receive_data, pos)
    if pack_config.IS_USE_BASE64 then
        tb.data  = _ejoysdk_crypt.base64decode(tb.data)
    end
    return tb
end

return M
