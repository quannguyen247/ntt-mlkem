"""Independent Kyber arithmetic vectors + 200 MHz RTL regression (Icarus)."""
import argparse
import random
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
Q, R = 3329, 65536
Z = [pow(17, int(f'{i:07b}'[::-1], 2), Q) for i in range(128)]


def transform(a, inverse=False):
    a = a.copy()
    k = 127 if inverse else 1
    for length in ([2, 4, 8, 16, 32, 64, 128] if inverse else [128, 64, 32, 16, 8, 4, 2]):
        for base in range(0, 256, 2 * length):
            z = Z[k]
            k += -1 if inverse else 1
            for j in range(base, base + length):
                x, y = a[j], a[j + length]
                if inverse:
                    a[j], a[j + length] = (x + y) % Q, (y - x) * z % Q
                else:
                    a[j], a[j + length] = (x + y * z) % Q, (x - y * z) % Q
    if inverse:
        # Existing RTL uses invntt_tomont: output carries one factor R.
        a = [x * pow(128, -1, Q) * R % Q for x in a]
    return a


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', type=Path, default=ROOT / 'build/ppa/regression')
    p.add_argument('--random', type=int, default=32)
    p.add_argument('--units', action='store_true', help='Also exhaust all canonical multiplier inputs')
    args = p.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(20260909)
    inputs = [[0]*256, [Q-1]*256, [1]+[0]*255, list(range(256)), [0, Q-1]*128]
    inputs += [[rng.randrange(Q) for _ in range(256)] for _ in range(args.random)]
    cases = []
    for a in inputs:
        f = transform(a)
        inv = transform(f, True)
        assert inv == [x * R % Q for x in a]
        cases += [(0, a, f), (1, a, transform(a, True))]
    for name, values in [('input', [x for _, a, _ in cases for x in a]),
                         ('expected', [x for _, _, a in cases for x in a])]:
        (out / f'{name}.mem').write_text(''.join(f'{x:03x}\n' for x in values))
    (out / 'mode.mem').write_text(''.join(f'{m}\n' for m, _, _ in cases))
    rtl = ROOT / 'Implementation/rtl'
    names = ['ntt_agu', 'ntt_butterfly', 'ntt_controller', 'ntt_core_top',
             'ntt_mod_mul_12b', 'ntt_ram_dual', 'ntt_twiddle_rom']
    tb = ROOT / 'Implementation/testbench/tb_ntt_core_top.sv'
    subprocess.run(['iverilog', '-g2012', '-s', 'tb_ntt_core_top',
                    f'-Ptb_ntt_core_top.CASES={len(cases)}', '-I', str(rtl/'utils'),
                    '-o', str(out/'sim.vvp'), str(tb)]
                   + [str(rtl/'modules'/f'{n}.v') for n in names], check=True)
    result = subprocess.run(['vvp', str(out/'sim.vvp')], cwd=out, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (out/'regression.log').write_text(result.stdout)
    print(result.stdout)
    result.check_returncode()
    if 'REGRESSION_PASS' not in result.stdout:
        raise RuntimeError('Missing PASS marker')
    if args.units:
        for unit, module in [('mul', 'ntt_mod_mul_12b')]:
            subprocess.run(['iverilog', '-g2012', '-DTEST_MULTIPLIER', '-s', 'tb_ntt_core_top', '-I', str(rtl/'utils'),
                            '-o', str(out/f'{unit}.vvp'),
                            str(tb),
                            str(rtl/'modules'/f'{module}.v')], check=True)
            test = subprocess.run(['vvp', str(out/f'{unit}.vvp')], text=True,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            (out/f'{unit}.log').write_text(test.stdout)
            print(test.stdout)
            test.check_returncode()
            if '_EXHAUSTIVE_PASS' not in test.stdout:
                raise RuntimeError(f'Missing {unit} PASS marker')


if __name__ == '__main__':
    main()
