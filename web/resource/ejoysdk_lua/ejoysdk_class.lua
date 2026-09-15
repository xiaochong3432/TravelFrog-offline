local Class = {
    --用于区别是否是一个对象 or Class or 普通table
    __ClassType__ = "<base class>"
}
Class.__index = Class

function Class:Inherit(class_type)
	local o = {}
    o.__index = o
    o.__ClassType__ = class_type or '<base class>'

    if self.__tostring 
        then
        o.__tostring = self.__tostring
    end

    return setmetatable(o, self)
end

function Class:New(...)
	local o = {}

	--子类，应该在自己的init函数中调用父类的init函数
	setmetatable(o, self)
    self._class = self

    if o._init 
        then
        o:_init(...)
    end
    return o
end

function Class:Impl(o, ...)
	--子类，应该在自己的init函数中调用父类的init函数
	setmetatable(o, self)

    if o._init 
        then
        o:_init(...)
    end
    return o
end

function Class:__tostring()
    local mt = getmetatable(self)
    local tbl_str = tostring(setmetatable(self, {}))
    setmetatable(self, mt)
    if self._class 
        then
        return self._class.__ClassType__ .. '实例: ' .. tbl_str
    else
        return self.__ClassType__ .. '类:' .. tbl_str
    end
end

return Class
