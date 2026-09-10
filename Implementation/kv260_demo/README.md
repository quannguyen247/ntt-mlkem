# KV260 MAX30102 → ARM → AXI → NTT/INTT: runbook cho người dùng và AI agents

## 1. Demo hiện tại

Entry point: `Implementation/kv260_demo/simple_demo.py`, chạy trên PC Linux.
App một nút thu raw thực từ MAX30102; tín hiệu đạt thì ARM chạy NTT/INTT trên PL.
Đồ thị là đợt vừa thu, không phải realtime liên tục. BPM/SpO₂ do PC ước lượng,
chưa hiệu chuẩn. NTT không tính BPM/SpO₂ và chưa phải mã hóa/giải mã ML-KEM hoàn chỉnh.

## 2. Chuẩn bị

| Thành phần | Yêu cầu |
|---|---|
| Kit | KV260, nguồn 12 V phù hợp |
| PC → kit | USB-A–micro-USB có dữ liệu, cắm J4 JTAG/UART |
| Sensor | MAX30102 đã hàn chân, 4 dây jumper phù hợp đầu nối |
| Kiểm tra điện | Đồng hồ đo; ngắt nguồn trước khi đổi dây |
| Vivado | 2025.2.1, hỗ trợ K26, board preset xilinx.com:kv260_som:part0:1.4 |
| Vitis | 2025.2.1, XSCT/hw_server và aarch64-none-elf-gcc/nm |
| Python | Python 3 + PySide6; phần còn lại dùng standard library |

Không cần SD, OS Linux trên kit, Vitis HLS hoặc BSP.
ELF tối giản chạy ở EL3, MMU/cache tắt. Script reset ARM, khởi tạo DDR và thay PL
mỗi lượt; không chạy app khác trên kit đồng thời. Không ghi flash/SD.

Kết nối đã dùng: **J2.1 → SCL (xám), J2.3 → SDA (tím)**.
XDC ánh xạ SCL=H12, SDA=E10, LVCMOS33. Module dùng 3.3 V và GND chung.
Không suy số chân nguồn bằng màu dây/hướng ảnh: đối chiếu đúng carrier.
Phiên bring-up trước đã đo nguồn và SCL/SDA idle khoảng 3.3 V; không thay bằng
5 V hoặc tự thêm pull-up khi chưa đo/kiểm tra module.

## 3. Mở app trên máy đã build

Từ root repo:

```bash
export VITIS_HOME=/home/quan/tools/Xilinx/2025.2.1/Vitis
python3 -c "from PySide6.QtWidgets import QApplication; print('Qt OK')"
python3 Implementation/kv260_demo/simple_demo.py
```

Máy khác: thay VITIS_HOME đúng thư mục Vitis. Thiếu PySide6 thì tạo venv và
cài `pip install PySide6` trong venv. Scripts dùng fcntl/compiler Linux;
chưa xác minh Windows cho flow sensor này.

Cần artifact local:
- `output/i2c.bit`
- `project/kv260_axi_test.gen/sources_1/bd/ntt_system/ip/ntt_system_ps_0/psu_init.tcl`

Các đường dẫn trên tương đối với thư mục demo. ELF được build mỗi lượt.

1. Cấp nguồn kit và nối USB J4; dừng các app/test khác dùng JTAG/ARM.
2. Đặt nhẹ đầu ngón tay phủ cửa sổ quang, giữ yên.
3. Bấm **Chạy demo: đọc raw → kiểm tra NTT + INTT**.
4. Chờ hết lượt: thu khoảng 10.24 giây, còn thời gian nạp FPGA và JTAG.
5. Đọc raw, ước lượng BPM/SpO₂, NTT/INTT PASS/FAIL.
6. Bỏ tay rồi chạy lại: tín hiệu không đạt → BPM/SpO₂ dấu —,
   **NTT: CHƯA CHẠY | INTT: CHƯA CHẠY**.

Quality gate là heuristic, không phải bộ phát hiện ngón tay được chứng nhận.
Dùng ngón tay cho demo; chưa kiểm chứng cấu hình cổ tay.
Không giảm ngưỡng để buộc PASS.

## 4. Build phần cứng và xuất artifact

Từ root repo:

```bash
export VIVADO_HOME=/home/quan/tools/Xilinx/2025.2.1/Vivado
"$VIVADO_HOME/bin/vivado" -mode batch -source Implementation/kv260_demo/build.tcl
```

Một lượt dựng PS–AXI–NTT và GPIO cảm biến, chạy đến bitstream rồi xuất
`output/i2c.bit` và `output/kv260_sensor.xsa`. Script chỉ xuất khi setup/hold
đạt ở 200 MHz. Đây là thiết kế KV260, không phải lượt đo PPA Artix-7 OOC.
`build.tcl` từ chối ghi đè `project/` hiện có: đóng project, chuyển thư mục
đó sang nơi lưu dự phòng rồi mới build lại. Không xóa captures trong `output/`.
Tên project bên trong vẫn là `kv260_axi_test` để giữ đường dẫn khởi tạo PS.

## 5. Mở thiết kế để trình bày (không bắt buộc Vitis GUI)

Nếu chỉ chuẩn bị block design, trong Vivado Tcl Console khi chưa mở project:

```tcl
set ::kv260_action prepare
source /duong/dan/repo/Implementation/kv260_demo/build.tcl
unset ::kv260_action
```

Mở `ntt_system.bd`: NTT ở `0xA0000000`, GPIO ở `0xA0010000`, PS cấp
clock 200 MHz. Sau Run Synthesis → Run Implementation → Generate Bitstream,
xuất artifact từ chính project này:

```tcl
set ::kv260_action publish
source /duong/dan/repo/Implementation/kv260_demo/build.tcl
unset ::kv260_action
```

Vivado Tcl dựng phần cứng; **XSCT** (Xilinx Software Command-line Tool)
khởi tạo và chạy chương trình ARM. Hai môi trường không dùng thay cho nhau.
Demo này biên dịch C/ASM bằng compiler Vitis và nạp ELF qua XSCT, không phụ
thuộc `Validation/ntt_platform` hay platform tạo bằng Vitis GUI.

## 6. Flow dữ liệu chính xác

1. Host build sensor_ntt.c + entry.S + link.ld thành ELF.
2. XSCT init PS/DDR, nạp PL và ELF, chạy Cortex-A53.
3. ARM kiểm tra PART_ID 0xFF=0x15 tại I²C 7-bit 0x57; đọc 1024 cặp Red/IR
   18-bit ở 100 samples/s; shutdown cảm biến.
4. Dừng ở quality_ready trước truy cập NTT. PC đọc DDR, kiểm tra chất lượng
   bằng ppg_quality.py và tính ước lượng BPM/SpO₂.
5. Bị loại: approval=0, ARM kết thúc với completed_blocks=0.
6. Đạt: ARM lấy **256 cặp cuối của chính đợt vừa thu**, tách mỗi số 18-bit
   thành low=raw&511, high=raw>>9. Thứ tự: red low, red high, IR low, IR high.
   Tổng 1024 hệ số, chia 4 khối × 256.
7. ARM ghi/đọc lại RAM AXI, chạy NTT rồi INTT trên output NTT thực của PL.
   Poll done có timeout.
8. PC so 1024 hệ số mỗi chiều với vector/ntt_gen.py và bảng twiddle dùng chung
   với RTL. Đây không phải kiểm định mật mã độc lập.
9. Quy ước Montgomery: INTT(NTT(x))=x×65536 mod 3329. PC bỏ hệ số bằng
   nghịch đảo modulo và kiểm tra khôi phục hệ số đã đóng gói.

Ước lượng y sinh dùng raw 18-bit riêng, không dùng hệ số 9-bit để tính SpO₂.

## 7. Bằng chứng và cách đọc lỗi

Mỗi lượt tạo output/sensor-ntt-TIMESTAMP/:

| File | Ý nghĩa |
|---|---|
| quality_raw.csv | 1024 cặp vừa đọc (quality-gated mode) |
| quality.json | Nhận/loại, lý do, ước lượng |
| sensor_raw.csv | 256 cặp cuối dùng cho NTT |
| ntt_actual.csv, intt_actual.csv | Kết quả từ PL qua ARM/DDR |
| comparison.csv, intt_comparison.csv | So từng hệ số |
| result.json | Status, mismatch, round-trip và hashes |
| hardware.log, sensor_ntt.elf | Công cụ và chương trình của lượt đó |

PASS yêu cầu status=PASS, ntt_status=intt_status=PASS, không mismatch và
normalized_roundtrip_pass=true. Exit 0 + INSUFFICIENT_SIGNAL chỉ là xử lý
từ chối thành công; không phải NTT PASS.

- Chu kỳ/tương quan chưa đạt: giữ tay nhẹ, tránh xê dịch/ánh sáng lọt, chạy lại.
- Missing prerequisite: kiểm tra VITIS_HOME hoặc build lại.
- Another demo is running: đợi lượt trước; không xóa lock để chạy song song.
- Lỗi PART_ID/I²C: kiểm tra dây/nguồn/pull-up và bitstream sensor.
- TEST KHÔNG HOÀN TẤT: giữ hardware.log; chưa kết luận RTL sai.
- Mismatch: giữ evidence; đối chiếu đúng source/bitstream; không sửa expected
  theo actual. Sau đổi RTL/build phải chạy lại, log cũ không chứng minh bản mới.

## 8. Kiểm tra riêng từng phần

Từ Implementation/kv260_demo, đã export VITIS_HOME:

```bash
# 3 vector, ARM tự kiểm tra 768 hệ số NTT, không cần sensor:
python3 build_test.py
"$VITIS_HOME/bin/xsct" -nodisp run_test.tcl

# Giống GUI, cần tín hiệu đạt:
python3 verify_sensor_ntt.py --quality-gate

# Chẩn đoán phép biến đổi, không yêu cầu có tay:
python3 verify_sensor_ntt.py
```

Chỉ chạy lần lượt. Test ARM dùng bitstream sensor và project local do build.tcl tạo.

## 9. Kịch bản demo 3–5 phút

1. Giới thiệu vi kiến trúc 12-bit, mở block design PS–PL.
2. Chỉ clock 200 MHz, timing routed và chân I²C.
3. Đặt tay, bấm chạy, xem raw và PASS.
4. Mở result.json/comparison.csv để giải thích kiểm chứng.
5. Bỏ tay, chạy lại để minh họa chưa đủ tín hiệu → chưa chạy.
6. Phân biệt ước lượng y sinh với kiểm chứng toán học NTT/INTT.

## 10. Bàn giao cho AI agents

- Branch đích dev_quan; không merge main.
- Source chính: rtl/modules/, rtl/utils/, vector/ntt_gen.py, kv260_demo/.
- Không sửa PQClean, Kyber-Round3-KAT, form(donotedit) hoặc phần ngoài nhiệm vụ.
- vio/ là VIO riêng; không nhập nhằng với ARM/AXI.
- Không commit project sinh tự động, bit/XSA/ELF hoặc captures sinh lý.
  Giữ local; commit Tcl/RTL/C/ASM/Python/Markdown để tái tạo.
- Không thay đổi RTL/quality gate/công thức dưới danh nghĩa cleanup.
- Ghi test thực đã chạy và giới hạn; không gọi estimated Fmax là hardware-verified.
- Root Makefile là flow cũ tham chiếu src/ và testbench/ không còn trong checkout;
  không dùng make test để xác minh demo này.

## 11. VIO tùy chọn

`vio/` chứa thiết kế độc lập: PS cấp clock/reset, JTAG/VIO điều khiển lõi.
Nó không có ARM–AXI–cảm biến và không thay thế demo chính. Chạy lần lượt:

```bash
"$VIVADO_HOME/bin/vivado" -mode batch -source Implementation/kv260_demo/vio/create_kv260_debug.tcl
"$VITIS_HOME/bin/xsct" -nodisp Implementation/kv260_demo/vio/init_and_program.tcl
"$VIVADO_HOME/bin/vivado" -mode batch -source Implementation/kv260_demo/vio/hardware_ntt_vector_test.tcl
```

Script tạo VIO dùng `create_project -force`; lưu project đã chỉnh tay trước
khi chạy. Test vector cần `Implementation/vector/tv_all.mem` do `ntt_gen.py`
tạo. `hardware_smoke_test.tcl` kiểm tra RAM và vector 0;
`hardware_ntt_vector_test.tcl` kiểm tra 256 hệ số vector all-max.
`verify_vio.tcl` chỉ kiểm tra khả năng truy cập VIO.

Trong Hardware Manager chọn file `vio/output/ntt_kv260_debug.ltx` đi kèm
đúng bitstream. Output probe 0..5 lần lượt là resetn, start, mode, ext_we,
ext_addr[7:0], ext_din[11:0]. Input 0..3 là ext_dout[11:0], busy, done,
done_sticky. Reset trước khi nạp đủ 256 hệ số; pulse start và chờ done_sticky.
Done không tự chứng minh kết quả đúng: phải đối chiếu đủ đầu ra.

## 12. Trạng thái bằng chứng

Các artifact/captures đã có được giữ nguyên khi chuyển thư mục. Log cũ
không chứng minh RTL mới hoặc thiết kế vừa refactor đã chạy trên kit.
Lượt sensor lịch sử `sensor-ntt-20260907-142221-678483` ghi PASS 1024 hệ số
mỗi chiều và round-trip chuẩn hóa; lượt VIO tháng 8 là một thiết kế khác.
Không dùng hai kết quả này thay cho kiểm thử lại sau build mới.

Sau di chuyển thư mục, nên tái tạo project nếu Vivado báo đường dẫn nguồn
cũ; không sửa dữ liệu expected để vượt test. Chỉ chạy một client JTAG/ARM.
Chưa kết nối kit hoặc chưa chạy test phải ghi **NOT RUN**, không ghi PASS.

Kiểm tra refactor ngày 10/09/2026:

- Build mới bằng Tcl gộp, trong `build/kv260-refactor-check/`: hoàn tất đến
  bitstream/XSA; clock 5 ns, WNS +1.216 ns, WHS +0.013 ns, không có endpoint
  setup/hold vi phạm. Đây là timing toàn thiết kế KV260, không thay số Artix-7.
- C/ASM của test ARM và demo quality-gated: biên dịch thành ELF thành công.
- Regression RTL: 266 phép biến đổi, 68.096 hệ số, PASS.
- XSim 2025.2.1: 74 phép biến đổi, 18.944 hệ số, PASS; 905/1161 chu kỳ.
- RTL, sensor.c, sensor_ntt.c và ngưỡng quality gate không đổi khi refactor.
- Kit: chưa chạy lại trong lượt refactor này. Các bước VIO đã sửa đường dẫn
  nguồn nhưng chưa build/chạy phần cứng lại trong lượt này.

## 13. Chụp waveform cho báo cáo

Testbench duy nhất: `Implementation/testbench/tb_ntt_core_top.sv`.
`benchmark/capture_wave.tcl` dùng trong **XSim**, không dùng trong XSCT.
Lượt XSim ngày 10/09 lưu `ntt_cycles.wdb`, `ntt_cycles.wcfg` và `xsim.log`
ở `build/ppa/waveform-20260910/` (local, không đưa database lớn lên Git).

Trong Vivado Tcl Console, thay ROOT bằng đường dẫn repo:

```tcl
open_wave_database ROOT/build/ppa/waveform-20260910/ntt_cycles.wdb
open_wave_config ROOT/build/ppa/waveform-20260910/ntt_cycles.wcfg
```

Giữ các tín hiệu clk, rst_n, start, mode, busy, done, cycles, len và cnt.
Lượt đầu NTT: cạnh nhận start ở 1502.5 ns, done lên ở 6027.5 ns,
chênh 4525 ns = 905 clock. Lượt kế INTT: 8637.5 → 14442.5 ns,
chênh 5805 ns = 1161 clock. Đặt hai cursor tại hai cạnh này, không đo từ
cạnh lên start ở cạnh xuống clock của testbench (lệch nửa chu kỳ).
Chụp riêng vùng Wave có tên tín hiệu, trục thời gian và hai cursor;
chụp NTT và INTT riêng để chữ rõ. Log PASS là ảnh bổ sung, không thay waveform.
