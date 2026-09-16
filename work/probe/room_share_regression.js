/* Isolated browser profile only: exercises real models, scenes and share callbacks. */
(async function () {
    const check = (ok, text) => { if (!ok) throw new Error(text); };
    const wait = ms => new Promise(r => setTimeout(r, ms));
    const clone = x => JSON.parse(JSON.stringify(x));
    document.getElementById('__notice_ok')?.click();
    const engine = window.__engine, models = core.ModelManage.getInstance();
    const user = models.getModel(UserModel), role = models.getModel(RoleModel);
    const fm = models.getModel(FurnitureModel), weather = models.getModel(WeatherModel);
    const pages = core.PageManage.getInstance();
    for (const [key,value] of Object.entries({guideStep:GuideStep.Complete, guideFurniture:6,
        guideFurnitureNotice:true, guideAnnualReview:true, guideDrawing:3, guideHandCraft:true}))
        user.setClientSettings(key,value);
    engine.state.travel.nextDepartAt = Math.floor(Date.now()/1000)+10000;
    engine.state.frog.motionNextAt = Math.floor(Date.now()/1000)+10000;
    const setRole = (status,motion) => {
        engine.state.frog.status=status; engine.state.frog.motion=motion;
        role.client_load_role(clone(engine.dispatch('client_load_role',{}).reply));
    };
    setRole(0,0);
    fm.furniture_load_furniture(clone(engine.dispatch('furniture_load_furniture',{}).reply));
    weather.weather_load({season:3,hours_type:3,weather:1});
    pages.addViewControl(MainInController,core.ViewLayerType.SceneLayer,core.RemoveViewType.HideBefore);
    await wait(1800);
    const room = pages.getControl(MainInController,core.ViewLayerType.SceneLayer).view;
    check(room.getFurnitureSlot('ani_25_1').numChildren===1,'default table candle has no animation');
    check(room.cover_light.visible,'night candle glow missing');
    check(!!room.getFurnitureSlot('ani_25_1').getChildAt(0).parent,'candle detached');
    const motions=[];
    for (const motion of [0,1,2,3,4,10,11,12,13]) {
        setRole(0,motion);
        await wait(450);
        check(!!room.player?.parent,'frog disappeared for motion '+motion);
        if (motion>=10) {
            check(room.curAnimName==='sleep_'+(motion-9),'sleep did not refresh');
            check(!!room.player.armature,'sleep spine not loaded');
            check(!room.cover_light.visible,'sleeping should extinguish candles');
        }
        motions.push(room.curAnimName);
    }
    setRole(0,4);
    check(room.cover_light.visible,'waking did not relight candles');
    weather.weather_load({season:3,hours_type:1,weather:1});
    check(!room.cover_light.visible,'morning did not remove candle glow');
    check(room.bgGroup.filters.length===0,'morning tint still present');
    weather.weather_load({season:3,hours_type:3,weather:1});
    room.updateSeason(); room.updateSeason();
    check(room.group_5_1.$children.filter(x=>x===room.offlineNightParticles).length===1,'night effect duplicated');

    engine.state.flowerpot.slots=[{id:2010604,stage:3,plantedAt:1}];
    engine.state.decoration={hasList:[],putId:0,status:0};
    const harvest=engine.dispatch('furniture_flowerpot_harvest',{type:1,index:1});
    check(harvest.reply.item_list[0].num===1,'harvest must yield one flower');
    role.client_load_decorate(clone(engine.dispatch('client_load_decorate',{}).reply));
    room.on_enterFlowerMap_tap(); await wait(350);
    let vase=pages.getControl(FlowerPotViewControl,core.ViewLayerType.WindowLayer).view;
    check(!vase.data.enable,'vase must remain locked at home');
    vase.close();
    setRole(1,0);
    check(!room.cover_light.visible,'empty house must have no flame');
    room.on_enterFlowerMap_tap(); await wait(350);
    vase=pages.getControl(FlowerPotViewControl,core.ViewLayerType.WindowLayer).view;
    check(vase.data.enable,'vase is locked while frog is away');
    check(vase.list.dataProvider.source.some(r=>r.id===10054),'harvested tulip absent from vase');
    role.changeDecoration(10054);
    await wait(400);
    check(engine.state.decoration.putId===10054 && role.decorationPutID===10054,'vase selection failed');
    check(!!room.flower.source && !!room.flower.texture,'vase flower has no image');
    check(!engine.state.items.house.some(r=>r.item_id===202254 && r.count>0),'flower was duplicated');
    vase.close();

    const ads=models.getModel(AdsModel), travel=models.getModel(TravelModel);
    const first=engine.state.mails.length;
    engine.state.ads.popDay=0;
    ads.req_share(1); await wait(100);
    check(engine.state.mails.length===first+1,'daily share produced no mail');
    check(travel.getMailInfoList().length===engine.state.mails.length,'daily mail missing in client');
    const opened=engine.dispatch('lottery_open',{}).reply;
    const extra=opened.extra_item;
    const stock=()=>engine.state.items.house.find(r=>r.item_id===extra.item_id)?.count||0;
    const before=stock();
    ads.req_share(3); await wait(100);
    const mail=engine.state.mails.at(-1);
    check(mail.items[0]?.item_id===extra.item_id,'lottery share mailed wrong item');
    check(stock()===before,'lottery bonus was credited before opening mail');
    check(travel.getMailInfoList().some(r=>r.id===mail.id),'share mail missing in mailbox model');
    travel.openMailInfo(mail.id);
    check(stock()===before+extra.count,'mail did not pay promised item');
    const count=engine.state.mails.length;
    ads.req_share(3);
    check(engine.state.mails.length===count,'duplicate share paid again');
    for (let i=0;i<6;i++) { engine.state.ads.popDay=0; ads.req_share(1); }
    core.SocketManage.getInstance().send('mail_load_mails',null,1,5,false);
    check(travel.getMailInfoList().length===engine.state.mails.length,'paginated mailbox lost reward mails');
    const reloaded=FrogEngine.createEngine({savePath:'save.json',verbose:false});
    check(reloaded.state.decoration.putId===10054,'vase lost on reload');
    // Leave a visible sleeping frog for the screenshot.
    core.DisplayManage.getInstance().popupLayer.removeChildren();
    setRole(0,11);
    await wait(600);
    return {passed:true,motions,candle:true,vaseLockedAtHome:true,vaseFlower:room.flower.source,
        harvest:1,shareMail:true,mailPages:true,persisted:true};
})()
