"""Materialize Korean address variants without changing EU/USA source files.

Only C++ address/symbol tokens are translated; comments and strings remain
unchanged. The checked-in map contains addresses and evidence, never game code.
"""
import argparse
import json
from pathlib import Path
import re

TOKENS = re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|(?P<address>0x82[0-9A-Fa-f]{6})(?![0-9A-Fa-f])|(?P<symbol>(?:__imp__)?sub_82[0-9A-Fa-f]{6})\b')


def prepare(project, output):
    mapping = json.loads((project/'korea-addresses.json').read_text(encoding='utf-8'))
    missing = set()
    def replace(match):
        address, symbol = match.group('address'), match.group('symbol')
        if not address and not symbol:
            return match.group()
        old = (address[2:] if address else symbol[-8:]).upper()
        entry = mapping.get(old)
        if entry:
            return ('0x' if address else symbol[:-8]) + entry['target']
        if symbol:
            missing.add(symbol)
        return match.group()
    for path in (project/'src').rglob('*'):
        if not path.is_file():
            continue
        target = output/path.relative_to(project/'src')
        target.parent.mkdir(parents=True,exist_ok=True)
        if path.suffix in ('.cpp','.h'):
            content = TOKENS.sub(replace,path.read_text(encoding='utf-8'))
            if not target.exists() or target.read_text(encoding='utf-8') != content:
                target.write_text(content,encoding='utf-8')
        else:
            target.write_bytes(path.read_bytes())
    if missing:
        raise ValueError('Unmapped Korean symbols: '+', '.join(sorted(missing)))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',type=Path)
    args=parser.parse_args()
    prepare(Path(__file__).resolve().parents[1]/'rexglue',args.output.resolve())
