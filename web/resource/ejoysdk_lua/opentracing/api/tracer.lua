-- Tracer is the entry point API between instrumentation code and the
-- tracing implementation.
--
-- This implementation both defines the public Tracer API, and provides
-- a default no-op behavior.
local Class = require "ejoysdk_lua.ejoysdk_class"
local M = Class:Inherit("Tracer")

local opentracing_span = require "ejoysdk_lua.opentracing.api.span"

-- 注释new相关 通过Class:Inherit来实现继承
-- local M = {}
-- local tracer_mt = {
--   __name = "opentracing.tracer";
--   __index = M;
-- }

-- local function new()
--   return setmetatable({
--   }, tracer_mt)
-- end

-- 重写init方法
function M:_init()
  
end

--- Starts and returns a new @class `Span` representing a unit of work.
--
-- Example usage:
--
-- Create a root @class `Span` (a @class `Span` with no causal references):
--
--      tracer:start_span("op-name")
--
-- Create a child @class `Span`:
--
--      tracer:start_span(
--              "op-name",
--              {["references"] = {{"child_of", parent_span:context()}}})
--
-- @param operation_name name of the operation represented by the new
--    @class `Span` from the perspective of the current service.
--
-- @param options (optional) table specifying modifications to make to the
--    newly created span. The following parameters are supported: `references`,
--    a list of referenced spans; `start_time`, the time to mark when the span
--    begins (in microseconds since epoch); `tags`, a table of tags to add to
--    the created span.
--
-- @return a @class `Span` instance
function M:start_span(_operation_name, _options)
  return opentracing_span:New(self)
end

--- Injects `span_context` into `carrier`.
--
-- Example usage:
--
--    carrier = {}
--    tracer:text_map_inject(span:context(), carrier)
--
-- @param span_context the @class `SpanContext` instance to inject
--
-- @param `carrier` a table to contain the span context
function M:text_map_inject(_span_context, _carrier)
end

--- Injects `span_context` into `carrier` using a format appropriate for HTTP
-- headers.
--
-- Example usage:
--
--    carrier = {}
--    tracer:http_headers_inject(span:context(), carrier)
--
-- @param span_context the @class `SpanContext` instance to inject
--
-- @param `carrier` a table to contain the span context
function M:http_headers_inject(_span_context, _carrier)
end

--- Returns a binary string representation for `span_context`
--
-- Example usage:
--
--    s = tracer:binary_inject(span:context())
--
-- @param span_context the @class `SpanContext` instance to inject
--
-- @return a string representing `span_context`
function M:binary_inject(_span_context)
  return ""
end

--- Returns a @class `SpanContext` instance extracted from the `carrier` or
-- `nil` if no such @class `SpanContext` could be found.
--
-- @param carrier the format-specific carrier object to extract from
--
-- @return an extracted @class `SpanContext` or `nil`
function M:text_map_extract(_carrier)
  return nil
end

--- Returns a @class `SpanContext` instance extracted from the `carrier` or
-- `nil` if no such @class `SpanContext` could be found. `http_headers_extract`
-- expects a format appropriate for HTTP headers and uses case-insensitive
-- comparisons for the keys.
--
-- @param carrier the format-specific carrier object to extract from
--
-- @return an extracted @class `SpanContext` or `nil`
function M:http_headers_extract(_carrier)
  return nil
end

--- Returns a @class `SpanContext` instance extracted from the binary string
--`carrier` or `nil` if no such @class `SpanContext` could be found.
--
-- @param carrier a binary storing an injected @class `SpanContext`
--
-- @return an extracted @class `SpanContext` or `nil`
function M:binary_extract(_carrier)
  return nil
end

return M

-- 注释new相关 通过Class:Inherit来实现继承
-- return {
--   new = new;
-- }
