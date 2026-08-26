from pathlib import Path

layer = Path('src/electron.renderer/display/LayerRender.hx')
s = layer.read_text(encoding='utf-8')
old = "\tpublic function new() {\n\t\tLightPreview.ensure();\n\t}\n"
new = "\tpublic function new() {}\n"
if old not in s:
    raise SystemExit('Expected LightPreview.ensure() constructor hook was not found')
s = s.replace(old, new, 1)
layer.write_text(s, encoding='utf-8')

for rel in [
    'src/electron.renderer/display/LightPreview.hx',
    'docs/FORK_LIGHTING_PREVIEW.md',
]:
    p = Path(rel)
    if not p.exists():
        raise SystemExit(f'Expected lighting file missing: {rel}')
    p.unlink()

# Guard against accidentally retaining runtime/editor lighting integration.
remaining = layer.read_text(encoding='utf-8')
if 'LightPreview' in remaining:
    raise SystemExit('LayerRender still references LightPreview')

print('Removed LDtk lighting preview while preserving animated tile code')
