// Read only rendered participant metadata. No microphone, captions, transcript,
// application internals, meeting chat, or network interception.
(() => {
  const roster = new Map();
  let ownID;
  let lastRosterAt = 0;
  const visible = node => !!(node.getClientRects().length && getComputedStyle(node).visibility !== 'hidden');
  const clean = text => (text || '').trim().replace(/\s+/g, ' ').slice(0,120);
  function read() {
    if (!/\/[a-z]{3}-[a-z]{4}-[a-z]{3}$/.test(location.pathname)) return;
    const list = [...document.querySelectorAll('[role="listitem"][data-participant-id]')].filter(visible);
    if (list.length) {
      roster.clear(); lastRosterAt = Date.now();
      for (const row of list) {
        const id = row.getAttribute('data-participant-id');
        const name = clean(row.getAttribute('aria-label'));
        const isSelf = /\(You\)/.test(row.innerText);
        if (isSelf) ownID = id;
        if (id && name) roster.set(id, {id,name,isSelf});
      }
    }
    const tiles = [...document.querySelectorAll('main [data-participant-id]')].filter(visible);
    const activeIDs = new Set();
    for (const tile of tiles) {
      const id = tile.getAttribute('data-participant-id');
      const name = clean(tile.querySelector('span.notranslate')?.textContent);
      if (id && name) roster.set(id, {id,name,isSelf:id === ownID});
      // Only explicit accessible speaking signals are accepted. Layout/highlight
      // colors are never treated as evidence that a participant is speaking.
      const signals = [tile, ...tile.querySelectorAll('[aria-label],[data-is-speaking],[data-speaking]')];
      if (signals.some(n => n.getAttribute('data-is-speaking') === 'true' || n.getAttribute('data-speaking') === 'true' || /^(?:speaking|currently speaking)$|\bis speaking\b/i.test(n.getAttribute('aria-label') || ''))) activeIDs.add(id);
    }
    const peopleButton = [...document.querySelectorAll('button,[role=button]')].find(n => (n.getAttribute('aria-label') || (n.getAttribute('aria-labelledby') || '').split(' ').map(id => document.getElementById(id)?.textContent || '').join(' ')).trim() === 'People');
    const count = Number(peopleButton?.innerText.match(/\d+/)?.[0]);
    const completeRoster = !!ownID && Date.now()-lastRosterAt < 3000 && count === list.length && count === roster.size;
    if (Date.now()-lastRosterAt > 10000 && !tiles.length) roster.clear();
    chrome.runtime.sendMessage({type:'speakers', participants:[...roster.values()].slice(0,100), activeIDs:[...activeIDs].filter(Boolean), completeRoster}).catch(()=>{});
  }
  setInterval(read, 500);
  read();
})();
