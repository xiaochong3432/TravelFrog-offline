-- OpenTracing EjoyTracer
local E = require 'ejoysdk_lua.ejoysdk'
local ETR_I = require 'ejoysdk_lua.opentracing.api.tracer'
local EREPORT = require 'ejoysdk_lua.opentracing.ejoysdk_remote_reporter'
local ESCOPE = require 'ejoysdk_lua.opentracing.ejoysdk_scope'
local ESPAN = require 'ejoysdk_lua.opentracing.ejoysdk_span'
local ESPANCONTEXT = require 'ejoysdk_lua.opentracing.ejoysdk_span_context'
local ECODEC = require 'ejoysdk_lua.opentracing.ejoysdk_text_map_codec'
local ETAGS = require 'ejoysdk_lua.opentracing.ejoysdk_tags'
local EREFERENCE = require "ejoysdk_lua.opentracing.ejoysdk_reference"
local EUUID = require "ejoysdk_lua.ejoysdk_uuid"
local EM = require "ejoysdk_lua.ejoysdk_module"
local Class = require 'ejoysdk_lua.ejoysdk_class' 

local M = ETR_I:Inherit("EjoyTracer")
local TAG = EM.MODULE.OPENTRACING .. "EjoyTracer"
local LUA_OPENTRACING_VERSION = '1.3.2.0' -- 对应 jaeger core版本

function M:unique_id()
  --jaeger 使用64bit或128bit随机数，当前使用64bit的span_id, 128bit的tracer_id
  return EUUID.random_i64()
end

-- 根据jaeger额外补充
-- Tracer Builder
local TracerBuilder = Class:Inherit('TracerBuilder')
function TracerBuilder:_init(sampler, reporter, service_name)
    -- E.LOG.debug(TAG, "TracerBuilder:_init")

    self.sampler = sampler
    self.reporter = reporter
    -- self.registry = registry
    self.service_name = service_name
    self.tags = {}
    self.scope_manager = ESCOPE.EjoyScope:New()
    self.http_codec = ECODEC:New(nil, nil, true)
end

function TracerBuilder:with_reporter(reporter)
  self.reporter = reporter
  return self
end

function TracerBuilder:with_sampler(sampler)
  self.sampler = sampler
  return self
end

-- function TracerBuilder:register_injector(format, injector)
--   self.registry.register(format, injector);
--   return self
-- end

-- function TracerBuilder:register_extractor(format, extractor)
--   self.registry.register(format, extractor);
--   return self
-- end

function TracerBuilder:with_scope_manager(scope_manager)
  self.scope_manager = scope_manager
  return self
end

function TracerBuilder:with_tag(k, v)
  -- table.insert(self.tags, { key = k, value = v })
  self.tags[k] = v
  return self
end

function TracerBuilder:with_tags(kv_tags)

  if self.tags ~= nil then
    for k, v in pairs(kv_tags) do
      self.tags[k] = v
    end
  end

  return self
end

function TracerBuilder:create_tracer()
  -- E.LOG.debug(TAG, "TracerBuilder:create_tracer")
  return M:New(self)
end

function TracerBuilder:build()
  -- E.LOG.debug(TAG, "TracerBuilder:build")
  -- E.LOG.debug(TAG, "TracerBuilder:self" .. tostring(self))
  if self.reporter == nil then
      -- E.LOG.debug(TAG, "TracerBuilder:new reporter")
      self.reporter = EREPORT:New()
      if self.reporter == nil then
        E.LOG.debug(TAG, "TracerBuilder:new reporter is nil")
        return
      end
  end
  -- if self.sampler == nil then

  -- end
  return self:create_tracer()
end

M.TracerBuilder = TracerBuilder

-- Span Builder
local SpanBuilder = Class:Inherit('SpanBuilder')
function SpanBuilder:_init(tracer, operation_name, start_time_ms)
  self.tracer = tracer
  self.operation_name = operation_name
  self.start_time_ms = start_time_ms
  self.references = {}
  self.tags = {}
  self.ignore_active_span = false
end

function SpanBuilder:add_reference(reference_type, reference)
  
    if reference == nil then
      return self
    elseif reference_type ~= ETAGS.CHILD_OF and reference_type ~= ETAGS.FOLLOWS_FROM then
      return self
    else 
      local new_refer = EREFERENCE:New(reference, reference_type)
      table.insert(self.references, new_refer)
    end 

    return self
end

function SpanBuilder:as_child_of(span_context)
  return self:add_reference(ETAGS.CHILD_OF, span_context)
end

function SpanBuilder:as_child_of_span(parent)

  if parent ~= nil then
    return self:add_reference(ETAGS.CHILD_OF, parent:context())
  end 

  return self:add_reference(ETAGS.CHILD_OF, nil)
end

function SpanBuilder:with_tag(k, v)
  -- table.insert(self.tags, { key = k, vlaue = v })
  self.tags[k] = v
  return self
end

function SpanBuilder:with_start_time_ms(start_time_ms)
  self.start_time_ms = start_time_ms
  return self
end

function SpanBuilder:preferred_reference()
  -- 找到最后一个child
  -- self.references存储的是ejoysdk_reference的数组
  local prefer = self.references[1]
  local length = #self.references
  if length > 1 then
    for i = 2, length do
      local reference = self.references[i]
      if (ETAGS.CHILD_OF == reference.reference_type) and (ETAGS.CHILD_OF ~= prefer.reference_type) then
          prefer = reference
          break
      end
    end
  end
  return prefer:get_span_context()
end

function SpanBuilder:create_new_context()
  -- local debug_id = 0
  local span_id = M:unique_id()
  local trace_id = M:unique_id()..span_id
  -- local flags = 1
  -- tracing todo: debug tags插入、sample采样处理

  local new_span_context = ESPANCONTEXT:New(trace_id, span_id, 0, self.baggage)
  -- this.tags.putall(samplingstatus.gettags());
  return new_span_context

end

function SpanBuilder:create_child_context()
  local parent = self:preferred_reference() 
  local span_id = M:unique_id()
  local child_span_context = ESPANCONTEXT:New(parent.trace_id, span_id, parent.span_id, self.flags, self.baggage)
  return child_span_context
end

function SpanBuilder:get_baggage()
  
  if #self.references == 1 then
    return self.references[1]:get_span_context():get_baggage()
  else
    local baggage = nil
    for _,v in pairs(self.references) do
      if v.get_baggage ~= nil then
        if baggage == nil then
          baggage = {}
        end
        for bk,bv in pairs(v.get_baggage()) do
          -- table.insert(baggage, { key = bk, value = bv })
          baggage[bk] = bv
        end
      end
    end
  end
end

function SpanBuilder:is_rpc_server()
  return ETAGS.SPAN_KIND_SERVER == self.tags[ETAGS.SPAN_KIND]
end

function SpanBuilder:ignore_active_span()
  self.ignore_active_span = true
  return self
end

function SpanBuilder:start()

  if self.references == nil then
    self.references = {}
  end

  -- if #self.references == 0 
  local new_span_context
  if not self.references or #self.references == 0 then
    new_span_context = self:create_new_context()
  elseif not self.references[1]:get_span_context():has_trace() then
    new_span_context = self:create_new_context()
  else
    new_span_context = self:create_child_context()
  end
  -- E.LOG.debug(TAG, "new_span_context")
  -- timestamp 处理 
  if not self.start_time_ms then
    self.start_time_ms = E.time_ms()
  end
  -- (tracer, operation_name, span_context, start_timestamp, tags, references

  local new_span = ESPAN:New(self.tracer, self.operation_name, new_span_context, self.start_time_ms, self.tags, self.references)
  return new_span
  
end

M.SpanBuilder = SpanBuilder

-- local function is_sampled()
-- if (this.references != null) {
--     iterator var1 = this.references.iterator();

--     while(var1.hasnext()) {
--         reference reference = (reference)var1.next();
--         if (reference.getspancontext().issampled()) {
--             return true;
--         }
--     }
-- }
-- end

-- 重写init方法
function M:_init(builder)
  -- E.LOG.debug(TAG, "_init " .. tostring(self))

  if builder == nil then 
    E.LOG.debug(TAG, "buider is nil")
    return 
  end

  -- E.LOG.debug(TAG, "service_name:" .. tostring(builder.service_name) .. " reporter:" .. tostring(builder.reporter) .. " sampler:" .. tostring(builder.sampler) .. " scope_manager:" .. tostring(builder.scope_manager))

  self.servic_ename = builder.service_name
  self.reporter = builder.reporter
  self.sampler = builder.sampler
  self.scope_manager = builder.scope_manager
  -- self.use_traceid_128bit = builder.use_traceid_128bit
  self.version = LUA_OPENTRACING_VERSION
  self.tags = {}
  table.insert(self.tags, { key = ETAGS.VERSION, value = self.version })
  self.ipv4 = 0

end
-- function M:start_span(operation_name, options)
--   return opentracing_span.New(self)
-- end

function M:get_version()
  return self.version
end

function M:get_service_name() 
  return self.servicename
end

function M:get_tags() 
  return self.tags
end

function M:get_ipv4()
  return self.ipv4
end

function M:get_reporter() 
  return self.reporter
end

-- function M:text_map_inject(span_context, carrier)
-- end

-- function M:text_map_extract(carrier)
--   return nil
-- end


function M:http_headers_inject(span_context, carrier)
  self.http_codec:inject(span_context, carrier)
end

function M:http_headers_extract(carrier)
  return self.http_codec:extract(carrier)
end

function M:context_as_string(span_context)
  return self.http_codec:context_as_string(span_context)
end

-- function M:binary_inject(span_context)
--   return ""
-- end

-- function M:binary_extract(carrier)
--   return nil
-- end

-- 根据jaeger额外补充
function M:scope_manager()
  return self.scope_manager
end

function M:active_span()
  return self.scope_manager:active_span()
end

-- reporter
function M:report_span(span)
  if self.reporter == nil then
    E.LOG.warn(TAG, "reporter is nil")
    return 
  end

  self.reporter:report_span(span)
end

local function create_span_builder(tracer, operation_name)

  return M.SpanBuilder:New(tracer, operation_name)
end

function M:build_span(operation_name)
  return create_span_builder(self, operation_name)
end

function M:close() 
  self.reporter:close()
  -- self.sampler.close()
end

function M:get_hostname()
  return ''
end

-- function M:use_traceid_128bit()
--     return self.use_traceid_128bit
-- end

function M:activate_span(span)
  return self.scope_manager:activate(span)
end

return M
