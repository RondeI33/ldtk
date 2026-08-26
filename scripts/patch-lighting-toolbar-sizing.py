from pathlib import Path

p = Path('src/electron.renderer/display/LightPreview.hx')
s = p.read_text(encoding='utf-8')

replacements = {
    '<div style="font:bold 10px sans-serif;display:flex;align-items:center;justify-content:center;width:100%;height:100%;">U</div>': '<div class="icon" style="font:bold 10px sans-serif;display:flex;align-items:center;justify-content:center;">U</div>',
    '<div style="font:bold 10px sans-serif;display:flex;align-items:center;justify-content:center;width:100%;height:100%;">L</div>': '<div class="icon" style="font:bold 10px sans-serif;display:flex;align-items:center;justify-content:center;">L</div>',
    '<div style="font:bold 9px sans-serif;display:flex;align-items:center;justify-content:center;width:100%;height:100%;">S</div>': '<div class="icon" style="font:bold 9px sans-serif;display:flex;align-items:center;justify-content:center;">S</div>',
    '<div style="font:bold 8px sans-serif;display:flex;align-items:center;justify-content:center;width:100%;height:100%;">LR</div>': '<div class="icon" style="font:bold 8px sans-serif;display:flex;align-items:center;justify-content:center;">LR</div>',
}

for old, new in replacements.items():
    if old not in s:
        raise SystemExit(f'Expected toolbar glyph markup not found: {old}')
    s = s.replace(old, new, 1)

start_marker = '\tstatic function _updateUiState() {'
end_marker = '\tstatic function _syncRootTransform(ed:page.Editor) {'
start = s.index(start_marker)
end = s.index(end_marker, start)
replacement = '''\tstatic function _updateUiState() {
\t\tif( _jUi==null )
\t\t\treturn;

\t\t// Use LDtk's native Visuals active state and its fixed 24x24 icon box.
\t\t_jUi.removeClass('active');
\t\t_jUi.filter('[data-mode="'+_mode+'"]').addClass('active');
\t\tif( _lowRes )
\t\t\t_jUi.filter('.forkLightingLowRes').addClass('active');
\t}

'''
s = s[:start] + replacement + s[end:]

fork_lines = '\n'.join(line for line in s.splitlines() if 'forkLighting' in line)
if 'width:100%;height:100%' in fork_lines:
    raise SystemExit('Sizing fix validation failed: percentage sizing remains')
if fork_lines.count('class="icon"') != 4:
    raise SystemExit('Sizing fix validation failed: expected four native icon boxes')

p.write_text(s, encoding='utf-8')
