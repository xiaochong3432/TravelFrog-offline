/* Browser verification of the 故事 (story) subsystem. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'story.json' });
  var o = {};

  var l0 = eng.dispatch('story_load', {}).reply;
  o.keys = Object.keys(l0).sort().join(',');
  o.before = l0.stories.length;

  // trips find stories
  var lunch = null;
  for (var i = 0; i < eng.state.items.bag.length; i++) {
    if (eng.state.items.bag[i] > 0) lunch = eng.state.items.bag[i];
  }
  for (var k = 0; k < 60; k++) {
    if (lunch === null) { eng.state.items.bag[0] = 1; lunch = 1; }
    eng.state.items.bag[0] = lunch;
    eng.state.travel.nextDepartAt = 1;
    eng.tick();
    eng.state.travel.returnAt = 1;
    eng.tick();
  }
  var l1 = eng.dispatch('story_load', {}).reply;
  o.found = l1.stories.length;
  o.newStoryId = l1.new_story_id;
  o.storyShape = l1.stories.length ? Object.keys(l1.stories[0]).sort().join(',') : null;
  o.giftStartsAtMinusOne = l1.stories.length ? l1.stories[0].gift : null;

  // send a gift
  var book = eng.state.storyBook;
  var target = book.list[0];
  var itemId = 3001;
  eng.state.items.house = [{ item_id: itemId, count: 3 }];
  eng.dispatch('story_send_gift', { id: target.id, gift: itemId });
  var l2 = eng.dispatch('story_load', {}).reply;
  o.giftRecorded = l2.stories[0].gift;
  o.houseAfter = eng.state.items.house.filter(function (h) { return h.item_id === itemId; })
    .reduce(function (a, h) { return a + h.count; }, 0);
  // a second gift to the same story must not be taken
  eng.dispatch('story_send_gift', { id: target.id, gift: itemId });
  o.houseAfterSecond = eng.state.items.house.filter(function (h) { return h.item_id === itemId; })
    .reduce(function (a, h) { return a + h.count; }, 0);

  // read new + feedback
  eng.dispatch('story_read_new_story', {});
  o.newIdAfterRead = eng.dispatch('story_load', {}).reply.new_story_id;
  eng.dispatch('story_feedback_gift', { id: target.id });
  o.feedback = eng.dispatch('story_load', {}).reply.stories[0].feedback;

  eng.save();
  o.saved = eng.state.storyBook.list.length;
  return JSON.stringify(o);
})()
