# KV260 MAX30102 → ARM → AXI → NTT/INTT: runbook cho người dùng và AI agents

## 1. Demo hiện tại

Entry point: `Implementation/kv260_axi_test/simple_demo.py`, chạy trên PC Linux.
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
python3 Implementation/kv260_axi_test/simple_demo.py
```

Máy khác: thay VITIS_HOME đúng thư mục Vitis. Thiếu PySide6 thì tạo venv và
cài `pip install PySide6` trong venv. Scripts dùng fcntl/compiler Linux;
chưa xác minh Windows cho flow sensor này.

Cần artifact local:
- `output/i2c.bit`
- `project/kv260_axi_test.gen/sources_1/bd/ntt_system/ip/ntt_system_ps_0/psu_init.tcl`

Các đường dẫn trên tương đối với kv260_axi_test. ELF được build mỗi lượt.

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

## 4. Build từ source

Từ root repo, chạy theo thứ tự, mỗi lệnh một tiến trình Vivado:

```bash
export VIVADO_HOME=/home/quan/tools/Xilinx/2025.2.1/Vivado
"$VIVADO_HOME/bin/vivado" -mode batch -source Implementation/kv260_axi_test/build.tcl
"$VIVADO_HOME/bin/vivado" -mode batch -source Implementation/kv260_axi_test/build_i2c.tcl
```

Bước 1 dựng PS→AXI→NTT và xuất kv260_axi_test.xsa (NTT-only).
Bước 2 thêm AXI GPIO, I²C; xuất i2c.bit, kv260_sensor.xsa, i2c_timing.rpt,
i2c_drc.rpt. Chờ SENSOR_ARTIFACTS_READY và build thành công.
Không dùng XSA NTT-only để chứng minh cảm biến.

build.tcl dùng create_project -force: lưu bản sao trước nếu có chỉnh sửa GUI.
project/output được ignore trong Git, giữ local để demo nhanh.

## 5. Vivado GUI cho ban giám khảo

Nếu project đã có: Open Project → kv260_axi_test/project/kv260_axi_test.xpr.

Nếu chưa có: trong Tcl Console, thay đường dẫn repo:

```tcl
cd /duong/dan/repo/Implementation/kv260_axi_test
set ::kv260_gui_only 1
source build.tcl
source build_i2c.tcl
unset ::kv260_gui_only
```

Script chuẩn bị thiết kế, dừng trước synthesis.

1. Open Block Design → ntt_system.bd.
2. Chỉ PS ps, interconnect, ntt và sensor_gpio.
3. Mở PS kiểm tra PL0=200 MHz. Address Editor: NTT=0xA0000000,
   GPIO=0xA0010000.
4. Sources → Constraints → sensor.xdc: hai chân I²C.
5. Run Synthesis → Run Implementation → Generate Bitstream.
6. Open Implemented Design → Report Timing Summary: clock 5 ns,
   setup/hold slack không âm. Xem DRC; không lấy report OOC thay routed.
7. Tại Tcl Console, trong kv260_axi_test: `source publish_i2c.tcl`.
   Script kiểm tra clock/setup/hold trước khi xuất artifact cho app.
8. Chạy app: app thực hiện khởi tạo PS và nạp bitstream.

Bản sensor AXI không có VIO. Nếu muốn điều khiển VIO bằng tay, đọc
[DEMO_VIVADO.md](../kv260_debug/DEMO_VIVADO.md), dùng bitstream riêng.
VIO không chứng minh CPU điều khiển AXI. Không nạp đồng thời hai thiết kế.

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

Từ Implementation/kv260_axi_test, đã export VITIS_HOME:

```bash
# 3 vector, ARM tự kiểm tra 768 hệ số NTT, không cần sensor:
python3 build_test.py
"$VITIS_HOME/bin/xsct" -nodisp run_test.tcl

# Giống GUI, cần tín hiệu đạt:
python3 verify_sensor_ntt.py --quality-gate

# Chẩn đoán phép biến đổi, không yêu cầu có tay:
python3 verify_sensor_ntt.py
```

Chỉ chạy lần lượt. Test ARM cần artifact build.tcl và project local.

## 9. Kịch bản demo 3–5 phút

1. Giới thiệu vi kiến trúc 12-bit, mở block design PS–PL.
2. Chỉ clock 200 MHz, timing routed và chân I²C.
3. Đặt tay, bấm chạy, xem raw và PASS.
4. Mở result.json/comparison.csv để giải thích kiểm chứng.
5. Bỏ tay, chạy lại để minh họa chưa đủ tín hiệu → chưa chạy.
6. Phân biệt ước lượng y sinh với kiểm chứng toán học NTT/INTT.

## 10. Bàn giao cho AI agents

- Branch đích dev_quan; không merge main.
- Source chính: rtl/modules/, rtl/utils/, vector/ntt_gen.py, kv260_axi_test/.
- Không sửa PQClean, Kyber-Round3-KAT, form(donotedit) hoặc phần ngoài nhiệm vụ.
- kv260_debug là VIO riêng; không nhập nhằng với ARM/AXI.
- Không commit project sinh tự động, bit/XSA/ELF hoặc captures sinh lý.
  Giữ local; commit Tcl/RTL/C/ASM/Python/Markdown để tái tạo.
- Không thay đổi RTL/quality gate/công thức dưới danh nghĩa cleanup.
- Ghi test thực đã chạy và giới hạn; không gọi estimated Fmax là hardware-verified.
- Root Makefile là flow cũ tham chiếu src/ và testbench/ không còn trong checkout;
  không dùng make test để xác minh demo này.
