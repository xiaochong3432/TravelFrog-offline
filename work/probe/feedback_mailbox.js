/* Independent profile only: exercises unread/read/empty mail and scene re-entry. */
(async function () {
    const wait=ms=>new Promise(r=>setTimeout(r,ms)), clone=x=>JSON.parse(JSON.stringify(x));
    document.getElementById('__notice_ok')?.click();
    const engine=window.__engine, models=core.ModelManage.getInstance(), pages=core.PageManage.getInstance();
    const user=models.getModel(UserModel), travel=models.getModel(TravelModel), weather=models.getModel(WeatherModel);
    if(user.getClientSettings().guideStep!==GuideStep.Complete)
        throw new Error('Run feedback_prepare.js and reload before this probe');
    engine.state.travel.nextDepartAt=Math.floor(Date.now()/1000)+10000;
    pages.addViewControl(MainOutController,core.ViewLayerType.SceneLayer,core.RemoveViewType.HideBefore);
    await wait(1500);
    let scene=pages.getControl(MainOutController,core.ViewLayerType.SceneLayer).view;
    const cases=[];
    async function inspect(label){
        travel.mail_load(clone(engine.dispatch('mail_load',{}).reply));
        scene.updateMail(); await wait(200);
        const box=scene.mailBox, p=box.localToGlobal(0,0);
        const parents=[]; for(let n=box;n;n=n.parent)parents.push({name:n.name,visible:n.visible,alpha:n.alpha});
        box.dispatchEventWith(egret.TouchEvent.TOUCH_TAP); await wait(350);
        const opened=!!scene.mailView?.parent;
        cases.push({label,boxVisible:box.visible,boxSource:box.source,boxTexture:!!box.texture,
            notification:scene.mailNotification.visible,notificationTexture:!!scene.mailNotification.texture,
            mails:travel.getMailInfoList().length,opened,x:p.x,y:p.y,width:box.width,height:box.height,
            parentsVisible:parents.every(x=>x.visible&&x.alpha>0)});
        if(scene.mailView?.parent)scene.mailView.parent.removeChild(scene.mailView);
    }
    engine.state.ads.popDay=0;
    engine.dispatch('adsmgr_share',{ads_type:1}); await wait(150);
    await inspect('unread');
    for(const mail of engine.state.mails)mail.read=true;
    await inspect('read');
    engine.state.mails=[];
    await inspect('empty');
    pages.addViewControl(MainInController,core.ViewLayerType.SceneLayer,core.RemoveViewType.HideBefore);
    await wait(1500);
    pages.addViewControl(MainOutController,core.ViewLayerType.SceneLayer,core.RemoveViewType.HideBefore);
    await wait(1500);
    scene=pages.getControl(MainOutController,core.ViewLayerType.SceneLayer).view;
    await inspect('reenter');
    weather.weather_load({season:3,hours_type:3,weather:1});await wait(600);
    await inspect('night');
    engine.state.ads.popDay=0;engine.dispatch('adsmgr_share',{ads_type:1});await wait(150);
    engine.save();
    const saved=FrogEngine.createEngine({savePath:'save.json',verbose:false});
    const persisted=saved.state.mails.length===engine.state.mails.length;
    await inspect('new-mail-again');
    scene.onHandleCamera(false);await inspect('camera-enter');
    scene.onHandleCamera(true);await inspect('camera-exit');
    for(let season=1;season<=4;season++)for(let hours_type=1;hours_type<=4;hours_type++){
        weather.weather_load({season,hours_type,weather:1});
        await wait(150);await inspect('season-'+season+'-time-'+hours_type);
    }
    // Drive the invitation tutorial's real UI callbacks. During its "enter the
    // house" step the garden intentionally hides everything except the door.
    const drawing=models.getModel(DrawingModel), oldDrawing=clone(drawing.data);
    drawing.data.state=DrawingState.invite;
    user.setClientSettings('guideDrawing',2);
    scene.checkDrawingGuide();
    const hiddenDuringGuide=!scene.mailBox.visible;
    scene.houseBtn.dispatchEventWith(egret.TouchEvent.TOUCH_TAP);
    await wait(1500);
    const restoredAfterDoor=scene.mailBox.visible&&user.getClientSettings().guideDrawing===3;
    drawing.data=oldDrawing;
    pages.addViewControl(MainOutController,core.ViewLayerType.SceneLayer,core.RemoveViewType.HideBefore);
    await wait(1500);
    scene=pages.getControl(MainOutController,core.ViewLayerType.SceneLayer).view;
    weather.weather_load({season:3,hours_type:1,weather:1});await wait(300);
    await inspect('after-invitation-guide');
    return {passed:cases.every(x=>x.boxVisible&&x.boxTexture&&x.parentsVisible&&x.opened)
        &&persisted&&hiddenDuringGuide&&restoredAfterDoor,persisted,hiddenDuringGuide,restoredAfterDoor,cases};
})()
