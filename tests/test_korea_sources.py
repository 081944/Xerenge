import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('korea_sources', Path(__file__).resolve().parents[1]/'scripts/prepare-korea-sources.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class KoreanSources(unittest.TestCase):
    def test_only_code_addresses_are_relocated(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            (root/'src').mkdir()
            (root/'korea-addresses.json').write_text(json.dumps({'8210FA20':{'target':'8210FA78'}}))
            original='// sub_8210FA20 0x8210FA20\nconst char* s="sub_8210FA20 0x8210FA20";\nvoid __imp__sub_8210FA20(); auto a=0x8210FA20u;\n'
            (root/'src/test.cpp').write_text(original)
            module.prepare(root,root/'output')
            output=(root/'output/test.cpp').read_text()
            self.assertEqual((root/'src/test.cpp').read_text(),original)
            self.assertIn('// sub_8210FA20 0x8210FA20',output)
            self.assertIn('"sub_8210FA20 0x8210FA20"',output)
            self.assertIn('__imp__sub_8210FA78()',output)
            self.assertIn('0x8210FA78u',output)

    def test_unknown_hook_fails_instead_of_silently_using_usa_address(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            (root/'src').mkdir()
            (root/'korea-addresses.json').write_text('{}')
            (root/'src/test.cpp').write_text('void sub_8210FA20();')
            with self.assertRaisesRegex(ValueError,'Unmapped Korean symbols'):
                module.prepare(root,root/'output')


if __name__=='__main__':
    unittest.main()
