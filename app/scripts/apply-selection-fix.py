from pathlib import Path
import subprocess
p = Path('src/electron.renderer/test/SceneSelectionTests.hx')
s = p.read_text()
old = 'rect=false,left=0.,top=0.,right=0.,bottom=0.'
assert s.count(old) == 1
p.write_text(s.replace(old, 'rect=false,left=0,top=0,right=0,bottom=0'))
subprocess.run(['git', 'add', str(p)], check=True)
print('Corrected fixture bounds to match the integer SelectionRect API.')
