# KV260 MAX30102 validation demo

Thư mục này chứa toàn bộ phần tích hợp và kiểm chứng trên KV260. RTL lõi NTT/INTT
vẫn nằm trong `Implementation/rtl`; wrapper AXI, firmware, pinout, trình điều phối
và tài liệu demo nằm ở đây để tách mã thiết kế khỏi môi trường validation.

Người trình bày chỉ chạy `demo.py`. `demo.tcl` là backend chung cho Vivado, XSCT
và XSim; không cần gọi các Tcl rời như trước.

## Chạy trong ngày demo

Từ root repository:

```bash
make demo-doctor
make demo
```

`make demo` mở giao diện. Đặt nhẹ ngón tay lên MAX30102, giữ yên và bấm
**Chạy một lượt demo**. App nạp FPGA, thu khoảng 10,24 giây dữ liệu mới, đánh
giá chất lượng rồi mới cho ARM gửi hệ số qua AXI vào NTT/INTT.

Muốn chạy không có GUI:

```bash
python3 Demo/demo.py run --quality-gate
python3 Demo/demo.py latest
```

## Cấu trúc nguồn

```text
Demo/
├── demo.py                  # entry point duy nhất cho người dùng
├── demo.tcl                 # backend Vivado, XSCT, XSim
├── firmware/                # chương trình A53 freestanding
│   ├── entry.S
│   ├── link.ld
│   ├── sensor.c
│   ├── sensor_ntt.c
│   └── test.c
├── rtl/ntt_core_axi_lite.v  # wrapper validation, không thuộc lõi OOC
├── sensor.xdc               # chân I2C trên KV260
├── README.md
```

`project/`, `output/` và `waveform/` là artifact local, được ignore. Không đưa
bitstream, XSA, ELF, dữ liệu sinh lý hoặc database waveform lên Git.

## Chuẩn bị

| Thành phần | Yêu cầu |
|---|---|
| Kit | KV260, nguồn 12 V phù hợp |
| PC tới kit | cáp USB-A–micro-USB có dữ liệu, cắm J4 JTAG/UART |
| Sensor | MAX30102 đã hàn chân, dùng 3,3 V và GND chung |
| Vivado/Vitis | 2025.2.1, hỗ trợ K26 và board preset `xilinx.com:kv260_som:part0:1.4` |
| Python | Python 3.10 trở lên; PySide6 chỉ cần cho GUI |

Đường dây đã dùng: J2.1 tới SCL và J2.3 tới SDA. XDC ánh xạ H12/E10,
LVCMOS33. Tắt nguồn trước khi đổi dây. Không suy chân nguồn theo màu dây hoặc
tự thêm pull-up khi chưa đo module.

Nếu tool không nằm trong PATH:

```bash
export VIVADO_HOME=/home/quan/tools/Xilinx/2025.2.1/Vivado
export VITIS_HOME=/home/quan/tools/Xilinx/2025.2.1/Vitis
```

Không cần SD, Linux trên kit, Vitis HLS hay BSP. Firmware tối giản chạy ở EL3,
MMU/cache tắt; mỗi lượt reset ARM và thay cấu hình PL volatile. Script không ghi
flash hoặc thẻ SD.

## Các lệnh được hỗ trợ

| Lệnh | Công dụng |
|---|---|
| `demo.py doctor` | kiểm tra tool, nguồn và độ khớp artifact |
| `demo.py doctor --hardware` | kiểm tra thêm target JTAG, không nạp PL |
| `demo.py regression` | sinh oracle độc lập và chạy RTL regression |
| `demo.py artix --clean` | OOC Artix-7 200 MHz, xuất timing/utilization/power |
| `demo.py build --clean` | tái tạo project, bitstream, XSA và manifest |
| `demo.py build --publish` | xuất artifact sau khi Generate Bitstream trong GUI |
| `demo.py waveform --clean` | chạy hai phép biến đổi trong XSim, lưu WDB/WCFG |
| `demo.py arm-test` | ba vector ARM–AXI–NTT, không cần MAX30102 |
| `demo.py run --quality-gate` | flow thật ở chế độ headless |
| `demo.py present` | GUI một nút; đây cũng là hành vi mặc định |
| `demo.py latest` | in kết quả JSON mới nhất để trình bày |

`demo.py build` từ chối ghi đè `project/`. Cờ `--clean` là lựa chọn có chủ ý
để xoá project sinh tự động và build lại; các capture trong `output/` được giữ.

## Build phần cứng

```bash
python3 Demo/demo.py build --clean
```

Backend dựng Zynq UltraScale+ PS, AXI4-Lite NTT và GPIO hai dây cho MAX30102.
NTT ở `0xA0000000`, GPIO ở `0xA0010000`, clock PL là 200 MHz. Artifact chỉ được
phát hành khi setup và hold đều không âm:

- `output/i2c.bit`
- `output/kv260_sensor.xsa`
- `output/psu_init.tcl`
- `output/i2c_timing.rpt`
- `output/i2c_drc.rpt`
- `output/build-manifest.json`

Manifest giữ hash RTL/XDC và hash artifact. `doctor` từ chối chạy khi source đã
đổi sau lần build hoặc artifact bị thay. Việc này ngăn một bitstream cũ vô tình
được dùng để chứng minh RTL mới.

Muốn chỉ tạo block design để mở trong Vivado:

```bash
python3 Demo/demo.py build --clean --prepare-only
```

Sau khi Generate Bitstream bằng GUI, dùng Python để publish và đóng dấu artifact;
không tự sửa manifest bằng tay:

```bash
python3 Demo/demo.py build --publish
```

Flow batch `build --clean` ít thao tác hơn và đã được dùng làm đường chuẩn.

## Flow dữ liệu được kiểm tra

1. Python biên dịch `sensor_ntt.c`, `entry.S`, `link.ld` thành ELF mới.
2. XSCT khởi tạo PS/DDR, nạp bitstream và ELF, rồi chạy Cortex-A53 số 0.
3. ARM đọc PART_ID `0x15` của MAX30102 ở địa chỉ I2C 7-bit `0x57`.
4. ARM thu 1024 cặp Red/IR 18-bit ở cấu hình 100 mẫu/s.
5. PC đọc đúng đợt raw đó tại breakpoint, kiểm tra mất mẫu, biên độ, drift,
   tương quan và chu kỳ. BPM/SpO2 chỉ được ước lượng khi tín hiệu đạt.
6. Nếu bị loại, PC ghi approval=0; ARM kết thúc với `completed_blocks=0` và chưa
   truy cập NTT.
7. Nếu đạt, ARM lấy 256 cặp cuối, tách mỗi giá trị 18-bit thành hai hệ số 9-bit.
   Thứ tự là red-low, red-high, IR-low, IR-high: tổng cộng 1024 hệ số.
8. ARM xử lý bốn khối 256 hệ số qua AXI, chạy NTT rồi INTT trên PL.
9. PC so đủ 1024 kết quả mỗi chiều với golden model của repo và kiểm tra
   round-trip sau khi bỏ hệ số Montgomery.

Flow sensor dùng golden model lịch sử của repo. Flow `demo.py regression` bổ sung
oracle tự sinh twiddle từ căn nguyên thủy 17, không đọc ROM RTL. Cả hai vẫn là
kiểm chứng kỹ thuật của dự án, không phải chứng nhận mật mã.

## Điều kiện kết luận

`PASS` yêu cầu đồng thời:

- raw mới được thu và quality gate chấp nhận;
- bốn block hoàn tất;
- NTT khớp 1024/1024 hệ số;
- INTT khớp 1024/1024 hệ số;
- round-trip chuẩn hoá khôi phục đúng 1024 hệ số đầu vào.

`INSUFFICIENT_SIGNAL` có exit code 0 vì flow từ chối hoạt động đúng, nhưng NTT và
INTT phải ghi `NOT_RUN`. Lỗi tool, JTAG, I2C hoặc timeout là `TEST KHÔNG HOÀN TẤT`;
chưa đủ căn cứ kết luận RTL sai.

Mỗi lượt tạo `output/sensor-ntt-TIMESTAMP/` với raw CSV, comparison CSV,
`result.json`, `hardware.log`, ELF và ảnh chụp giao diện. Giữ nguyên thư mục này
khi gặp lỗi để truy nguyên.

## Phạm vi tuyên bố

Demo chứng minh đường MAX30102 → ARM → AXI → lõi NTT/INTT và phép đối chiếu toán
học trong repo. Nó chưa phải ML-KEM hoàn chỉnh, không có basemul/PolyEngine và
không chứng minh raw cảm biến đã được mã hoá. BPM/SpO2 chưa hiệu chuẩn, không dùng
cho quyết định sức khoẻ. PPA Artix-7 do `demo.py artix` tạo là phép đo khác với
tích hợp KV260 này. Xem ranh giới và nguồn chuẩn trong `Docs/SPEC.md`.

Flow VIO cũ đã được bỏ vì tạo một đường demo phần cứng thứ hai, nhiều script và
không kiểm tra sensor–ARM–AXI. Waveform báo cáo nay do `demo.py waveform` tạo từ
testbench self-checking chính; debug live dùng evidence CSV/JSON của flow AXI.
