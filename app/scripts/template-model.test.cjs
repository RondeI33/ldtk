const {test}=require('node:test');
const assert=require('node:assert/strict');
const {materialize,removeEntities}=require('../assets/js/selection-template-editor.js');
const make=()=>({entities:[{sourceIid:'a',layerDefUid:1,refs:[{fieldDefUid:10,values:['b','a',null]}]},{sourceIid:'b',layerDefUid:2,refs:[{fieldDefUid:10,values:['a']}]}],cells:[{layerDefUid:3,value:1}],excludedLayerUids:[]});
test('layer exclusion does not mutate the stored draft',()=>{const t=make();t.excludedLayerUids=[3];const snapshot=JSON.stringify(t);assert.equal(materialize(t).cells.length,0);assert.equal(JSON.stringify(t),snapshot);});
test('excluding entity layers disconnects only outgoing targets that no longer exist',()=>{const t=make();t.excludedLayerUids=[2];const out=materialize(t);assert.equal(out.entities.length,1);assert.deepEqual(out.entities[0].refs[0].values,[null,'a',null]);});
test('removing an entity notifies the typed field serializer for every incoming reference',()=>{const t=make(),calls=[];removeEntities(t,['b'],(...args)=>calls.push(args));assert.equal(t.entities.length,1);assert.deepEqual(t.entities[0].refs[0].values,[null,'a',null]);assert.equal(calls.length,1);assert.equal(calls[0][4],'reset');});
test('explicitly excluded generated output excludes its source as well',()=>{const t=make();t.excludedLayerUids=[4];const out=materialize(t,[{uid:4,type:'AutoLayer',source:3}]);assert.equal(out.cells.length,0);assert(out.excludedLayerUids.includes(3));});
test('internal cycles and self references are preserved',()=>{const out=materialize(make());assert.deepEqual(out.entities[0].refs[0].values,['b','a',null]);assert.deepEqual(out.entities[1].refs[0].values,['a']);});
