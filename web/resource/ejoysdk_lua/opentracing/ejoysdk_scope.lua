-- OpenTracing EjoyScope
-- local E = require 'ejoysdk_lua.ejoysdk'
local Class = require 'ejoysdk_lua.ejoysdk_class'
local M = {}

-- EjoyScope
-- wrapped = span
local EjoyScope = Class:Inherit('EjoyScope')
function EjoyScope:_init()

end

function EjoyScope:config_with_span(scop_manager, wrapped)
    self.scop_manager = scop_manager
    self.wrapped = wrapped
    self.to_restore = scop_manager.tls_scope().get()
    scop_manager.tls_scope.set(self);
end

function EjoyScope:close()
    if self.scope_manager.tls_scope.get() ~= self then
        return
    end

    self.scop_manager.tls_scope.set(self.to_restore)
end

function EjoyScope:span()
    return self.wrapped
end

-- jaeger里面的scope是依附Thread的，在lua只有单线程标识，所以可以直接返回当前scope即可
function EjoyScope:get()
    return self
end

function EjoyScope:set(new_scope)
    return new_scope
end

M.EjoyScope = EjoyScope

-- EjoyScopeManager
local EjoyScopeManager = Class:Inherit('EjoyScopeManager')
function EjoyScopeManager:_init()
    self.tls_scope = M.EjoyScope:New()
end

function EjoyScopeManager:activate(span)
    self.tls_scope.config_with_span(self, span)
    return self.tls_scope
end

function EjoyScopeManager:active_span()
    local scope = self.tls_scope.get()
    if scope == nil then
        return nil
    else
        return scope.span
    end
end

M.EjoyScopeManager = EjoyScopeManager
return M
