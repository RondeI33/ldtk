'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const S=require('../assets/js/camera-preview-sprite.cjs');
const guid='1234567890abcdef1234567890abcdef';
const id='9223372036854775701';
const meta=`fileFormatVersion: 2
guid: ${guid}
TextureImporter:
  spritePixelsToUnits: 32
  spriteMode: 2
  spriteSheet:
    sprites:
    - name: JoshuaIdle_0
      rect: {x: 8, y: 20, width: 32, height: 44}
      alignment: 9
      pivot: {x: 0.25, y: 0.125}
      internalID: ${id}
    - name: JoshuaIdle_1
      rect: {x: 48, y: 20, width: 32, height: 44}
      alignment: 7
      pivot: {x: 0.9, y: 0.9}
      internalID: 9223372036854775702
`;
const prefab=`%YAML 1.1
%TAG !u! tag:unity3d.com,2011:
--- !u!4 &9223372036854775801
Transform:
  m_GameObject: {fileID: 100}
  m_Father: {fileID: 0}
  m_LocalPosition: {x: 300, y: -20, z: 0}
  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}
  m_LocalScale: {x: 2, y: 3, z: 1}
--- !u!4 &9223372036854775802
Transform:
  m_GameObject: {fileID: 101}
  m_Father: {fileID: 9223372036854775801}
  m_LocalPosition: {x: 0.25, y: 1.5, z: 0}
  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}
  m_LocalScale: {x: 1, y: 0.5, z: 1}
--- !u!212 &9223372036854775803
SpriteRenderer:
  m_GameObject: {fileID: 101}
  m_Enabled: 1
  m_Sprite: {fileID: ${id}, guid: ${guid}, type: 3}
  m_FlipX: 1
  m_FlipY: 0
`;
// Synthetic parser vectors, not the unavailable Unity camera-comparison fixture.
test('meta preserves native rectangles, custom pivot, PPU and exact 64-bit sprite IDs',()=>{
  const m=S.parseMeta(meta,96,80);
  assert.equal(m.ppu,32); assert.equal(m.frames[0].fileId,id);
  assert.deepEqual(m.frames[0].rect,{x:8,y:20,width:32,height:44});
  assert.deepEqual(m.frames[0].pivot,{x:.25,y:.125});
  assert.deepEqual(m.frames[1].pivot,{x:.5,y:0});
});
test('prefab selects actual renderer frame and composes offsets/scales without root translation',()=>{
  const p=S.parsePrefab(prefab,S.parseMeta(meta,96,80));
  assert.equal(p.frameIndex,0);
  assert.deepEqual({...p.matrix,b:p.matrix.b+0},{a:-2,b:0,c:0,d:1.5,x:.5,y:4.5});
});
test('renderer rotation is composed and its world offset follows parent rotation',()=>{
  const rotated=prefab.replace('z: 0, w: 1','z: 0.7071067811865476, w: 0.7071067811865476');
  const m=S.parsePrefab(rotated,S.parseMeta(meta,96,80)).matrix;
  assert.ok(Math.abs(m.x+4.5)<1e-10); assert.ok(Math.abs(m.y-.5)<1e-10);
  assert.ok(Math.abs(m.b+2)<1e-10); assert.ok(Math.abs(m.c+1.5)<1e-10);
});
test('all built-in pivot alignments are recognized, single sprite defaults use Unity center',()=>{
  for(let alignment=0;alignment<9;alignment++){
    const text=`guid: ${guid}\nTextureImporter:\n  spritePixelsToUnits: 16\n  spriteMode: 1\n  spriteAlignment: ${alignment}\n`;
    const m=S.parseMeta(text,32,44); assert.equal(m.frames[0].fileId,'21300000');
    assert.ok(m.frames[0].pivot.x>=0&&m.frames[0].pivot.y<=1);
  }
});
test('old name tables recover exact fileID when sprite records omit internalID',()=>{
  const text=meta.replace(`      internalID: ${id}\n`,'').replace('  spriteSheet:',`  internalIDToNameTable:\n  - first: {213: ${id}}\n    second: JoshuaIdle_0\n  spriteSheet:`);
  assert.equal(S.parseMeta(text,96,80).frames[0].fileId,id);
});
test('bad or unsupported metadata is rejected rather than silently resized',()=>{
  for(const text of [meta.replace('32\n  spriteMode','0\n  spriteMode'),meta.replace('spriteMode: 2','spriteMode: 0'),meta.replace('width: 32','width: 320'),meta.replace('x: 0.25','x: 2.5'),meta.replace('alignment: 9','alignment: 10'),meta.replace('x: 8','x: 8.5'),'!!js/function function(){}']) assert.throws(()=>S.parseMeta(text,96,80));
});
test('unknown renderer and malformed, cyclic, nested or tilted prefabs fail closed',()=>{
  const m=S.parseMeta(meta,96,80);
  assert.equal(S.parsePrefab(prefab.replace(guid,'abcdef1234567890abcdef1234567890'),m),null);
  assert.throws(()=>S.parsePrefab(prefab.replace(id,'123'),m),/fileID/);
  assert.throws(()=>S.parsePrefab(prefab.replace('m_Father: {fileID: 0}','m_Father: {fileID: 9223372036854775802}'),m),/Cyclic/);
  assert.throws(()=>S.parsePrefab(prefab.replace('m_Father: {fileID: 0}','m_Father: {fileID: 44}'),m),/missing/);
  assert.throws(()=>S.parsePrefab(prefab.replace('Transform:\n','Transform:\n  m_PrefabInstance: {fileID: 123}\n'),m),/variant/);
  assert.throws(()=>S.parsePrefab(prefab.replace('m_LocalRotation: {x: 0','m_LocalRotation: {x: 0.1'),m),/2D plane/);
});
test('PNG bounds are validated before decoding',()=>{
  const bytes=fs.readFileSync(path.join(__dirname,'../assets/img/joshua-idle-preview.png'));
  assert.deepEqual(S.pngSize(bytes),{width:32,height:44});
  assert.throws(()=>S.pngSize(Buffer.from('not a png')));
  const giant=Buffer.from(bytes);giant.writeUInt32BE(100000,16);assert.throws(()=>S.pngSize(giant));
});
test('inspection is read-only and explicitly reports fallback or verified provenance',()=>{
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'smartive-sprite-'));
  try{
    const image=path.join(temp,'idle.png');fs.copyFileSync(path.join(__dirname,'../assets/img/joshua-idle-preview.png'),image);
    const before=fs.readFileSync(image);
    assert.equal(S.inspect(image).verified,false);
    const single=`guid: ${guid}\nTextureImporter:\n  spritePixelsToUnits: 16\n  spriteMode: 1\n  spriteAlignment: 7\n`;
    fs.writeFileSync(image+'.meta',single);
    const asset=path.join(temp,'Joshua.prefab');fs.writeFileSync(asset,prefab.replace(id,'21300000'));
    assert.equal(S.inspect(image,asset).verified,true);
    assert.equal(S.inspect(image).verified,false);
    assert.equal(S.inspect(image,asset).matrix.y,4.5);
    assert.deepEqual(fs.readFileSync(image),before);assert.equal(fs.readFileSync(image+'.meta','utf8'),single);
  }finally{fs.rmSync(temp,{recursive:true,force:true});}
});
