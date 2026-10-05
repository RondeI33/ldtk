from pathlib import Path
import subprocess
p=Path('app/scripts/selection-ui-smoke.cjs')
s=p.read_text()
old='  const ev=code=>win.webContents.executeJavaScript(code,true);'
assert s.count(old)==1
new='''  const ev=async code=>{
    const result=await win.webContents.executeJavaScript(`(()=>{try{return {ok:true,value:eval(${JSON.stringify(code)})};}catch(e){return {ok:false,error:String(e.stack||e)};}})()`,true);
    if(!result.ok)throw Error(result.error+'\\nExpression: '+code);
    return result.value;
  };'''
p.write_text(s.replace(old,new))
subprocess.run(['git','add',str(p)],check=True)
