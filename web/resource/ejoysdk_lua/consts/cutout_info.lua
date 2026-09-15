-- 定义特殊异形屏机型的刘海区域，只描述机型本身的刘海信息, 应用全屏时有用,lua初始化时注册到native端
-- 以机器型号为Key(全小写,android取Build.Model), 包括四个方向上的刘海信息
-- 每个方向的刘海信息包括
-- -- type: 刘海类型: 1:存在 , 2: 不存在 , 0: 未知
-- -- regions: 刘海区域信息 【x,y,width,height]四个维度,有多少添加多少,一个都没就这字段不要也罢
-- -- safe_inset: 安全区域, 以[左,上,右,下]的顺序描述靠近四个边的安全距离偏移
-- 其中一个或多个方向没有刘海信息，则传空table即可，默认全0

-- 配置中心下发对应的格式：{"Pixel 2":{"type":1,"cutout_rects":[{"width":100,"height":100,"y":0,"x":0},{"width":100,"height":100,"y":1080,"x":0}],"safe_inset":[0,0,0,0]}}

return {
    ['android'] = {
        --["mi max 2"] = {
        --    type = 1,
        --    safe_inset = {
        --        0,100,0,100
        --    }
        --},
        --["mi max 2"] = {
        --    type = 1,
        --    regions = {
        --        {},{x=0,y=0,width=100,height=100},{}
        --    },
        --    safe_inset = {
        --        0,100,0,100
        --    }
        --}
    },
    ['ios'] = {

    },
    ['windows'] = {

    }
}

