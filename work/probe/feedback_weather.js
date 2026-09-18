(async function () {
    document.getElementById('__notice_ok')?.click();
    const models=core.ModelManage.getInstance(), user=models.getModel(UserModel);
    user.setClientSettings('guideStep',GuideStep.Complete);
    const weather=models.getModel(WeatherModel), results=[];
    const check=(id,passed,detail)=>results.push({id,passed,detail});
    weather.weather_load({season:3,hours_type:1,weather:Tabikaeru.Define.WeatherType.light_rain});
    const first=weather.getSeasonSpine().length;
    for(let i=0;i<5;i++)weather.getSeasonSpine();
    check('48-no-accumulated-rain',weather.getSeasonSpine().length===first,{first,after:weather.getSeasonSpine().length});
    const pages=core.PageManage.getInstance();
    pages.addViewControl(MainOutController,core.ViewLayerType.SceneLayer,core.RemoveViewType.HideBefore);
    await new Promise(r=>setTimeout(r,1500));
    const scene=pages.getControl(MainOutController,core.ViewLayerType.SceneLayer).view;
    weather.weather_load({season:3,hours_type:3,weather:Tabikaeru.Define.WeatherType.sunny || 1});
    await new Promise(r=>setTimeout(r,1500));
    check('48-night-refresh',scene.seasonKey==='33',{key:scene.seasonKey,source:scene.background.source});
    weather.weather_load({season:3,hours_type:1,weather:Tabikaeru.Define.WeatherType.sunny || 1});
    await new Promise(r=>setTimeout(r,500));
    const names=weather.getSeasonSpine().map(x=>x.name);
    check('48-rain-stops',!names.includes(Tabikaeru.DefineExtra.RainSpineX.name),names);
    check('48-day-refresh',scene.seasonKey==='31' && !scene.imgLightCover.source,scene.seasonKey);
    const tables=['SeasonCover','SeasonSpine','SeasonPartical'];
    const snapshot=JSON.stringify(tables.map(k=>Tabikaeru.DefineExtra[k]));
    for(let season=1;season<=4;season++)for(let hours_type=1;hours_type<=4;hours_type++){
        weather.data={season,hours_type,weather:Tabikaeru.Define.WeatherType.light_rain};
        weather.getSeasonCover();weather.getSeasonSpine();
        weather.data.weather=Tabikaeru.Define.WeatherType.light_snow;weather.getSeasonPartical();
    }
    check('48-static-weather-tables-unchanged',JSON.stringify(tables.map(k=>Tabikaeru.DefineExtra[k]))===snapshot);
    return {passed:results.every(r=>r.passed),results};
})()
