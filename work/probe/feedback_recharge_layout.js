/* Dedicated profile: open the real clover purchase page and report its geometry. */
(async function(){
 document.getElementById('__notice_ok')?.click();
 const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
 const pages=core.PageManage.getInstance();
 pages.addViewControl(RechargeViewController,core.ViewLayerType.WindowLayer,core.RemoveViewType.HideBefore);
 await wait(1400);
 const control=pages.getControl(RechargeViewController,core.ViewLayerType.WindowLayer),view=control?.view;
 if(!view)throw new Error('recharge view did not open');
 const rect=node=>node&&({x:node.x,y:node.y,width:node.width,height:node.height,measuredWidth:node.measuredWidth,
   measuredHeight:node.measuredHeight,visible:node.visible,scaleX:node.scaleX,scaleY:node.scaleY});
 const page=view.pageGroup?.getCurPage?.()||view;
 const rows=[];
 const list=page?.listItem;
 if(list)for(let i=0;i<list.numElements;i++)rows.push(rect(list.getVirtualElementAt(i)));
 else for(const row of view.viewList||[])rows.push(rect(row));
 const walk=(node,depth=0,out=[])=>{
   if(depth<3)for(const child of node?.$children||[]){out.push({type:child.constructor?.name,...rect(child)});walk(child,depth+1,out);}
   return out;
 };
 const before=window.__engine.state.clover;
 if(view.viewList?.[0])view.viewList[0].dispatchEventWith(egret.TouchEvent.TOUCH_TAP);
 await wait(500);
 const after=window.__engine.state.clover;
 const compact=view instanceof RechargeSimpleView&&rows.length===6&&rows.every((row,i)=>row.height===85&&row.y===85*i);
 const inside=rows.every(row=>row.y+row.height<=view.c_scrollerContent.height+1)
   &&view.c_scroller.height<=view.c_view.height;
 return {passed:compact&&inside&&after===before+400,stage:{width:egret.MainContext.instance.stage.stageWidth,height:egret.MainContext.instance.stage.stageHeight},
   view:rect(view),panel:rect(view.c_view),page:view.constructor?.name,pageBounds:rect(page),rows,
   compact,inside,purchase:{before,after},tree:walk(view)};
})()
