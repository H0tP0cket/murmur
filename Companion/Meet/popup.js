const status = document.querySelector('#status');
async function command(command) { const reply = await chrome.runtime.sendMessage({command}); status.textContent = reply.status; }
document.querySelector('#connect').addEventListener('click',()=>command('connect'));
document.querySelector('#disconnect').addEventListener('click',()=>command('disconnect'));
command('status');
setInterval(()=>command('status'),1000);
