"""Load in Python, never in the game; verify exports and WinMM forwarding."""
import ctypes as c
import concurrent.futures
import json
from pathlib import Path
import pefile

root = Path(__file__).resolve().parent
path = root / 'build' / 'winmm.dll'
manifest = json.loads((root / 'winmm-exports.json').read_text())
pe = pefile.PE(str(path))
actual = {x.ordinal: x.name.decode() if x.name else None for x in pe.DIRECTORY_ENTRY_EXPORT.symbols}
assert actual == {x['ordinal']: x['name'] for x in manifest}, 'export mismatch'
imports = [x.dll.decode() for x in pe.DIRECTORY_ENTRY_IMPORT]
assert all(x.lower() in {'kernel32.dll', 'msvcrt.dll', 'bcrypt.dll', 'ntdll.dll'} or
           x.lower().startswith('api-ms-win-crt-') for x in imports), imports
proxy = c.WinDLL(str(path))
system = c.WinDLL(str(Path(__import__('os').environ['SystemRoot']) / 'System32' / 'winmm.dll'))
for lib in (proxy, system):
    lib.timeGetTime.restype = c.c_uint32
    lib.timeGetDevCaps.argtypes = [c.c_void_p, c.c_uint]
    lib.timeGetSystemTime.argtypes = [c.c_void_p, c.c_uint]
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
    values = list(pool.map(lambda _: proxy.timeGetTime(), range(64)))
now = system.timeGetTime()
assert all(((now - x) & 0xffffffff) < 2000 for x in values)
for entry in manifest:
    assert proxy[entry['ordinal']]
    if entry['name']:
        assert c.cast(proxy[entry['name']], c.c_void_p).value == c.cast(proxy[entry['ordinal']], c.c_void_p).value
a, b = (c.c_uint32 * 2)(), (c.c_uint32 * 2)()
assert proxy.timeGetDevCaps(a, c.sizeof(a)) == system.timeGetDevCaps(b, c.sizeof(b)) == 0
assert list(a) == list(b)
timer = (c.c_uint32 * 3)()
assert proxy.timeGetSystemTime(timer, c.sizeof(timer)) == 0
assert timer[0] == 1 and ((system.timeGetTime() - timer[1]) & 0xffffffff) < 2000
print(f'PASS: {len(actual)} names/ordinals, concurrent first calls, timer and pointer arguments. Imports: {imports}')
