"""Generate reference vectors and build minimal A53 ELF (no BSP dependency)."""
from pathlib import Path
import importlib.util
import os
import subprocess

here = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('golden', here.parent / 'vector/ntt_gen.py')
golden = importlib.util.module_from_spec(spec)
spec.loader.exec_module(golden)
zetas, _ = golden.parse_twiddles(here.parent / 'rtl/utils/ntt_funcs.vh')
inputs = [[0]*256, [3328]*256, [(i*17+123)%3329 for i in range(256)]]
out = here/'output'
out.mkdir(exist_ok=True)
def array(name, rows):
    return 'static const unsigned short '+name+'[3][256] = {\n'+',\n'.join('{'+','.join(map(str,r))+'}' for r in rows)+'\n};\n'
(out/'vectors.h').write_text(array('inputs',inputs)+array('expected',[golden.ntt_ref(r,zetas) for r in inputs]))
gcc = os.environ.get('AARCH64_GCC', str(Path(os.environ.get('VITIS_HOME','/home/quan/tools/Xilinx/2025.2.1/Vitis'))/'gnu/aarch64/lin/aarch64-none/bin/aarch64-none-elf-gcc'))
subprocess.run([gcc,'-O2','-ffreestanding','-fno-builtin','-nostdlib','-mgeneral-regs-only','-I'+str(out),'-T'+str(here/'link.ld'),str(here/'entry.S'),str(here/'test.c'),'-o',str(out/'test.elf')], check=True)
