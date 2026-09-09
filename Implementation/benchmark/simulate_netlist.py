"""Run routed functional regression and capture SAIF using installed Vivado tools."""
import argparse
import os
import shutil
import subprocess
from pathlib import Path


def main():
    p = argparse.ArgumentParser()
    p.add_argument('run', type=Path, help='Directory containing routed.v and routed.dcp')
    p.add_argument('--vectors', type=Path, required=True)
    p.add_argument('--vivado-bin', type=Path, required=True)
    args = p.parse_args()
    run = args.run.resolve()
    sim = run/'simulation'
    sim.mkdir(exist_ok=True)
    for name in ('input.mem', 'expected.mem', 'mode.mem'):
        shutil.copyfile(args.vectors/name, sim/name)
    cases = len((sim/'mode.mem').read_text().splitlines())
    env = os.environ.copy()
    env['PATH'] = str(args.vivado_bin.resolve()) + os.pathsep + env['PATH']
    def execute(name, command):
        with (sim/f'{name}.log').open('w') as log:
            subprocess.run(command, cwd=sim, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    execute('compile', ['xvlog', '--sv', str(run/'routed.v'),
                       str(Path(__file__).resolve().parents[1]/'testbench/tb_ntt_core_top.sv'),
                       str(args.vivado_bin.resolve().parent/'data/verilog/src/glbl.v')])
    execute('elaborate', ['xelab', '-L', 'unisims_ver', '-L', 'unimacro_ver',
                         '--debug', 'all', '--generic_top', f'CASES={cases}',
                         'tb_ntt_core_top', 'glbl', '-s', 'ppa_sim'])
    execute('simulate', ['xsim', 'ppa_sim', '-tclbatch',
                        str(Path(__file__).with_name('capture_saif.tcl').resolve())])
    log = (sim/'simulate.log').read_text()
    if 'REGRESSION_PASS' not in log or 'MISMATCH' in log:
        raise RuntimeError(f'Netlist regression failed: {sim}/simulate.log')
    print(f'NETLIST_REGRESSION_PASS cases={cases}; SAIF: {sim}/activity.saif')


if __name__ == '__main__':
    main()
