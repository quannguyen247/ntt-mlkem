# NTT/INTT Artix-7: 200 MHz, không DSP

## Cấu hình và kết quả hiện tại

Top `ntt_core_top`, chip `xc7a100tfgg676-3`, n=256, q=3329,
Vivado 2025.2.1 build 6403652, Linux. Benchmark core riêng ở chế độ
out-of-context (OOC); demo MAX30102/KV260 dùng project `kv260_axi_test`.

Kết quả batch sau routing ngày 09/09/2026, `build/ppa/nodsp_final`:

| Chỉ tiêu | Kết quả |
|---|---:|
| Clock | 200 MHz / 5 ns |
| WNS / TNS | +0.152 ns / 0 |
| WHS / THS | +0.078 ns / 0 |
| LUT / FF | 824 / 311 |
| DSP48E1 / BRAM18 | 0 / 0 |
| NTT / INTT, start đến done | 905 / 1161 chu kỳ |
| NTT / INTT latency | 4.525 / 5.805 us |
| Power total / dynamic, vectorless | 148 / 64 mW |
| Power confidence | High |

Timing 200 MHz được xác nhận trên core OOC, chưa phải thử FPGA vật lý.
Không coi Fmax suy từ WNS là tần số đã thử trên board. Các số 620 LUT,
1 DSP, 1 BRAM18 và 35 mW SAIF thuộc phiên bản cũ; report trong
`results/2026-09-09/` giữ làm lịch sử, không đại diện RTL hiện tại.
Report hiện tại và dấu vết kiểm chứng: [kết quả không DSP](results/2026-09-09-nodsp/README.md).

## Strategy và một file constraint chung

- Synthesis: **Vivado Synthesis Defaults**, `-mode out_of_context`, `-max_dsp 0`.
- Implementation: **Vivado Implementation Defaults**, không thêm Explore
  hay post-route physical optimization.
- Batch: `synth_design -directive Default`, `opt_design`, `place_design`,
  `phys_opt_design`, `route_design`. Vivado 2025.2.1 Default GUI có bước
  pre-route phys_opt; run đã kiểm tra không đổi kết quả so batch bỏ bước này.
- Project gốc và script mới cùng dùng `Implementation/constraint/ntt.xdc`.

Đã bỏ `core_200mhz.xdc` vốn chỉ lặp clock và hợp nhất `ooc_clock.xdc`.
XDC chung chứa clock 5 ns; `HD.CLK_SRC=BUFGCTRL_X0Y0` là BUFG giả định
của mạch bao quanh phục vụ OOC hold/clock analysis, không phải chân board.
Các giá trị switching activity 50% gốc được giữ nguyên để so power cùng giả định.

Không thêm false-path, multicycle hay nới clock để che đường chậm. Các đường
I/O ngoài core chưa có input/output delay vì chưa xác định mạch bao quanh.
Khi tích hợp cần đóng timing toàn hệ thống. Không lấy XDC này làm pinout KV260.

## Ba lỗi đã gặp

| Lỗi | Nguyên nhân | Sửa |
|---|---|---|
| Project 1-5713 | Metadata cũ và thông báo board rỗng của Vivado 2025.2.1 | Bỏ metadata cũ; riêng thông báo board rỗng chuyển INFO |
| BD 41-1661: PS locked | Artix project còn BD Zynq UltraScale+ của KV260 | Gỡ tham chiếu BD/wrapper khỏi XPR, giữ file BD |
| Synth 8-3323: Used=1/Available=0 | `max_dsp=0` mâu thuẫn `use_dsp="yes"` | Đổi RTL sang `use_dsp="no"`, report xác nhận 0 DSP |

Artix không có PS ARM; không thể upgrade IP Zynq để chạy trên Artix.
Available=0 là ngân sách synthesis do người dùng đặt, không phải chip không có DSP.
Đã tái hiện Project 1-5713 trên project mới hoàn toàn, chọn Part và không
có BD. Vì thế không tuyên bố đã sửa lỗi bên trong Vivado. Script lưu quy tắc
`set_msg_config -id {Project 1-5713} -string {Board part ''} -new_severity INFO`.
Thông báo vẫn có trong log; cảnh báo board có tên cụ thể không đổi. Không
cài board giả hay gán board KV260/AC701 cho chip benchmark để làm mất cảnh báo.
Lần sửa này giữ nguyên pipeline bộ nhân 5 chu kỳ, butterfly 7 stage, Montgomery,
twiddle, bộ nhớ, FIFO và giao tiếp. Chỉ đổi ánh xạ phép nhân sang LUT.

## Chạy project đang có

Đóng project NTT trong Vivado trước khi chạy script sửa. Nếu đã sửa bên ngoài
GUI, đóng cửa sổ cũ **không lưu đè**, rồi mở lại XPR.
Chạy từ repo `/home/quan/Desktop/github-repo/ntt-mlkem` (trên máy này cùng
checkout với đường dẫn Samsung).

```sh
export PATH=/home/quan/tools/Xilinx/2025.2.1/Vivado/bin:$PATH
python3 Implementation/benchmark/regress.py --out build/ppa/vectors
vivado -mode batch -source Implementation/benchmark/repair_project.tcl
```

Script lưu XPR trong `build/ppa/project-backup-<thời gian>/NTT.xpr`, bỏ
tham chiếu board/BD cũ và cấu hình Default. File BD không bị xóa.
Vivado 2025.2.1 từng crash khi `remove_files` trực tiếp IP bị khóa;
script bỏ tham chiếu trong XPR trước khi mở để tránh đường xử lý đó.

1. Mở `Implementation/NTT.xpr`, xác nhận top `ntt_core_top`, part đúng.
2. Sources/Constraints: `constraint/ntt.xdc`.
3. Settings/Synthesis: Default, max_dsp=0, More Options=`-mode out_of_context`.
4. Settings/Implementation: Default.
5. Run Synthesis rồi Run Implementation, chạy lại khi out-of-date.
6. Open Implemented Design: Timing Summary, Utilization, Power và DRC.
7. Run Behavioral Simulation, chờ `REGRESSION_PASS`. Project đặt runtime=all
   nên tự chạy đến `$finish`; không bấm Run All thêm sau khi đã kết thúc.

Không Generate Bitstream để nạp core OOC trực tiếp lên board. Muốn demo
phần cứng, rebuild KV260 theo `../kv260_axi_test/DEMO_GUIDE.md` rồi test lại;
bitstream cũ không chứa RTL vừa sửa.

## Project sạch và batch

```sh
vivado -mode batch -source Implementation/benchmark/create_project.tcl \
  -tclargs build/ppa/artix_default
vivado -mode batch -source Implementation/benchmark/run_ooc.tcl \
  -tclargs build/ppa/reproduce_nodsp
```

Lệnh 1 tạo `build/ppa/artix_default/ntt_artix200.xpr`; chọn output khác nếu
project tồn tại. Lệnh 2 chạy P&R, lưu `routed.dcp`, `timing.rpt`,
`utilization.rpt`, `power_vectorless.rpt`, `drc.rpt`, `route.rpt`.
`BENCHMARK_FINISHED` chỉ báo script kết thúc; phải kiểm tra WNS/WHS>=0,
TNS/THS=0, failing endpoints=0, DSP=0 và routing errors=0.

Hai DRC cảnh báo OOC còn lại: `CFGBVS-1` vì chưa có điện áp cấu hình board;
`RTSTAT-10` vì `done` chỉ xuất khỏi core. Giữ cảnh báo, không bịa điện áp
hay tắt DRC. Chúng khác ba lỗi project/IP/DSP kể trên.

## Kiểm chứng

```sh
python3 Implementation/benchmark/regress.py --out build/ppa/nodsp_regression \
  --random 128 --units
python3 Implementation/benchmark/simulate_netlist.py build/ppa/reproduce_nodsp \
  --vectors build/ppa/vectors \
  --vivado-bin /home/quan/tools/Xilinx/2025.2.1/Vivado/bin
```

Cần Python 3 và Icarus (`iverilog`, `vvp`); netlist dùng XSim. Một testbench
`testbench/tb_ntt_core_top.sv`. Reference tự sinh twiddle từ root 17/đảo 7 bit,
không lấy expected từ ROM RTL. RTL: 266 phép biến đổi / 68096 hệ số;
multiplier: 3329² = 11082241 cặp canonical, kiểm tra số học và latency 5 chu kỳ.
Routed functional: 74 phép / 18944 hệ số với vectors mặc định. Script netlist
có sinh SAIF nhưng không tự nạp vào power report chính.

INTT giữ `invntt_tomont`: `INTT(NTT(a)) = a*65536 mod 3329`.
Muốn khôi phục a chuẩn thì nhân thêm 169 mod q. Không nói NTT/INTT là
toàn bộ ML-KEM hay raw cảm biến đã được mã hóa an toàn.

## Đối chiếu paper và trình bày

| Thiết kế | Chip | LUT | FF | DSP | BRAM18 | MHz | Chu kỳ NTT/INTT |
|---|---|---:|---:|---:|---:|---:|---:|
| Paper 1 hybrid gamma, 2 butterfly [1] | XC7A100T-FGG676-3 | 541 | 680 | 0 | 4 | 417 | 461/461 |
| Paper 2 [2] | XC7A100T-CSG324-3 | 503 | 545 | 1 | 2 | 200 | 1029/1285 |
| Core này, batch Default | XC7A100T-FGG676-3 | 824 | 311 | 0 | 0 | 200 | 905/1161 |

Paper 1 dùng Vivado 2023.2, AreaOptimized_high/P&R Explore, 2 butterfly và ROM
để giảm phép nhân. Nhanh hơn và ít LUT hơn core này, nhưng cần 4 BRAM18.
Chỉ dùng hybrid gamma khi so NTT/INTT; alpha/beta là forward-only.
Core này ưu tiên không DSP/BRAM và Default 200 MHz. 0 BRAM không có nghĩa
không bộ nhớ: 160 LUT đang làm distributed RAM/SRL.

So paper 2: thêm LUT (824 so với 503), ít FF (311 so với 545), bỏ 1 DSP/2 BRAM
và ít hơn 124 chu kỳ cho mỗi phép NTT/INTT. Đây là đánh đổi, không thắng mọi PPA.
Package/tool khác và không có RTL bài báo để chạy lại cùng flow.
Chu kỳ ở đây không gồm load/readback; phải thống nhất ranh giới thao tác,
thứ tự dữ liệu và chuẩn hóa INTT khi so end-to-end. Paper 2 Eq.(8) lấy
nghịch đảo latency nhưng ghi Kbps; dùng phép biến đổi/giây hoặc us để tránh nhầm.
Nguyên lý tham khảo là pipeline/đánh đổi tài nguyên; không tuyên bố sao chép
multiplier ROM của paper 1 hay Barrett của paper 2.

Hai bài không cung cấp power định lượng trong bảng kết quả: ghi **NR**.
Không suy power từ LUT, MHz hay nhãn DSP-free. Power 148 mW/64 mW ở đây là
**Vivado post-route vectorless estimate, activity 50%, confidence High**.
High không chứng minh activity đúng với cảm biến hoặc công suất đo board.
Không so trực tiếp với 119 mW/35 mW SAIF của bản cũ để kết luận mức giảm.
Muốn chứng minh tiết kiệm năng lượng: baseline và optimized phải cùng
part/tool/clock/môi trường/workload/cửa sổ đo/phương pháp power.
Không lấy công suất trung bình gồm load/idle nhân riêng compute latency
để gọi là năng lượng một NTT.

Câu trình bày đề xuất:

> Lõi NTT/INTT 256 hệ số modulo 3329 đạt timing 200 MHz sau routing trên Artix-7
> với strategy mặc định, không DSP và BRAM. Thiết kế đánh đổi thêm LUT để
> giảm tài nguyên chuyên dụng. Công suất ước lượng trong Vivado có công bố
> giả định activity; chưa kết luận ít năng lượng hơn hai công trình tham khảo.

Trình diễn theo thứ tự: code pipeline -> XDC 5 ns -> Settings Default ->
Timing/Utilization -> log PASS -> Power kèm giả định -> bảng đối chiếu.
Demo MAX30102/KV260 chứng minh đường dữ liệu ứng dụng, không thay thế
PPA Artix và không chứng minh độ chính xác y khoa.

## Nguồn và bàn giao cho AI

1. Information2024,15,400, *Compact and Low-Latency FPGA-Based Number Theoretic
   Transform Architecture for CRYSTALS Kyber Postquantum Cryptography Scheme*,
   Section4.2/Table1: https://doi.org/10.3390/info15070400 .
2. Electronics2026,15,513, *Deeply Pipelined NTT Accelerator with Ping-Pong
   Memory and LUT-Only Barrett Reduction for Post-Quantum Cryptography*,
   Sections4.1.1–4.1.3/Tables1–2: https://doi.org/10.3390/electronics15030513 .
   PDF sửa23/07/2026 ghi tool “Vivado14.1”; chưa xác minh chuỗi version này.
3. AMD UG901 USE_DSP: https://docs.amd.com/r/2024.1-English/ug901-vivado-synthesis/USE_DSP .
4. AMD UG907 Power: https://docs.amd.com/api/khub/documents/34c_HGWWD2BlUy_tqfiKQg/content .

Giữ `dev_quan`; không sửa `form(donotedit)` hay reference sources.
Report cũ là snapshot có ngày, không ghi đè thành số của RTL mới.
Chỉ đổi strategy khi Default không đạt yêu cầu; ghi kết quả đối chứng.
Không bỏ `max_dsp=0` để che lỗi. XPR machine-local được ignore;
Tcl sửa/tạo project là nguồn tái lập quản lý bằng Git.
