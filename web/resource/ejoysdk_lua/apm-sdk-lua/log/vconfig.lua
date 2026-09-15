-- Log.V config
local config = {}

config.available_fnames = {
    -- 可以调用的接口
    Warning = true,
    Warningf = true,
    WarningS = true,
    Info = true,
    Infof = true,
    InfoS = true,
    Debug = true,
    Debugf = true,
    DebugS = true
}

config.max_level = 0xF -- 最多 15 级

return config
