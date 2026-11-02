'use strict';
const assert=require('node:assert/strict');
const test=require('node:test');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const {evaluate,verify,roundHalfEven,queryPaths,createClient}=require('../assets/js/camera-model-revision2.cjs');

const iid='51250efa-0356-4d66-ba09-be0514944976';
function fixture() {
  const model={
    schemaVersion:1,modelRevision:2,controller:'legacy',
    outputPixels:{x:846.22,y:476},assignmentProbeOffset:{x:0,y:0},
    levels:[{iid,identifier:'Outside',ldtkWorldOrigin:{x:0,y:1664},
      unityTopLeft:{x:0,y:-104},pixelsPerUnit:16}],
    rooms:[{id:iid,levelIid:iid,priority:0,mode:0,
      assignment:{x:0,y:-214,width:106,height:110},
      bounds:{x:2,y:-212,width:102,height:108},
      inclusiveAssignment:true,clamp:true,neutralFacing:true,ortho:8,aspect:16/9,lookAhead:4,
      targetOffset:{x:0,y:0},framingOffset:{x:0,y:4},followOffset:{x:0,y:1.5},
      composition:{x:0,y:0},zoneProbeOffset:{x:0,y:1.25},
      vertical:{exported:true,clinging:4,rising:4,apex:0,falling:-4},
      look:{ledgePeek:0,afterConfiner:false,allowYInCorridor:false},
      zoomPixelsPerUnit:16,zoomPixelSnap:true,scaleFramingWithZoom:true}],
    cameras:[{id:'tall-cam-id',name:'CM_TallRoom',activation:'none',ortho:8,followOffset:{x:0,y:5}}],
    unityZones:[],referenceCases:[],
  };
  const samples=[
    {name:'Outside grounded',localPoint:{x:848,y:880},state:{direction:0,motion:'grounded'},expected:{x:620.44,y:664,width:455.11,height:256}},
    {name:'Outside left',localPoint:{x:848,y:880},state:{direction:-1,motion:'grounded'},expected:{x:556.44,y:664,width:455.11,height:256}},
    {name:'Outside right',localPoint:{x:848,y:880},state:{direction:1,motion:'grounded'},expected:{x:684.44,y:664,width:455.11,height:256}},
    {name:'Outside apex',localPoint:{x:848,y:880},state:{direction:0,motion:'apex'},expected:{x:620.44,y:728,width:455.11,height:256}},
    {name:'Outside falling',localPoint:{x:848,y:880},state:{direction:0,motion:'falling'},expected:{x:620.44,y:792,width:455.11,height:256}},
    {name:'Outside Tall Camera',localPoint:{x:848,y:880},state:{cameraId:'CM_TallRoom'},expected:{x:620.44,y:608,width:455.11,height:256}},
    {name:'Outside left-bottom clamp',localPoint:{x:16,y:1744},state:{},expected:{x:32,y:1472,width:455.11,height:256}},
    {name:'Outside top-right clamp',localPoint:{x:1680,y:16},state:{},expected:{x:1208.89,y:0,width:455.11,height:256}},
  ];
  model.referenceCases=samples.map(s=>({...s,levelIid:iid}));
  return model;
}
function near(a,b,label,tolerance=0.02) {
  assert.ok(Number.isFinite(a)&&Math.abs(a-b)<=tolerance,label+': '+a+' != '+b);
}
test('C# handoff legacy reference rectangles: grounded, facing, apex, falling, Tall, confiner',()=>{
  const model=fixture();
  for(const tc of model.referenceCases){
    const got=evaluate(model,tc.levelIid,tc.localPoint,tc.state);
    for(const field of ['x','y','width','height'])near(got[field],tc.expected[field],tc.name+' '+field);
  }
  assert.equal(verify(model).verified,true);
  assert.equal(verify(model).count,8);
});
test('half-to-even rounding mirrors C# zoom step/pixel snap',()=>{
  for(const [v,result] of [[0.5,0],[1.5,2],[2.5,2],[3.5,4],[-0.5,0],[-1.5,-2],[-2.5,-2]])
    assert.equal(roundHalfEven(v),result);
});
test('model drift blocks false verification rather than claiming Unity parity',()=>{
  const model=fixture();
  model.referenceCases[1].expected.x+=1;
  const checked=verify(model);
  assert.equal(checked.verified,false);
  assert.match(checked.detail,/drift.*Outside left/i);
});
test('rig neutral direction resolves right and corridor/ledge handling remains deterministic',()=>{
  const m=fixture(),room=m.rooms[0];
  room.neutralFacing=false;room.lookAhead=3;room.scaleFramingWithZoom=false;
  room.framingOffset.y=2;room.vertical={exported:true,apex:2,falling:2,rising:2,clinging:2};
  room.followOffset={x:0,y:0};
  room.targetOffset={x:0,y:0.5};
  room.clamp=false;
  const idle=evaluate(m,iid,{x:848,y:880},{direction:0});
  const right=evaluate(m,iid,{x:848,y:880},{direction:1});
  const left=evaluate(m,iid,{x:848,y:880},{direction:-1});
  near(idle.x,right.x,'rig neutral points right',1e-8);
  near(right.x-left.x,3*2*16,'rig facing bias total displacement',1e-8);
  room.mode=1;room.corridorY=-150;room.look={ledgePeek:4,afterConfiner:true,allowYInCorridor:false};
  const before=evaluate(m,iid,{x:848,y:880},{look:'none'});
  const after=evaluate(m,iid,{x:848,y:880},{look:'ledge'});
  near(before.y,after.y,'corridor disallows ledge look',1e-8);
  room.look.allowYInCorridor=true;
  const ledge=evaluate(m,iid,{x:848,y:880},{look:'ledge'});
  near(ledge.y-before.y,4*16,'ledge is applied after confiner (Unity down)',1e-8);
});
test("camera zoom uses exported output pixel height and banker's rounded discrete steps",()=>{
  const m=fixture(),room=m.rooms[0];
  room.clamp=false;
  m.unityZones=[{id:'zoom+',kind:'zoom',area:{x:50,y:-170,width:10,height:30},priority:5,allowedModes:7,zoom:8}];
  const frame=evaluate(m,iid,{x:848,y:880},{motion:'grounded'});
  near(frame.height,47.6,'zoom+8 height');
  near(frame.width,47.6*16/9,'zoom+8 width');
});
test('overlapping zoom zones require explicit zone identifier for deterministic evaluation',()=>{
  const m=fixture();
  m.unityZones=[
    {id:'z1',kind:'zoom',area:{x:50,y:-170,width:10,height:30},priority:1,zoom:1},
    {id:'z2',kind:'zoom',area:{x:50,y:-170,width:10,height:30},priority:1,zoom:3},
  ];
  assert.throws(()=>evaluate(m,iid,{x:848,y:880},{}),/Overlapping zoom/);
  assert.ok(evaluate(m,iid,{x:848,y:880},{zoneId:'z2'}).width>0);
});
test('detached dynamic client methods preserve their instance when invoked from Haxe',()=>{
  const {update,clear}=createClient();
  const result=update({
    profile:{unityCameraModel:fixture(),updatedAtUtc:'2026-11-02T12:00:00Z'},
    sidecarPath:'/tmp/World.ldtk-camera.json',
    levelIid:iid,point:{x:848,y:880},state:{},requestEnabled:false
  });
  assert.equal(result.source,'Local (verified)');
  near(result.frame.y,664,'Detached Haxe query returns real model frame');
  clear();
  const after=update({
    profile:{unityCameraModel:fixture(),updatedAtUtc:'2026-11-02T12:00:00Z'},
    sidecarPath:'/tmp/World.ldtk-camera.json',
    levelIid:iid,point:{x:848,y:880},state:{},requestEnabled:false
  });
  assert.equal(after.source,'Local (verified)');
});
test('query paths preserve the same Unity .ldtk sidecar family',()=>{
  assert.deepEqual(queryPaths('/tmp/World.ldtk-camera.json'),{
    query:'/tmp/World.ldtk-camera-query.json',
    answer:'/tmp/World.ldtk-camera-answer.json',
  });
  assert.throws(()=>queryPaths('/tmp/World.ldtk'),/sidecar/);
});
test('Unity answer wins over local solver only on exact request / scene / state match',()=>{
  const d=fs.mkdtempSync(path.join(os.tmpdir(),'smartive-rev2-'));
  try{
    const profilePath=path.join(d,'World.ldtk-camera.json');
    const model=fixture();
    const profile={unityCameraModel:model,updatedAtUtc:'2026-11-02T11:00:00Z'};
    const point={x:848,y:880},state={direction:0,motion:'grounded',look:'none',cameraId:'CM_TallRoom',zoneId:''};
    const client=createClient();
    let first=client.update({sidecarPath:profilePath,profile,levelIid:iid,point,state});
    assert.match(first.source,/Local/);
    const paths=queryPaths(profilePath);
    const query=JSON.parse(fs.readFileSync(paths.query,'utf8'));
    assert.equal(query.levelIid,iid); assert.equal(query.localPoint.y,880);
    assert.equal(query.state.cameraId,'CM_TallRoom');
    const result=evaluate(model,iid,point,state);
    const response={schemaVersion:1,source:'unity',ok:true,requestId:'stale',levelIid:iid,
      snapshotUpdatedAtUtc:profile.updatedAtUtc,localPoint:point,state,frame:result};
    fs.writeFileSync(paths.answer,JSON.stringify(response));
    first=client.update({sidecarPath:profilePath,profile,levelIid:iid,point,state});
    assert.match(first.source,/Local/,'Stale answer was accepted');
    response.requestId=query.requestId;
    response.frame={x:400,y:500,width:300,height:180,serializedVersion:'2'};
    response.center={x:550,y:590};
    fs.writeFileSync(paths.answer,JSON.stringify(response));
    const accepted=client.update({sidecarPath:profilePath,profile,levelIid:iid,point,state});
    assert.match(accepted.source,/Unity/);
    near(accepted.frame.x,400,'Unity answer x',1e-8);
    client.lastWrite=0;
    const moved=client.update({sidecarPath:profilePath,profile,levelIid:iid,point:{x:900,y:900},state});
    assert.doesNotMatch(moved.source,/Unity/,'Old answer is reused after moving Joshua');
  }finally{fs.rmSync(d,{recursive:true,force:true});}
});
test('drifted reference data fails closed to dimension-only until an authoritative Unity answer',()=>{
  const m=fixture();
  m.referenceCases[0].expected.x+=2;
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'smartive-drift-'));
  try{
    const c=createClient();
    const r=c.update({sidecarPath:path.join(dir,'World.ldtk-camera.json'),
      profile:{unityCameraModel:m,updatedAtUtc:'2026-11-02T11:00:00Z'},
      levelIid:iid,point:{x:848,y:880},state:{},requestEnabled:false});
    assert.equal(r.frame,null);
    assert.match(r.diagnostics.join(' '),/drift/);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
