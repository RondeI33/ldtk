'use strict';
// Plain DOM/jQuery-free controls hosted in an LDtk Dialog. No browser prompt/confirm.
const clone = value => JSON.parse(JSON.stringify(value));
const list = (o, key) => Array.isArray(o && o[key]) ? o[key] : [];

function excludedLayers(template, layers = []) {
  const excluded = new Set(list(template, 'excludedLayerUids').map(Number));
  // Generated output cannot be frozen while editing its source. Exclude that source too.
  for (const layer of layers) if (excluded.has(layer.uid) && layer.type === 'AutoLayer' && layer.source != null)
    excluded.add(layer.source);
  return excluded;
}
function materialize(template, layers = []) {
  const out = clone(template), excluded = excludedLayers(out, layers);
  out.excludedLayerUids = [...excluded];
  out.entities = list(out, 'entities').filter(x => !excluded.has(Number(x.layerDefUid)));
  out.cells = list(out, 'cells').filter(x => !excluded.has(Number(x.layerDefUid)));
  const included = new Set(out.entities.map(x => x.sourceIid));
  for (const entity of out.entities) for (const ref of list(entity, 'refs'))
    ref.values = list(ref, 'values').map(target => included.has(target) ? target : null);
  return out;
}
function removeEntities(template, ids, clearField) {
  const removed = new Set(ids);
  template.entities = list(template, 'entities').filter(e => !removed.has(e.sourceIid));
  for (const e of template.entities) for (const f of list(e, 'refs')) {
    list(f, 'values').forEach((target, index) => {
      if (removed.has(target)) {
        if (clearField) clearField(e, f.fieldDefUid, index, null, 'reset');
        f.values[index] = null;
      }
    });
  }
}

function mount(root, api) {
  let draft = clone(api.template), selected = new Set(), zoom = 1, marquee = null, pan = null;
  let imageCache = new Map(), cellCache = new Map(), history = [], future = [], disposed = false;
  const layers = api.layers || [];
  const doc = root.ownerDocument;
  function el(tag, cls, text, parent) {
    const n = doc.createElement(tag); if (cls) n.className = cls;
    if (text != null) n.textContent = text; if (parent) parent.appendChild(n); return n;
  }
  const style = el('style', '', `
.template-editor-host{font-size:13px;min-width:0}
.template-editor-host *{box-sizing:border-box}
.te-top,.te-tools{display:flex;gap:7px;align-items:center;margin:8px 0;flex-wrap:wrap}
.te-top input{flex:1;min-width:120px}
.te-layout{display:grid;grid-template-columns:170px minmax(180px,1fr) 270px;gap:12px;height:min(520px,60vh)}
.te-layers,.te-inspector{overflow:auto;min-width:0;padding:6px;background:#1c2027;border:1px solid #444b57}
.te-layers label{display:flex;align-items:flex-start;gap:6px;padding:6px 2px;overflow-wrap:anywhere}
.te-center{display:flex;flex-direction:column;min-width:0;min-height:0}
.te-viewport{position:relative;overflow:auto;flex:1;min-height:150px;background-color:#181b21;background-image:linear-gradient(#272d3555 1px,transparent 1px),linear-gradient(90deg,#272d3555 1px,transparent 1px);background-size:16px 16px;border:1px solid #444b57;outline:none;cursor:default}
.te-viewport:focus{border-color:#8ab7ff}
.te-viewport.is-panning{cursor:grabbing}
.te-stage{position:relative;margin:14px;transform-origin:top left;user-select:none}
.te-item{position:absolute;cursor:pointer}
.te-item.is-selected{outline:2px solid #ffcc00;outline-offset:1px}
.te-item img{position:absolute;image-rendering:pixelated;max-width:none;pointer-events:none}
.te-links{position:absolute;left:0;top:0;overflow:visible;pointer-events:none}
.te-links line{pointer-events:stroke;cursor:pointer;stroke:#8ab7ff;stroke-width:3;vector-effect:non-scaling-stroke}
.te-links line.is-selected{stroke:#ffcc00;stroke-width:5}
.te-marquee{position:absolute;border:1px solid #ffcc00;background:#ffcc0020;pointer-events:none}
.te-field{border-bottom:1px solid #444b57;padding:7px 0}
.te-field label{display:block;font-weight:bold;overflow-wrap:anywhere;margin-bottom:4px}
.te-value{display:flex;align-items:center;gap:3px;margin:4px 0}
.te-value input:not([type=checkbox]),.te-value select,.te-value textarea{width:100%;min-width:0;flex:1}
.te-value textarea{min-height:55px;resize:vertical}
.template-editor-host .te-value button{width:28px;min-width:28px;flex:0 0 28px;padding:4px;margin:0;text-transform:none}
.template-editor-host .te-tools button{width:auto;flex:0 0 auto;padding:6px 10px;margin:0;text-transform:none}
.template-editor-host .te-tools{flex-wrap:nowrap}
.template-editor-host .te-layers input[type=checkbox]{width:18px;height:18px;flex:0 0 18px;margin:0}
.template-editor-host .te-value input,.template-editor-host .te-value select{padding:5px;min-height:28px}
.template-editor-host .te-value textarea{height:65px}
.template-editor-host .te-inspector button{font-size:12px;text-transform:none}
.te-muted{opacity:.65;font-size:11px;line-height:1.4}
.te-error{color:#ffa691;white-space:pre-wrap;min-height:18px;margin:6px 0}
.te-summary{font-size:12px;line-height:1.4;margin-top:6px}
.te-inspector h3{margin:2px 0 8px;font-size:14px;overflow-wrap:anywhere}
@media(max-width:850px){.te-layout{grid-template-columns:120px minmax(120px,1fr) 220px}}
`, root);
  const top = el('div','te-top',null,root);
  el('label','','Name',top);
  const name = el('input','template-name',null,top); name.value = draft.name || ''; name.type='text'; name.setAttribute('aria-label','Template name');
  const layout = el('div','te-layout',null,root);
  const layerPanel = el('div','te-layers',null,layout);
  const center = el('div','te-center',null,layout);
  const inspector = el('div','te-inspector',null,layout);
  const tools=el('div','te-tools',null,center);
  function button(parent,text,fn,cls) { const b=el('button',cls,text,parent); b.type='button';b.addEventListener('click',fn);return b; }
  button(tools,'Delete',removeSelected,'te-delete');
  const undo=button(tools,'Undo',()=>restore(false),'te-undo');
  const redo=button(tools,'Redo',()=>restore(true),'te-redo');
  button(tools,'Fit',fit,'te-fit');
  button(tools,'−',()=>scaleBy(.8)); button(tools,'+',()=>scaleBy(1.25));
  const viewport=el('div','te-viewport',null,center);viewport.tabIndex=0;viewport.setAttribute('aria-label','Template contents. Select objects or links and press Delete.');
  const stage=el('div','te-stage',null,viewport);
  const summary=el('div','te-summary',null,center);
  el('div','te-muted','Click to select. Shift-click adds to selection. Drag empty space to select an area. Middle-mouse drag pans. Mouse wheel zooms around the cursor. Delete removes only draft contents.',center);
  const error=el('div','te-error',null,root);
  function showError(message){error.textContent=String(message||'');}
  function record(){draft.name=name.value;history.push(clone(draft));if(history.length>50)history.shift();future=[];}
  function changed(){renderLayers();renderPreview();renderInspector();undo.disabled=!history.length;redo.disabled=!future.length;}
  function restore(isRedo){const from=isRedo?future:history,to=isRedo?history:future;if(!from.length)return;to.push(clone(draft));draft=from.pop();name.value=draft.name||'';selected.clear();showError('');changed();}
  function perform(fn){try{record();fn();showError('');changed();}catch(e){draft=history.pop()||draft;showError(e.message||e);changed();}}
  function active(){return materialize(draft,layers);}
  function currentEntity(id){return list(draft,'entities').find(e=>e.sourceIid===id);}
  function choose(id,extend){if(!extend)selected.clear();if(extend&&selected.has(id))selected.delete(id);else selected.add(id);renderPreview();renderInspector();viewport.focus({preventScroll:true});}
  function removeSelected(){if(!selected.size)return;perform(()=>{
    const ids=[...selected].filter(x=>x.startsWith('e:')).map(x=>x.slice(2));
    removeEntities(draft,ids,api.changeField);
    for(const key of selected)if(key.startsWith('r:')){const [id,uid,idx]=JSON.parse(key.slice(2));const e=currentEntity(id);if(e)api.changeField(e,uid,idx,null,'reset');}
    draft.cells=list(draft,'cells').filter((c,i)=>!selected.has('c:'+i));selected.clear();
  });}
  function renderLayers(){
    layerPanel.replaceChildren();el('strong','','Include layers',layerPanel);
    const excluded=excludedLayers(draft,layers);
    for(const layer of layers){
      const label=el('label','',null,layerPanel),check=el('input','te-layer',null,label);check.type='checkbox';check.checked=!excluded.has(layer.uid);check.dataset.uid=layer.uid;
      el('span','',layer.name,label);
      check.addEventListener('change',()=>perform(()=>{
        let next=new Set(list(draft,'excludedLayerUids').map(Number));
        if(check.checked){next.delete(layer.uid);if(layer.source!=null)next.delete(layer.source);for(const l of layers)if(l.source===layer.uid)next.delete(l.uid);}
        else{next.add(layer.uid);if(layer.type==='AutoLayer'&&layer.source!=null)next.add(layer.source);}
        draft.excludedLayerUids=[...next].sort((a,b)=>a-b);selected.clear();
      }));
    }
    el('p','te-muted','Unchecked layers are not placed, including entity tile stamps on those layers. Generated auto-layers follow their source layer.',layerPanel);
  }
  function entityVisual(e){const key=JSON.stringify(e.json);if(!imageCache.has(key))imageCache.set(key,api.entityImage(e));return imageCache.get(key);}
  function entityBox(e){let v;try{v=entityVisual(e);}catch(_){v={entityWidth:e.json.width||16,entityHeight:e.json.height||16,pivotX:(e.json.__pivot||[0,0])[0],pivotY:(e.json.__pivot||[0,0])[1]};}
    return {x:e.relX-v.entityWidth*v.pivotX,y:e.relY-v.entityHeight*v.pivotY,w:v.entityWidth,h:v.entityHeight,visual:v};}
  function renderPreview(){
    stage.replaceChildren();const t=active(),included=new Set(t.entities.map(e=>e.sourceIid));
    const w=Math.max(1,Number(draft.width)||1),h=Math.max(1,Number(draft.height)||1);
    Object.assign(stage.style,{width:w+'px',height:h+'px',transform:`scale(${zoom})`});
    const allLayers=[...layers].sort((a,b)=>b.order-a.order);
    for(const layer of allLayers){
      for(let i=0;i<list(draft,'cells').length;i++){
        const c=draft.cells[i];if(c.layerDefUid!==layer.uid||excludedLayers(draft,layers).has(layer.uid))continue;
        const g=c.gridSize||layer.grid||16,n=el('div','te-item te-cell',null,stage);n.dataset.key='c:'+i;
        Object.assign(n.style,{left:c.relX+'px',top:c.relY+'px',width:g+'px',height:g+'px'});
        if(selected.has('c:'+i))n.classList.add('is-selected');
        try{const k=JSON.stringify([c.layerDefUid,c.kind,c.value,c.tiles]);if(!cellCache.has(k))cellCache.set(k,api.cellImage(c));const v=cellCache.get(k);
          if(v&&v.color)n.style.background=v.color;
          for(const tile of v&&v.tiles||[]){const img=el('img','',null,n);img.src=tile.url;Object.assign(img.style,{width:g+'px',height:g+'px',transform:`scale(${tile.flips&1?-1:1},${tile.flips&2?-1:1})`});}
        }catch(_){n.style.background='#6b7483';}
        n.addEventListener('click',ev=>{ev.stopPropagation();choose('c:'+i,ev.shiftKey);});
      }
      for(const e of t.entities)if(e.layerDefUid===layer.uid){
        const b=entityBox(e),n=el('div','te-item te-entity',null,stage);n.dataset.key='e:'+e.sourceIid;n.title=e.json.__identifier||'Entity';
        Object.assign(n.style,{left:b.x+'px',top:b.y+'px',width:b.w+'px',height:b.h+'px'});
        if(b.visual.url){const img=el('img','',null,n);img.src=b.visual.url;Object.assign(img.style,{left:(b.visual.left+b.w*b.visual.pivotX)+'px',top:(b.visual.top+b.h*b.visual.pivotY)+'px',width:b.visual.width+'px',height:b.visual.height+'px'});}
        else n.style.background=e.json.__smartColor||'#7d91ac';
        if(selected.has('e:'+e.sourceIid))n.classList.add('is-selected');
        n.addEventListener('click',ev=>{ev.stopPropagation();choose('e:'+e.sourceIid,ev.shiftKey);});
      }
    }
    const svg=doc.createElementNS('http://www.w3.org/2000/svg','svg');svg.classList.add('te-links');svg.setAttribute('width',w);svg.setAttribute('height',h);stage.appendChild(svg);
    let links=0;
    for(const e of t.entities)for(const f of list(e,'refs'))list(f,'values').forEach((target,idx)=>{
      const b=t.entities.find(v=>v.sourceIid===target);if(!b)return;links++;
      const key='r:'+JSON.stringify([e.sourceIid,f.fieldDefUid,idx]);
      const line=doc.createElementNS(svg.namespaceURI,'line');line.dataset.key=key;
      line.setAttribute('x1',e.relX);line.setAttribute('y1',e.relY);line.setAttribute('x2',b.relX);line.setAttribute('y2',b.relY);
      if(selected.has(key))line.classList.add('is-selected');svg.appendChild(line);
      line.addEventListener('click',ev=>{ev.stopPropagation();choose(key,ev.shiftKey);});
    });
    summary.textContent=`${t.entities.length} entities · ${t.cells.length} cells · ${links} connections · ${Math.round(zoom*100)}%`;
  }
  function renderInspector(){
    inspector.replaceChildren();
    if(selected.size!==1){el('h3','',selected.size?`${selected.size} selected`:'Properties',inspector);el('p','te-muted','Select an entity to edit its fields, or a connection to disconnect it.',inspector);return;}
    const key=[...selected][0];
    if(key.startsWith('r:')){
      const[id,uid,idx]=JSON.parse(key.slice(2)),e=currentEntity(id);el('h3','','Connection',inspector);
      if(e){const f=api.inspect(e).find(f=>f.uid===uid);el('p','',`${e.json.__identifier} → ${f?f.name:uid} [${idx}]`,inspector);}
      button(inspector,'Remove connection',removeSelected,'te-remove-connection');return;
    }
    if(key.startsWith('c:')){el('h3','','Grid cell',inspector);button(inspector,'Remove cell',removeSelected);return;}
    const e=currentEntity(key.slice(2));if(!e)return;
    el('h3','',e.json.__identifier||'Entity',inspector);button(inspector,'Remove entity',removeSelected,'te-remove-entity');
    let fields;try{fields=api.inspect(e);}catch(err){showError(err.message||err);return;}
    for(const field of fields){
      const group=el('div','te-field',null,inspector);group.dataset.uid=field.uid;el('label','',field.name,group);
      for(let i=0;i<field.values.length;i++){
        const row=el('div','te-value',null,group);row.dataset.index=i;let input;const value=field.values[i];
        const commit=v=>perform(()=>api.changeField(e,field.uid,i,v,'set'));
        if(field.type==='F_EntityRef'||field.type==='F_Enum'){
          input=el('select','te-input',null,row);const opts=field.type==='F_EntityRef'?active().entities.map(x=>[x.sourceIid,`${x.json.__identifier} (${x.relX}, ${x.relY})`]):field.options.map(x=>[x,x]);
          const none=el('option','',field.canBeNull?'None':'None (required)',input);none.value='';
          for(const [id,label]of opts){const op=el('option','',label,input);op.value=id;}
          if(value!=null&&!opts.some(x=>x[0]===value)){const op=el('option','','External / excluded target',input);op.value=value;}
          input.value=value==null?'':value;input.addEventListener('change',()=>commit(input.value||null));
        }else if(field.type==='F_Bool'){
          input=el('input','te-input',null,row);input.type='checkbox';input.checked=!!value;input.addEventListener('change',()=>commit(input.checked?'true':'false'));
        }else if(field.type==='F_Point'){
          const x=el('input','te-point-x',null,row),y=el('input','te-point-y',null,row);x.type=y.type='number';x.value=value?value.x:'';y.value=value?value.y:'';x.placeholder='X px';y.placeholder='Y px';
          const update=()=>{if(x.value!==''&&y.value!=='')commit({x:Number(x.value),y:Number(y.value)});};x.addEventListener('change',update);y.addEventListener('change',update);
        }else if(field.type==='F_Tile'){
          el('span','te-muted',value?'Tile configured':'No tile / default',row);
        }else{
          input=el(field.type==='F_Text'?'textarea':'input','te-input',null,row);
          if(input.tagName==='INPUT')input.type=field.type==='F_Color'?'color':field.type==='F_Int'||field.type==='F_Float'?'number':'text';
          if(field.type==='F_Float')input.step='any';
          if(field.min!=null)input.min=field.min;if(field.max!=null)input.max=field.max;
          input.value=value==null?'':String(value);input.addEventListener('change',()=>commit(input.value));
        }
        const reset=button(row,'↺',()=>perform(()=>api.changeField(e,field.uid,i,null,'reset')),'te-reset');reset.title='Reset value to default / clear connection';reset.setAttribute('aria-label',`Reset ${field.name}`);
        if(field.isArray){const rem=button(row,'×',()=>perform(()=>api.changeField(e,field.uid,i,null,'remove')),'te-remove-value');rem.title='Remove array item';rem.disabled=field.minLength!=null&&field.values.length<=field.minLength;}
      }
      if(field.isArray){const add=button(group,'+ Value',()=>perform(()=>api.changeField(e,field.uid,field.values.length,null,'add')),'te-add-value');add.disabled=field.maxLength!=null&&field.values.length>=field.maxLength;}
      if(!field.canBeNull&&(field.type==='F_EntityRef'||field.type==='F_Point')&&field.values.some(v=>v==null))el('div','te-muted','Required value is empty. Set it before placement.',group);
    }
  }
  function clampZoom(value){return Math.max(.02,Math.min(8,value));}
  function setZoom(next, clientX=null, clientY=null){
    const old=zoom,newZoom=clampZoom(next);
    if(Math.abs(newZoom-old)<1e-6)return;
    const rect=viewport.getBoundingClientRect();
    const sx=clientX==null?rect.width*.5:clientX-rect.left;
    const sy=clientY==null?rect.height*.5:clientY-rect.top;
    const stageLeft=stage.offsetLeft,stageTop=stage.offsetTop;
    const worldX=(viewport.scrollLeft+sx-stageLeft)/old;
    const worldY=(viewport.scrollTop+sy-stageTop)/old;
    zoom=newZoom;renderPreview();
    viewport.scrollLeft=stage.offsetLeft+worldX*zoom-sx;
    viewport.scrollTop=stage.offsetTop+worldY*zoom-sy;
  }
  function fit(){
    zoom=Math.min(3,Math.max(.02,(viewport.clientWidth-30)/Math.max(1,draft.width)));
    zoom=Math.min(zoom,(viewport.clientHeight-30)/Math.max(1,draft.height));
    renderPreview();
    viewport.scrollLeft=Math.max(0,(stage.scrollWidth*zoom-viewport.clientWidth)*.5);
    viewport.scrollTop=Math.max(0,(stage.scrollHeight*zoom-viewport.clientHeight)*.5);
  }
  function scaleBy(f){setZoom(zoom*f);}
  viewport.addEventListener('keydown',ev=>{
    if(ev.key==='Delete'||ev.key==='Backspace'){ev.preventDefault();ev.stopPropagation();removeSelected();}
    if((ev.ctrlKey||ev.metaKey)&&ev.key.toLowerCase()==='z'){ev.preventDefault();ev.stopPropagation();restore(ev.shiftKey);}
  });
  viewport.addEventListener('wheel',ev=>{
    ev.preventDefault();
    ev.stopPropagation();
    const factor=Math.exp(-ev.deltaY*0.0015);
    setZoom(zoom*factor,ev.clientX,ev.clientY);
  },{passive:false});
  viewport.addEventListener('mousedown',ev=>{
    if(ev.button!==1)return;
    pan={x:ev.clientX,y:ev.clientY,left:viewport.scrollLeft,top:viewport.scrollTop};
    viewport.classList.add('is-panning');
    viewport.focus({preventScroll:true});
    ev.preventDefault();
    ev.stopPropagation();
  });
  function point(ev){const b=stage.getBoundingClientRect();return{x:(ev.clientX-b.left)/zoom,y:(ev.clientY-b.top)/zoom};}
  stage.addEventListener('mousedown',ev=>{if(ev.button!==0||ev.target.closest('.te-item')||ev.target.tagName==='line')return;
    const p=point(ev);marquee={start:p,extend:ev.shiftKey};if(!ev.shiftKey)selected.clear();viewport.focus({preventScroll:true});ev.preventDefault();});
  function move(ev){
    if(pan){
      viewport.scrollLeft=pan.left-(ev.clientX-pan.x);
      viewport.scrollTop=pan.top-(ev.clientY-pan.y);
      ev.preventDefault();
      return;
    }
    if(!marquee)return;const p=point(ev),a=marquee.start;let box=stage.querySelector('.te-marquee');if(!box)box=el('div','te-marquee',null,stage);Object.assign(box.style,{left:Math.min(a.x,p.x)+'px',top:Math.min(a.y,p.y)+'px',width:Math.abs(a.x-p.x)+'px',height:Math.abs(a.y-p.y)+'px'});
  }
  function up(ev){
    if(pan){
      pan=null;viewport.classList.remove('is-panning');
      if(ev)ev.preventDefault();
      return;
    }
    if(!marquee)return;const p=point(ev),a=marquee.start;marquee=null;const l=Math.min(a.x,p.x),r=Math.max(a.x,p.x),t=Math.min(a.y,p.y),b=Math.max(a.y,p.y);
    const intersect=v=>v.x<=r&&v.x+v.w>=l&&v.y<=b&&v.y+v.h>=t;
    for(const e of active().entities)if(intersect(entityBox(e)))selected.add('e:'+e.sourceIid);
    list(draft,'cells').forEach((c,i)=>{const g=c.gridSize||16;if(!excludedLayers(draft,layers).has(c.layerDefUid)&&intersect({x:c.relX,y:c.relY,w:g,h:g}))selected.add('c:'+i);});renderPreview();renderInspector();}
  doc.addEventListener('mousemove',move);doc.addEventListener('mouseup',up);
  changed();const timer=setTimeout(()=>{if(!disposed){fit();name.focus();name.select();}},80);
  return {
    getDraft(){draft.name=name.value.trim();if(!draft.name)throw Error('Enter a template name.');const t=active();if(!t.entities.length&&!t.cells.length)throw Error('Include at least one entity or cell.');return clone(draft);},
    showError,
    dispose(){disposed=true;pan=null;clearTimeout(timer);doc.removeEventListener('mousemove',move);doc.removeEventListener('mouseup',up);imageCache.clear();cellCache.clear();root.replaceChildren();}
  };
}
module.exports={mount,materialize,excludedLayers,removeEntities};
