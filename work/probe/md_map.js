/* Start a museum adventure and open the map page -- the state the explore view
   expects. (Opening it with `cur_museum = 0` makes the client itself show
   「地图数据错误」 and close the window, which is its own documented behaviour.) */
const out = {};
const E = window.__engine;
const start = E.dispatch('museumday_start_advance', { id: 1 });
out.start = start.reply;
const loaded = E.dispatch('museumday_load', {}).reply;
out.cur_museum = loaded.cur_museum;
out.path = loaded.path.length;
out.compass = loaded.compass;
try {
  core.PageManage.getInstance().addViewControl(MuseumDayExploreViewControl,
    core.ViewLayerType.WindowLayer);
  out.opened = true;
} catch (e) {
  out.opened = String(e && e.message || e);
}
return JSON.stringify(out);
