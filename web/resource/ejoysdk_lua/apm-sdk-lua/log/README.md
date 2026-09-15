## 用法
1. 设置正确的搜索路径，保证能够搜索到`ejoysdk_lua.apm-sdk-lua.log.init`

2. 保存以下代码到`test.lua`
```lua
local Log = require "ejoysdk_lua.apm-sdk-lua.log"

Log.Info("hello world")
Log.InfoS("today is {week}", os.date("%A"))

if Log.V(3) then
    Log.Info("verbose >= 3 -- true")
end

Log.config({verbose=2})
if Log.V(3) then
    -- don't output
    Log.Info("verbose >= 3 -- false")
end
```

3. 执行`lua test.lua`, 会得到如下输出
```bash
[2021-05-28 10:20:43.000 INF *app*]@test.lua:3: hello world
[2021-05-28 10:20:43.000 INF *app*]@test.lua:4: today is week:Friday
[2021-05-28 10:20:43.000 INF *app*]@test.lua:7: verbose >= 3 -- true
```

4. 项目可以根据自身需要，灵活配置，打造适合自身的 log 系统

5. 详细用法及配置，请参考[日志系统](https://yuque.antfin.com/gserver/tadpole/kxag73)