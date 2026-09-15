(function () {
  /* After a full page reload the engine must load the same counts back: that is the
     persistence half of the check. Reads only the save, not the panel. */
  var out = { fresh: true };
  var save = {};
  try { save = JSON.parse(window.localStorage.getItem('frog.offline.save') || '{}'); }
  catch (e) { out.parseErr = String(e.message); }
  out.handbookCollections = save.handbook ? save.handbook.collections.length : null;
  out.handbookSpecialtys = save.handbook ? save.handbook.specialtys.length : null;
  out.encyAll = save.encyAll === true;
  out.museumUnlocked = save.museumUnlocked === true;
  out.pictures = save.pictures ? save.pictures.length : null;
  out.furniture = save.furniture && save.furniture.owned ? save.furniture.owned.length : null;
  out.ballPresent = !!document.getElementById('__save_ball');
  return JSON.stringify(out);
})()
