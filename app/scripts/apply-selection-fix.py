from pathlib import Path
import json


def replace_once(s, old, new):
    if s.count(old) != 1:
        raise RuntimeError('Expected one exact patch anchor: ' + old[:100])
    return s.replace(old, new, 1)


def replace_section(s, start, end, new):
    a = s.index(start)
    b = s.index(end, a)
    return s[:a] + new + s[b:]


p = Path('src/electron.renderer/GenericLevelElementGroup.hx')
s = p.read_text()
s = replace_once(s, '\tvar dragSnapshotActive = false;', '\tvar dragAnchor : Dynamic = null;\n\tvar dragSnapshotActive = false;')
s = s.replace('\t\tdragSnapshotActive = false;\n', '\t\tdragSnapshotActive = false;\n\t\tdragAnchor = null;\n')
s = replace_once(s, '\tpublic function dispose() {\n\t\trenderWrapper.remove();', '\tpublic function dispose() {\n\t\tif( dragSnapshotActive && dragSourceCut ) restoreDragSource();\n\t\trenderWrapper.remove();')
s = replace_section(s, '\tfunction getDeltaX(origin:Coords, now:Coords)', '\tpublic function getSmartRelativeLayerInstance()', '''\tfunction getDeltaX(origin:Coords, now:Coords) {
		return misc.SelectionMove.delta(this,origin,now).x;
	}

	function getDeltaY(origin:Coords, now:Coords) {
		return misc.SelectionMove.delta(this,origin,now).y;
	}

''')
s = replace_section(s, '\tpublic function hasIncompatibleGridSizes()', '\tfunction isEntitySelected(', '''\tpublic function hasIncompatibleGridSizes() {
		var rel=getSmartRelativeLayerInstance();
		var step=rel==null ? 1. : rel.def.scaledGridSize*1.;
		for(ge in elements) switch ge {
			case GridCell(li,_), Entity(li,_), PointField(li,_):
				var ratio=step/li.def.scaledGridSize;
				if(Math.abs(ratio-Math.round(ratio))>0.00001) return true;
			case null:
		}
		return false;
	}

''')
s = replace_once(s, '\tpublic function onMoveStart(isCopy:Bool) {\n\t\tdeduplicateElementsForDrag();\n\t\tcaptureDragSnapshot();', '''\tpublic function onMoveStart(isCopy:Bool, ?origin:Coords) {
		dragAnchor=null;
		deduplicateElementsForDrag();
		for(li in getSelectedLayerInstances()) editor.ensureLevelTimeline(li.level);
		captureDragSnapshot();
		if(origin!=null) dragAnchor=misc.SelectionMove.anchor(this,origin);''')
s = replace_section(s, '\tpublic function commitDragSnapshot(', '\tpublic function toSelectionTemplate(', '''\tpublic function commitDragSnapshot(origin:Coords, to:Coords, isCopy:Bool, flipX=false, flipY=false) : Array<data.inst.LayerInstance> {
		return misc.SelectionMove.commit(this,origin,to,isCopy,flipX,flipY);
	}


''')
s = replace_section(s, '\tpublic function moveSelecteds(', '\tpublic function hasFlippableGridContent()', '''\tpublic function moveSelecteds(origin:Coords, to:Coords, isCopy:Bool) : Array<data.inst.LayerInstance> {
		dragAnchor=null;
		deduplicateElementsForDrag();
		captureDragSnapshot();
		dragAnchor=misc.SelectionMove.anchor(this,origin);
		var affected=misc.SelectionMove.commit(this,origin,to,isCopy);
		onMoveEnd();
		return affected;
	}


''')
s = replace_once(s, '\t\t\t\t\tif( ei.isOver(m.layerX, m.layerY) )', '\t\t\t\t\tvar local=m.cloneRelativeToLayer(li);\n\t\t\t\t\tif( ei.isOver(local.layerX, local.layerY) )')
s = replace_once(s, '''					core.wrapper.x = li.pxParallaxX + ei.x - bounds.left;
					core.wrapper.y = li.pxParallaxY + ei.y - bounds.top;''', '''					core.wrapper.setScale(li.def.getScale());
					core.wrapper.x = li.pxParallaxX + ei.x*li.def.getScale() - bounds.left;
					core.wrapper.y = li.pxParallaxY + ei.y*li.def.getScale() - bounds.top;''')
s = s.replace('levelToGhostY( li.pxParallaxX+(prev.cy+0.5)', 'levelToGhostY( li.pxParallaxY+(prev.cy+0.5)')
s = s.replace('levelToGhostY( li.pxParallaxX+(next.cy+0.5)', 'levelToGhostY( li.pxParallaxY+(next.cy+0.5)')
s = replace_once(s, '''			var key = switch ge {
				case GridCell(li,cx,cy):''', '''			// Empty entries are bounds only. Do not carry stale empty-cell
			// references into the next drag, where they could pick up background.
			switch ge {
				case GridCell(li,cx,cy): if(!li.hasAnyGridValue(cx,cy)) continue;
				case PointField(_,_,fi,idx): if(fi.getPointGrid(idx)==null) continue;
				case _:
			}
			var key = switch ge {
				case GridCell(li,cx,cy):''')
s = replace_once(s, '''		if( s.isTiles ) {
			var tiles : Array<Dynamic> = s.tiles;
			var stacking = tiles.length>1 || App.ME.settings.v.tileStacking;''', '''		if( s.isTiles ) {
			// Restore exactly the cut snapshot on cancellation, not a merge.
			li.removeAllGridTiles(s.cx,s.cy,false);
			var tiles : Array<Dynamic> = s.tiles;
			var stacking = true;''')
p.write_text(s)

p = Path('src/electron.renderer/tool/SelectionTool.hx')
s = p.read_text()
s = replace_once(s, 'group.onMoveStart(isCopy);', 'group.onMoveStart(isCopy,origin);')
a = s.index('\t\t\t\tvar changedLayers = group.commitDragSnapshot(origin, m, isCopy);')
b = s.index('\n\t\t\t\tfor(li in changedLayers)', a)
s = s[:a] + '''				// Place directly at the ghost's final transformed coordinates.
				// Pasting first and flipping the destination afterward erases
				// unrelated tiles under the intermediate (unflipped) positions.
				var changedLayers = group.commitDragSnapshot(origin,m,isCopy,dragFlipX,dragFlipY);
''' + s[b:]
for axis in [('cLeft','leftPx','pxParallaxX'),('cRight','rightPx','pxParallaxX'),('cTop','topPx','pxParallaxY'),('cBottom','bottomPx','pxParallaxY')]:
    name,coord,offset=axis
    import re
    pattern = r'var '+name+r' = Std.int\( \('+coord+'-li.'+offset+r'\) /\s*li.def.scaledGridSize \);'
    s,n=re.subn(pattern, 'var '+name+' = M.floor( ('+coord+'-li.'+offset+') / li.def.scaledGridSize );',s)
    if n!=1: raise RuntimeError('Missing rectangle floor conversion '+name)
p.write_text(s)

p = Path('src/electron.renderer/misc/Coords.hx')
s = p.read_text()
s = s.replace('return Std.int( ( levelX - getRelativeLayerInst().pxParallaxX ) / getRelativeLayerInst().def.getScale() );', 'return M.floor( ( levelX - getRelativeLayerInst().pxParallaxX ) / getRelativeLayerInst().def.getScale() );')
s = s.replace('return Std.int( ( levelY - getRelativeLayerInst().pxParallaxY ) / getRelativeLayerInst().def.getScale() );', 'return M.floor( ( levelY - getRelativeLayerInst().pxParallaxY ) / getRelativeLayerInst().def.getScale() );')
s = replace_once(s, 'return Std.int( ( layerX + getRelativeLayerInst().pxParallaxX - li.pxParallaxX ) / li.def.scaledGridSize );', 'return M.floor( ( levelX - li.pxParallaxX ) / li.def.scaledGridSize );')
s = replace_once(s, 'return Std.int( ( layerY + getRelativeLayerInst().pxParallaxY - li.pxParallaxY ) / li.def.scaledGridSize );', 'return M.floor( ( levelY - li.pxParallaxY ) / li.def.scaledGridSize );')
p.write_text(s)

p = Path('app/package.json')
pkg=json.loads(p.read_text()); pkg['version']='1.0.23'
pkg['scripts']['test:selection']='node scripts/run-selection-tests.cjs'
p.write_text(json.dumps(pkg,indent='\t')+'\n')
p = Path('app/package-lock.json')
if p.exists():
    lock=json.loads(p.read_text()); lock['version']='1.0.23'
    if '' in lock.get('packages',{}): lock['packages']['']['version']='1.0.23'
    p.write_text(json.dumps(lock,indent=2)+'\n')
print('Applied ordinary-selection fix; template placement and template storage were not modified.')
