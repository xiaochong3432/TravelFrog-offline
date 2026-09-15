local E = require 'ejoysdk_lua.ejoysdk'
local EM = require "ejoysdk_lua.ejoysdk_module"

local TAG = EM.MODULE.CHAT .. 'opentracing'

local OPENTRACING = {}
local TracerHttp
local TracerTags
local TracerContext
local TracerLink = {}


local M = {}
local RPC = {}
M.RPC = RPC

function OPENTRACING.get_tracer()
    if TracerHttp == nil then
        local ETRACER = require 'ejoysdk_lua.opentracing.ejoysdk_tracer'
        local TracerBuilder = ETRACER.TracerBuilder
        TracerHttp = TracerBuilder:New(nil, nil, 'ejoysdk'):build()
    end
    return TracerHttp
end

function OPENTRACING.get_tags()
    if TracerTags == nil then
        TracerTags = require 'ejoysdk_lua.opentracing.ejoysdk_tags'
    end
    return TracerTags
end

function OPENTRACING.get_context()
    return TracerContext
end

function OPENTRACING.set_context(context)
    TracerContext = context
end

-- 调用链上下文
function RPC.get_span_dep(span_buz)
    return TracerLink[span_buz]
end

function RPC.set_span_dep(span, span_buz)
    TracerLink[span_buz] = span
end

-- opentracing
-- opentracing 增加APM Vendor控制
function RPC.opentracing_enable()
    return E.HTTP.opentracing_enable()
end

-- opentracing 分以下步骤：
--  1. params.opentracing 启用tracing的开关 opentracing = {parent_span=parent_span, reference=reference}
--  2. request start span
function RPC.start_rpc_span(method, cmd, params)

    if not RPC.opentracing_enable() then
        return nil
    end

    local opentracing = params._opentracing
    local net_span = nil
    if opentracing and type(opentracing) == 'table' then
        -- local tracer = OPENTRACING.get_tracer_builder():New(nil, nil, 'ejoysdk'):build()

        -- 找到同业务span_buz的reference并加入
        if opentracing.span_buz ~= nil and opentracing.reference ~= nil then
            local parent_span = RPC.get_span_dep(opentracing.span_buz)
            if parent_span ~= nil and type(parent_span) == 'table' then
                net_span = OPENTRACING.get_tracer():build_span(opentracing.span_buz or method):as_child_of_span(parent_span):start()
            end
        end

        if net_span == nil then
            -- 新增一个tracer
            net_span = OPENTRACING.get_tracer():build_span(opentracing.span_buz or method):start()
        end

        net_span:set_tag(OPENTRACING.get_tags().HTTP_URL, cmd)
        net_span:set_tag(OPENTRACING.get_tags().HTTP_METHOD, method)
        net_span:set_tag(OPENTRACING.get_tags().SPAN_KIND, OPENTRACING.get_tags().SPAN_KIND_CLIENT)

    end

    return net_span
end

-- opentracing
--  3. 对Header做inject
function RPC.inject_tracing_header(span, content_header)
    -- tracing header
    if not RPC.opentracing_enable() then
        return
    end

    if span ~= nil then
        local context = span:context()
        if context ~= nil then

            local trace_id = tostring(context:get_trace_id())

            E.LOG.debug(TAG, 'RPC_trace_id=' .. tostring(trace_id))

            local context_string =  trace_id .. ':' .. tostring(context:get_span_id()) .. ':' .. tostring(context:get_parent_id()) ..':1'
            if content_header ~= nil then
                content_header[OPENTRACING.get_tags().INJECT_HTTP_HEADER] = context_string
            else
                content_header = {[OPENTRACING.get_tags().INJECT_HTTP_HEADER] = context_string}
            end

            --_ejoysdk.log("[ejoysdk]http#post#header: opentracing context_string = "..context_string)
        end
    end

    return content_header
end

-- opentracing
--  4. response finish span
function RPC.stop_rpc_span(opentracing, span, info)

    if not RPC.opentracing_enable() then
        return
    end

    if span ~= nil then
        span:set_tag(OPENTRACING.get_tags().HTTP_STATUS, tostring((info and info.code)) or "-1")
        span:finish_now()
        if opentracing.span_buz then
            -- 跟随关系不用覆盖dep，root和父子需要覆盖
            if opentracing.reference and opentracing.reference == OPENTRACING.get_tags().FOLLOWS_FROM then
                return
            end

            RPC.set_span_dep(span, opentracing.span_buz)
        end
    end
end

return M