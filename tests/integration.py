"""Real Ghidra integration. Requires GHIDRA_INSTALL_DIR and a suitable JAVA_HOME."""
import json, os, queue, subprocess, sys, tempfile, threading, uuid
from pathlib import Path
root=Path(__file__).resolve().parents[1]

def main():
    with tempfile.TemporaryDirectory(prefix='dissect-integration-') as temp:
        work=Path(temp)
        binary=work/'thermostat'
        subprocess.run(['cc','-O0','-g','-fno-inline',str(root/'examples/thermostat.c'),'-o',str(binary)],check=True)
        log=(work/'engine.log').open('w')
        process=subprocess.Popen([sys.executable,str(root/'Resources/Engine/engine.py'),'--ghidra',os.environ['GHIDRA_INSTALL_DIR']],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log,text=True,bufsize=1)
        messages=queue.Queue()
        def receive():
            for line in process.stdout:
                if line.startswith('@DISSECT@'): messages.put(json.loads(line[len('@DISSECT@'):]))
        threading.Thread(target=receive,daemon=True).start()
        checks=[]
        def request(method,**params):
            cancel_on_analysis=params.pop('_cancel_on_analysis',False)
            expect_error=params.pop('_expect_error',False)
            rid=str(uuid.uuid4()); process.stdin.write(json.dumps(dict(id=rid,method=method,params=params))+'\n'); process.stdin.flush()
            while True:
                response=messages.get(timeout=180)
                if response.get('event'):
                    if cancel_on_analysis and response.get('message','').startswith('Analyzing'):
                        process.stdin.write(json.dumps(dict(id=str(uuid.uuid4()),method='cancel',params={'requestID':rid}))+'\n'); process.stdin.flush()
                        cancel_on_analysis=False
                    continue
                assert response['id']==rid, response
                if expect_error:
                    assert 'error' in response, response
                    return response
                if 'error' in response: raise AssertionError(response)
                return response['result']
        try:
            assert request('doctor')['ghidra']=='12.2'; checks.append('real engine startup')
            assert request('languages')['languages']; checks.append('installed processor and compiler discovery')
            status=request('create',source=str(binary),workspace=str(work/'sample.dissect'))
            assert status['analysis']=='complete' and status['functions']>0; checks.append('native executable import and analysis')
            functions=request('index',kind='functions',query='alarm_for_temperature')['items']; assert functions
            address=functions[0]['address']
            detail=request('function',address=address); assert 'alarm_for_temperature' in detail['code'] and detail['assembly']; checks.append('real decompilation and assembly')
            assert request('references',address=address)['items']; checks.append('caller references')
            strings=request('index',kind='strings',query='Dissect workshop')['items']; assert strings; checks.append('defined strings search')
            assert request('references',address=strings[0]['address'])['items']; checks.append('string cross references')
            assert '  ' in request('bytes',address=address)['text']; checks.append('memory bytes')
            assert request('index',kind='functions',limit=1)['hasMore']; checks.append('pagination')
            request('edit',address=address,operation='rename',value='temperature_alarm')
            assert request('function',address=address)['name']=='temperature_alarm'; checks.append('rename refresh')
            request('undo'); assert request('function',address=address)['name']=='alarm_for_temperature'
            request('redo'); assert request('function',address=address)['name']=='temperature_alarm'; checks.append('undo and redo')
            request('edit',address=address,operation='note',value='Hysteresis band 28–32 C. 🛠')
            request('edit',address=address,operation='signature',value='int temperature_alarm(int temperature)')
            assert 'temperature' in request('function',address=address)['signature']; checks.append('function signature/type edit')
            request('close'); request('open',workspace=str(work/'sample.dissect'))
            saved=request('function',address=address)
            assert saved['name']=='temperature_alarm' and saved['note']=='Hysteresis band 28–32 C. 🛠'; checks.append('save close reopen with edits and unicode notes')
            bad=request('edit',address=address,operation='signature',value='this is not a prototype',_expect_error=True)
            assert request('function',address=address)['name']=='temperature_alarm'; checks.append('malformed signature rollback')
            cancelled=request('analyze',_cancel_on_analysis=True,_expect_error=True)
            assert cancelled.get('cancelled') and request('status')['analysis']=='interrupted'
            assert request('function',address=address)['note']==saved['note']
            request('analyze'); assert request('status')['analysis']=='complete'; checks.append('cancel checkpoint and successful reanalysis')
            raw=work/'firmware.bin';raw.write_bytes(bytes.fromhex('b82a000000c3'))
            raw_status=request('create',source=str(raw),workspace=str(work/'raw.dissect'),language='x86:LE:64:default',compiler='gcc',imageBase='08000000')
            assert int(raw_status['imageBase'],16)==0x08000000
            assert 'b8 2a 00 00 00 c3' in request('bytes',address=raw_status['imageBase'])['text']; checks.append('raw firmware explicit language compiler and image base')
            request('define',address=raw_status['imageBase'])
            raw_code=request('function',address=raw_status['imageBase'])['code']
            assert '0x2a' in raw_code or '42' in raw_code; checks.append('define and decompile function in raw firmware')
            request('close'); request('open',workspace=str(work/'sample.dissect'))
            assert request('function',address=address)['note']==saved['note']; checks.append('switch between workspaces without losing edits')
            arm=request('create',source=str(root/'examples/firmware-arm64-macho.o'),workspace=str(work/'arm.dissect'))
            assert 'AARCH64' in arm['language']
            arm_rows=request('index',kind='functions',query='alarm_for_temperature')['items']; assert arm_rows
            arm_detail=request('function',address=arm_rows[0]['address'])
            assert arm_detail['code'] and not arm_detail['warning']; checks.append('ARM64 Mach-O import and decompilation')
            print(json.dumps({'passed':len(checks),'checks':checks},indent=2),flush=True)
        except Exception:
            process.terminate(); process.wait(timeout=15); log.flush()
            print((work/'engine.log').read_text()[-15000:],file=sys.stderr)
            raise
        finally:
            if process.poll() is None:
                process.stdin.close()
                process.wait(timeout=30)
            log.close()
if __name__=='__main__':main()
