-- OpenTracing EjoyReference
-- local E = require 'ejoysdk_lua.ejoysdk'
-- local EM = require "ejoysdk_lua.ejoysdk_module"

local Class = require 'ejoysdk_lua.ejoysdk_class'
local M = Class:Inherit("EjoyReference")
-- local TAG = EM.MODULE.OPENTRACING .. "EjoyReference"

function M:_init(span_context, type)
    -- E.LOG.debug(TAG, "_init")
    self.span_context = span_context
    self.type = type
end

function M:get_span_context()
    return self.span_context
end

function M:get_type()
    return self.type
end

-- function M:equals(o)
--     local other_spc =  o.get_span_context
--     return true
-- end

return M
