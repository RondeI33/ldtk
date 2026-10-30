'use strict';

// Editor-only, read-only Unity asset inspection. Never writes the image, metadata,
// prefab, project JSON or undo history. FAILSAFE_SCHEMA preserves 64-bit fileIDs.
const fs = require('node:fs');
const path = require('node:path');
const yaml = require('js-yaml');
const MAX_TEXT = 8 * 1024 * 1024;
const MAX_IMAGE = 16 * 1024 * 1024;
const MAX_PIXELS = 16777216;
const identity = () => ({a: 1, b: 0, c: 0, d: 1, x: 0, y: 0});
const object = v => v && typeof v === 'object' && !Array.isArray(v);
const fail = message => { throw Error(message); };

function numeric(v, name, fallback) {
  if (v === undefined && fallback !== undefined) return fallback;
  if (typeof v !== 'number' && typeof v !== 'string' || String(v).trim() === '') fail('Invalid ' + name);
  const n = Number(v);
  if (!Number.isFinite(n)) fail('Invalid ' + name);
  return n;
}
function boundedText(text) {
  if (typeof text !== 'string' || Buffer.byteLength(text) > MAX_TEXT) fail('Unity text file exceeds 8 MiB');
  return text;
}
function parseYaml(text) {
  return yaml.load(boundedText(text), {schema: yaml.FAILSAFE_SCHEMA, json: false});
}
function readBounded(file, limit) {
  const stat = fs.statSync(file);
  if (!stat.isFile() || stat.size > limit) fail('File is not a regular file or exceeds the preview size limit: ' + path.basename(file));
  const bytes = fs.readFileSync(file);
  if (bytes.length > limit) fail('File grew beyond the preview size limit');
  return bytes;
}
function pngSize(bytes) {
  if (!Buffer.isBuffer(bytes) || bytes.length < 33 || !bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10])) || bytes.toString('ascii',12,16) !== 'IHDR') fail('Choose a PNG image');
  const width = bytes.readUInt32BE(16), height = bytes.readUInt32BE(20);
  if (!width || !height || width * height > MAX_PIXELS || width > 16384 || height > 16384) fail('PNG dimensions exceed the preview limit');
  return {width, height};
}
function pivot(alignment, value) {
  const predefined = [[.5,.5],[0,1],[.5,1],[1,1],[0,.5],[1,.5],[0,0],[.5,0],[1,0]];
  const a = numeric(alignment, 'sprite alignment', 0);
  if (!Number.isInteger(a) || a < 0 || a > 9) fail('Unsupported sprite alignment');
  const p = a === 9 ? [numeric(value?.x, 'pivot X'), numeric(value?.y, 'pivot Y')] : predefined[a];
  if (p.some(v => v < 0 || v > 1)) fail('Sprite pivot must be normalized to 0–1');
  return {x: p[0], y: p[1]};
}
function parseMeta(text, width, height) {
  const doc = parseYaml(text), importer = doc?.TextureImporter;
  if (!object(importer) || !/^[a-f0-9]{32}$/i.test(doc.guid || '')) fail('Not a Unity texture .meta file');
  const ppu = numeric(importer.spritePixelsToUnits ?? importer.spritePixelsPerUnit, 'sprite Pixels Per Unit');
  if (ppu <= 0 || ppu > 1000000) fail('Sprite PPU must be positive');
  const mode = numeric(importer.spriteMode, 'sprite mode');
  if (mode !== 1 && mode !== 2) fail('Only Single and Multiple Unity sprite imports are supported');
  const names = new Map();
  for (const item of importer.internalIDToNameTable || []) {
    if (object(item.first) && typeof item.second === 'string') {
      for (const id of Object.values(item.first)) names.set(item.second, String(id));
    }
  }
  for (const [id, name] of Object.entries(importer.fileIDToRecycleName || {})) names.set(String(name), id);
  const entries = mode === 1 ? [{name: 'Single sprite', rect: {x:0,y:0,width,height}, alignment:importer.spriteAlignment, pivot:importer.spritePivot, internalID:'21300000'}] : importer.spriteSheet?.sprites;
  if (!Array.isArray(entries) || !entries.length || entries.length > 4096) fail('The .meta file has no supported sprite rectangles');
  const frames = entries.map((entry, index) => {
    const rect = {};
    for (const key of ['x','y','width','height']) {
      rect[key] = numeric(entry.rect?.[key], 'sprite rectangle ' + key);
      if (!Number.isInteger(rect[key])) fail('Sprite rectangles must use whole pixels');
    }
    if (rect.x < 0 || rect.y < 0 || rect.width <= 0 || rect.height <= 0 || rect.x + rect.width > width || rect.y + rect.height > height) fail('Sprite rectangle lies outside the PNG');
    const name = String(entry.name ?? ('Frame ' + index));
    return {name, rect, pivot:pivot(entry.alignment, entry.pivot), fileId:String(entry.internalID ?? names.get(name) ?? '')};
  });
  return {guid: doc.guid, ppu, frames};
}
function multiply(parent, child) {
  return {
    a:parent.a*child.a+parent.c*child.b, b:parent.b*child.a+parent.d*child.b,
    c:parent.a*child.c+parent.c*child.d, d:parent.b*child.c+parent.d*child.d,
    x:parent.a*child.x+parent.c*child.y+parent.x, y:parent.b*child.x+parent.d*child.y+parent.y,
  };
}
function transformMatrix(t, root) {
  const pos = t.m_LocalPosition, scale = t.m_LocalScale, q = t.m_LocalRotation;
  const qx=numeric(q?.x,'rotation X'), qy=numeric(q?.y,'rotation Y');
  let z=numeric(q?.z,'rotation Z'), w=numeric(q?.w,'rotation W');
  if (Math.abs(qx)>1e-5 || Math.abs(qy)>1e-5) fail('The SpriteRenderer is tilted out of the 2D plane; configure it manually');
  const length = Math.hypot(z,w);
  if (length < 1e-8) fail('Invalid prefab rotation');
  z/=length; w/=length;
  const sx=numeric(scale?.x,'scale X'), sy=numeric(scale?.y,'scale Y');
  if (Math.abs(sx)<1e-8 || Math.abs(sy)<1e-8) fail('A zero-scale SpriteRenderer cannot be previewed');
  return {a:(1-2*z*z)*sx,b:2*z*w*sx,c:-2*z*w*sy,d:(1-2*z*z)*sy,
    x:root?0:numeric(pos?.x,'renderer position X'), y:root?0:numeric(pos?.y,'renderer position Y')};
}
function parsePrefab(text, meta) {
  boundedText(text);
  // Unity's document tags and anchors identify native objects, not executable YAML tags.
  const headers = [...text.matchAll(/^--- !u!(\d+) &(-?\d+)( stripped)?\s*$/gm)];
  if (!headers.length || headers.length > 10000) fail('Not a supported text Unity prefab');
  const transforms = new Map(), renderers = [];
  for (let i=0;i<headers.length;i++) {
    const header=headers[i], type=Number(header[1]);
    if (type !== 4 && type !== 212) continue;
    const body=parseYaml(text.slice(header.index+header[0].length,headers[i+1]?.index ?? text.length));
    const value=body?.[type===4?'Transform':'SpriteRenderer'];
    if (!object(value)) fail('Malformed prefab object');
    const record={id:header[2],value,stripped:!!header[3]};
    if (type===4) transforms.set(record.id,record); else renderers.push(record);
  }
  const candidates=renderers.filter(r=>String(r.value.m_Sprite?.guid)===meta.guid && String(r.value.m_Enabled ?? '1')!=='0');
  if (!candidates.length) return null;
  if (candidates.length!==1) fail('Several enabled SpriteRenderers use this sheet; select a simpler prefab or configure manually');
  const renderer=candidates[0], spriteId=String(renderer.value.m_Sprite.fileID);
  const frameIndex=meta.frames.findIndex(f=>f.fileId===spriteId);
  if (frameIndex<0) fail('The prefab sprite fileID is not present in the selected .meta');
  const gameObject=String(renderer.value.m_GameObject?.fileID);
  let current=[...transforms.values()].find(t=>String(t.value.m_GameObject?.fileID)===gameObject);
  if (!current) fail('SpriteRenderer Transform is missing');
  const chain=[],seen=new Set();
  while (current) {
    if (seen.has(current.id) || chain.length>128) fail('Cyclic or excessively deep prefab Transform hierarchy');
    seen.add(current.id);
    if (current.stripped || String(current.value.m_PrefabInstance?.fileID ?? '0')!=='0' || String(current.value.m_CorrespondingSourceObject?.fileID ?? '0')!=='0') fail('Nested/variant prefab transforms require Unity resolution; configure the renderer manually');
    chain.push(current.value);
    const parent=String(current.value.m_Father?.fileID ?? '');
    if (parent==='0') break;
    current=transforms.get(parent);
    if (!current) fail('Prefab parent Transform is missing');
  }
  let matrix=identity();
  chain.reverse().forEach((t,i)=>{matrix=multiply(matrix,transformMatrix(t,i===0));});
  if (String(renderer.value.m_FlipX)==='1') {matrix.a=-matrix.a;matrix.b=-matrix.b;}
  if (String(renderer.value.m_FlipY)==='1') {matrix.c=-matrix.c;matrix.d=-matrix.d;}
  if (Object.values(matrix).some(v=>!Number.isFinite(v)||Math.abs(v)>1000000)) fail('Prefab transform exceeds the preview range');
  return {frameIndex,matrix};
}
function unityRoot(file) {
  let dir=path.dirname(path.resolve(file));
  for (let i=0;i<32;i++) {
    if (fs.existsSync(path.join(dir,'Assets')) && fs.existsSync(path.join(dir,'ProjectSettings'))) return dir;
    const parent=path.dirname(dir); if(parent===dir) break; dir=parent;
  }
  return null;
}
function findDefault(projectPath) {
  if(!projectPath) return null;
  const root=unityRoot(projectPath);
  if (!root) return null;
  const image=path.join(root,'Assets/DitherParadox/Sprites/Characters/Joshua/JoshuaIdle.png');
  return fs.existsSync(image) && fs.existsSync(image+'.meta') ? image : null;
}
function inspect(imagePath, prefabPath=null, selectedFrame=null) {
  const bytes=readBounded(imagePath,MAX_IMAGE),size=pngSize(bytes);
  const metaPath=imagePath+'.meta';
  if (!fs.existsSync(metaPath)) return {source:imagePath,dataUrl:'data:image/png;base64,'+bytes.toString('base64'),...size,
    frames:[{name:'Single PNG (no .meta)',rect:{x:0,y:0,...size},pivot:{x:.5,y:0},fileId:''}],frameIndex:0,ppu:16,matrix:identity(),verified:false,
    warning:'Brak .meta — PPU, pivot i offset wymagają ręcznej konfiguracji.'};
  const meta=parseMeta(readBounded(metaPath,MAX_TEXT).toString('utf8'),size.width,size.height);
  let frameIndex=meta.frames.findIndex(f=>/idle/i.test(f.name));
  if(frameIndex<0) frameIndex=0;
  let matrix=identity(),verified=false,warning='PPU i pivot z .meta. Transformacja prefabu niezweryfikowana.';
  let paths=[];
  if(prefabPath) paths=[prefabPath];
  else {
    const root=unityRoot(imagePath),dir=root && path.join(root,'Assets/DitherParadox/Prefabs/Characters/Joshua');
    if(dir && fs.existsSync(dir)) paths=fs.readdirSync(dir).filter(n=>n.endsWith('.prefab')).sort().slice(0,16).map(n=>path.join(dir,n));
  }
  const matches=[];
  for(const file of paths) {
    try {
      const result=parsePrefab(readBounded(file,MAX_TEXT).toString('utf8'),meta);
      if(result) matches.push({...result,path:file});
    } catch(error) {if(prefabPath) throw error; warning='PPU i pivot z .meta. Prefab wymaga ręcznej weryfikacji.';}
  }
  if(prefabPath && !matches.length) fail('The selected prefab does not use this sprite asset');
  if(matches.length===1) {
    matrix=matches[0].matrix;frameIndex=matches[0].frameIndex;verified=true;warning='';prefabPath=matches[0].path;
  } else if(matches.length>1) warning='Kilka prefabów pasuje do grafiki — wybierz właściwy prefab.';
  if(selectedFrame!==null) {
    if(!Number.isInteger(selectedFrame)||selectedFrame<0||selectedFrame>=meta.frames.length) fail('Invalid idle frame selection');
    frameIndex=selectedFrame;
  }
  return {source:imagePath,prefabPath,dataUrl:'data:image/png;base64,'+bytes.toString('base64'),...size,...meta,frameIndex,matrix,verified,warning};
}
async function crop(definition) {
  const image=new Image();
  await new Promise((resolve,reject)=>{image.onload=resolve;image.onerror=()=>reject(Error('Cannot decode the selected PNG'));image.src=definition.dataUrl;});
  if(image.naturalWidth!==definition.width||image.naturalHeight!==definition.height) fail('PNG dimensions do not match the decoded image');
  const frame=definition.frames[definition.frameIndex],r=frame.rect;
  const canvas=document.createElement('canvas');canvas.width=r.width;canvas.height=r.height;
  const context=canvas.getContext('2d');context.imageSmoothingEnabled=false;
  // Unity rectangles start at bottom-left. HTML canvas starts at top-left.
  context.drawImage(image,r.x,definition.height-r.y-r.height,r.width,r.height,0,0,r.width,r.height);
  return {...definition,dataUrl:canvas.toDataURL('image/png'),width:r.width,height:r.height,pivotX:frame.pivot.x,pivotY:frame.pivot.y,name:frame.name};
}
async function load(imagePath,prefabPath=null,selectedFrame=null) {return crop(inspect(imagePath,prefabPath,selectedFrame));}
module.exports={parseMeta,parsePrefab,pngSize,multiply,findDefault,inspect,crop,load};

/** Own the importer UI for exactly one editor instance. Late image decodes cannot
 * leak across project switches; only this disposable controller reads assets. */
function attach(projectPath,onChange) {
  const controls=document.querySelector('#cameraPreviewControls');
  const imagePicker=controls.querySelector('.cameraSpriteFile');
  const prefabPicker=controls.querySelector('.cameraPrefabFile');
  const framePicker=controls.querySelector('.cameraSpriteFrame');
  const status=controls.querySelector('.cameraSpriteStatus');
  let generation=0,disposed=false,imagePath=null,prefabPath=null;
  const listeners=[];
  const listen=(el,event,fn)=>{el.addEventListener(event,fn);listeners.push(()=>el.removeEventListener(event,fn));};
  const message=text=>{status.textContent=text;};
  const refresh=async (selectedFrame=null)=>{
    if(!imagePath || disposed) return;
    const request=++generation;
    message('Odczyt grafiki i metadanych Unity…');
    try {
      const result=await load(imagePath,prefabPath,selectedFrame);
      if(disposed || request!==generation) return;
      framePicker.replaceChildren();
      result.frames.forEach((f,i)=>{const option=document.createElement('option');option.value=String(i);option.textContent=f.name;framePicker.append(option);});
      framePicker.value=String(result.frameIndex); framePicker.disabled=result.frames.length<2;
      const fields={cameraSpritePpu:result.ppu,cameraSpritePivotX:result.pivotX,cameraSpritePivotY:result.pivotY,cameraSpriteOffsetX:result.matrix.x,cameraSpriteOffsetY:result.matrix.y};
      for(const [key,value] of Object.entries(fields)) controls.querySelector('.'+key).value=String(value);
      onChange(result);
      message(result.verified ? 'PPU, klatka i pivot z .meta; transformacja ze wskazanego prefabu.' : result.warning);
      status.dataset.verified=String(result.verified);
    } catch(error) {
      if(!disposed && request===generation){message('Nie wczytano: '+error.message+' Poprzednia grafika pozostaje aktywna.');status.dataset.verified='false';}
    }
  };
  listen(imagePicker,'change',()=>{if(!imagePicker.files?.length)return;imagePath=imagePicker.files[0].path;prefabPath=null;prefabPicker.value='';refresh();});
  listen(prefabPicker,'change',()=>{if(!prefabPicker.files?.length)return;if(!imagePath){message('Najpierw wybierz PNG ze zgodnym plikiem .meta.');return;}prefabPath=prefabPicker.files[0].path;refresh();});
  listen(framePicker,'change',()=>refresh(Number(framePicker.value)));
  for(const input of controls.querySelectorAll('.cameraSpriteParams input')) listen(input,'input',()=>{status.dataset.verified='false';message('Parametry zmienione ręcznie — nie jest to zweryfikowany prefab Unity.');});
  message('Grafika zastępcza: PPU/pivot/offset niezweryfikowane. Wybierz JoshuaIdle.png z .meta i prefab.');
  try{imagePath=findDefault(projectPath);if(imagePath)refresh();}catch(error){message('Automatyczne wyszukiwanie: '+error.message);}
  return {tryAuto(file){if(imagePath||disposed)return;try{imagePath=findDefault(file);if(imagePath)refresh();}catch(error){message(error.message);}},dispose(){disposed=true;generation++;listeners.forEach(off=>off());}};
}
module.exports.attach=attach;
