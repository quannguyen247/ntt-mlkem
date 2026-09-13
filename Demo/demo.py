#!/usr/bin/env python3
"""Single entry point for the KV260 MAX30102 validation and presentation flow."""

from __future__ import annotations

import argparse
import csv
import fcntl
import hashlib
import importlib.util
import json
import math
import os
import shutil
import statistics as stats
import subprocess
import sys
import time
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
IMPL = ROOT / "Implementation"
FIRMWARE = HERE / "firmware"
OUTPUT = HERE / "output"
PROJECT = HERE / "project"
WAVEFORM = HERE / "waveform"
MANIFEST = OUTPUT / "build-manifest.json"
Q = 3329
R = 65536
RTL_MODULES = [
    "ntt_agu",
    "ntt_butterfly",
    "ntt_controller",
    "ntt_core_top",
    "ntt_mod_mul_12b",
    "ntt_ram_dual",
    "ntt_twiddle_rom",
]


def _candidate_tools(name: str) -> list[Path]:
    env_name = "VIVADO_HOME" if name == "vivado" else "VITIS_HOME"
    home = os.environ.get(env_name)
    candidates: list[Path] = []
    if home:
        candidates.append(Path(home) / "bin" / name)
    found = shutil.which(name)
    if found:
        candidates.append(Path(found))
    candidates.append(Path(f"/home/quan/tools/Xilinx/2025.2.1/{'Vivado' if name == 'vivado' else 'Vitis'}/bin/{name}"))
    return candidates


def tool(name: str, required: bool = True) -> Path | None:
    for candidate in _candidate_tools(name):
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate.resolve()
    if required:
        raise FileNotFoundError(f"Không tìm thấy {name}; đặt VIVADO_HOME/VITIS_HOME hoặc PATH")
    return None


def vitis_tool(name: str, required: bool = True) -> Path | None:
    home = os.environ.get("VITIS_HOME")
    candidates: list[Path] = []
    if home:
        vitis_home = Path(home)
        candidates += [
            vitis_home / "gnu/aarch64/lin/aarch64-none/bin" / name,
            vitis_home.parent / "gnu/aarch64/lin/aarch64-none/bin" / name,
        ]
    xsct = tool("xsct", required=False)
    if xsct:
        vitis_dir = xsct.parent.parent
        candidates += [
            vitis_dir / "gnu/aarch64/lin/aarch64-none/bin" / name,
            vitis_dir.parent / "gnu/aarch64/lin/aarch64-none/bin" / name,
        ]
    install = Path("/home/quan/tools/Xilinx/2025.2.1")
    candidates += [
        install / "gnu/aarch64/lin/aarch64-none/bin" / name,
        install / "Vitis/gnu/aarch64/lin/aarch64-none/bin" / name,
    ]
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate.resolve()
    if required:
        raise FileNotFoundError(f"Không tìm thấy {name} trong Vitis")
    return None


def run(command: list[str | Path], cwd: Path = HERE, log: Path | None = None) -> None:
    printable = " ".join(str(item) for item in command)
    print(f"$ {printable}", flush=True)
    if log is None:
        subprocess.run([str(item) for item in command], cwd=cwd, check=True)
        return
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w") as stream:
        process = subprocess.Popen(
            [str(item) for item in command],
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        assert process.stdout is not None
        for line in process.stdout:
            print(line, end="", flush=True)
            stream.write(line)
            stream.flush()
        if process.wait() != 0:
            raise subprocess.CalledProcessError(process.returncode, printable)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def design_sources() -> list[Path]:
    paths = list((IMPL / "rtl/modules").glob("*.v"))
    paths += list((IMPL / "rtl/utils").glob("*.vh"))
    paths += [HERE / "rtl/ntt_core_axi_lite.v", HERE / "sensor.xdc"]
    return sorted(path.resolve() for path in paths)


def design_digest() -> str:
    digest = hashlib.sha256()
    for path in design_sources():
        digest.update(path.relative_to(ROOT).as_posix().encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def write_manifest(provenance: str) -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    artifacts = [OUTPUT / name for name in ("i2c.bit", "kv260_sensor.xsa", "psu_init.tcl")]
    missing = [str(path) for path in artifacts if not path.is_file()]
    if missing:
        raise FileNotFoundError("Thiếu artifact để lập manifest: " + ", ".join(missing))
    data = {
        "schema": 1,
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "provenance": provenance,
        "design_source_sha256": design_digest(),
        "artifacts": {path.name: {"bytes": path.stat().st_size, "sha256": sha256(path)} for path in artifacts},
    }
    MANIFEST.write_text(json.dumps(data, indent=2) + "\n")
    print(f"ARTIFACT_MANIFEST={MANIFEST}")


def artifact_status() -> tuple[bool, str]:
    if not MANIFEST.is_file():
        return False, f"thiếu {MANIFEST.relative_to(ROOT)}"
    try:
        data = json.loads(MANIFEST.read_text())
    except (json.JSONDecodeError, OSError) as exc:
        return False, f"manifest lỗi: {exc}"
    if data.get("design_source_sha256") != design_digest():
        return False, "RTL/XDC đã đổi sau lần build artifact"
    for name, expected in data.get("artifacts", {}).items():
        path = OUTPUT / name
        if not path.is_file():
            return False, f"thiếu artifact {name}"
        if path.stat().st_size != expected.get("bytes") or sha256(path) != expected.get("sha256"):
            return False, f"artifact {name} không khớp manifest"
    for required in ("i2c.bit", "kv260_sensor.xsa", "psu_init.tcl"):
        if required not in data.get("artifacts", {}):
            return False, f"manifest thiếu {required}"
    return True, data.get("provenance", "không ghi provenance")


def correlation(a: list[float], b: list[float]) -> float:
    mean_a, mean_b = stats.mean(a), stats.mean(b)
    centered_a = [value - mean_a for value in a]
    centered_b = [value - mean_b for value in b]
    denominator = math.sqrt(sum(value * value for value in centered_a) * sum(value * value for value in centered_b))
    return sum(x * y for x, y in zip(centered_a, centered_b)) / denominator if denominator else 0.0


def detrend(values: list[float]) -> list[float]:
    count = len(values)
    mean_x = (count - 1) / 2
    mean_y = stats.mean(values)
    denominator = sum((index - mean_x) ** 2 for index in range(count))
    slope = sum((index - mean_x) * (value - mean_y) for index, value in enumerate(values)) / denominator
    residual = [value - mean_y - slope * (index - mean_x) for index, value in enumerate(values)]
    return [stats.mean(residual[index - 2:index + 3]) for index in range(2, count - 2)]


def estimate_quality(rows: list[tuple[int, int, int]], sample_rate: int = 100) -> dict:
    result = {
        "accepted": False,
        "bpm": None,
        "spo2": None,
        "reason": "Chưa đủ tín hiệu",
        "calibrated": False,
        "medical_use": False,
        "sample_rate_hz": sample_rate,
    }

    def reject(reason: str) -> dict:
        result["reason"] = reason
        return result

    if len(rows) < 1000:
        return reject("Cần khoảng 10 giây mẫu liên tục")
    if any(rows[index][0] != rows[index - 1][0] + 1 for index in range(1, len(rows))):
        return reject("Mất mẫu")
    if any(not 0 <= value < 262144 for row in rows for value in row[1:]):
        return reject("Raw ngoài miền 18-bit")

    rows = rows[200:]
    red = [row[1] for row in rows]
    infrared = [row[2] for row in rows]
    dc = [stats.mean(red), stats.mean(infrared)]
    result["dc_red"], result["dc_ir"] = dc
    if min(dc) < 200:
        return reject("Mức phản xạ quá thấp: chưa có tay hoặc tín hiệu quá yếu")
    if max(red + infrared) >= 260000:
        return reject("Tín hiệu gần bão hòa")
    for channel, mean in zip((red, infrared), dc):
        chunks = [stats.mean(channel[index:index + 100]) for index in range(0, len(channel) - 99, 100)]
        if (max(chunks) - min(chunks)) / mean > 0.08:
            return reject("Tay hoặc ánh sáng thay đổi quá nhiều; giữ yên rồi thử lại")

    red_ac, infrared_ac = detrend(red), detrend(infrared)
    rms = [math.sqrt(stats.mean(value * value for value in channel)) for channel in (red_ac, infrared_ac)]
    perfusion = [rms[index] / dc[index] for index in (0, 1)]
    result["perfusion_rms"] = perfusion
    if min(perfusion) < 0.0003 or max(perfusion) > 0.5:
        return reject("Biên độ dao động chưa đủ tin cậy")
    channel_correlation = correlation(red_ac, infrared_ac)
    result["red_ir_correlation"] = channel_correlation
    if channel_correlation < 0.85:
        return reject("Hai kênh Red/IR chưa đồng nhất")

    lags = range(33, 151)
    scores = {lag: correlation(infrared_ac[:-lag], infrared_ac[lag:]) for lag in lags}
    peaks = [lag for lag in range(34, 150) if scores[lag] >= scores[lag - 1] and scores[lag] > scores[lag + 1]]
    if not peaks:
        return reject("Chưa thấy chu kỳ nhịp rõ")
    best = max(scores[lag] for lag in peaks)
    if best < 0.65:
        return reject("Chu kỳ chưa ổn định")
    lag = min(candidate for candidate in peaks if scores[candidate] >= best * 0.95)
    for half in (infrared_ac[:len(infrared_ac) // 2], infrared_ac[len(infrared_ac) // 2:]):
        if correlation(half[:-lag], half[lag:]) < 0.55:
            return reject("Nhịp không ổn định trong cả cửa sổ")

    ratio = perfusion[0] / perfusion[1]
    spo2 = -45.060 * ratio * ratio + 30.354 * ratio + 94.845
    if not 70 <= spo2 <= 100:
        return reject("Ước lượng ngoài miền demo; cần tín hiệu hoặc hiệu chuẩn tốt hơn")
    result.update(
        accepted=True,
        bpm=round(60 * sample_rate / lag, 1),
        spo2=round(spo2, 1),
        ratio=ratio,
        autocorrelation=scores[lag],
        reason="Đạt kiểm tra tín hiệu demo; số ước lượng chưa hiệu chuẩn",
    )
    return result


def quality_command(capture: Path) -> int:
    with (capture / "quality_raw.csv").open() as stream:
        rows = [(int(row["index"]), int(row["red"]), int(row["ir"])) for row in csv.DictReader(stream)]
    result = estimate_quality(rows)
    (capture / "quality.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(result["reason"])
    return 0 if result["accepted"] else 2


def load_golden():
    path = IMPL / "vector/ntt_gen.py"
    spec = importlib.util.spec_from_file_location("ntt_golden", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Không nạp được {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def compile_firmware(source: str, destination: Path, defines: list[str] | None = None) -> None:
    gcc = vitis_tool("aarch64-none-elf-gcc")
    assert gcc is not None
    command = [
        gcc,
        *(defines or []),
        "-O2",
        "-Wall",
        "-Wextra",
        "-ffreestanding",
        "-fno-builtin",
        "-nostdlib",
        "-mgeneral-regs-only",
        "-I",
        FIRMWARE,
        "-I",
        OUTPUT,
        "-T",
        FIRMWARE / "link.ld",
        FIRMWARE / "entry.S",
        FIRMWARE / source,
        "-o",
        destination,
    ]
    run(command)


def build_arm_test() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    golden = load_golden()
    zetas, _ = golden.parse_twiddles(IMPL / "rtl/utils/ntt_funcs.vh")
    inputs = [[0] * 256, [3328] * 256, [(index * 17 + 123) % Q for index in range(256)]]

    def c_array(name: str, rows: list[list[int]]) -> str:
        body = ",\n".join("{" + ",".join(map(str, row)) + "}" for row in rows)
        return f"static const unsigned short {name}[3][256] = {{\n{body}\n}};\n"

    vectors = c_array("inputs", inputs) + c_array("expected", [golden.ntt_ref(row, zetas) for row in inputs])
    (OUTPUT / "vectors.h").write_text(vectors)
    compile_firmware("test.c", OUTPUT / "test.elf")
    xsct = tool("xsct")
    assert xsct is not None
    run([xsct, "-nodisp", HERE / "demo.tcl", "arm-test"])


def run_sensor(quality_gate: bool) -> int:
    ok, reason = artifact_status()
    if not ok:
        raise RuntimeError(f"Artifact chưa sẵn sàng: {reason}. Chạy `python3 {HERE / 'demo.py'} build`.")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    lock_path = OUTPUT / "demo.lock"
    with lock_path.open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise RuntimeError("Một lượt demo khác đang chạy") from exc

        capture = OUTPUT / (time.strftime("sensor-ntt-%Y%m%d-%H%M%S") + f"-{time.time_ns() % 1_000_000:06d}")
        capture.mkdir()
        print(f"EVIDENCE={capture}", flush=True)
        elf = capture / "sensor_ntt.elf"
        defines = ["-DQUALITY_GATE", "-DSAMPLE_LIMIT=1024", "-DRAW_CAPACITY=1024"] if quality_gate else []
        compile_firmware("sensor_ntt.c", elf, defines)
        xsct = tool("xsct")
        assert xsct is not None
        run([xsct, "-nodisp", HERE / "demo.tcl", "sensor", elf, capture], log=capture / "hardware.log")

        quality = json.loads((capture / "quality.json").read_text()) if quality_gate else None
        if quality is not None and not quality["accepted"]:
            report = {
                "status": "INSUFFICIENT_SIGNAL",
                "ntt_status": "NOT_RUN",
                "intt_status": "NOT_RUN",
                "quality": quality,
                "completed_blocks": 0,
            }
            (capture / "result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
            print(json.dumps(report, ensure_ascii=False))
            return 0

        with (capture / "sensor_raw.csv").open() as stream:
            raw = list(csv.DictReader(stream))
        with (capture / "ntt_actual.csv").open() as stream:
            actual = list(csv.DictReader(stream))
        if len(raw) != 256 or len(actual) != 1024:
            raise RuntimeError(f"Số mẫu bất thường: raw={len(raw)}, ntt={len(actual)}")

        packed: list[int] = []
        for index, row in enumerate(raw):
            if int(row["index"]) != index:
                raise RuntimeError(f"Mất thứ tự mẫu ở index {index}")
            for channel in ("red", "ir"):
                value = int(row[channel])
                if not 0 <= value < 2**18:
                    raise RuntimeError(f"Raw {channel} ngoài miền 18-bit ở index {index}")
                low, high = value & 511, value >> 9
                if low | (high << 9) != value:
                    raise RuntimeError("Đóng gói 9+9 bit không bảo toàn dữ liệu")
                packed.extend([low, high])

        golden = load_golden()
        zetas, invzetas = golden.parse_twiddles(IMPL / "rtl/utils/ntt_funcs.vh")
        expected = sum((golden.ntt_ref(packed[block * 256:(block + 1) * 256], zetas) for block in range(4)), [])
        mismatches: list[int] = []
        with (capture / "comparison.csv").open("w", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(["block", "index", "packed", "arm_input", "expected", "fpga_actual", "pass"])
            for index, row in enumerate(actual):
                passed = int(row["input"]) == packed[index] and int(row["actual"]) == expected[index]
                writer.writerow([index // 256, index % 256, packed[index], row["input"], expected[index], row["actual"], int(passed)])
                if not passed:
                    mismatches.append(index)

        with (capture / "intt_actual.csv").open() as stream:
            inverse = list(csv.DictReader(stream))
        if len(inverse) != 1024:
            raise RuntimeError(f"Số hệ số INTT bất thường: {len(inverse)}")
        inverse_expected = sum((golden.intt_ref(expected[block * 256:(block + 1) * 256], invzetas) for block in range(4)), [])
        inverse_mismatches: list[int] = []
        with (capture / "intt_comparison.csv").open("w", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(["index", "expected", "actual", "pass"])
            for index, row in enumerate(inverse):
                passed = int(row["actual"]) == inverse_expected[index]
                writer.writerow([index, inverse_expected[index], row["actual"], int(passed)])
                if not passed:
                    inverse_mismatches.append(index)

        normalized = [int(row["actual"]) * pow(R, -1, Q) % Q for row in inverse]
        roundtrip = normalized == packed
        passed = not mismatches and not inverse_mismatches and roundtrip
        report = {
            "status": "PASS" if passed else "FAIL",
            "fresh_sensor_pairs": 256,
            "quality_capture_pairs": 1024 if quality_gate else None,
            "ntt_blocks": 4,
            "coefficients_compared": 1024,
            "ntt_status": "PASS" if not mismatches else "FAIL",
            "ntt_mismatches": mismatches,
            "intt_status": "PASS" if not inverse_mismatches else "FAIL",
            "intt_coefficients_compared": 1024,
            "intt_mismatches": inverse_mismatches,
            "normalized_roundtrip_pass": roundtrip,
            "intt_convention": "INTT(NTT(x)) = x * 2^16 mod 3329; host removes the Montgomery factor",
            "path": "MAX30102 -> ARM capture -> lossless 9+9 packing -> AXI -> PL NTT/INTT -> host comparison",
            "reference": "repo ntt_gen.py and shared RTL twiddle table; not independent cryptographic certification",
            "quality": quality,
            "sha256": {
                path.name: sha256(path)
                for path in (capture / "sensor_raw.csv", capture / "ntt_actual.csv", elf, OUTPUT / "i2c.bit")
            },
        }
        (capture / "result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps(report, ensure_ascii=False, indent=2))
        print(f"EVIDENCE={capture}")
        return 0 if passed else 1


def build_hardware(clean: bool, prepare_only: bool, publish: bool) -> None:
    vivado = tool("vivado")
    assert vivado is not None
    if publish:
        if clean:
            raise RuntimeError("`build --publish` không đi cùng `--clean`")
        project_file = PROJECT / "kv260_sensor_demo.xpr"
        if not project_file.is_file():
            raise RuntimeError(f"Không có project để publish: {project_file}")
        run(
            [vivado, "-mode", "batch", "-source", HERE / "demo.tcl", "-tclargs", "publish"],
            log=OUTPUT / "vivado-publish.log",
        )
        write_manifest("published by Demo/demo.py after Vivado GUI build")
        return
    if PROJECT.exists() and clean:
        shutil.rmtree(PROJECT)
    if PROJECT.exists():
        raise RuntimeError(f"{PROJECT} đã tồn tại; dùng `build --clean` nếu chắc chắn muốn tái tạo")
    action = "prepare" if prepare_only else "build"
    run([vivado, "-mode", "batch", "-source", HERE / "demo.tcl", "-tclargs", action], log=OUTPUT / "vivado-build.log")
    if not prepare_only:
        write_manifest("built by Demo/demo.py")


def reference_transform(values: list[int], inverse: bool = False) -> list[int]:
    """Algorithmic oracle derived from q=3329 and primitive root 17, not RTL ROM data."""
    result = values.copy()
    roots = [pow(17, int(f"{index:07b}"[::-1], 2), Q) for index in range(128)]
    root_index = 127 if inverse else 1
    lengths = [2, 4, 8, 16, 32, 64, 128] if inverse else [128, 64, 32, 16, 8, 4, 2]

    for length in lengths:
        for base in range(0, 256, 2 * length):
            root = roots[root_index]
            root_index += -1 if inverse else 1
            for index in range(base, base + length):
                left = result[index]
                right = result[index + length]
                if inverse:
                    result[index] = (left + right) % Q
                    result[index + length] = (right - left) * root % Q
                else:
                    result[index] = (left + right * root) % Q
                    result[index + length] = (left - right * root) % Q

    if inverse:
        scale = pow(128, -1, Q) * R
        result = [value * scale % Q for value in result]
    return result


def write_regression_vectors(directory: Path, random_count: int) -> int:
    import random

    rng = random.Random(20260909)
    inputs = [
        [0] * 256,
        [Q - 1] * 256,
        [1] + [0] * 255,
        list(range(256)),
        [0, Q - 1] * 128,
    ]
    inputs += [[rng.randrange(Q) for _ in range(256)] for _ in range(random_count)]
    cases: list[tuple[int, list[int], list[int]]] = []
    for values in inputs:
        forward = reference_transform(values)
        inverse = reference_transform(forward, inverse=True)
        if inverse != [value * R % Q for value in values]:
            raise RuntimeError("Oracle NTT/INTT không round-trip theo quy ước Montgomery")
        cases += [
            (0, values, forward),
            (1, values, reference_transform(values, inverse=True)),
        ]

    directory.mkdir(parents=True, exist_ok=True)
    flattened = {
        "input": [value for _, row, _ in cases for value in row],
        "expected": [value for _, _, row in cases for value in row],
    }
    for name, values in flattened.items():
        (directory / f"{name}.mem").write_text("".join(f"{value:03x}\n" for value in values))
    (directory / "mode.mem").write_text("".join(f"{mode}\n" for mode, _, _ in cases))
    return len(cases)


def regression(output: Path, random_count: int, units: bool) -> None:
    output = output.resolve()
    cases = write_regression_vectors(output, random_count)
    rtl = IMPL / "rtl"
    testbench = IMPL / "testbench/tb_ntt_core_top.sv"
    simulator = output / "sim.vvp"
    run([
        "iverilog",
        "-g2012",
        "-s",
        "tb_ntt_core_top",
        f"-Ptb_ntt_core_top.CASES={cases}",
        "-I",
        rtl / "utils",
        "-o",
        simulator,
        testbench,
        *[rtl / "modules" / f"{name}.v" for name in RTL_MODULES],
    ])
    run(["vvp", simulator], cwd=output, log=output / "regression.log")
    if "REGRESSION_PASS" not in (output / "regression.log").read_text(errors="replace"):
        raise RuntimeError("RTL regression không có PASS marker")

    if units:
        multiplier = output / "multiplier.vvp"
        run([
            "iverilog",
            "-g2012",
            "-DTEST_MULTIPLIER",
            "-s",
            "tb_ntt_core_top",
            "-I",
            rtl / "utils",
            "-o",
            multiplier,
            testbench,
            rtl / "modules/ntt_mod_mul_12b.v",
        ])
        run(["vvp", multiplier], cwd=output, log=output / "multiplier.log")
        if "MUL_EXHAUSTIVE_PASS" not in (output / "multiplier.log").read_text(errors="replace"):
            raise RuntimeError("Multiplier regression không có PASS marker")


def build_artix(output: Path, clean: bool) -> None:
    vivado = tool("vivado")
    assert vivado is not None
    output = output.resolve()
    if output.exists() and clean:
        shutil.rmtree(output)
    if output.exists():
        raise RuntimeError(f"{output} đã tồn tại; dùng `artix --clean` để tái tạo")
    run(
        [vivado, "-mode", "batch", "-source", HERE / "demo.tcl", "-tclargs", "artix", output],
        log=output.parent / "artix200-build.log",
    )


def write_wave_vectors(directory: Path) -> None:
    original = [(index * 17 + 123) % Q for index in range(256)]
    forward = reference_transform(original)
    cases = [(0, original, forward), (1, forward, reference_transform(forward, inverse=True))]
    directory.mkdir(parents=True, exist_ok=True)
    for name, values in (
        ("input", [value for _, row, _ in cases for value in row]),
        ("expected", [value for _, _, row in cases for value in row]),
    ):
        (directory / f"{name}.mem").write_text("".join(f"{value:03x}\n" for value in values))
    (directory / "mode.mem").write_text("".join(f"{mode}\n" for mode, _, _ in cases))


def build_waveform(clean: bool) -> None:
    vivado = tool("vivado")
    assert vivado is not None
    bin_dir = vivado.parent
    if WAVEFORM.exists() and clean:
        shutil.rmtree(WAVEFORM)
    WAVEFORM.mkdir(parents=True, exist_ok=True)
    write_wave_vectors(WAVEFORM)
    rtl = IMPL / "rtl"
    modules = [rtl / "modules" / f"{name}.v" for name in RTL_MODULES]
    run([bin_dir / "xvlog", "--sv", "-d", "TB_CASES=2", "-i", rtl / "utils", IMPL / "testbench/tb_ntt_core_top.sv", *modules], cwd=WAVEFORM, log=WAVEFORM / "compile.log")
    run([bin_dir / "xelab", "--debug", "all", "tb_ntt_core_top", "-s", "kv260_demo_wave"], cwd=WAVEFORM, log=WAVEFORM / "elaborate.log")
    run([bin_dir / "xsim", "kv260_demo_wave", "--wdb", "ntt_cycles.wdb", "--tclbatch", HERE / "demo.tcl"], cwd=WAVEFORM, log=WAVEFORM / "xsim.log")
    text = (WAVEFORM / "xsim.log").read_text(errors="replace")
    if "REGRESSION_PASS cases=2 coefficients=512" not in text:
        raise RuntimeError(f"Waveform không có PASS marker; xem {WAVEFORM / 'xsim.log'}")
    print(f"WAVEFORM_READY={WAVEFORM / 'ntt_cycles.wdb'}")
    print(f"WAVE_CONFIG={WAVEFORM / 'ntt_cycles.wcfg'}")


def doctor(check_hardware: bool, require_gui: bool = False) -> bool:
    checks: list[tuple[str, bool, str]] = []

    def add(name: str, passed: bool, detail: str) -> None:
        checks.append((name, passed, detail))

    add("Python", sys.version_info >= (3, 10), sys.version.split()[0])
    for name in ("vivado", "xsct"):
        path = tool(name, required=False)
        add(name, path is not None, str(path) if path else "không tìm thấy")
    for name in ("aarch64-none-elf-gcc", "aarch64-none-elf-nm"):
        path = vitis_tool(name, required=False)
        add(name, path is not None, str(path) if path else "không tìm thấy")
    required_sources = [HERE / "demo.tcl", FIRMWARE / "sensor_ntt.c", HERE / "rtl/ntt_core_axi_lite.v"]
    add("Demo sources", all(path.is_file() for path in required_sources), ", ".join(path.name for path in required_sources))
    artifacts_ok, artifact_reason = artifact_status()
    add("Current artifacts", artifacts_ok, artifact_reason)
    try:
        import PySide6  # noqa: F401
        qt_ok, qt_detail = True, "PySide6 OK"
    except ImportError:
        qt_ok, qt_detail = False, "thiếu PySide6; CLI headless vẫn dùng được"
    add("Presentation GUI", qt_ok or not require_gui, qt_detail)
    if check_hardware:
        xsct = tool("xsct", required=False)
        if xsct:
            result = subprocess.run([str(xsct), "-nodisp", str(HERE / "demo.tcl"), "probe"], cwd=HERE, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            add("KV260 JTAG", result.returncode == 0 and "KV260_TARGET_FOUND" in result.stdout, result.stdout.strip()[-500:])
        else:
            add("KV260 JTAG", False, "không có xsct")
    for name, passed, detail in checks:
        print(f"[{'OK' if passed else 'FAIL'}] {name}: {detail}")
    return all(passed for _, passed, _ in checks)


def latest_result() -> int:
    candidates = sorted(OUTPUT.glob("sensor-ntt-*/result.json"), key=lambda path: path.stat().st_mtime)
    if not candidates:
        print("Chưa có result.json")
        return 1
    path = candidates[-1]
    data = json.loads(path.read_text())
    print(f"LATEST_RESULT={path}")
    print(json.dumps(data, ensure_ascii=False, indent=2))
    return 0


def presentation_gui(autostart: bool) -> int:
    from collections import deque
    from PySide6.QtCore import QPointF, QProcess, QTimer
    from PySide6.QtGui import QColor, QPainter, QPen, QPolygonF
    from PySide6.QtWidgets import QApplication, QLabel, QPushButton, QVBoxLayout, QWidget

    class Plot(QWidget):
        def __init__(self):
            super().__init__()
            self.rows = deque(maxlen=1024)
            self.setMinimumSize(800, 420)

        def paintEvent(self, event):  # noqa: N802
            painter = QPainter(self)
            painter.fillRect(self.rect(), QColor("#15191f"))
            painter.setRenderHint(QPainter.Antialiasing)
            width, height = self.width(), self.height()
            rows = list(self.rows)
            for column, name, color in ((1, "RED raw ADC counts", "#ff7777"), (2, "IR raw ADC counts", "#77caff")):
                top = 30 + (column - 1) * (height // 2)
                graph_height = height // 2 - 65
                values = [row[column] for row in rows]
                low, high = (min(values), max(values)) if values else (0, 1)
                padding = max(10, (high - low) * 0.1)
                low, high = max(0, low - padding), high + padding
                painter.setPen(QColor("#eeeeee"))
                painter.drawText(12, top - 10, name + " (autoscale)")
                painter.drawText(10, top + 15, str(round(high)))
                painter.drawText(10, top + graph_height, str(round(low)))
                painter.setPen(QColor("#667078"))
                painter.drawRect(80, top, width - 100, graph_height)
                if len(rows) > 1:
                    painter.setPen(QPen(QColor(color), 1.5))
                    last = rows[-1][0]
                    points = [
                        QPointF(80 + (row[0] - last + 1023) / 1023 * (width - 100), top + graph_height - (row[column] - low) / (high - low) * graph_height)
                        for row in rows
                    ]
                    painter.drawPolyline(QPolygonF(points))
                painter.setPen(QColor("#eeeeee"))
                painter.drawText(80, top + graph_height + 20, "1024 samples (about 10.24 s at configured 100 samples/s)")

    class Demo(QWidget):
        def __init__(self):
            super().__init__()
            self.setWindowTitle("KV260: MAX30102 to NTT/INTT")
            self.resize(1080, 740)
            layout = QVBoxLayout(self)
            layout.addWidget(QLabel("Đặt nhẹ ngón tay lên MAX30102, giữ yên rồi bấm Chạy demo."))
            self.vitals = QLabel("BPM: — | SpO₂: — | Chưa thu tín hiệu")
            self.status = QLabel("Sẵn sàng. Flow: MAX30102 → ARM → AXI → NTT → INTT → đối chiếu host")
            self.status.setWordWrap(True)
            self.result = QLabel("RAW: CHƯA TEST | NTT: CHƯA TEST | INTT: CHƯA TEST")
            self.button = QPushButton("Chạy một lượt demo")
            layout.addWidget(self.vitals)
            layout.addWidget(self.status)
            layout.addWidget(self.result)
            layout.addWidget(self.button)
            self.plot = Plot()
            layout.addWidget(self.plot)
            layout.addWidget(QLabel("BPM/SpO₂ chỉ là ước lượng demo chưa hiệu chuẩn, không dùng để đánh giá sức khỏe."))
            self.process = QProcess(self)
            self.process.setProcessChannelMode(QProcess.MergedChannels)
            self.process.setWorkingDirectory(str(HERE))
            self.process.readyReadStandardOutput.connect(self.read_output)
            self.process.finished.connect(self.finished)
            self.process.errorOccurred.connect(self.process_error)
            self.button.clicked.connect(self.start)
            self.buffer = ""
            self.evidence: Path | None = None

        def start(self):
            artifacts_ok, reason = artifact_status()
            if not artifacts_ok:
                self.status.setText("Không chạy: " + reason + ". Build lại artifact trước buổi demo.")
                return
            self.button.setEnabled(False)
            self.buffer = ""
            self.evidence = None
            self.plot.rows.clear()
            self.plot.update()
            self.vitals.setText("BPM: — | SpO₂: — | Đang thu khoảng 10 giây")
            self.result.setText("RAW: ĐANG ĐỌC | NTT/INTT: ĐANG CHỜ QUALITY GATE")
            self.result.setStyleSheet("")
            self.status.setText("Đang nạp FPGA, thu 1024 cặp Red/IR và kiểm tra trên kit. Không chạy JTAG client khác.")
            self.process.start(sys.executable, ["-u", str(HERE / "demo.py"), "run", "--quality-gate"])

        def read_output(self):
            text = bytes(self.process.readAllStandardOutput()).decode(errors="replace")
            self.buffer += text
            print(text, end="", flush=True)
            for line in text.splitlines():
                if line.startswith("EVIDENCE="):
                    self.evidence = Path(line.split("=", 1)[1])

        def process_error(self, _error):
            self.status.setText("Lỗi process: " + self.process.errorString())
            self.button.setEnabled(True)

        def finished(self, code, _status):
            self.read_output()
            self.button.setEnabled(True)
            for line in self.buffer.splitlines():
                if line.startswith("EVIDENCE="):
                    self.evidence = Path(line.split("=", 1)[1])
            if self.evidence is None or not (self.evidence / "result.json").is_file():
                self.result.setText("TEST KHÔNG HOÀN TẤT; chưa kết luận NTT/INTT sai")
                self.status.setText(self.buffer[-1200:])
                return
            data = json.loads((self.evidence / "result.json").read_text())
            quality = data.get("quality") or {}
            if data["status"] == "INSUFFICIENT_SIGNAL":
                self.result.setText("RAW: ĐÃ THU | NTT: CHƯA CHẠY | INTT: CHƯA CHẠY")
                self.vitals.setText("BPM: — | SpO₂: — | Tín hiệu chưa đạt")
            else:
                self.result.setText(f"RAW: ĐÃ THU | NTT: {data['ntt_status']} (1024) | INTT: {data['intt_status']} (1024)")
                self.vitals.setText(f"Ước lượng demo: BPM ≈ {quality.get('bpm', '—')} | SpO₂ ≈ {quality.get('spo2', '—')}%")
            passed = code == 0 and data["status"] == "PASS"
            self.result.setStyleSheet("font-weight: bold; color: " + ("#5edc91" if passed else "#ff7777"))
            self.status.setText(quality.get("reason", "") + " | Evidence: " + str(self.evidence))
            raw_path = self.evidence / "quality_raw.csv"
            if not raw_path.is_file():
                raw_path = self.evidence / "sensor_raw.csv"
            if raw_path.is_file():
                with raw_path.open() as stream:
                    rows = [(int(row["index"]), int(row["red"]), int(row["ir"])) for row in csv.DictReader(stream)]
                self.plot.rows.extend(rows)
                self.plot.update()
            self.grab().save(str(self.evidence / "presentation.png"))

        def closeEvent(self, event):  # noqa: N802
            if self.process.state() != QProcess.NotRunning:
                self.status.setText("Đợi lượt kiểm thử kết thúc trước khi đóng.")
                event.ignore()
            else:
                event.accept()

    app = QApplication(sys.argv)
    window = Demo()
    window.show()
    if autostart:
        QTimer.singleShot(300, window.start)
    return app.exec()


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description="KV260 MAX30102 one-command validation flow")
    subparsers = result.add_subparsers(
        dest="command",
        metavar="{doctor,regression,artix,build,waveform,run,present,arm-test,latest}",
    )

    doctor_parser = subparsers.add_parser("doctor", help="kiểm tra tool, artifact và tùy chọn JTAG")
    doctor_parser.add_argument("--hardware", action="store_true", help="kết nối read-only để tìm target KV260")

    regression_parser = subparsers.add_parser("regression", help="tạo oracle độc lập và chạy RTL regression")
    regression_parser.add_argument("--out", type=Path, default=ROOT / "build/regression", help="thư mục kết quả")
    regression_parser.add_argument("--random", type=int, default=32, help="số vector ngẫu nhiên, seed cố định")
    regression_parser.add_argument("--units", action="store_true", help="kiểm tra vét cạn multiplier 3329^2 cặp")

    artix_parser = subparsers.add_parser("artix", help="chạy OOC Artix-7 200 MHz và xuất báo cáo PPA")
    artix_parser.add_argument("--out", type=Path, default=ROOT / "build/artix200", help="thư mục báo cáo")
    artix_parser.add_argument("--clean", action="store_true", help="xóa kết quả sinh tự động trước khi chạy")

    build_parser = subparsers.add_parser("build", help="build bitstream/XSA và đóng dấu artifact")
    build_parser.add_argument("--clean", action="store_true", help="xóa project sinh tự động hiện có trước khi build")
    build_mode = build_parser.add_mutually_exclusive_group()
    build_mode.add_argument("--prepare-only", action="store_true", help="chỉ tạo block design để mở GUI")
    build_mode.add_argument("--publish", action="store_true", help="xuất và đóng dấu artifact sau khi build bằng GUI")

    waveform_parser = subparsers.add_parser("waveform", help="tạo waveform XSim NTT rồi INTT")
    waveform_parser.add_argument("--clean", action="store_true", help="tạo lại thư mục waveform")

    run_parser = subparsers.add_parser("run", help="chạy sensor, NTT/INTT và đối chiếu headless")
    run_parser.add_argument("--quality-gate", action="store_true", help="thu 1024 mẫu và chỉ chạy NTT khi tín hiệu đạt")

    present_parser = subparsers.add_parser("present", help="mở GUI một nút cho buổi trình bày")
    present_parser.add_argument("--autostart", action="store_true", help="chạy ngay khi GUI mở")

    subparsers.add_parser("arm-test", help="test AXI NTT bằng ba vector, không cần MAX30102")
    subparsers.add_parser("latest", help="in result.json mới nhất")

    return result


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "__quality":
        return quality_command(Path(sys.argv[2]).resolve())
    args = parser().parse_args()
    command = args.command or "present"
    try:
        if command == "doctor":
            return 0 if doctor(args.hardware) else 1
        if command == "regression":
            regression(args.out, args.random, args.units)
            return 0
        if command == "artix":
            build_artix(args.out, args.clean)
            return 0
        if command == "build":
            build_hardware(args.clean, args.prepare_only, args.publish)
            return 0
        if command == "waveform":
            build_waveform(args.clean)
            return 0
        if command == "run":
            return run_sensor(args.quality_gate)
        if command == "present":
            return presentation_gui(getattr(args, "autostart", False))
        if command == "arm-test":
            build_arm_test()
            return 0
        if command == "latest":
            return latest_result()
        raise RuntimeError(f"Lệnh không hỗ trợ: {command}")
    except (FileNotFoundError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
