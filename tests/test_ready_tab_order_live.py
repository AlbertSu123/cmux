#!/usr/bin/env python3
"""Live notification ordering regression; run inside an isolated tagged cmux terminal.

Requires CMUX_TAG and a single disposable workspace with one terminal, or the
five-tab fixture left by a prior run. Uses the default cached pane.surfaces read
intentionally: explicit workspace selectors bypass the stale-cache regression.
"""
from pathlib import Path
import json,os,subprocess,time,traceback
def main():
    CLI=str(Path(__file__).resolve().parents[1] / 'scripts/cmux-debug-cli.sh')
    assert os.environ.get('CMUX_TAG'), 'Run inside a tagged cmux test terminal with CMUX_TAG set'
    log=open('/tmp/cmux-live-ready-results.jsonl','w',buffering=1)
    def call(*args):
     p=subprocess.run([CLI,'--json',*args],env=os.environ,capture_output=True,text=True,timeout=20)
     if p.returncode:raise RuntimeError(p.stderr+p.stdout)
     try:result=json.loads(p.stdout)
     except json.JSONDecodeError:result={'text':p.stdout.strip()}
     log.write(json.dumps({'command':args,'result':result})+'\n');return result
    def tabs():return call('list-pane-surfaces')['surfaces']
    def wait_order(expected):
     deadline=time.monotonic()+10
     while True:
      current=tabs()
      if [x['ref'] for x in current]==expected or time.monotonic()>deadline:return current
      time.sleep(.1)
    def check(condition,message):
     log.write(json.dumps({'check':message,'passed':bool(condition)})+'\n')
     assert condition,message
    try:
     initial=tabs()
     if len(initial)==1:
      first=initial[0]['ref']
      second=call('new-surface','--focus','false')['surface_ref']
      for ref,name in [(first,'Typing — pinned'),(second,'Reference — pinned')]:
       call('tab-action','--tab',ref,'--action','rename','--title',name)
       call('tab-action','--tab',ref,'--action','pin')
      for name in ['Working A','Working B','Working C']:
       ref=call('new-surface','--focus','false')['surface_ref']
       call('tab-action','--tab',ref,'--action','rename','--title',name)
     else:
      check(len(initial)==5 and {x['title'] for x in initial} ==
            {'Typing — pinned','Reference — pinned','Working A','Working B','Working C'},
            'Refuse to modify a workspace that is not the disposable test fixture')
      first=next(x['ref'] for x in initial if x['title']=='Typing — pinned')
      second=next(x['ref'] for x in initial if x['title']=='Reference — pinned')
     call('focus-panel','--panel',first)
     before=tabs();before_refs=[x['ref'] for x in before]
     selected=next(x['ref'] for x in before if x['selected'])
     pins=before_refs[:2]
     check(pins==[first,second],'Two pinned tabs occupy leftmost positions')
     target=before_refs[-1]
     call('notify','--surface',target,'--title','Ready A','--body','Live ordering test')
     expected=pins+[target]+[x for x in before_refs[2:] if x!=target]
     after=wait_order(expected)
     check([x['ref'] for x in after]==expected,'Completed tab moves immediately after both pins')
     check(next(x['ref'] for x in after if x['selected'])==selected,'Completion does not change selected tab')
     target2=expected[-1]
     call('notify','--surface',target2,'--title','Ready B','--body','Second live completion')
     expected2=pins+[target2]+[x for x in expected[2:] if x!=target2]
     after2=wait_order(expected2)
     check([x['ref'] for x in after2]==expected2,'Newest completion moves ahead of previous completion')
     check(next(x['ref'] for x in after2 if x['selected'])==selected,'Repeated completions preserve typing focus')
     call('notify','--surface',second,'--title','Pinned ready','--body','Pinned tab must stay in place')
     time.sleep(2)
     check([x['ref'] for x in tabs()]==expected2,'Pinned completion leaves tab order unchanged')
     log.write(json.dumps({'status':'PASS'})+'\n')
     print('LIVE READY TAB CHECKS PASSED')
    except Exception:
     log.write(json.dumps({'error':traceback.format_exc()})+'\n');raise


if __name__ == "__main__":
    main()
