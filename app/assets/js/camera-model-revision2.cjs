'use strict';

// Renderer-only, read-only evaluation of Unity Camera Model revision 2.
// Unity is authoritative. All positions here are in Unity world units until
// the final conversion to LDtk level-local pixels (Y axis inverted).
// No level asset, prefab or .ldtk file is ever mutated by this module.
const fs = require('node:fs');
const path = require('node:path');
const MOTIONS = ['grounded', 'rising', 'apex', 'falling', 'clinging'];

function number(value, name, fallback) {
  if (value == null && fallback !== undefined) return fallback;
  if (typeof value !== 'number' || !Number.isFinite(value)) throw Error('Invalid Unity camera number: ' + name);
  return value;
}
function boolean(value, fallback) { return value == null ? fallback : value === true; }
function object(value, name) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw Error('Invalid camera model object: ' + name);
  return value;
}
function vec(value, name, defaultX = 0, defaultY = 0) {
  if (value == null) return {x:defaultX,y:defaultY};
  object(value,name);
  return {x:number(value.x,name+'.x'),y:number(value.y,name+'.y')};
}
function rect(value, name) {
  object(value,name);
  const x=number(value.x,name+'.x'), y=number(value.y,name+'.y');
  const width=number(value.width,name+'.width'), height=number(value.height,name+'.height');
  if(width<=0 || height<=0) throw Error('Invalid camera model rectangle: '+name);
  return {x,y,width,height};
}
function contains(rectangle, point, inclusive=true) {
  const maxX=rectangle.x+rectangle.width, maxY=rectangle.y+rectangle.height;
  return point.x>=rectangle.x && point.y>=rectangle.y &&
    (inclusive ? point.x<=maxX && point.y<=maxY : point.x<maxX && point.y<maxY);
}
function roundHalfEven(n) {
  if (!Number.isFinite(n)) throw Error('Camera model rounding requires a finite value');
  const lower=Math.floor(n), fraction=n-lower;
  if (fraction<0.5) return lower;
  if (fraction>0.5) return lower+1;
  return lower%2===0 ? lower : lower+1;
}
function clamp(v,min,max) {return Math.max(min,Math.min(max,v));}
function clamp01(v) {return clamp(v,0,1);}
function allowed(zone,mode) {
  const mask=zone.allowedModes==null ? 7 : number(zone.allowedModes,'zone.allowedModes');
  return (Math.trunc(mask)&(1<<mode))!==0;
}
function levelFor(model,iid) {
  const levels=Array.isArray(model.levels) ? model.levels : [];
  const level=levels.find(x=>x && (x.iid===iid || x.levelIid===iid || x.ldtkLevelIid===iid));
  if (!level) throw Error('Unity camera model has no level IID '+iid);
  return level;
}
function zoneFor(model,kind,point,mode,levelIid,state) {
  const list=Array.isArray(model.unityZones) ? model.unityZones : [];
  const matches=list.filter(z=>{
    if (!z || z.kind!==kind) return false;
    if(z.levelIid && z.levelIid!==levelIid) return false;
    if(z.enabled===false || !allowed(z,mode)) return false;
    return contains(rect(z.area,'zone.area'),point,kind!=='pan');
  });
  if (!matches.length) return null;
  const top=Math.max(...matches.map(z=>number(z.priority,'zone.priority',0)));
  const tied=matches.filter(z=>number(z.priority,'zone.priority',0)===top);
  if (tied.length===1) return tied[0];
  if(state.zoneId) {
    const selected=tied.find(z=>z.id===state.zoneId || z.entityIid===state.zoneId);
    if(selected) return selected;
  }
  if(kind==='pan') return tied[0]; // Stable source order for pan-only ties.
  throw Error('Overlapping '+kind+' zones depend on entry history; select an explicit zone ID');
}
function cameraFor(model,id) {
  if (!id) return null;
  const cams=Array.isArray(model.cameras) ? model.cameras : [];
  const choice=cams.find(c=>c && (c.id===id || c.name===id));
  if (!choice) throw Error('Unknown Unity camera selection: '+id);
  return choice;
}
function normalizedState(state) {
  const input=state && typeof state==='object' ? state : {};
  const dir=Number(input.direction==null?0:input.direction);
  if (!Number.isInteger(dir) || dir<-1 || dir>1) throw Error('Facing must be -1, 0 or +1');
  const motion=input.motion||'grounded';
  const look=input.look||'none';
  if(!MOTIONS.includes(motion)) throw Error('Unsupported Unity camera motion: '+motion);
  if(look!=='none'&&look!=='ledge') throw Error('Unsupported Unity camera look: '+look);
  return {direction:dir,motion,look,cameraId:String(input.cameraId||''),zoneId:String(input.zoneId||'')};
}
function worldPoint(level,local) {
  const ppu=number(level.pixelsPerUnit,'level.pixelsPerUnit');
  if(ppu<=0)throw Error('Invalid level PPU');
  const origin=vec(level.unityTopLeft,'level.unityTopLeft');
  const pt=vec(local,'localPoint');
  return {x:origin.x+pt.x/ppu, y:origin.y-pt.y/ppu};
}
function pixelFrame(level,world) {
  const ppu=number(level.pixelsPerUnit,'level.pixelsPerUnit');
  const topLeft=vec(level.unityTopLeft,'level.unityTopLeft');
  const x=(world.x-topLeft.x)*ppu;
  const y=(topLeft.y-world.y-world.height)*ppu;
  const width=world.width*ppu,height=world.height*ppu;
  const centerX=x+width/2,centerY=y+height/2;
  for(const v of [x,y,width,height,centerX,centerY]) if(!Number.isFinite(v))throw Error('Camera frame exceeds numeric limits');
  if(width<=0 || height<=0 || width>10000000 || height>10000000)throw Error('Unity camera frame dimensions are invalid');
  return {x,y,width,height,centerX,centerY,column:null,row:null};
}
function evaluate(model,levelIid,localPoint,requestedState) {
  object(model,'unityCameraModel');
  if(model.schemaVersion!==1 || model.modelRevision!==2) throw Error('Requires unityCameraModel schemaVersion 1, modelRevision 2');
  const state=normalizedState(requestedState);
  const level=levelFor(model,levelIid);
  const p=worldPoint(level,localPoint);
  const assignmentProbe=vec(model.assignmentProbeOffset,'assignmentProbeOffset');
  const probeAssignment={x:p.x+assignmentProbe.x,y:p.y+assignmentProbe.y};
  const rooms=(Array.isArray(model.rooms)?model.rooms:[])
    .filter(r=>r && r.levelIid===levelIid && contains(rect(r.assignment,'room.assignment'),probeAssignment,boolean(r.inclusiveAssignment,true)));
  if(!rooms.length) throw Error('No Unity camera room contains Joshua in level '+levelIid);
  // Highest priority wins. Stable source order resolves equal room priorities.
  rooms.sort((x,y)=>number(y.priority,'room.priority',0)-number(x.priority,'room.priority',0));
  const room=rooms[0],mode=number(room.mode,'room.mode',0);
  if(!Number.isInteger(mode)||mode<0||mode>2) throw Error('Invalid camera room mode');
  const roomProbe=vec(room.zoneProbeOffset,'room.zoneProbeOffset');
  const probe={x:p.x+roomProbe.x,y:p.y+roomProbe.y};
  const requestedCamera=cameraFor(model,state.cameraId);
  const lensZone=mode===2 ? null : zoneFor(model,'camera',probe,mode,levelIid,state);
  const lensCamera=lensZone && lensZone.camera ? cameraFor(model,String(lensZone.camera)) : null;
  const zoom=mode===2 ? null : zoneFor(model,'zoom',probe,mode,levelIid,state);
  const focus=mode===2 ? null : zoneFor(model,'focus',probe,mode,levelIid,state);
  const pan=mode===2 ? null : zoneFor(model,'pan',probeAssignment,mode,levelIid,state);
  const option=requestedCamera||lensCamera;
  const base=number(option?.ortho ?? lensZone?.ortho ?? room.ortho,'camera.ortho');
  if(base<=0)throw Error('Camera orthographic size must be positive');
  let ortho=base;
  const output=vec(model.outputPixels,'model.outputPixels');
  if(output.y<=0||output.x<=0)throw Error('Unity output camera pixel dimensions must be positive');
  let zoomApplies=false;
  if(zoom) {
    const ppu=number(room.zoomPixelsPerUnit,'room.zoomPixelsPerUnit',number(level.pixelsPerUnit,'level.ppu'));
    if(ppu<=0)throw Error('Invalid zoom PPU');
    const steps=roundHalfEven(output.y/(2*ppu*base))+number(zoom.zoom,'zone.zoom',0);
    ortho=output.y/(2*ppu*Math.max(1,steps));
    zoomApplies=number(zoom.zoom,'zone.zoom',0)!==0;
  }
  const aspect=number(room.aspect,'room.aspect',output.x/output.y);
  if(aspect<=0)throw Error('Invalid camera aspect');
  const width=2*ortho*aspect,height=2*ortho;
  const direction=state.direction===0 && room.neutralFacing===false ? 1 : state.direction;
  const framing=vec(room.framingOffset,'room.framingOffset');
  const vertical=room.vertical||{};
  if(vertical && typeof vertical!=='object')throw Error('Invalid vertical camera profile');
  const motionY=state.motion==='grounded' ? framing.y :
    number(vertical[state.motion],'room.vertical.'+state.motion,framing.y);
  const orthoRatio=boolean(room.scaleFramingWithZoom,false) ? ortho/base : 1;
  const lookAhead=number(room.lookAhead,'room.lookAhead',0);
  const targetOffset=vec(room.targetOffset,'room.targetOffset');
  let c={
    x:p.x+targetOffset.x+(framing.x+direction*lookAhead)*orthoRatio,
    y:p.y+targetOffset.y+motionY*orthoRatio,
  };
  if(mode===1)c.y=number(room.corridorY,'room.corridorY');
  if(pan) {
    const offset=vec(pan.offset,'pan.offset');
    c.x+=offset.x;
    if(mode!==1 || pan.allowCorridorY===true)c.y+=offset.y;
  }
  const lookConfig=room.look||{};
  const lookDistance=number(lookConfig.ledgePeek,'look.ledgePeek',0);
  const allowLook=mode!==2 && (mode!==1 || lookConfig.allowYInCorridor===true);
  const lookOffset=state.look==='ledge' && allowLook ? -lookDistance : 0;
  const afterConfiner=lookConfig.afterConfiner===true;
  if(!afterConfiner)c.y+=lookOffset;
  if(focus) {
    const pts=Array.isArray(focus.points)?focus.points:[];
    if(pts.length) {
      let selected=null,best=Infinity;
      for(const point of pts) {
        const fp=vec(point,'focus.point');
        const distance=(fp.x-probe.x)**2+(fp.y-probe.y)**2;
        if(distance<best){best=distance;selected=fp;}
      }
      if(selected) {
        const weight=clamp01(number(focus.weight,'focus.weight',1));
        c.x+=(selected.x-c.x)*weight;
        if(mode!==1 || room.allowFocusY===true)c.y+=(selected.y-c.y)*weight;
      }
    }
  }
  const follow=vec(option?.followOffset ?? lensZone?.offset ?? room.followOffset,'camera.followOffset');
  c.x+=follow.x;c.y+=follow.y;
  const composition=vec(room.composition,'room.composition');
  c.x-=width*composition.x;c.y-=height*composition.y;
  if(mode===2)c=vec(room.fixedCenter,'room.fixedCenter');
  if(room.clamp===true) {
    const bounds=rect(room.bounds,'room.bounds');
    c.x=bounds.width<=width ? bounds.x+bounds.width/2 : clamp(c.x,bounds.x+width/2,bounds.x+bounds.width-width/2);
    c.y=bounds.height<=height ? bounds.y+bounds.height/2 : clamp(c.y,bounds.y+height/2,bounds.y+bounds.height-height/2);
  }
  if(afterConfiner)c.y+=lookOffset;
  if(zoomApplies && room.zoomPixelSnap===true) {
    const pixelStep=2*ortho/output.y;
    c.x=roundHalfEven(c.x/pixelStep)*pixelStep;
    c.y=roundHalfEven(c.y/pixelStep)*pixelStep;
  }
  const frame=pixelFrame(level,{x:c.x-width/2,y:c.y-height/2,width,height});
  return {...frame,roomId:room.id||'',cameraId:option?.id||'',
    lensZoneId:lensZone?.id||'',zoomZoneId:zoom?.id||'',
    focusZoneId:focus?.id||'',panZoneId:pan?.id||'',orthographicSize:ortho};
}
function verify(model) {
  try {
    object(model,'unityCameraModel');
    const cases=model.referenceCases;
    if(!Array.isArray(cases)||!cases.length) return {verified:false,count:0,detail:'No Unity reference cases were exported'};
    for(const tc of cases) {
      const name=tc.name||tc.levelIid||'unnamed';
      let result, thrown;
      try {result=evaluate(model,tc.levelIid,tc.localPoint,tc.state);}
      catch(error){thrown=String(error.message||error);}
      if(typeof tc.error==='string'&&tc.error.trim().length>0) {
        if(!thrown)return {verified:false,count:cases.length,detail:'Unity camera model drift in '+name+': expected an error'};
        continue;
      }
      if(thrown)return {verified:false,count:cases.length,detail:'Unity camera model drift in '+name+': '+thrown};
      const wanted=rect(tc.expected,'reference.expected');
      for(const key of ['x','y','width','height']) {
        if(Math.abs(wanted[key]-result[key])>0.02)
          return {verified:false,count:cases.length,detail:'Unity camera model drift in '+name+' ('+key+': Unity '+wanted[key]+', LDtk '+result[key]+')'};
      }
      if(tc.expectedCenter) {
        const center=vec(tc.expectedCenter,'reference.expectedCenter');
        if(Math.abs(center.x-result.centerX)>0.02 || Math.abs(center.y-result.centerY)>0.02)
          return {verified:false,count:cases.length,detail:'Unity camera model drift in '+name+' (center)'};
      }
    }
    return {verified:true,count:cases.length,detail:'Unity model verified ('+cases.length+' cases)'};
  } catch(error) {
    return {verified:false,count:0,detail:'Unity model verification failed: '+String(error.message||error)};
  }
}
function validReply(data,expected) {
  if(!data || data.schemaVersion!==1 || data.source!=='unity' || data.requestId!==expected.id ||
     data.levelIid!==expected.levelIid || data.ok!==true) return null;
  if(data.snapshotUpdatedAtUtc && data.snapshotUpdatedAtUtc!==expected.snapshotUpdatedAtUtc)return null;
  if(!data.localPoint||Math.abs(data.localPoint.x-expected.point.x)>0.00001||Math.abs(data.localPoint.y-expected.point.y)>0.00001)return null;
  if(data.state && JSON.stringify(normalizedState(data.state))!==JSON.stringify(expected.state))return null;
  const frame=rect(data.frame,'answer.frame'), center=data.center ? vec(data.center,'answer.center') :
    {x:frame.x+frame.width/2,y:frame.y+frame.height/2};
  if(!Number.isFinite(center.x)||!Number.isFinite(center.y))return null;
  return {...frame,centerX:center.x,centerY:center.y,column:null,row:null};
}
function queryPaths(profilePath) {
  if(typeof profilePath!=='string'||!profilePath.endsWith('-camera.json'))throw Error('Expected a camera profile sidecar path');
  const stem=profilePath.slice(0,-'.json'.length);
  return {query:stem+'-query.json',answer:stem+'-answer.json'};
}
function atomicWrite(destination,body) {
  const temporary=destination+'.tmp-'+process.pid+'-'+Math.random().toString(36).slice(2);
  try {fs.writeFileSync(temporary,body,'utf8');fs.renameSync(temporary,destination);}
  finally {try{fs.unlinkSync(temporary);}catch(_){}}
}
class CameraModelClient {
  constructor(){
    this.session=Date.now().toString(36)+'-'+Math.random().toString(36).slice(2);
    this.sequence=0;
    this.model=null;
    this.validation=null;
    this.request=null;
    this.signature='';
    this.pendingSignature='';
    this.lastWrite=0;
    this.lastError='';
  }
  clear(){
    this.model=null;this.validation=null;this.request=null;this.signature='';
    this.pendingSignature='';this.lastWrite=0;this.lastError='';
  }
  update(input){
    const {profile,sidecarPath,levelIid,point}=input;
    const model=profile&&profile.unityCameraModel;
    if(!model||model.modelRevision!==2) return null;
    if(this.model!==model){this.clear();this.model=model;this.validation=verify(model);}
    const st=normalizedState(input.state);
    const diagnostics=Array.isArray(model.diagnostics) ? model.diagnostics.filter(x=>typeof x==='string').slice(0,6) : [];
    const signature=JSON.stringify({sidecarPath,stamp:profile.updatedAtUtc,levelIid,point,state:st});
    if(signature!==this.signature){this.signature=signature;this.request=null;this.pendingSignature=signature;}
    let local=null,localError='';
    if(this.validation.verified) {
      try{local=evaluate(model,levelIid,point,st);}
      catch(e){localError=String(e.message||e);}
    } else if(this.validation.count===0) {
      // No reference cases: local evaluation is available but not authoritative.
      try{local=evaluate(model,levelIid,point,st);}
      catch(e){localError=String(e.message||e);}
    }
    const now=Date.now();
    if(input.requestEnabled!==false && (this.pendingSignature || !this.request) && now-this.lastWrite>=200) {
      this.lastWrite=now;
      try {
        const paths=queryPaths(sidecarPath);
        const req={schemaVersion:1,requestId:'ldtk-'+this.session+'-'+(++this.sequence),
          levelIid,localPoint:{x:point.x,y:point.y},state:st};
        atomicWrite(paths.query,JSON.stringify(req));
        this.request={id:req.requestId,levelIid,point:{x:point.x,y:point.y},
          state:st,snapshotUpdatedAtUtc:profile.updatedAtUtc,started:now,answerPath:paths.answer};
        this.pendingSignature='';
        this.lastError='';
      } catch(e) {this.lastError='Unity query write: '+String(e.message||e);this.pendingSignature='';}
    }
    let replyFrame=null,answerError='';
    if(this.request){
      try {
        const stat=fs.statSync(this.request.answerPath);
        if(stat.size>0 && stat.size<1024*1024){
          const reply=JSON.parse(fs.readFileSync(this.request.answerPath,'utf8'));
          if(reply.requestId===this.request.id && reply.levelIid===levelIid){
            if(reply.ok===false)answerError=String(reply.error||'Unity could not evaluate this camera state');
            else replyFrame=validReply(reply,this.request);
          }
        }
      } catch(error) {if(error.code!=='ENOENT' && !(error instanceof SyntaxError))this.lastError=String(error.message||error);}
    }
    const timedOut=this.request && now-this.request.started>1500;
    if(replyFrame){
      return {frame:replyFrame,source:'Unity (exact settled)',verified:true,
        status:'Unity query response',diagnostics,error:'',referenceCount:this.validation.count};
    }
    const diagnostic=[this.validation.detail,...diagnostics].filter(Boolean);
    if(answerError)diagnostic.unshift(answerError);
    if(this.lastError)diagnostic.unshift(this.lastError);
    if(local){
      return {frame:local,source:this.validation.verified?'Local (verified)':'Local (unverified)',
        verified:this.validation.verified,status:timedOut?'Unity query unavailable':'Waiting for Unity response',
        diagnostics:diagnostic,error:localError,referenceCount:this.validation.count};
    }
    return {frame:null,source:'Dimension-only fallback',verified:false,
      status:timedOut?'Unity query unavailable':'Waiting for Unity response',
      diagnostics:diagnostic,error:localError||answerError,referenceCount:this.validation.count};
  }
}
// Haxe Dynamic invokes methods as detached function references. Return closures
// bound to the client so both update() and clear() retain the correct instance.
function createClient(){
  const client=new CameraModelClient();
  return {update:(input)=>client.update(input),clear:()=>client.clear()};
}
module.exports={evaluate,verify,normalizedState,roundHalfEven,queryPaths,validReply,createClient};
