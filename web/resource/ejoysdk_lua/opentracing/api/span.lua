-- Span represents a unit of work executed on behalf of a trace. Examples of
-- spans include a remote procedure call, or a in-process method call to a
-- sub-component. Every span in a trace may have zero or more causal parents,
-- and these relationships transitively form a DAG. It is common for spans to
-- have at most one parent, and thus most traces are merely tree structures.
local Class = require "ejoysdk_lua.ejoysdk_class"
local M = Class:Inherit("Span")

local opentracing_span_context = require 'ejoysdk_lua.opentracing.api.span_context'

-- 注释new相关 通过Class:Inherit来实现继承
-- local M = {}
-- local span_mt = {
--   __name = "opentracing.span";
--   __index = M;
-- }

-- local function new(tracer)
--   return setmetatable({
--     ["tracer_"] = tracer
--   }, span_mt)
-- end

-- 重写init方法，传入tracer
function M:_init(_tracer)
  self.tracer_ = _tracer
end

--- Provides access to the @class `SpanContext` associated with this @class
-- `Span`.
--
-- The @class `SpanContext` contains state that propagates from @class `Span`
-- to @class `Span` in a larger tracer.
--
-- @return the @class `SpanContext` associated with this @class `Span`
function M:context()
  return opentracing_span_context:New()
end

-- Provides access to the @class `Tracer` that created this span.
--
-- @return the @class `Tracer` that created this span.
function M:tracer()
  return self.tracer_
end

-- Changes the operation name.
function M:set_operation_name(_operation_name)
end

--- Indicates the work represented by this @class `Span` has completed or
-- terminated.
--
-- If `finish` is called a second time, it is guaranteed to do nothing.
--
-- @param finish_timestamp (optional) a timestamp represented by microseconds - lua sdk use milliseconds
--    since the epoch to mark when the span ended. If unspecified, the current
--    time will be used.
function M:finish(_finish_timestamp)
end

--- Attaches a key/value pair to the @class `Span`.
--
-- The value must be a string, bool, numeric type, or table of such values.
--
-- @param key key or name of the tag. Must be a string.
--
-- @param value value of the tag
function M:set_tag(_key, _value)
end

--- Attaches a log record to the @class `Span`.
--
-- For example:
--
--    span:log_kv({
--      ["event"] = "time to first byte",
--      ["packet.size"] = packet:size()})
--
-- @param key_values a table of string keys and values of string, bool, or
--      numeric types
--
-- @param timestamp an optional timestamp as a unix timestamp.
--      defaults to the current time
function M:log_kv(_key_values, _timestamp)
end

--- Stores a Baggage item in the @class `Span` as a key/value pair.
--
-- Enables powerful distributed context propagation functionality where
-- arbitrary application data can be carried along the full path of request
-- execution throughout the system.
--
-- Note 1: Baggage is only propagated to the future (recursive) children of this
-- @class `Span`.
--
-- Note 2: Baggage is sent in-band with every subsequent local and remote calls,
-- so this feature must be used with care.
--
-- @param key Baggage item key
--
-- @param value Baggage item value
function M:set_baggage_item(_key, _value)
end

--- Retrieves value of the baggage item with the given key.
--
-- @param key key of the baggage item
--
-- @return value of the baggage item with given key or `nil`
function M:get_baggage_item(_key)
  return nil
end

--- Returns an iterator over each attached baggage item
function M:each_baggage_item()
end

return M

-- 注释new相关 通过Class:Inherit来实现继承
-- return {
--   new = new;
-- }
