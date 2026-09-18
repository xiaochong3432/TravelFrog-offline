/* Inspect the real hit target as well as visible/texture flags. */
(async function () {
    document.getElementById('__notice_ok')?.click();
    const wait=ms=>new Promise(r=>setTimeout(r,ms));
    const scene=core.PageManage.getInstance().getControl(MainOutController,core.ViewLayerType.SceneLayer).view;
    const stage=egret.MainContext.instance.stage, box=scene.mailBox;
    function findNotice(node){
        if(node instanceof Result.MainOutNotification)return node;
        for(const child of node.$children||[]){const found=findNotice(child);if(found)return found;}
    }
    for(let i=0;i<8;i++){
        const notice=findNotice(stage);if(!notice)break;
        notice.cover.dispatchEventWith(egret.TouchEvent.TOUCH_TAP);await wait(200);
    }
    scene.scroll();
    const home=scene.scroller.viewport.scrollH;
    const cases=[];
    for(const scroll of [0,home,scene.background.width-scene.scroller.width]){
        scene.scroller.viewport.scrollH=scroll;await wait(300);
        const p=box.localToGlobal(box.width/2,box.height/2),hit=stage.$hitTest(p.x,p.y);
        const rect=document.querySelector('canvas').getBoundingClientRect();
        const names=[];for(let n=hit;n;n=n.parent)names.push(n.__class__||n.constructor.name);
        cases.push({scroll,boxVisible:box.visible,centerOnScreen:p.x>=0&&p.x<stage.stageWidth,
            hitMailbox:hit===box,hitNames:names,tap:{x:p.x*rect.width/stage.stageWidth,y:p.y*rect.height/stage.stageHeight}});
    }
    return {passed:cases[1].boxVisible&&cases[1].centerOnScreen&&cases[1].hitMailbox,cases};
})()
