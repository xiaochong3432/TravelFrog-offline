
-- OpenTracing EjoySpanContext
-- local E = require 'ejoysdk_lua.ejoysdk'
local ESPC = require 'ejoysdk_lua.opentracing.api.span_context'

local M = ESPC:Inherit("EjoySpanContext")
-- local TAG = "EjoySpanContext"

-- sample预留
-- local flag_sampled = 1
-- local flag_debug = 1

-- 重写init方法
-- 128bit trace_id
function M:_init(trace_id, span_id, parent_id, baggage)
    -- E.LOG.debug(TAG, "_init" .. " trace_id:" .. trace_id .. " span_id:" .. span_id)
    self.trace_id = trace_id
    self.span_id = span_id
    self.parent_id = parent_id
    self.baggage = baggage or {}
end

function M:get_trace_id()
    return self.trace_id
end

function M:get_span_id()
    return self.span_id
end

function M:get_parent_id()
    return self.parent_id
end

function M:has_trace()
    return self.trace_id ~= nil and self.span_id ~= nil
end

function M:get_baggage()

    return self.baggage
end

function M:get_baggage_count()
    return #self.baggage
end

-- function M:baggage_items()
--     return self.baggage
-- end

function M:get_baggage_item(key)
    local value = nil
    if self.baggage then
        value = self.baggage[key]
    end
    return value
end

function M:to_span_id()
    return tostring(self.span_id)
end

function M:to_trace_id()
    return tostring(self.trace_id)
end

-- sampled 和 debug标记未实现情况下是0
function M:get_flag()
    return 0
end
-- function M:to_string()
--     return tostring(self.trace_id)
-- end

return M
