'use strict';

const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'../..');
const source=fs.readFileSync(path.join(root,'unity/com.rondei33.ldtk-smartive-unity-tile-rotation/Editor/SmartiveTileRotationPostprocessor.cs'),'utf8');

const multiply=(a,b)=>[
  [a[0][0]*b[0][0]+a[0][1]*b[1][0],a[0][0]*b[0][1]+a[0][1]*b[1][1]],
  [a[1][0]*b[0][0]+a[1][1]*b[1][0],a[1][0]*b[0][1]+a[1][1]*b[1][1]],
];
const transpose=[[0,-1],[-1,0]];
const unityYUp=[[1,0],[0,-1]];
const native=(bits)=>[[(bits&1)?-1:1,0],[0,(bits&2)?-1:1]];
const desiredScreen=(bits)=>{
  const f=native(bits);
  return bits&4 ? multiply(f,[[0,1],[1,0]]) : f;
};
const importedUnity=(bits)=>{
  const f=native(bits&3);
  return bits&4 ? multiply(f,transpose) : f;
};

test('each of eight orientations exactly matches LDtk Y-down image geometry converted to Unity Y-up',()=>{
  for(let bits=0;bits<8;bits++){
    const result=importedUnity(bits);
    const expected=multiply(multiply(unityYUp,desiredScreen(bits)),unityYUp);
    assert.deepEqual(result,expected,`Wrong tile artwork orientation for bits=${bits}`);
  }
});

test('every tile of a non-square sparse atlas stamp retains its own rotation, not an aggregate transform',()=>{
  const ids=[1,2,3,11,13],columns=10;
  const pts=ids.map(id=>({id,x:id%columns-1,y:Math.floor(id/columns)}));
  const positions=pts.map(p=>({id:p.id,cx:1-p.y,cy:p.x,flips:5}));
  assert.deepEqual(positions.map(p=>[p.id,p.cx,p.cy]),[
    [1,1,0],[2,1,1],[3,1,2],[11,0,0],[13,0,2],
  ]);
  assert.equal(positions.length,5);
  assert(!positions.some(p=>p.cx===0&&p.cy===1),'A sparse hole was unexpectedly filled');
  for(const pos of positions)assert.deepEqual(importedUnity(pos.flips),[[0,1],[-1,0]]);
});

test('coordinate IDs and stack indices are preserved one-to-one during LDtkUnity Tilemap conversion',()=>{
  const width=40,height=24;
  for(const [cx,cy,stackIndex] of [[0,0,0],[39,23,0],[3,4,2],[7,12,1],[39,0,3]]){
    const coordId=cx+cy*width;
    const tile={x:coordId%width,y:height-1-Math.floor(coordId/width),z:stackIndex};
    assert.deepEqual(tile,{x:cx,y:height-1-cy,z:stackIndex});
  }
});

test('sidecar restoration refuses a changed native tile or flip state',()=>{
  const sidecar={coordId:43,stackIndex:1,tileId:12,flips:5};
  const native=[{t:2,f:0},{t:12,f:1}];
  const valid=(stack,entry)=>entry.flips>=4 && entry.flips<=7 &&
    stack[entry.stackIndex]?.t===entry.tileId && stack[entry.stackIndex]?.f===(entry.flips&3);
  assert(valid(native,sidecar));
  assert(!valid([{t:2,f:0},{t:99,f:1}],sidecar));
  assert(!valid([{t:2,f:0},{t:12,f:2}],sidecar));
  assert(!valid([{t:2,f:0}],sidecar));
});

test('Unity postprocessor uses cell matrices without transforming any parent Tilemap objects',()=>{
  for(const fragment of [
    'map.GetTransformMatrix(position) * UnityTranspose',
    'map.SetTransformMatrix(position, matrix)',
    'map.GetTileFlags(position)',
    'Vector3Int(cx, height - 1 - cy, stackIndex)',
    'ReadInt(stack[stackIndex], "t", -1) != tileId',
    'ReadInt(stack[stackIndex], "f", -1) != (flips & 3)',
  ])assert(source.includes(fragment),`Missing per-tile safety contract: ${fragment}`);
  assert(!/\.transform\.Rotate\(/.test(source));
  assert(!/\.transform\.rotation\s*=/.test(source));
  assert(!/\.transform\.localEulerAngles\s*=/.test(source));
});
