/* Dedicated profile: place the same material into two workbench slots in one visit. */
(async function(){
  document.getElementById('__notice_ok')?.click();
  const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
  const engine=window.__engine;
  const models=core.ModelManage.getInstance();
  const furniture=models.getModel(FurnitureModel);
  const items=models.getModel(ItemModel);
  const pages=core.PageManage.getInstance();
  const firstMaterial=10101;
  const secondMaterial=10102;

  engine.state.furniture.bench=[-1,-1,-1,-1,-1,-1,-1,-1,-1,-1];
  engine.state.furniture.benchLock=0;
  engine.state.items.house=(engine.state.items.house||[]).filter(row=>
    ![firstMaterial,secondMaterial,10001,10002,10003,10004,10005,10006,10007].includes(Number(row.item_id)));
  engine.state.items.house.push({item_id:firstMaterial,count:1},{item_id:secondMaterial,count:1});
  items.item_load_items(engine.dispatch('item_load_items',{}).reply);
  furniture.furniture_load_furniture(engine.dispatch('furniture_load_furniture',{}).reply);

  pages.addViewControl(FurnitureBenchViewController,core.ViewLayerType.WindowLayer,core.RemoveViewType.HideBefore);
  await wait(500);
  const bench=pages.getControl(FurnitureBenchViewController,core.ViewLayerType.WindowLayer)?.view;
  if(!bench)throw new Error('workbench did not open');

  const openSlot=async index=>{
    bench.onItemListTap({itemIndex:index});
    await wait(250);
    const bag=pages.getControl(ToolBagViewController,core.ViewLayerType.NoticeLayer)?.view;
    if(!bag)throw new Error('material picker did not open for slot '+index);
    bag.validateNow?.();
    bag.updatePage();
    await wait(100);
    const rows=[];
    const provider=bag.list.dataProvider;
    for(let i=0;i<(provider?.length||0);i++)rows.push(provider.getItemAt(i));
    return {bag,rows};
  };

  const first=await openSlot(0);
  const firstRow=first.rows.find(row=>Number(row.item_id)===firstMaterial);
  first.bag.onListTap({item:firstRow});
  await wait(450);
  const afterFirst={
    clientCount:items.getHouseItemCount(firstMaterial),
    engineCount:(engine.state.items.house.find(row=>Number(row.item_id)===firstMaterial)||{}).count||0,
    slots:furniture.getBenchItems().slice()
  };

  const second=await openSlot(1);
  const staleFirstRow=second.rows.find(row=>Number(row.item_id)===firstMaterial);
  const secondRow=second.rows.find(row=>Number(row.item_id)===secondMaterial);
  const secondListCount=secondRow?.count;
  second.bag.onListTap({item:secondRow});
  await wait(450);
  const afterSecond={
    clientCount:items.getHouseItemCount(secondMaterial),
    engineCount:(engine.state.items.house.find(row=>Number(row.item_id)===secondMaterial)||{}).count||0,
    slots:furniture.getBenchItems().slice()
  };
  const passed=firstRow?.count===1
    &&afterFirst.clientCount===0&&afterFirst.engineCount===0
    &&!staleFirstRow
    &&secondListCount===1
    &&afterSecond.clientCount===0&&afterSecond.engineCount===0
    &&afterSecond.slots[0]===firstMaterial&&afterSecond.slots[1]===secondMaterial;
  return {passed,firstListCount:firstRow?.count,afterFirst,staleFirstShown:!!staleFirstRow,secondListCount,afterSecond};
})()
