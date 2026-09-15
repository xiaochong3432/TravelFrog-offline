local Time = require "ejoysdk_lua.apm-sdk-lua.common.time.time"
local E = require "ejoysdk_lua.ejoysdk"

local get_now = os.time

---return a unix time, the number of seconds elapsed since 1970
---@return second float
function Time.now()
    return get_now()
end

---return a unix time of utc, the number of seconds elapsed since 1970
---@return second float
function Time.now_utc()
    local utc_ms = E.system_ms()
    if utc_ms and utc_ms > 0 then
        return math.floor(utc_ms / 1000)
    end
    return get_now()
end

---return a unix time, the number of milliseconds elapsed since 1970
---@return millisecond float
function Time.now_ms()
    -- E.system_ms() 某些环境可以拿到毫秒级的时间戳
    return E.system_ms() or os.time() * 1000
end

-- 返回CPU运行时间 用于计算elapse
---@return millisecond float
function Time.system_clock()
    return E.system_clock()
end

return Time
