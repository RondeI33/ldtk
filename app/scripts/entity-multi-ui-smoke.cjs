'use strict';
// Verify the rendered inspector is actually reachable, not merely present in
// the DOM. Keep native editor methods and every data assertion unchanged.
const {app}=require('electron');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
app.on('browser-window-created',(_,win)=>{
 const capture=win.webContents.capturePage.bind(win.webContents);
 win.webContents.capturePage=async(...args)=>{
  const layout=await win.webContents.executeJavaScript(`(()=>{
   const p=document.querySelector('.multiEntityInstanceEditor');if(!p)return null;
   const r=p.getBoundingClientRect(),field=p.querySelector('input.multiValue');
   const ancestors=[];for(let n=p;n;n=n.parentElement){const s=getComputedStyle(n),b=n.getBoundingClientRect();ancestors.push({tag:n.tagName,id:n.id,cls:n.className,left:b.left,top:b.top,width:b.width,height:b.height,opacity:s.opacity,display:s.display,visibility:s.visibility,z:s.zIndex,overflow:s.overflow,bg:s.backgroundColor});}
   const f=field.getBoundingClientRect(),x=f.left+f.width/2,y=f.top+f.height/2;
   const hit=document.elementFromPoint(x,y);
   return {rect:{x:r.x,y:r.y,w:r.width,h:r.height},ancestors,field:{id:field.id,x,y},hit:hit?{tag:hit.tagName,id:hit.id,cls:hit.className}:null,reachable:hit===field,html:p.outerHTML};
  })()`,true);
  if(layout){
   const out=path.join(__dirname,'../test-results/entity-multi');fs.mkdirSync(out,{recursive:true});
   fs.writeFileSync(path.join(out,'layout.json'),JSON.stringify(layout,null,2));
   console.log('MULTI inspector hit test',JSON.stringify({...layout,html:undefined}));
   assert(layout.rect.w>100&&layout.rect.h>50,'Inspector has no visible bounds');
   assert(layout.reachable,'Inspector field is covered or outside the visible viewport');
   // Native pointer input must focus the actual field without changing selection.
   win.webContents.sendInputEvent({type:'mouseMove',x:Math.round(layout.field.x),y:Math.round(layout.field.y)});
   win.webContents.sendInputEvent({type:'mouseDown',x:Math.round(layout.field.x),y:Math.round(layout.field.y),button:'left',clickCount:1});
   win.webContents.sendInputEvent({type:'mouseUp',x:Math.round(layout.field.x),y:Math.round(layout.field.y),button:'left',clickCount:1});
   await new Promise(r=>setTimeout(r,150));
   const focused=await win.webContents.executeJavaScript('document.activeElement.id',true);
   assert.equal(focused,layout.field.id,'Mouse click did not focus multi-edit input');
  }
  await win.webContents.executeJavaScript('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))',true);
  await new Promise(r=>setTimeout(r,200));
  return capture(...args);
 };
});
require('./entity-multi-ui-cases.cjs');
