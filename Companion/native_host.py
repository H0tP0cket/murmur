#!/usr/bin/python3
"""Chrome native messaging bridge. Writes bounded, expiring metadata locally only."""
import json, os, re, struct, sys, tempfile, time
from pathlib import Path
ROOT = Path.home() / 'Library/Application Support/Oblivion'
ALLOWED = 'chrome-extension://koikkoppmobklaimhplgjgkfljiclnjj/'

def reply(status):
    body=json.dumps({'status':status}).encode()
    sys.stdout.buffer.write(struct.pack('<I',len(body))+body)
    sys.stdout.buffer.flush()

def sanitize(message):
    room=message.get('room','')
    if not isinstance(room,str) or not re.fullmatch(r'[a-z]{3}-[a-z]{4}-[a-z]{3}',room): raise ValueError('Invalid meeting')
    participants=[]
    for person in message.get('participants',[])[:100]:
        if not isinstance(person,dict): continue
        identifier=person.get('id'); name=person.get('name')
        if isinstance(identifier,str) and isinstance(name,str) and identifier and name.strip():
            participants.append({'id':identifier[:250],'name':' '.join(name.split())[:120],'isSelf':person.get('isSelf') is True})
    ids={p['id'] for p in participants}
    active=[i for i in message.get('activeIDs',[])[:100] if isinstance(i,str) and i in ids]
    return {'room':room,'participants':participants,'activeIDs':active,'completeRoster':message.get('completeRoster') is True}

def main():
    if len(sys.argv)<2 or sys.argv[1] != ALLOWED: return
    while True:
        header=sys.stdin.buffer.read(4)
        if not header: return
        if len(header)!=4: return
        size=struct.unpack('<I',header)[0]
        if size>65536: return
        body=sys.stdin.buffer.read(size)
        if len(body)!=size: return
        try:
            state=json.loads((ROOT/'bridge-session.json').read_text())
            if time.time()-state['updatedAt']>5: raise ValueError('No active call')
            payload=sanitize(json.loads(body))
            payload.update(session=state['session'],receivedAt=time.time())
            fd,path=tempfile.mkstemp(prefix='.speakers-',dir=ROOT)
            try:
                with os.fdopen(fd,'w') as f: json.dump(payload,f)
                os.replace(path,ROOT/'meet-speakers.json')
            finally:
                if os.path.exists(path): os.unlink(path)
            reply('Connected to your active MurMur call.')
        except (ValueError,KeyError,TypeError,FileNotFoundError): reply('Start a call in MurMur to connect speaker names.')
        except Exception: reply('Unable to update local speaker names.')

if __name__ == '__main__': main()
