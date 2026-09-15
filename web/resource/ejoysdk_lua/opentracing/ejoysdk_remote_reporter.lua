-- OpenTracing EjoyReporter
local E = require 'ejoysdk_lua.ejoysdk'
local Class = require 'ejoysdk_lua.ejoysdk_class'
local M = Class:Inherit("EjoyRemoteReporter")
local EM = require "ejoysdk_lua.ejoysdk_module"

local TAG = EM.MODULE.OPENTRACING .. "EjoyRemoteReporter"

function M:_init()
    -- E.LOG.debug(TAG, "_init")
end

function M:report_span(span)
    -- 打入APM的span
    local ok, trace_collector = pcall(require, "ejoysdk_lua.apm-sdk-lua.trace.collector")
    if ok then
        if trace_collector ~= nil then
            trace_collector.collect(span)
        end
    else
        E.LOG.debug(TAG, "collector not exist")
    end
    
end

return M
