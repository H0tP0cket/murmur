"""Integration tests for the shipping native helper, not a Python runtime shim."""
import json, os, struct, subprocess, tempfile, time, unittest
from pathlib import Path
BINARY = Path(__file__).parents[1] / '.build/debug/MurMurMeetBridge'
ORIGIN = 'chrome-extension://koikkoppmobklaimhplgjgkfljiclnjj/'

class NativeBridgeTests(unittest.TestCase):
    def run_host(self, root, message=None, origin=ORIGIN, raw=None):
        message = message or {'room':'abc-defg-hij','participants':[{'id':'one','name':'  Avery   Quinn ','isSelf':False}], 'activeIDs':['one','unknown'], 'completeRoster':True, 'transcript':'must not be retained'}
        payload=json.dumps(message).encode()
        return subprocess.run([str(BINARY), origin], input=raw if raw is not None else struct.pack('<I',len(payload))+payload,
            env=dict(os.environ,MURMUR_LIBRARY_ROOT=str(root)),capture_output=True,timeout=3)
    def session(self, root, age=0):
        (root/'bridge-session.json').write_text(json.dumps({'session':'current','updatedAt':time.time()-age}))
    def test_only_bounded_metadata_reaches_current_session(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);self.session(root)
            result=self.run_host(root);self.assertEqual(result.returncode,0)
            self.assertEqual(struct.unpack('<I',result.stdout[:4])[0],len(result.stdout)-4)
            data=json.loads((root/'meet-speakers.json').read_text())
            self.assertEqual(data['session'],'current');self.assertEqual(data['activeIDs'],['one'])
            self.assertEqual(data['participants'][0]['name'],'Avery Quinn')
            self.assertNotIn('transcript',data)
            self.assertEqual((root/'meet-speakers.json').stat().st_mode & 0o777,0o600)
    def test_expired_call_does_not_accept_names(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);self.session(root,age=10)
            self.run_host(root);self.assertFalse((root/'meet-speakers.json').exists())
    def test_untrusted_origin_and_oversized_or_truncated_packets_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);self.session(root)
            for kwargs in [dict(origin='https://invalid.example/'),dict(raw=struct.pack('<I',65537)),dict(raw=b'\x02\x00')]:
                result=self.run_host(root,**kwargs);self.assertEqual(result.returncode,0);self.assertEqual(result.stdout,b'')
            self.assertFalse((root/'meet-speakers.json').exists())
    def test_broken_state_does_not_crash_or_write_metadata(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'bridge-session.json').write_text('{broken')
            result=self.run_host(root);self.assertEqual(result.returncode,0)
            self.assertIn('Start a call',json.loads(result.stdout[4:])['status']);self.assertFalse((root/'meet-speakers.json').exists())

if __name__=='__main__': unittest.main()
