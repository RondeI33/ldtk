# Apply exact, locally exercised line edits; removed by branch CI after committing source.
from pathlib import Path
import hashlib
import subprocess

def patch(path, expected, changes):
    p=Path(path)
    old=p.read_text() if p.exists() else ""
    assert hashlib.sha256(old.encode()).hexdigest()==expected, "Source changed: "+path
    lines=old.splitlines(keepends=True)
    for start,end,replacement in reversed(changes):
        lines[start:end]=replacement.splitlines(keepends=True)
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text("".join(lines))
    subprocess.run(["git","add",path],check=True)

patch('.github/workflows/ldtk-smartive-1.0.0-release.yml', '0e51ce7e871d8bc7ffdc5b398448f7d2baa47c552179462e6fe2412b6878ae23', [
    (16, 16, r"""      - src/electron.renderer/GenericLevelElementGroup.hx
      - src/electron.renderer/misc/SelectionMove.hx
      - src/electron.renderer/misc/Coords.hx
      - src/electron.renderer/display/Camera.hx
      - src/electron.renderer/test/SceneSelectionTests.hx
      - app/scripts/*selection*.cjs
"""),
    (296, 299, r"""      - name: Ordinary scene selection and template regressions in Electron
        working-directory: app
        run: xvfb-run -a -s "-screen 0 1600x1000x24" npm run test:selection
"""),
    (303, 304, r"""          path: app/test-results
"""),
])

patch('.github/workflows/selection-regression.yml', 'b0aad51d21eb3cac8d095d5ab68a6e13a595f5c2391e35160c628a253b1c35f6', [
    (10, 10, r"""      - src/electron.renderer/display/Camera.hx
"""),
    (26, 28, r""""""),
    (30, 46, r""""""),
    (60, 78, r""""""),
])

patch('app/scripts/selection-ui-smoke.cjs', '303c26ad340b3904e6ff927f790aa72aceff0189f093b41fec33dfc09f8992a7', [
    (5, 5, r"""process.argv=process.argv.filter((arg,i)=>i===0 || path.resolve(arg)!==__filename);
"""),
    (25, 26, r"""    const result=await win.webContents.executeJavaScript(`(()=>{try{return {ok:true,value:(${code})};}catch(e){return {ok:false,error:String(e.stack||e)};}})()`,true);
"""),
    (35, 35, r"""  require('electron').Menu.setApplicationMenu(null);
"""),
    (36, 37, r"""  await until('document.querySelector("#page.home")','Initial Home page did not finish loading');
"""),
    (39, 40, r"""  for(const group of ['matrix','edgeCases','pointCases','zoomCases']) {
"""),
    (49, 50, r"""  for(const burst of [false,true]) for(const copy of [false,true]) {
    const tag=(copy?"copy":"move")+(burst?"-queued":"");
    await until('SceneSelectionTests.historySettled()','Previous history restoration did not finish');
"""),
    (51, 52, r"""    await until('SceneSelectionTests.historySettled()','Fixture viewport did not settle');
    win.webContents.focus();
"""),
    (53, 53, r"""    fs.writeFileSync(path.join(output,tag+"-baseline.json"),JSON.stringify(baseline,null,2));
    assert.equal(baseline.selected,5,'The drag must start with the full five-element scene selection');
"""),
    (59, 66, r"""    let ghost=null;
    if(!burst) {
      await until('SceneSelectionTests.uiState().running','Ordinary selection drag did not start');
      win.webContents.sendInputEvent({type:'mouseMove',x:to.x,y:to.y,modifiers:mods});
      await until('SceneSelectionTests.uiState().moving && SceneSelectionTests.uiState().ghost','Selection ghost did not appear');
      ghost=await ev('SceneSelectionTests.uiState()');
      fs.writeFileSync(path.join(output,tag+'-ghost.json'),JSON.stringify({baseline,ghost,from,to},null,2));
      assert.equal(ghost.dx,128,'Displayed X delta differs from expected snapped drag');
      assert.equal(ghost.dy,128,'Displayed Y delta differs from expected snapped drag');
      fs.writeFileSync(path.join(output,tag+'-preview.png'),(await win.webContents.capturePage()).toPNG());
    } else {
      // Intentionally queue press, movement and release together. The editor
      // must not use the last DOM pointer position as the press origin.
      win.webContents.sendInputEvent({type:'mouseMove',x:to.x,y:to.y,modifiers:mods});
    }
"""),
    (67, 67, r"""    await until('!SceneSelectionTests.uiState().running && SceneSelectionTests.uiState().gridA===1','Selection drop did not finish at the expected cell');
"""),
    (68, 69, r""""""),
    (70, 70, r"""    fs.writeFileSync(path.join(output,tag+'-state.json'),JSON.stringify({baseline,ghost,after,from,to},null,2));
"""),
    (77, 78, r"""    await ev('SceneSelectionTests.undo()');await until('SceneSelectionTests.historySettled()','Undo restoration did not finish');
"""),
    (81, 82, r"""    await ev('SceneSelectionTests.redo()');await until('SceneSelectionTests.historySettled()','Redo restoration did not finish');
"""),
    (85, 87, r"""    mouseResults.push({copy,burst,passed:true});
    console.log('PASS: actual '+tag+' -> exact ghost/drop agreement, transparent holes, Undo/Redo');
"""),
])

patch('app/scripts/template-ui-smoke.cjs', 'aa6fb2830ab29309cf0fde8660e521d444a139e1715c8aa729b52d02b8dba0c2', [
    (5, 5, r"""process.argv=process.argv.filter((arg,i)=>i===0 || path.resolve(arg)!==__filename);
"""),
    (8, 9, r"""const timer=setTimeout(()=>{console.error('FAIL: UI smoke test timed out');app.exit(1);},120000);
"""),
    (19, 20, r"""  async function until(code,message,timeoutMs=8000){const end=Date.now()+timeoutMs;while(Date.now()<end){if(await ev(`!!(${code})`))return;await delay(40);}throw Error(message+'; state='+JSON.stringify(await ev('TemplateTestHooks.inputState()')));}
"""),
    (23, 24, r"""  await until('(window.TemplateTestHooks=window.TemplateTestHooks || (typeof exports!=="undefined" && exports.TemplateTestHooks)) && document.querySelector("#page")','App did not expose test hooks');await until('document.querySelector("#page.home")','Initial Home page did not finish loading');
  require('electron').Menu.setApplicationMenu(null);
"""),
    (51, 52, r"""  win.webContents.focus();
"""),
    (140, 141, r"""  await until('TemplateTestHooks.historySettled()','History restore did not finish before activating placement');
"""),
    (182, 183, r"""  await until('!TemplateTestHooks.saveInProgress() && !TemplateTestHooks.needSaving()','Project Save did not finish',30000);
"""),
    (221, 222, r"""  await until('TemplateTestHooks.saveDidComplete()','Project Save after import callback did not finish',30000);
"""),
])

patch('docs/SCENE_SELECTION.md', 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', [
    (0, 0, r"""# Ordinary scene selections

These rules concern the normal level Selection tool, not Selection Templates.

Moving or copying a selection transfers only its selected content. Empty positions in a rectangular selection are transparent: they do not erase existing data in the destination, including data on the same layer. Unselected and hidden layers are not swept by the rectangle. The empty-space selection option can retain a rectangular visual/flip boundary; it does not turn the rectangle into an eraser.

An actual selected Tiles/IntGrid cell still writes at its destination. IntGrid replaces the value at that explicit cell. Tiles preserve the complete source tile stack; destination tiles are replaced when tile stacking is off and merged when it is on. This is distinct from empty gaps, which never write anything.

The drag preview and final drop use one frozen source coordinate frame and one shared movement step. Mixed compatible layer grids keep their relative arrangement. Invalid or incompatible destination alignment cancels the whole operation instead of dropping only part of a selection. Cancelling restores the source cut.

Queued X/Y tile flips are committed at their final positions in the same history operation as the move/copy. They do not paste over background at an intermediate unflipped position. Existing key bindings are not reassigned.

## Tests

From `app`, run `npm run test:selection`. On a headless Linux runner, use `xvfb-run -a -s '-screen 0 1600x1000x24' npm run test:selection`.

The runner compiles an instrumented renderer, runs the ordinary-selection data matrix and real Electron mouse workflows, then runs the existing Selection Templates regression. It restores the production renderer when finished. Test hooks are excluded from production builds.

The fixtures cover transparent holes on occupied layers; hidden/unselected layers; different grids and offsets; pointer grab positions; all movement directions; overlapping source/destination; source tile stacks; queued flips; point arrays and entity references; cancellation and invalid destinations; and Undo/Redo.

The automated suite includes 445 data scenarios and 4,884 assertions, four actual mouse workflows with Undo/Redo, five template-model tests, and the existing 20-scenario template UI regression. The Electron UI suites run on Linux; Windows and macOS packaging remain separate release jobs.
"""),
])

patch('docs/SMARTIVE_CHANGELOG.md', 'ceff980788c8bd3c3bc8da3c9ed92032ad8947ea3980400296ee2153083b03e0', [
    (0, 0, r"""# 1.0.23

## Ordinary scene selection: transparent gaps and consistent movement

- Fixed ordinary scene selection, move, duplicate and clipboard-style movement. This is not a change to Selection Template placement.
- A selection's empty rectangle area is now transparent when moving or copying: it never clears unselected destination cells or unrelated layers.
- Unified ordinary selection transfers around one immutable source snapshot and one snapped displacement shared with the visible drag ghost. Grabbing the opposite edge of a tile no longer shifts the final drop by a tile relative to the preview.
- Corrected cross-layer coordinate conversion for different grids, offsets, scaled layers and negative coordinates. Screen-to-world and world-to-screen conversion now use the same active rendered level frame, avoiding rounding drift at fractional zoom.
- Pointer press/move/release now use their own queued event coordinates rather than a later DOM mouse position, fixing fast-drag origin shifts.
- Fixed vertical auto-scroll cancellation leaving the previous Y target active during manual navigation.
- Applied queued tile flips directly at the final destination rather than pasting and then flipping. Sparse flipped selections no longer erase unrelated content at intermediate positions.
- Preserved full source tile stacks and the explicit tile-stacking preference.
- Added all-or-nothing preflight checks for invalid destinations and copied entity limits, plus restoration of temporarily cut content on cancellation.
- Fixed independent selected point-handle movement/copying and kept copied entity paths and internal references attached to the copied group.
- Kept existing shortcut assignments and template placement/storage behavior unchanged.
- Added 445 ordinary-selection data scenarios with 4,884 assertions, plus real Electron mouse move/copy and Undo/Redo workflows, including press/move/release queued in one frame. The release also runs the existing Selection Templates regression.

### Builds

- Windows x64 installer.
- Universal macOS DMG.
- Linux x64 AppImage.


"""),
])

patch('src/electron.renderer/display/Camera.hx', '95fa2e33229fea5ac830bbc3409eda25497db10db3ca520989a8d5820d8a3557', [
    (227, 228, r"""		targetWorldX = targetWorldY = null;
"""),
])

patch('src/electron.renderer/misc/Coords.hx', '4b51e9560e22b2cd47b7810465a87ec8b9a1cb39c6d054f4affc3acea0a2f9b0', [
    (26, 27, r"""			{
			var editor=Editor.ME;
			// In level mode invert the actual level render transform. World
			// and level roots are rounded separately; mixing them introduces
			// a one-screen-pixel bias that becomes a cell near grid borders.
			if(!editor.worldMode && editor.curLevel!=null)
				return editor.curLevel.worldX + (canvasX/Const.SCALE-editor.levelRender.root.x)/editor.camera.adjustedZoom;
			return (canvasX/Const.SCALE-editor.worldRender.root.x)/editor.camera.adjustedZoom;
		}
"""),
    (34, 35, r"""			{
			var editor=Editor.ME;
			// In level mode invert the actual level render transform. World
			// and level roots are rounded separately; mixing them introduces
			// a one-screen-pixel bias that becomes a cell near grid borders.
			if(!editor.worldMode && editor.curLevel!=null)
				return editor.curLevel.worldY + (canvasY/Const.SCALE-editor.levelRender.root.y)/editor.camera.adjustedZoom;
			return (canvasY/Const.SCALE-editor.worldRender.root.y)/editor.camera.adjustedZoom;
		}
"""),
    (109, 109, r"""	/** Heaps queues pointer events. Use the event's own position rather than
	 * App.lastKnownMouse, which may already point at a later move/release. */
	public static function fromHeapsEvent(event:hxd.Event):Coords {
		var offset=App.ME.jCanvas.offset();
		return new Coords(M.round(event.relX/pixelRatio+offset.left),M.round(event.relY/pixelRatio+offset.top));
	}

"""),
    (111, 121, r"""		var editor=Editor.ME;
		if(editor.worldMode && editor.curLevel!=null)
			return fromWorldCoords(editor.curLevel.worldX+lx,editor.curLevel.worldY+ly);
		var z=editor.camera.adjustedZoom;
		var px=(lx*z+editor.levelRender.root.x)*Const.SCALE/pixelRatio+App.ME.jCanvas.offset().left;
		var py=(ly*z+editor.levelRender.root.y)*Const.SCALE/pixelRatio+App.ME.jCanvas.offset().top;
		return new Coords(M.round(px),M.round(py));
"""),
    (123, 124, r"""	/** Create from World coords, using the same render frame as worldXf/Yf. **/
"""),
    (125, 135, r"""		var editor=Editor.ME, z=editor.camera.adjustedZoom;
		var inLevel=!editor.worldMode && editor.curLevel!=null;
		var root:h2d.Object=inLevel ? editor.levelRender.root : editor.worldRender.root;
		var x=inLevel ? wx-editor.curLevel.worldX : wx;
		var y=inLevel ? wy-editor.curLevel.worldY : wy;
		var px=(x*z+root.x)*Const.SCALE/pixelRatio+App.ME.jCanvas.offset().left;
		var py=(y*z+root.y)*Const.SCALE/pixelRatio+App.ME.jCanvas.offset().top;
		return new Coords(M.round(px),M.round(py));
"""),
])

patch('src/electron.renderer/misc/SelectionMove.hx', 'daee0d245021193177fce04f9aa3a38951d2bf3819d29d2281eca9ddb579fa61', [
    (24, 26, r"""			x:(Math.floor((to.worldX-a.offsetX)/grid)-Math.floor((M.round(a.x)-a.offsetX)/grid))*grid,
			y:(Math.floor((to.worldY-a.offsetY)/grid)-Math.floor((M.round(a.y)-a.offsetY)/grid))*grid,
"""),
    (199, 200, r"""			var sourceField:data.inst.FieldInstance=p.s.fi;
			var fi=ei.getFieldInstance(sourceField.def,true);
"""),
])

patch('src/electron.renderer/page/Editor.hx', '1aa2ebeb4a5e1aca4448e28de2512e454f1ec42433b389397723c6294e5c06c0', [
    (105, 106, r"""			.on("mouseup.client", function(ev) {
				// Canvas releases are consumed in the Heaps queue, after their
				// matching press/moves. The DOM callback otherwise overtakes them.
				if( !new J(ev.target).is("canvas#webgl") )
					onMouseUp(new Coords(ev.pageX,ev.pageY));
			} )
"""),
    (1110, 1111, r"""			case ERelease: onMouseUp(Coords.fromHeapsEvent(e));
"""),
    (1119, 1120, r"""			case EReleaseOutside: onMouseUp(Coords.fromHeapsEvent(e));
"""),
    (1148, 1149, r"""		var m = Coords.fromHeapsEvent(ev);
"""),
    (1177, 1179, r"""	function onMouseUp(?at:Coords) {
		var m = at==null ? getMouse() : at;
"""),
    (1205, 1206, r"""		var m = Coords.fromHeapsEvent(ev);
"""),
])

patch('src/electron.renderer/test/SceneSelectionTests.hx', '101c68b62fae038e1af4c0371128fb1130c8b1132434d4bec5d3dc7b711763cf', [
    (85, 86, r"""		e.x=x; e.y=y;
		for(fd in e.def.fieldDefs) e.getFieldInstance(fd,true);
		return e;
"""),
    (272, 272, r"""	public static function zoomCases():Dynamic {
		for(zoom in [0.5,1.,2.,3.]) for(grid in [8,16,32]) for(copy in [false,true]) {
			caseName='camera-zoom=$zoom grid=$grid copy=$copy'; reset(grid,3);
			Editor.ME.camera.setZoom(zoom);
			Editor.ME.ge.emit(ViewportChanged(true));
			var a=li(aUid), e=actor(8*grid+3,8*grid+5);
			a.setIntGrid(8,8,1,false); a.setIntGrid(13,12,9,false);
			var g=selection([GridCell(a,8,8),Entity(e._li,e)],true,8*grid+3,8*grid-3,10*grid+2,10*grid-4);
			var from=coords(3+8*grid+grid-2,-3+8*grid+grid-2), to=coords(3+12*grid+1,-3+12*grid+1);
			// A screen pixel spans several world pixels when zoomed out. Derive
			// the expected cell from the actual native Coords UI hit-test, not an
			// unrepresentable ideal world position passed into the fixture.
			var nativeFrom=from.cloneRelativeToLayer(a), nativeTo=to.cloneRelativeToLayer(a);
			var dx=nativeTo.cx-nativeFrom.cx, dy=nativeTo.cy-nativeFrom.cy;
			transfer(g,from,to,copy,true);
			check(a.getIntGrid(8+dx,8+dy)==1,"camera zoom changed snapped cell relative to native pointer grid");
			check(a.getIntGrid(13,12)==9,"camera zoom erased a hole");
			for(ge in g.allElements()) switch ge { case Entity(_,ei): check(ei.x==8*grid+3+dx*grid && ei.y==8*grid+5+dy*grid,"camera zoom drifted entity"); case _: }
			g.dispose(); passes.push(caseName);
		}
		caseName="camera-cancel-clears-both-axes";
		Editor.ME.camera.scrollTo(100,200);
		Editor.ME.camera.cancelAutoScrolling();
		check(Editor.ME.camera.targetWorldX==null && Editor.ME.camera.targetWorldY==null,"camera cancellation left vertical autoscroll active");
		passes.push(caseName);
		Editor.ME.camera.setZoom(2);
		return {cases:passes.length,assertions:assertions};
	}

"""),
    (281, 281, r"""		Editor.ME.ge.emit(ViewportChanged(true));
"""),
    (286, 287, r"""		var mouse=Editor.ME.getMouse();
		return {mouse:{x:mouse.levelX,y:mouse.levelY,cx:mouse.cx,cy:mouse.cy},copy:Editor.ME.selectionTool.isCopy,anchor:g.dragAnchor,running:Editor.ME.selectionTool.isRunning(),moving:Editor.ME.selectionTool.moveStarted,
"""),
    (291, 291, r"""	}
	public static function historySettled():Bool {
		App.ME.requestCpu();
		@:privateAccess for(e in Editor.ME.ge.eofEvents.keys()) switch e {
			case LayerInstancesRestoredFromHistory(_), LevelRestoredFromHistory(_), ViewportChanged(_): return false;
			case _:
		}
		return true;
"""),
])

patch('src/electron.renderer/test/SelectionTemplatesTestHooks.hx', '0c9df8f431819df7d6f64be5d22df34b43f8e1fd001f6c9a21be34d7e92bcadc', [
    (88, 88, r"""	public static function historySettled():Bool {
		// Observe the real end-of-frame restoration; do not simulate or skip it.
		App.ME.requestCpu();
		@:privateAccess for(e in Editor.ME.ge.eofEvents.keys()) switch e {
			case LayerInstancesRestoredFromHistory(_), LevelRestoredFromHistory(_), ViewportChanged(_): return false;
			case _:
		}
		return true;
	}
"""),
])
