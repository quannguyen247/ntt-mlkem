# Đặc tả lõi NTT/INTT 12 bit

Tài liệu này mô tả đúng RTL đang có trong repository. Đây là đặc tả của một
lõi biến đổi NTT/INTT dùng cho miền tham số ML-KEM, không phải đặc tả của một
bộ tăng tốc ML-KEM hoàn chỉnh.

## 1. Phạm vi và chuẩn tham chiếu

| Thuộc tính | Giá trị |
|---|---:|
| Bậc đa thức | `n = 256` |
| Mô-đun | `q = 3329` |
| Độ rộng hệ số | 12 bit, miền chuẩn `0..3328` |
| Căn nguyên thủy dùng sinh oracle | `ζ = 17` |
| Montgomery radix | `R = 2^16` |
| `R^-1 mod q` | `169` |
| Hướng thuận | Cooley-Tukey, `len = 128, 64, ..., 2` |
| Hướng nghịch | Gentleman-Sande, `len = 2, 4, ..., 128`, sau đó scale |

[FIPS 203](https://doi.org/10.6028/NIST.FIPS.203) là nguồn chuẩn cho ML-KEM.
[Đặc tả Kyber v3.02](https://pq-crystals.org/kyber/data/kyber-specification-round3-20210804.pdf)
là nguồn lịch sử của cấu trúc NTT đã dùng khi phát triển RTL. Khi hai tài liệu
khác nhau, FIPS 203 có ưu tiên cao hơn. RTL hiện chỉ hiện thực NTT và INTT;
chưa có lấy mẫu, `BaseCaseMultiply`, đóng gói khóa, encapsulation hoặc
decapsulation.

## 2. Quy ước toán học

Phép cộng và trừ luôn trả kết quả chuẩn trong `0..q-1`. Bộ nhân
`ntt_mod_mul_12b` tính:

```text
MontMul(a, b) = a * b * R^-1 mod q
```

Phần giảm Montgomery dùng `QINV = 3327`, thỏa
`q * QINV = -1 mod 2^16`:

```text
t = a * b
m = (t * QINV) mod 2^16
u = (t + m * q) / 2^16
r = u >= q ? u - q : u
```

Các hằng số nhân với `q` và `QINV` được triển khai bằng dịch và cộng/trừ;
phép nhân dữ liệu 12 x 12 được ép ánh xạ LUT bằng `use_dsp = "no"`. Bộ nhân có
độ trễ năm chu kỳ. Butterfly thêm các thanh ghi căn chỉnh dữ liệu và valid.

INTT giữ quy ước `invntt_tomont` của Kyber:

```text
INTT(NTT(a)) = a * R mod q
```

Muốn nhận lại hệ số chuẩn `a`, phía host nhân kết quả với `R^-1 = 169 mod q`.
Không được bỏ bước này khi đối chiếu round-trip.

## 3. Vi kiến trúc

```text
controller -> AGU -> RAM hai bank -> butterfly pipeline -> FIFO địa chỉ -> RAM
                          ^                |
                          |          twiddle ROM
```

- `ntt_controller.v`: FSM `IDLE`, `RUN`, `SCALE`; phát `len`, vị trí, chỉ số
  twiddle và đếm 128 butterfly mỗi tầng. INTT có thêm 256 lượt scale.
- `ntt_agu.v`: tạo hai địa chỉ cho mỗi butterfly theo `len`, vị trí và block.
- `ntt_ram_dual.v`: 256 hệ số chia thành hai bank 128 x 12 bit. Parity của địa
  chỉ chọn bank, cho phép đọc và ghi hai hệ số mỗi chu kỳ.
- `ntt_twiddle_rom.v` và `ntt_funcs.vh`: bảng twiddle thuận/nghịch 128 phần tử.
- `ntt_mod_mul_12b.v`: pipeline Montgomery năm chu kỳ, không DSP.
- `ntt_butterfly.v`: dùng chung datapath cho NTT, INTT và pha scale.
- `ntt_core_top.v`: ghép datapath, FIFO địa chỉ write-back và giao tiếp nạp/đọc
  hệ số bên ngoài.

Một butterfly được tái sử dụng cho toàn bộ phép biến đổi. Lựa chọn này giảm
tài nguyên chuyên dụng, đổi lại số chu kỳ cao hơn kiến trúc nhiều butterfly.
`start` chỉ được chấp nhận ở cạnh lên khi core không bận. Trong lúc `busy=1`,
RAM thuộc quyền datapath; ngoài thời gian đó, cổng `ext_*` dùng để nạp hoặc đọc.

## 4. Giao tiếp lõi

| Tín hiệu | Hướng | Rộng | Ý nghĩa |
|---|---|---:|---|
| `clk` | vào | 1 | Clock đồng bộ |
| `rst_n` | vào | 1 | Reset tích cực mức thấp |
| `start` | vào | 1 | Xung bắt đầu một chu kỳ |
| `mode` | vào | 1 | `0`: NTT, `1`: INTT |
| `ext_we` | vào | 1 | Cho phép ghi RAM khi core rảnh |
| `ext_addr` | vào | 8 | Chỉ số hệ số `0..255` |
| `ext_din` | vào | 12 | Hệ số ghi vào |
| `ext_dout` | ra | 12 | Hệ số đọc ra |
| `busy` | ra | 1 | Datapath đang sở hữu RAM |
| `done` | ra | 1 | Xung hoàn tất |

Kết quả regression tại 200 MHz cho thấy `start` đến `done` là 905 chu kỳ với
NTT và 1161 chu kỳ với INTT. Tương ứng 4,525 us và 5,805 us. Các số này không
gồm 256 lần ghi input và 256 lần đọc output qua wrapper AXI.

## 5. Wrapper AXI4-Lite của demo

`Demo/rtl/ntt_core_axi_lite.v` chỉ là lớp tích hợp KV260. Base address trong
block design là `0xA0000000`.

| Offset | Tên | Quyền | Bit / hành vi |
|---:|---|---|---|
| `0x000` | `CONTROL` | R/W | bit 0 `start`, bit 1 `mode` |
| `0x004` | `STATUS` | R | bit 0 `busy`, bit 1 `done_sticky` |
| `0x008` | `CLEAR` | R/W | ghi bit 0 bằng 1 để xóa `done_sticky` |
| `0x400 + 4*i` | `COEFF[i]` | R/W | bit 11:0, với `i = 0..255` |

Địa chỉ không căn bốn byte trả `DECERR`. Ghi status, truy cập coefficient khi
core bận, hoặc phát `start` khi core bận trả `SLVERR`. Ghi coefficient phải bật
hai byte strobe thấp. `irq` phản ánh `done_sticky`.

## 6. Kết quả triển khai đã kiểm chứng

### Artix-7 OOC

Flow tái lập dùng Vivado 2025.2.1, part `xc7a100tfgg676-3`, top
`ntt_core_top`, constraint 5 ns, synthesis/implementation Default,
`-mode out_of_context` và `-max_dsp 0`.

| Chỉ tiêu | Kết quả post-route |
|---|---:|
| LUT / FF | 824 / 311 |
| DSP48E1 / BRAM18 | 0 / 0 |
| WNS / TNS | +0,152 ns / 0 |
| WHS / THS | +0,078 ns / 0 |
| Power total / dynamic | 148 / 64 mW |

Power là ước lượng vectorless của Vivado với switching activity mặc định 50%
và confidence `High`. Đây không phải số đo trên board và không đủ để kết luận
năng lượng thấp hơn thiết kế khác. `0 BRAM` cũng không có nghĩa là không dùng
bộ nhớ: 142 LUTRAM và 18 SRL nằm trong tổng LUT.

Tái tạo báo cáo bằng một entry point:

```bash
python3 Demo/demo.py artix --clean
```

### KV260 tích hợp

Block design dùng K26, PL 200 MHz, wrapper NTT tại `0xA0000000` và GPIO sensor
tại `0xA0010000`. Timing, DRC, bitstream và XSA được tạo bằng:

```bash
python3 Demo/demo.py build --clean
```

Fresh build ngày 13/09/2026 có WNS `+1,216 ns`, WHS `+0,013 ns`, không có
failing endpoint và không có DRC error. DRC còn bốn warning trong AXI downsizer
sinh bởi IP Integrator (`PDCN-1569` và `RTSTAT-10`); chúng được giữ trong
`Demo/output/i2c_drc.rpt`, không bị tắt để làm đẹp báo cáo. Manifest local giữ
hash source cùng hash bitstream, XSA và PS init.

Kết quả Artix OOC dùng để báo PPA của core. Kết quả KV260 dùng để chứng minh
khả năng tích hợp PS, AXI và sensor. Không trộn hai phạm vi thành một phép đo.

## 7. Cơ sở xác minh tính đúng

Oracle trong `Demo/demo.py` tự sinh twiddle từ căn 17 và phép đảo 7 bit; nó
không đọc ROM twiddle của RTL. Mỗi vector kiểm tra cả NTT, INTT độc lập và quan
hệ round-trip Montgomery. Testbench duy nhất là
`Implementation/testbench/tb_ntt_core_top.sv`.

```bash
# 5 directed + 32 random, mỗi input sinh một case NTT và một case INTT
python3 Demo/demo.py regression --out build/regression --random 32

# Thêm vét cạn 3329^2 cặp đầu vào chuẩn của multiplier
python3 Demo/demo.py regression --out build/regression-units --random 128 --units

# Hai case tương tự trong XSim và tạo waveform WDB/WCFG
python3 Demo/demo.py waveform --clean
```

Mốc hiện tại:

- RTL regression: 74 phép biến đổi, 18.944 hệ số.
- Routed functional regression đã lưu trong báo cáo dự án: 74 phép biến đổi,
  18.944 hệ số.
- Multiplier exhaustive: 11.082.241 cặp canonical, đồng thời kiểm tra độ trễ
  năm chu kỳ.
- Demo khi có kit: bốn block, 1.024 hệ số mỗi chiều và round-trip chuẩn hóa.

Các test trên chứng minh sự phù hợp với oracle và quy ước đã nêu, không thay
thế kiểm định mật mã, phân tích side-channel hay chứng nhận FIPS.

## 8. Đối chiếu công trình liên quan

| Thiết kế | FPGA | LUT | FF | DSP | BRAM18 | MHz | Chu kỳ NTT/INTT |
|---|---|---:|---:|---:|---:|---:|---:|
| Kieu-Do-Nguyen et al., hybrid gamma x2 | XC7A100T-FGG676-3 | 541 | 680 | 0 | 4 | 417 | 461 / 461 |
| Sonbul et al. | XC7A100T-CSG324-3 | 503 | 545 | 1 | 2 | 200 | 1029 / 1285 |
| Lõi này, batch Default | XC7A100T-FGG676-3 | 824 | 311 | 0 | 0 | 200 | 905 / 1161 |

Thiết kế này không sao chép datapath gamma/quarter-square của bài 2024 và
không dùng Barrett pipeline của bài 2026. Điểm chọn thiết kế là một butterfly
dùng chung, Montgomery pipeline, RAM phân tán hai bank và không dùng DSP/BRAM.
So với bài 2026, lõi hiện tại ít hơn 124 chu kỳ cho mỗi chiều nhưng dùng nhiều
LUT hơn. So với hybrid gamma x2, lõi hiện tại chậm hơn và dùng nhiều LUT hơn,
đổi lại không dùng bốn BRAM. Đây là đối chiếu trade-off; khác package, tool,
strategy và ranh giới I/O nên không được tuyên bố thắng toàn diện.

## 9. Nguồn thiết kế và truy vết

| Nội dung cần trả lời | Nguồn quy chuẩn / bằng chứng |
|---|---|
| Tham số và thuật toán ML-KEM | [NIST FIPS 203](https://csrc.nist.gov/pubs/fips/203/final) |
| NTT Kyber và mã tham chiếu lịch sử | [CRYSTALS-Kyber resources](https://pq-crystals.org/kyber/resources.shtml) |
| Kiến trúc NTT FPGA liên quan | [Kieu-Do-Nguyen et al., 2024](https://doi.org/10.3390/info15070400) |
| Kiến trúc pipeline/Barrett liên quan | [Sonbul et al., 2026](https://doi.org/10.3390/electronics15030513) |
| Ràng buộc ánh xạ DSP | [AMD UG901, USE_DSP](https://docs.amd.com/r/2024.1-English/ug901-vivado-synthesis/USE_DSP) |
| Ý nghĩa và giới hạn power estimate | [AMD UG907](https://docs.amd.com/r/en-US/ug907-vivado-power-analysis-optimization) |
| Giao tiếp MAX30102 | [Analog Devices MAX30102 datasheet](https://www.analog.com/media/en/technical-documentation/data-sheets/max30102.pdf) |
| RTL thực thi | `Implementation/rtl/` |
| Oracle, regression và flow Vivado | `Demo/demo.py`, `Demo/demo.tcl` |

Khi trả lời “RTL từ đâu ra”, câu chính xác là: nhóm tự viết RTL dựa trên tham
số và thuật toán chuẩn ML-KEM/Kyber, tham khảo các trade-off kiến trúc trong hai
bài báo, rồi xác minh bằng oracle sinh độc lập, test vét cạn multiplier, RTL
regression, post-route regression và flow phần cứng. Không nói RTL được NIST
chứng nhận hoặc sao chép nguyên kiến trúc của bài báo.
