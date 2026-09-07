# Trình bày NTT bằng Vivado GUI trên KV260

Thiết kế này dùng PS cấp clock 200 MHz, VIO điều khiển NTT qua JTAG.
Chưa có ARM điều khiển NTT qua AXI hoặc cảm biến thật trong block design này.
Project `Implementation/NTT.xpr` là project làm việc khác; dùng project bên dưới cho bài demo này.

## Chuẩn bị project

1. Dùng Vivado 2025.2.1, cài board `xilinx.com:kv260_som:part0:1.4`.
2. Mở Vivado. Trong Tcl Console, thay đường dẫn repo theo máy rồi chạy:

   ```tcl
   cd C:/Users/Quan/Desktop/Github-repo/ntt-mlkem/Implementation/kv260_debug
   set ::kv260_gui_only 1
   source create_kv260_debug.tcl
   ```

   Script tạo block design và wrapper, dừng trước synthesis. Chỉ chạy khi
   chưa có project hoặc muốn tạo lại: script dùng `create_project -force`.
   Nếu đã có chỉnh sửa GUI, lưu bản sao trước khi tạo lại.
3. Những lần sau chọn **Open Project**, mở `project/ntt_kv260_debug.xpr`.
4. Trong Sources mở `ntt_kv260_debug_bd.bd`: trình bày PS → clock/reset,
   VIO → `ntt_debug_0` → `ntt_core_top`. Mở PS kiểm tra PL0 = 200 MHz.
5. Bấm **Run Synthesis**, sau đó **Run Implementation**, rồi **Open Implemented Design**.
6. Chọn **Reports → Timing → Report Timing Summary**. Kiểm tra `clk_pl_0`
   có period 5 ns, setup/hold không có endpoint vi phạm. Không dùng số OOC
   để thay cho timing của toàn bộ thiết kế đã route.
7. Bấm **Generate Bitstream**. Dùng `.bit` và `.ltx` cùng lần build trong
   `project/ntt_kv260_debug.runs/impl_1/`.
8. Để các script test dùng đúng bản vừa tạo, chép bằng File Explorer:
   `ntt_kv260_debug_bd_wrapper.bit` và `.ltx` từ thư mục trên vào `output/`,
   đổi tên thành `ntt_kv260_debug.bit` và `ntt_kv260_debug.ltx`.
   Khi cần XSA mới: **File → Export → Export Hardware**, chọn Include bitstream.

## Nạp và thao tác VIO

1. Cấp nguồn 12 V cho KV260 và nối USB-A–micro-USB vào J4.
2. Đóng Hardware Manager. Trong PowerShell tại `Implementation/kv260_debug`:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\init_and_program.ps1
   ```

   Script cần project đã generate: nó đọc `psu_init.tcl` trong `project/`.
   Chỉ nạp `.bit` trong Hardware Manager không thay thế bước khởi tạo PS.
   Nếu cài AMD tools ở chỗ khác, sửa đường dẫn XSCT trong script PowerShell.
3. Mở Hardware Manager → Open Target → Auto Connect; chọn `xck26_0`.
   Trong Tcl Console của Vivado:

   ```tcl
   set dev [get_hw_devices xck26_0]
   set_property PROBES.FILE [file normalize output/ntt_kv260_debug.ltx] $dev
   set_property BSCAN_SWITCH_USER_MASK 0001 $dev
   refresh_hw_device $dev
   ```

4. Mở VIO dashboard, thêm các probe; xem bảng probe trong README.
   Các giá trị Output phải được **Commit** để có hiệu lực.
5. Reset: `probe_out1=0` (start), `probe_out3=0` (write enable),
   `probe_out0=0`, Commit; sau đó `probe_out0=1`, Commit.
6. Demo RAM: khi `ext_we=0`, đặt `probe_out4=2A` (hex, địa chỉ 42),
   `probe_out5=ABC` (hex), Commit. Đặt `probe_out3=1`, Commit;
   đặt lại `0`, Commit; refresh input, `ext_dout` phải là `ABC`.
   Giữ write enable bằng 0 khi đổi địa chỉ để tránh ghi nhầm RAM.
7. Trước khi chạy NTT phải nạp đủ 256 hệ số; một lần ghi RAM chưa phải test NTT.
   Sau khi nạp: mode=0, start=1 Commit rồi start=0 Commit.
   Quan sát `done_sticky=1`. Busy/done có thể quá ngắn để nhìn thấy trong GUI.
   Đổi địa chỉ và refresh để đọc kết quả. Reset trước lượt test kế tiếp.

## Kiểm tra đủ 256 hệ số

Việc nhập 256 số bằng tay dễ nhầm. Dùng script kiểm tra đầy đủ sau phần
thao tác VIO. Đóng Hardware Manager trước khi chạy Vivado batch:

```powershell
python ..\vector\ntt_gen.py
& 'C:\AMDDesignTools\2025.2.1\Vivado\bin\vivado.bat' -mode batch -source .\hardware_ntt_vector_test.tcl
Get-Content .\output\hardware_ntt_vector_test.log
```

Script đọc `tv_all.mem`, chọn case index 1 (all-max, 3328), nạp 256 hệ số,
chạy NTT rồi so sánh 256 đầu ra. Kết quả mong đợi:

```text
COEFFICIENTS_CHECKED=256
MISMATCHES=0
HARDWARE_NTT_VECTOR_TEST_PASS
```

Các report/log lưu sẵn trong `output/` thuộc phiên cũ ngày 12/08/2026:
timing WNS +0.650 ns tại 200 MHz và test NTT pass. Sau khi thay RTL/build,
phải kiểm tra lại; những file cũ không chứng minh bản mới đã chạy trên board.
`done_sticky=1` chỉ chứng minh kết thúc, không chứng minh kết quả đúng.
