"""Capture fresh MAX30102 -> ARM -> NTT PL and compare all outputs on host.
Run only with the realtime viewer stopped. Requires existing i2c.bit build.
"""
from pathlib import Path
import csv, hashlib, importlib.util, json, subprocess, time, sys, fcntl, os

here=Path(__file__).resolve().parent
(here/'output').mkdir(exist_ok=True)
lock=(here/'output/demo.lock').open('w')
try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError:raise SystemExit('Another demo is running; wait for it to finish')
gated='--quality-gate' in sys.argv
out=here/'output'/(time.strftime('sensor-ntt-%Y%m%d-%H%M%S')+f'-{time.time_ns()%1000000:06d}')
out.mkdir(exist_ok=False)
print('EVIDENCE='+str(out),flush=True)
tool=Path(os.environ.get('VITIS_HOME','/home/quan/tools/Xilinx/2025.2.1/Vitis'))
gcc=tool/'gnu/aarch64/lin/aarch64-none/bin/aarch64-none-elf-gcc'
for required in (gcc,tool/'bin/xsct',here/'output/i2c.bit',here/'project/kv260_axi_test.gen/sources_1/bd/ntt_system/ip/ntt_system_ps_0/psu_init.tcl'):
    if not required.is_file():raise SystemExit('Missing prerequisite: '+str(required)+'; see README.md')
os.environ['VITIS_HOME']=str(tool)
elf=out/'sensor_ntt.elf'
defines=['-DQUALITY_GATE','-DSAMPLE_LIMIT=1024','-DRAW_CAPACITY=1024'] if gated else []
subprocess.run([str(gcc),*defines,'-O2','-Wall','-Wextra','-ffreestanding','-fno-builtin','-nostdlib','-mgeneral-regs-only','-T',str(here/'link.ld'),str(here/'entry.S'),str(here/'sensor_ntt.c'),'-o',str(elf)],check=True)
with (out/'hardware.log').open('w') as log:
    p=subprocess.Popen([str(tool/'bin/xsct'),'-nodisp',str(here/'run_sensor.tcl'),str(elf),str(out)],cwd=here,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    for line in p.stdout:
        print(line,end='',flush=True);log.write(line);log.flush()
    if p.wait()!=0: raise SystemExit('Hardware capture failed; see '+str(out/'hardware.log'))
quality=json.loads((out/'quality.json').read_text()) if gated else None
if quality is not None and not quality['accepted']:
    report={'status':'INSUFFICIENT_SIGNAL','ntt_status':'NOT_RUN','intt_status':'NOT_RUN','quality':quality,'completed_blocks':0}
    (out/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False));raise SystemExit(0)
with (out/'sensor_raw.csv').open() as f: raw=list(csv.DictReader(f))
with (out/'ntt_actual.csv').open() as f: actual=list(csv.DictReader(f))
assert len(raw)==256 and len(actual)==1024
packed=[]
for i,row in enumerate(raw):
    assert int(row['index'])==i
    for channel in ('red','ir'):
        value=int(row[channel]);assert 0<=value<2**18
        low,high=value&511,value>>9
        assert low|(high<<9)==value
        packed.extend([low,high])
spec=importlib.util.spec_from_file_location('golden',here.parent/'vector/ntt_gen.py')
golden=importlib.util.module_from_spec(spec);spec.loader.exec_module(golden)
zetas,invzetas=golden.parse_twiddles(here.parent/'rtl/utils/ntt_funcs.vh')
expected=sum([golden.ntt_ref(packed[b*256:(b+1)*256],zetas) for b in range(4)],[])
mismatches=[]
with (out/'comparison.csv').open('w',newline='') as f:
    writer=csv.writer(f);writer.writerow(['block','index','packed','arm_input','expected','fpga_actual','pass'])
    for i,row in enumerate(actual):
        assert int(row['block'])==i//256 and int(row['index'])==i%256
        ok=int(row['input'])==packed[i] and int(row['actual'])==expected[i]
        writer.writerow([i//256,i%256,packed[i],row['input'],expected[i],row['actual'],int(ok)])
        if not ok:mismatches.append(i)
report={'status':'PASS' if not mismatches else 'FAIL','fresh_sensor_pairs':256,'ntt_blocks':4,'coefficients_compared':1024,'mismatches':mismatches,'path':'sensor -> ARM capture -> lossless 9+9 packing -> AXI -> PL NTT; host compares afterward','reference':'repo ntt_gen.py and shared RTL twiddle table, not independent cryptographic certification','sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [out/'sensor_raw.csv',out/'ntt_actual.csv',elf,here/'output/i2c.bit']}}
with (out/'intt_actual.csv').open() as f: inverse=list(csv.DictReader(f))
assert len(inverse)==1024
inverse_expected=sum([golden.intt_ref(expected[b*256:(b+1)*256],invzetas) for b in range(4)],[])
inv_mismatches=[]
with (out/'intt_comparison.csv').open('w',newline='') as f:
    writer=csv.writer(f);writer.writerow(['index','expected','actual','pass'])
    for i,row in enumerate(inverse):
        assert int(row['index'])==i
        ok=int(row['actual'])==inverse_expected[i]
        writer.writerow([i,inverse_expected[i],row['actual'],int(ok)])
        if not ok:inv_mismatches.append(i)
report.update(ntt_status='PASS' if not mismatches else 'FAIL',intt_status='PASS' if not inv_mismatches else 'FAIL',intt_coefficients_compared=1024,intt_mismatches=inv_mismatches,
              inverse_reference_returns_original=(inverse_expected==packed),
              status='PASS' if not mismatches and not inv_mismatches else 'FAIL')
report['quality']=quality
report['quality_capture_pairs']=1024 if gated else None
normalized=[int(r['actual'])*pow(65536,-1,3329)%3329 for r in inverse]
report['normalized_roundtrip_pass']=(normalized==packed)
report['intt_convention']='INTT(NTT(x)) = x * 2^16 mod 3329; host removes Montgomery factor for roundtrip check'
if normalized!=packed:report['status']='FAIL'
(out/'result.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2));print('EVIDENCE='+str(out))
if mismatches or inv_mismatches or normalized!=packed:raise SystemExit(1)
