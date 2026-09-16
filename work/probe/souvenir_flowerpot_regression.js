/* Run with cdp_drive.js --step in:work/probe/souvenir_flowerpot_regression.js.
 * Uses the real client page/scroller and bundled engine in an isolated profile. */
(async function () {
    const check = (ok, message) => { if (!ok) throw new Error(message); };
    const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
    document.getElementById('__notice_ok')?.click();
    check(!!window.__engine, 'in-page engine missing');
    const models = core.ModelManage.getInstance();
    const drawing = models.getModel(DrawingModel);
    const user = models.getModel(UserModel);
    const oldDrawing = drawing.data;
    const settings = user.getClientSettings();
    const oldGuide = settings.guideStep;
    const stage = egret.MainContext.instance.stage;
    const cases = [[0,-1,false], [1,0,false], [2,-1,false], [3,-1,false],
                   [2,0,true], [3,1,true], [0,-1,false]];
    const results = [];
    try {
        settings.guideStep = GuideStep.Complete;
        for (const [state, guest, expected] of cases) {
            drawing.data = Object.assign({}, oldDrawing, {state, guest, bag:[-1,-1,-1,-1,-1,-1]});
            const view = new BagTable();
            view.width = stage.stageWidth;
            view.height = stage.stageHeight;
            stage.addChild(view);
            try {
                await wait(350);
                check(!!view.table, 'BagTable did not construct its pages');
                check(!!view.souvenir === expected, 'wrong souvenir visibility: ' + state + '/' + guest);
                results.push({state, guest, souvenir:!!view.souvenir});
            } finally { if (view.parent) view.parent.removeChild(view); }
        }
        const initial = new DrawingModel();
        initial.initModel();
        check(initial.data.state === DrawingState.wait, 'initial client state must wait');
        initial.destroy();
        const engine = window.__engine;
        // Real bundle harvesting and save reload must preserve the selected variety.
        engine.state.flowerpot.slots = [
            {id:2010604, stage:3, plantedAt:1}, {id:2010802, stage:3, plantedAt:1},
        ];
        const tulip = engine.dispatch('furniture_flowerpot_harvest', {type:1,index:1});
        const tomato = engine.dispatch('furniture_flowerpot_harvest', {type:1,index:2});
        check(tulip.reply.item_list[0].item_id === 202254, 'night queen tulip mismatch');
        check(tomato.reply.item_list[0].item_id === 4103, 'cherry tomato mismatch');
        const reloaded = FrogEngine.createEngine({savePath:'save.json',verbose:false});
        check(reloaded.state.items.house.some(x=>x.item_id===202254 && x.count>0), 'flower save lost');
        check(reloaded.state.items.house.some(x=>x.item_id===4103 && x.count>0), 'crop save lost');
        window.__regressionResult = {passed:true, cases:results, harvest:[202254,4103], persisted:true};
        console.log('REGRESSION PASS ' + JSON.stringify(window.__regressionResult));
        return window.__regressionResult;
    } finally {
        drawing.data = oldDrawing;
        settings.guideStep = oldGuide;
    }
})()
