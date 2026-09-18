/* Dedicated test profile only: seed an uncollected home motion, then use the
 * real widget buttons, capture rectangle, protocol callback and persisted save. */
(async function () {
    const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
    const results = [];
    const check = (id, passed, detail) => results.push({id, passed:!!passed, detail});
    const tap = button => button.dispatchEventWith(egret.TouchEvent.TOUCH_TAP);
    document.getElementById('__notice_ok')?.click();
    const engine=window.__engine, pages=core.PageManage.getInstance();
    const models=core.ModelManage.getInstance(), moments=models.getModel(MomentModel);
    models.getModel(UserModel).setClientSettings('hasFriendVisit',true);
    function find(node, type) {
        if(node instanceof type)return node;
        for(const child of node.$children||[]){const found=find(child,type);if(found)return found;}
    }
    for(let i=0;i<12;i++) {
        const notice=find(egret.MainContext.instance.stage,Result.MainOutNotification);
        if(notice)tap(notice.cover);
        await wait(200);
    }
    engine.state.frog.status=0;
    engine.state.frog.motion=0;
    engine.state.frog.motionNextAt=Math.floor(Date.now()/1000)+10000;
    engine.state.travel.nextDepartAt=Math.floor(Date.now()/1000)+10000;
    // Keep unrelated crafted-item reward animations out of this camera fixture.
    models.getModel(HandCraftModel).boxCraftList=[];
    models.getModel(RoleModel).client_load_role(JSON.parse(JSON.stringify(engine.dispatch('client_load_role',{}).reply)));
    pages.addViewControl(MainInController,core.ViewLayerType.SceneLayer,core.RemoveViewType.HideBefore);
    await wait(1200);
    // A normal room-entry informational modal must be acknowledged before
    // testing whether a lower-layer camera control can receive a touch.
    const dismissed=[];
    for(let i=0;i<8;i++) {
        const roomAlert=find(egret.MainContext.instance.stage,ModalAlert);
        if(!roomAlert)break;
        dismissed.push(roomAlert._content);
        tap(roomAlert.cover);await wait(200);
    }
    const room=pages.getControl(MainInController,core.ViewLayerType.SceneLayer).view;
    const row=Object.values(Tabikaeru.DataManager.instance().momentData.get('list')).find(row=>row.type===1 && row.param===room.curAnimName);
    if(!row || !room.player)throw new Error('Expected a capturable home motion: '+room.curAnimName);
    engine.state.moments=(engine.state.moments||[]).filter(id=>id!==row.id);
    delete moments.data.has_map[row.id];
    engine.save();
    async function openCamera() {
        pages.addViewControl(ComponentBoxViewControl,core.ViewLayerType.WindowLayer);
        await wait(300);
        tap(pages.getControl(ComponentBoxViewControl,core.ViewLayerType.WindowLayer).view.btnCamera);
        await wait(500);
        return pages.getControl(CameraViewControl,core.ViewLayerType.WindowLayer).view;
    }
    const camera=await openCamera();
    check('home-scene',camera.picView===room,egret.getQualifiedClassName(camera.picView));
    check('stage-size',Main.stageWidth>0 && Main.stageHeight>0,[Main.stageWidth,Main.stageHeight]);
    check('capture-switch-visible',camera.btnSwitch.visible);
    const point=camera.btnSwitch.localToGlobal(camera.btnSwitch.width/2,camera.btnSwitch.height/2);
    let hit=camera.stage.$hitTest(point.x,point.y);
    const hitNames=[];
    for(let node=hit;node;node=node.parent)hitNames.push(egret.getQualifiedClassName(node));
    while(hit && hit!==camera.btnSwitch)hit=hit.parent;
    check('capture-switch-hit',!!hit,{point,hitNames});
    tap(camera.btnCamera);
    await wait(200);
    check('full-preview',camera.groupShow.visible && camera.imagePic.texture?.textureWidth>0);
    check('full-does-not-unlock',!moments.hasMoment(row.id));
    tap(camera.btnDelete);
    tap(camera.btnSwitch);
    await wait(200);
    check('crop-centered',camera.isSectionCut && camera.groupFrame.x>=0 && camera.groupFrame.y>=0 &&
        camera.groupFrame.x+camera.groupFrame.width<=camera.width && camera.groupFrame.y+camera.groupFrame.height<=camera.height,
        [camera.groupFrame.x,camera.groupFrame.y,camera.groupFrame.width,camera.groupFrame.height]);
    camera.groupTab.setSelected(2);
    await wait(100);
    check('crop-large',camera.sizeSection===350,camera.sizeSection);
    camera.checkFrame(camera.width-camera.groupFrame.width,camera.height-camera.groupFrame.height);
    tap(camera.btnCamera1);
    await wait(300);
    check('empty-crop-does-not-unlock',!moments.hasMoment(row.id));
    tap(camera.btnDelete);
    const frog=room.player.parent.localToGlobal(room.player.x,room.player.y);
    camera.checkFrame(frog.x-15-camera.sizeSection/2,frog.y-48-camera.sizeSection/2);
    tap(camera.btnCamera1);
    await wait(600);
    check('crop-preview',camera.imagePic.texture?.textureWidth===350 && camera.imagePic.texture?.textureHeight===350,
        [camera.imagePic.texture?.textureWidth,camera.imagePic.texture?.textureHeight]);
    check('moment-unlocked',moments.hasMoment(row.id) && engine.state.moments.includes(row.id),row);
    check('moment-persisted',JSON.parse(localStorage.getItem('frog.offline.save')).moments.includes(row.id));
    const popups=[];
    (function walk(node){if(node instanceof MomentPopView)popups.push(node);for(const child of node.$children||[])walk(child);})(camera.stage);
    check('moment-popup',popups.some(popup=>popup.imagePic.texture?.textureWidth>0));
    window.__cameraProbe={camera,popups,row};
    return {passed:results.every(result=>result.passed),dismissed,results};
})()
