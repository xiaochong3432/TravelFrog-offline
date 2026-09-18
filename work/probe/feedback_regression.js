/* Run only with a dedicated test profile: changes that profile's game state. */
(async function () {
    const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
    const clone = x => JSON.parse(JSON.stringify(x));
    const results = [];
    const check = (id, ok, detail) => results.push({id, passed:!!ok, detail});
    document.getElementById('__notice_ok')?.click();
    const engine=window.__engine, models=core.ModelManage.getInstance();
    const user=models.getModel(UserModel), role=models.getModel(RoleModel);
    const fm=models.getModel(FurnitureModel), weather=models.getModel(WeatherModel);
    const pages=core.PageManage.getInstance();
    for (const [k,v] of Object.entries({guideStep:GuideStep.Complete,guideFurniture:6,
        guideFurnitureNotice:true,guideAnnualReview:true,guideDrawing:3,guideHandCraft:true})) user.setClientSettings(k,v);
    engine.state.travel.nextDepartAt=Math.floor(Date.now()/1000)+10000;
    engine.state.frog.motionNextAt=Math.floor(Date.now()/1000)+10000;
    const setRole=(status,motion)=>{
        engine.state.frog.status=status; engine.state.frog.motion=motion;
        role.client_load_role(clone(engine.dispatch('client_load_role',{}).reply));
    };
    setRole(0,0);
    fm.furniture_load_furniture(clone(engine.dispatch('furniture_load_furniture',{}).reply));
    weather.weather_load({season:3,hours_type:3,weather:1});
    pages.addViewControl(MainInController,core.ViewLayerType.SceneLayer,core.RemoveViewType.HideBefore);
    await wait(1500);
    let room=pages.getControl(MainInController,core.ViewLayerType.SceneLayer).view;
    const flame=()=>room.getFurnitureSlot('ani_25_1').numChildren>0;
    check('40-night-awake',flame(),room.curAnimName);
    for(let i=0;i<2;i++) {
        pages.addViewControl(MainOutController,core.ViewLayerType.SceneLayer,core.RemoveViewType.HideBefore);
        await wait(1200);
        pages.addViewControl(MainInController,core.ViewLayerType.SceneLayer,core.RemoveViewType.HideBefore);
        await wait(1200);
        room=pages.getControl(MainInController,core.ViewLayerType.SceneLayer)?.view || room;
        check('40-reenter-'+i,flame(),room.curAnimName);
    }
    setRole(0,11); await wait(300);
    check('56-sleep-hat',room.frogCap.visible,room.curAnimName);
    check('40-sleep-unlit',!flame(),room.curAnimName);
    setRole(0,0);
    weather.weather_load({season:3,hours_type:1,weather:1});
    check('40-day-awake',flame(),room.curAnimName);
    const eggs=models.getModel(EasterEggModel);
    const oldEggs=eggs.data.egg_list;
    eggs.data.egg_list=[Tabikaeru.EasterEgg.Grooming];
    room.updateFlogStatus();
    check('56-mirror-hat',!room.frogCap.visible,room.curAnimName);
    eggs.data.egg_list=oldEggs;
    setRole(1,0);
    check('56-away-hat',!room.frogCap.visible);
    check('40-away-unlit',!flame());
    setRole(0,0);
    pages.addViewControl(MainOutController,core.ViewLayerType.SceneLayer,core.RemoveViewType.HideBefore);
    await wait(600);
    const garden=pages.getControl(MainOutController,core.ViewLayerType.SceneLayer).view;
    engine.dispatch('furniture_load_flowerpot',{});
    engine.state.flowerpot.slots[0]={id:2010604,stage:3,plantedAt:1};
    fm.furniture_load_flowerpot(clone(engine.dispatch('furniture_load_flowerpot',{}).reply));
    garden.update_flowerpot();
    garden.scroller.viewport.scrollH=123;
    await wait(100);
    const before=garden.scroller.viewport.scrollH;
    const inventory=()=>engine.state.items.house.filter(x=>x.item_id===202254).reduce((sum,x)=>sum+x.count,0);
    const inventoryBefore=inventory();
    fm.req_flowerpot_harvest(1,1,()=>{});
    await wait(1500);
    check('52-harvest-scroll',Math.abs(garden.scroller.viewport.scrollH-before)<1,
        {before,after:garden.scroller.viewport.scrollH});
    check('52-harvest-completed',inventory()===inventoryBefore+1,
        {slot:engine.state.flowerpot.slots[0],recent:(window.__probeLog||[]).filter(x=>x.includes('flowerpot')).slice(-6)});
    const channel=BaseChannel.getInstance();
    check('32-save-handler',channel.save_texture_to_album!==BaseChannel.prototype.save_texture_to_album,
        channel.save_texture_to_album.toString().slice(0,160));
    const texture=new egret.RenderTexture();
    texture.drawToTexture(garden,new egret.Rectangle(0,0,500,350));
    try { check('32-save-png',await channel.save_texture_to_album(texture,true)); }
    finally {texture.dispose();}
    await wait(500);
    return {passed:results.every(r=>r.passed),results};
})()
