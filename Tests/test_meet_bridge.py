import importlib.util, io, json, struct, sys, tempfile, time, unittest
from pathlib import Path
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('host', Path(__file__).parents[1]/'Companion/native_host.py')
host=importlib.util.module_from_spec(spec);spec.loader.exec_module(host)

class Stream:
    def __init__(self,data=b''): self.buffer=io.BytesIO(data)

class NativeBridgeTests(unittest.TestCase):
    def message(self):
        return {'room':'abc-defg-hij','participants':[{'id':'one','name':'Morgan','isSelf':False}], 'activeIDs':['one','unknown'], 'completeRoster':True, 'transcript':'This must never be copied'}
    def run_host(self,root,origin=None):
        raw=json.dumps(self.message()).encode(); out=Stream()
        with patch.object(host,'ROOT',root), patch.object(sys,'argv',['host',origin or host.ALLOWED]), patch.object(sys,'stdin',Stream(struct.pack('<I',len(raw))+raw)), patch.object(sys,'stdout',out):host.main()
        return out.buffer.getvalue()
    def test_only_bounded_metadata_reaches_current_session(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'bridge-session.json').write_text(json.dumps({'session':'current','updatedAt':time.time()}))
            self.run_host(root)
            data=json.loads((root/'meet-speakers.json').read_text())
            self.assertEqual(data['session'],'current');self.assertEqual(data['activeIDs'],['one'])
            self.assertNotIn('transcript',data)
            self.assertEqual((root/'meet-speakers.json').stat().st_mode & 0o777,0o600)
    def test_expired_call_does_not_accept_names(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'bridge-session.json').write_text(json.dumps({'session':'ended','updatedAt':time.time()-10}))
            self.run_host(root);self.assertFalse((root/'meet-speakers.json').exists())
    def test_other_extension_origin_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);self.assertEqual(self.run_host(root,'chrome-extension://untrusted/'),b'')
            self.assertEqual(list(root.iterdir()),[])

if __name__=='__main__':unittest.main()
