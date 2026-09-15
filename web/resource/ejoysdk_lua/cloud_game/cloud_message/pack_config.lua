local M = {}
--协议版本号
M.VERSION = 1
M.PKG_NAME = "com.ejoy.ejoysdk_demo.go"
--消息超时
M.MSG_TIME_OUT = 3
--心跳
M.HEART_BEAT_INTERVAL = 10
M.UDP_IO_TICK = 0.1
M.TYPE = {
    HEART_BEAT = 0,
    USER_DATA = 1,
    ACK = 2
}
-- 1M
M.MAX_BODY_SIZE = 1024 * 1024
M.IS_USE_ZIP = true
M.IS_USE_BASE64 = true
M.SEND_HEART_BEAT = true

function M.init_pkg_name(pkg_name)
    M.PKG_NAME = pkg_name
end

return M
