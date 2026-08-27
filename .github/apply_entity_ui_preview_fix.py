from pathlib import Path


def replace(path: str, old: str, new: str, count: int = 1):
    p = Path(path)
    s = p.read_text()
    found = s.count(old)
    if found != count:
        raise SystemExit(f"{path}: expected {count} copies of patch anchor, found {found}: {old[:120]!r}")
    p.write_text(s.replace(old, new, count))


# The entity-definition panel gained several fork sections. Stock LDtk hides overflow on
# the whole right column, which can make the Variables section unreachable on shorter screens.
replace(
    'app/assets/css/app.scss',
    '''\t\t.rightColumn {\n\t\t\toverflow: hidden;\n\t\t\tdisplay: grid;\n''',
    '''\t\t.rightColumn {\n\t\t\tmin-height: 0;\n\t\t\toverflow-x: hidden;\n\t\t\toverflow-y: auto;\n\t\t\tdisplay: grid;\n'''
)

# Put a dedicated variable-preview toggle immediately below Zen mode in Visuals.
replace(
    'app/assets/tpl/pages/editor.html',
    '''\t\t<li class="zen" title="**Zen mode** This mode automatically hides the left panel to give more editing space." keys="TAB" tip="right">\n\t\t\t<div class="icon zen on"></div>\n\t\t\t<div class="icon zen off"></div>\n\t\t</li>\n\n\t\t<li class="grid" title="**Grid** Show the layer grid. In supported layer types, hiding the grid will also allow free positioning of elements." keys="G" tip="right">\n''',
    '''\t\t<li class="zen" title="**Zen mode** This mode automatically hides the left panel to give more editing space." keys="TAB" tip="right">\n\t\t\t<div class="icon zen on"></div>\n\t\t\t<div class="icon zen off"></div>\n\t\t</li>\n\n\t\t<li class="variablePreviews" title="**Variable previews** Show or hide entity variable/field previews in the level view. This only changes editor visuals; values and exported data are untouched." tip="right">\n\t\t\t<div class="icon showDetailsOn on"></div>\n\t\t\t<div class="icon showDetailsOff off"></div>\n\t\t</li>\n\n\t\t<li class="grid" title="**Grid** Show the layer grid. In supported layer types, hiding the grid will also allow free positioning of elements." keys="G" tip="right">\n'''
)

# Keep the toggle as editor UI state: it must never touch project/sidecar/export data.
replace(
    'src/electron.renderer/page/Editor.hx',
    '''\tpublic var gifMode = false;\n\tvar zenModeRevealed = false;\n''',
    '''\tpublic var gifMode = false;\n\tpublic var showVariablePreviews(default,null) = true;\n\tvar zenModeRevealed = false;\n'''
)

replace(
    'src/electron.renderer/page/Editor.hx',
    '''\t\tapplyEditOption( jEditOptions.find("li.zen"), ()->settings.v.zenMode, (v)->{\n\t\t\tsetZenMode(v);\n\t\t\tsetZenModeReveal(true);\n\t\t});\n\t\tapplyEditOption( jEditOptions.find("li.grid"), ()->settings.v.grid, (v)->setGrid(v) );\n''',
    '''\t\tapplyEditOption( jEditOptions.find("li.zen"), ()->settings.v.zenMode, (v)->{\n\t\t\tsetZenMode(v);\n\t\t\tsetZenModeReveal(true);\n\t\t});\n\t\tapplyEditOption( jEditOptions.find("li.variablePreviews"), ()->showVariablePreviews, (v)->setVariablePreviews(v) );\n\t\tapplyEditOption( jEditOptions.find("li.grid"), ()->settings.v.grid, (v)->setGrid(v) );\n'''
)

replace(
    'src/electron.renderer/page/Editor.hx',
    '''\tpublic function setShowDetails(v:Bool) {\n''',
    '''\tpublic function setVariablePreviews(v:Bool) {\n\t\tshowVariablePreviews = v;\n\t\tlevelRender.invalidateAll();\n\t\tselectionTool.invalidateRender();\n\t\tupdateEditOptions();\n\t\tN.quick( "Variable previews: "+L.onOff(showVariablePreviews) );\n\t}\n\n\n\tpublic function setShowDetails(v:Bool) {\n'''
)

# Hide only the field/variable visuals. Identifier labels and EntityRef links keep rendering.
replace(
    'src/electron.renderer/display/EntityRender.hx',
    '''\tpublic function renderFields() {\n\n\t\tfieldGraphics.clear();\n\n\t\t// Attach fields\n\t\tvar color = ei.getSmartColor(false);\n\t\tvar ctx : display.FieldInstanceRender.FieldRenderContext = EntityCtx(fieldGraphics, ei, ld);\n\t\tFieldInstanceRender.renderFields(\n\t\t\tei.def.fieldDefs.filter( fd->fd.editorDisplayPos==Above && ei._project.forkConfig.isFieldVisible(ei,fd) ).map( fd->ei.getFieldInstance(fd,true) ),\n\t\t\tcolor, ctx, above\n\t\t);\n\t\tFieldInstanceRender.renderFields(\n\t\t\tei.def.fieldDefs.filter( fd->fd.editorDisplayPos==Center && ei._project.forkConfig.isFieldVisible(ei,fd) ).map( fd->ei.getFieldInstance(fd,true) ),\n\t\t\tcolor, ctx, center\n\t\t);\n\t\tFieldInstanceRender.renderFields(\n\t\t\tei.def.fieldDefs.filter( fd->fd.editorDisplayPos==Beneath && ei._project.forkConfig.isFieldVisible(ei,fd) ).map( fd->ei.getFieldInstance(fd,true) ),\n\t\t\tcolor, ctx, beneath\n\t\t);\n''',
    '''\tpublic function renderFields() {\n\n\t\tabove.removeChildren();\n\t\tcenter.removeChildren();\n\t\tbeneath.removeChildren();\n\t\tfieldGraphics.clear();\n\n\t\t// Attach fields\n\t\tvar color = ei.getSmartColor(false);\n\t\tvar ctx : display.FieldInstanceRender.FieldRenderContext = EntityCtx(fieldGraphics, ei, ld);\n\t\tif( Editor.ME.showVariablePreviews ) {\n\t\t\tFieldInstanceRender.renderFields(\n\t\t\t\tei.def.fieldDefs.filter( fd->fd.editorDisplayPos==Above && ei._project.forkConfig.isFieldVisible(ei,fd) ).map( fd->ei.getFieldInstance(fd,true) ),\n\t\t\t\tcolor, ctx, above\n\t\t\t);\n\t\t\tFieldInstanceRender.renderFields(\n\t\t\t\tei.def.fieldDefs.filter( fd->fd.editorDisplayPos==Center && ei._project.forkConfig.isFieldVisible(ei,fd) ).map( fd->ei.getFieldInstance(fd,true) ),\n\t\t\t\tcolor, ctx, center\n\t\t\t);\n\t\t\tFieldInstanceRender.renderFields(\n\t\t\t\tei.def.fieldDefs.filter( fd->fd.editorDisplayPos==Beneath && ei._project.forkConfig.isFieldVisible(ei,fd) ).map( fd->ei.getFieldInstance(fd,true) ),\n\t\t\t\tcolor, ctx, beneath\n\t\t\t);\n\t\t}\n'''
)
