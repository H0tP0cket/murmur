let port;
let binding;
let latestStatus = 'Open a Google Meet call, then connect it here.';

function connectHost() {
  if (port) return;
  try {
    port = chrome.runtime.connectNative('dev.oblivion.meet');
    port.onMessage.addListener(message => { latestStatus = message.status || 'Connected'; });
    port.onDisconnect.addListener(() => {
      latestStatus = chrome.runtime.lastError?.message || 'Desktop connection closed.';
      port = undefined;
    });
  } catch (error) { latestStatus = String(error.message || error); }
}

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (sender.tab) {
    if (message.type !== 'speakers' || sender.tab.id !== binding?.tabId || !sender.url?.startsWith('https://meet.google.com/')) return;
    const room = new URL(sender.url).pathname.split('/')[1];
    if (room !== binding.room) return;
    connectHost();
    port?.postMessage({room, participants: message.participants, activeIDs: message.activeIDs, completeRoster: message.completeRoster});
    return;
  }
  if (sender.id !== chrome.runtime.id) return;
  if (message.command === 'status') { reply({status: latestStatus, connected: !!binding}); return; }
  if (message.command === 'disconnect') {
    binding = undefined; port?.disconnect(); port = undefined;
    latestStatus = 'Disconnected. Audio capture in murmur is unchanged.';
    reply({status: latestStatus}); return;
  }
  if (message.command === 'connect') {
    chrome.tabs.query({active:true, currentWindow:true}).then(tabs => {
      const tab = tabs[0];
      const url = tab?.url ? new URL(tab.url) : null;
      const room = url?.pathname.split('/')[1];
      if (url?.hostname !== 'meet.google.com' || !/^[a-z]{3}-[a-z]{4}-[a-z]{3}$/.test(room || '')) {
        reply({status:'Open an active Google Meet call first.'}); return;
      }
      binding = {tabId:tab.id, room}; connectHost();
      latestStatus = 'Connecting this meeting to murmur…';
      reply({status:latestStatus});
    });
    return true;
  }
});
chrome.tabs.onRemoved.addListener(tabId => {
  if (binding?.tabId === tabId) { binding = undefined; port?.disconnect(); port = undefined; }
});
