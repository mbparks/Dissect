import json
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Resources/Engine'))
from storage import *

class StorageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
    def tearDown(self):
        self.tmp.cleanup()
    def fixture(self):
        (self.root/'original.bin').write_bytes(b'\x01\x02\x03')
        data = dict(schema=1,format='dissect-workspace',program='/Binary',sha256=digest(self.root/'original.bin'))
        atomic_json(self.root/'workspace.json', data)
        return data
    def test_roundtrip_and_atomic_replace(self):
        data = self.fixture()
        self.assertEqual(read_manifest(self.root), data)
        data['name'] = 'hello 🌲'
        atomic_json(self.root/'workspace.json',data)
        self.assertEqual(read_manifest(self.root)['name'], 'hello 🌲')
        self.assertEqual(list(self.root.glob('.dissect-*')), [])
    def test_original_tampering_rejected(self):
        self.fixture(); (self.root/'original.bin').write_bytes(b'changed')
        with self.assertRaises(WorkspaceError): read_manifest(self.root)
    def test_newer_schema_is_not_overwritten(self):
        data=self.fixture(); data['schema']=100
        atomic_json(self.root/'workspace.json',data)
        original=(self.root/'workspace.json').read_bytes()
        with self.assertRaises(WorkspaceError): read_manifest(self.root)
        self.assertEqual(original,(self.root/'workspace.json').read_bytes())
    def test_nested_symlink_rejected(self):
        self.fixture(); (self.root/'database').mkdir()
        (self.root/'database'/'link').symlink_to('/tmp')
        with self.assertRaises(WorkspaceError): read_manifest(self.root)
    def test_original_path_cannot_be_injected(self):
        data=self.fixture(); data['program']='../../elsewhere'
        atomic_json(self.root/'workspace.json',data)
        with self.assertRaises(WorkspaceError): read_manifest(self.root)
    def test_empty_and_oversize_input(self):
        p=self.root/'sample'; p.touch()
        with self.assertRaises(WorkspaceError): plain_file(p)
        p.write_bytes(b'abcd')
        with self.assertRaises(WorkspaceError): plain_file(p,3)
    def test_bounds_and_names(self):
        for offset,limit in [(-1,1),(0,501),(0,0),(True,1)]:
            with self.assertRaises(WorkspaceError): page_bounds(offset,limit)
        for name in ['','2name','x;rm -rf','a b','a'*129]:
            with self.assertRaises(WorkspaceError): label(name)
        self.assertEqual(label('alarm_for_temperature'), 'alarm_for_temperature')
    def test_second_workspace_writer_is_rejected(self):
        from engine import Engine
        first,second=Engine(self.root),Engine(self.root)
        first.acquire(self.root)
        try:
            with self.assertRaises(WorkspaceError): second.acquire(self.root)
        finally: first.close();second.close()
    def test_atomic_write_rejects_symlink(self):
        target=self.root/'target'; target.write_text('original')
        link=self.root/'link'; link.symlink_to(target)
        with self.assertRaises(WorkspaceError): atomic_json(link,{'a':1})
        self.assertEqual(target.read_text(),'original')

if __name__=='__main__': unittest.main()
