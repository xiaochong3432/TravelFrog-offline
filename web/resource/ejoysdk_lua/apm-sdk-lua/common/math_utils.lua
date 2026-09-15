-------------------------------------------------------------------------------
-- Created Date: 2021.11.10
-- Author: 三傻
-- Desc: 数学运算相关
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local M = {}
M.__index = M

-- 增量方差计算类  参考 http://www.calmkart.com/?p=369
local variance = {}
variance.__index = variance

function variance.new()
    local obj = {
        avg = 0,
        std = 0, --标准差
        var = 0, --方差
        n = 0
    }
    return setmetatable(obj, variance)
end

-- update 增量计算方差
function variance:update(value)
    local incre_avg = (self.n * self.avg + value) / (self.n + 1)
    self.var = (self.n * (self.var + (incre_avg - self.avg) ^ 2) + (incre_avg - value) ^ 2) / (self.n + 1)
    self.avg = incre_avg
    self.std = math.sqrt(self.var)
    self.n = self.n + 1
end

-- get_std 获取标准差
function variance:get_std()
    return self.std
end

-- get_var 获取方差
function variance:get_var()
    return self.var
end

-- 计算复位
function variance:clear()
    self.sth = 0
    self.avg = 0
    self.n = 0
end

function M.new_variance()
    return variance.new()
end

return M