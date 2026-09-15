-- OpenTracing EjoyTextMapCodec
local E = require 'ejoysdk_lua.ejoysdk'
local ESPC = require 'ejoysdk_lua.opentracing.ejoysdk_span_context'
local EM = require "ejoysdk_lua.ejoysdk_module"
local Class = require 'ejoysdk_lua.ejoysdk_class'
local M = Class:Inherit("EjoyTextMapCodec")
local TAG = EM.MODULE.OPENTRACING .. "EjoyTextMapCodec"


local SPAN_CONTEXT_KEY = "uber-trace-id"
local BAGGAGE_KEY_PREFIX = "uberctx-"
local JAEGER_BAGGAGE_KEY = "jaeger-baggage"

function M:_init(context_key, baggage_prefix, url_encoding)
    -- E.LOG.debug(TAG, "_init")
    self.baggage_prefix = baggage_prefix or BAGGAGE_KEY_PREFIX
    self.url_encoding = url_encoding
    self.context_key = context_key or SPAN_CONTEXT_KEY
end

local function encoded_value(value)
    return value
end

local function decoded_value(value)
    return value
end

function M:prefixed(key, prefix)
    return key..prefix
end

function M:un_prefixed(key, prefix)
    return string.sub(key, #prefix - #key)
end

-- split_string(session_id, ':')[1]
function M:context_as_string(span_context)

    if span_context == nil then
        return ''
    end

    local context_string = tostring(span_context:get_trace_id()) .. ':' .. tostring(span_context:get_span_id()) .. ':' .. tostring(span_context:get_parent_id()) ..':' .. tostring(span_context:get_flag())
    return context_string
end

function M:inject(span_context, carrier)
    E.LOG.debug(TAG, "inject")

    carrier = carrier or {}

    carrier[self.context_key] = M:context_as_string(span_context)

    for k, v in pairs(span_context.baggage_items) do
        carrier[M:prefixed(k, self.baggage_prefix)] = encoded_value(v)
    end
end

-- local function context_from_string(value)
--     if value ~= nil then
--         local value_ids = E.split_string(value, ':')
--         if #value_ids ~= 4 then
--             E.LOG.debug(TAG, "inject")
--         else
--             local v_trace_id = value_ids[1]
--             local v_span_id = value_ids[2]
--             local v_parent_id = value_ids[3]
--             local new_span_context = ESPC:New(v_trace_id, v_span_id, v_parent_id)
--             return new_span_context
--         end
--     end
--     return nil
-- end

function M:extract(carrier)
    E.LOG.debug(TAG, "extract")

    local e_baggage = {}
    local e_trace_id = nil
    local e_span_id = nil
    local e_parent_id = nil

    for k, v in pairs(carrier) do
        if k == self.contextKey then
            local value_ids = E.split_string(decoded_value(v), ':')
            if #value_ids ~= 4 then
                E.LOG.debug(TAG, "extract contextKey error")
            else
                e_trace_id = value_ids[1]
                e_span_id = value_ids[2]
                e_parent_id = value_ids[3]
            end
        elseif E.Utils.start_with(k, self.baggage_prefix) then
            table.insert(e_baggage, { key = M:un_prefixed(k) , value = decoded_value(v) })
        elseif k == JAEGER_BAGGAGE_KEY then
            local header_var_list = E.split_string(decoded_value(v), ',')
            for var_info in pairs(header_var_list) do
                local detail_var_list = E.split_string(var_info, '=')
                if #detail_var_list ~= 2 then
                    E.LOG.debug(TAG, "extract header_var_list error")
                else
                    table.insert(e_baggage, { key = var_info[1], value = var_info[2] })
                end
            end
        end
    end

    local e_span_context = ESPC:New(e_trace_id, e_span_id, e_parent_id, e_baggage)
    return e_span_context
end

return M



