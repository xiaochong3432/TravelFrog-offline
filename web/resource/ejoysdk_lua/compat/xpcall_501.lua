local unpack = table.unpack or unpack

local M = {}

function M.xpcall(f, msgh, arg1, ...)

    local ret = { pcall(f, arg1, ...) }
    if not ret[1] and msgh then
        msgh()
    end

    return unpack(ret)
end

return M