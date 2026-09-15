(function () {
  var out = {};
  var msg = document.querySelector('#__save_panel div:nth-child(2)');
  var panel = document.getElementById('__save_panel');
  /* the note line is the panel's second child (title, note, rows…) */
  var divs = panel ? panel.querySelectorAll(':scope > div') : [];
  out.note = divs.length > 1 ? divs[1].textContent : null;
  var save = {};
  try { save = JSON.parse(window.localStorage.getItem('frog.offline.save') || '{}'); }
  catch (e) { out.parseErr = String(e.message); }
  out.handbookCollections = save.handbook ? save.handbook.collections.length : null;
  out.handbookSpecialtys = save.handbook ? save.handbook.specialtys.length : null;
  out.encyAll = save.encyAll === true;
  out.museumUnlocked = save.museumUnlocked === true;
  out.pictures = save.pictures ? save.pictures.length : null;
  out.furniture = save.furniture && save.furniture.owned ? save.furniture.owned.length : null;
  return JSON.stringify(out);
})()
