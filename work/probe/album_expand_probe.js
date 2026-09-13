/* 相册扩容：点悬浮球上真实存在的那个按钮，然后核对状态与客户端读数。 */
(function () {
  var eng = window.__engine;
  if (!eng) return JSON.stringify({ error: 'no engine' });
  var out = {};

  function findButton(label) {
    var all = document.querySelectorAll('button, div, span');
    for (var i = 0; i < all.length; i++) {
      if (all[i].textContent === label) return all[i];
    }
    return null;
  }

  out.hasExpandButton = !!findButton('扩容相册到上限');
  out.hasStateButton = !!findButton('相册用量');

  var before = eng.dispatch('client_gm', { cmd: 'album_state' });
  out.before = before.reply && before.reply.info;

  var btn = findButton('扩容相册到上限');
  if (btn && btn.click) btn.click();

  var after = eng.dispatch('client_gm', { cmd: 'album_state' });
  out.after = after.reply && after.reply.info;

  /* 客户端侧：相册扩容提示读的就是 getHouseItemCount(9000) */
  var Item = core.ModelManage.getInstance().getModel(ItemModel);
  out.clientCount9000 = Item.getHouseItemCount(9000);

  /* 满扩容之后放一张新照片进相册：客户端走 album_save_new */
  eng.state.albumPending = eng.state.albumPending || [];
  eng.state.pictureSeq = (eng.state.pictureSeq || 0) + 1;
  var row = { id: eng.state.pictureSeq, pic_id: 3102, read: 0, new: 1 };
  eng.state.albumPending.push(row);
  var saved = eng.dispatch('album_save_new', { id: row.id });
  out.saveNewCode = saved.reply && saved.reply.code;
  out.pictures = (eng.state.pictures || []).length;
  return JSON.stringify(out, null, 1);
})()