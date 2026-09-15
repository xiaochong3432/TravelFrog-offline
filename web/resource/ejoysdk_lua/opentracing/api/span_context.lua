-- SpanContext represents @class `Span` state that must propagate to
-- descendant @class `Span`\ s and across process boundaries.
--
-- SpanContext is logically divided into two pieces: the user-level "Baggage"
--  (see `Span.set_baggage_item` and `Span.get_baggage_item`) that
--  propagates across @class `Span` boundaries and any
--  tracer-implementation-specific fields that are needed to identify or
--  otherwise contextualize the associated @class `Span` (e.g., a ``(trace_id,
--  span_id, sampled)`` tuple).
local Class = require "ejoysdk_lua.ejoysdk_class"
local M = Class:Inherit("SpanContext")

-- 注释new相关 通过Class:Inherit来实现继承
-- local span_context_methods = {}
-- local span_context_mt = {
--   __name = "opentracing.span_context";
--   __index = span_context_methods;
-- }

-- local function new()
--   return setmetatable({
--   }, span_context_mt)
-- end

-- 重写init方法
function M:_init()
  
end

-- return {
--   new = new;
-- }

return M