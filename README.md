# 12-bit NTT/INTT core for ML-KEM

IC4Duck phát triển một lõi NTT/INTT 256 hệ số, mô-đun 3329, hướng tới thiết bị
edge có tài nguyên hạn chế. Lõi dùng chung datapath thuận/nghịch, một butterfly,
Montgomery multiplier ánh xạ LUT và RAM phân tán hai bank. Demo KV260 nối
MAX30102, Cortex-A53, AXI4-Lite và lõi PL thành một flow có bằng chứng CSV/JSON.

Đây là lõi NTT/INTT, chưa phải một hiện thực ML-KEM hoàn chỉnh. Dữ liệu sensor
trong demo cũng chưa được mã hóa và các giá trị BPM/SpO2 chưa được hiệu chuẩn.

## Chạy nhanh

```bash
make test          # 74 phép NTT/INTT, 18.944 hệ số
make demo-doctor   # kiểm tra tool và độ mới của artifact KV260
make demo          # mở giao diện demo một nút
```

Các flow còn lại vẫn dùng cùng entry point `Demo/demo.py`:

```bash
make artix         # OOC Artix-7 200 MHz và báo cáo PPA
make demo-build    # dựng lại bitstream/XSA KV260
make demo-wave     # tạo waveform XSim tự kiểm tra
```

## Cấu trúc repository

```text
ntt-mlkem/
├── Implementation/
│   ├── rtl/               # lõi NTT/INTT synthesizable
│   ├── testbench/         # testbench self-checking dùng chung
│   ├── constraint/        # clock OOC 5 ns
│   └── vector/            # golden model lịch sử của repo
├── Demo/
│   ├── demo.py            # entry point cho regression, PPA và demo board
│   ├── demo.tcl           # backend duy nhất cho Vivado, XSim và XSCT
│   ├── firmware/          # A53 freestanding
│   ├── rtl/               # wrapper AXI4-Lite của KV260
│   └── README.md
├── Docs/
│   └── SPEC.md            # đặc tả, nguồn tham khảo và traceability
└── Makefile
```

`Demo/project`, `Demo/output`, `Demo/waveform` và `build` là artifact local đã
được ignore. Bitstream, XSA, ELF, dữ liệu sinh lý và waveform database không
được commit.

Đọc [đặc tả thiết kế](Docs/SPEC.md) để xem quy ước toán học, register map,
phương pháp xác minh, PPA và nguồn tham khảo. Đọc [hướng dẫn demo](Demo/README.md)
trước khi nạp KV260.

## Nhóm phát triển

- Nguyen Dong Quan
- Huynh Nhat Phat
- Nguyen Duc Phuc
- Ngo Gia Bao

## License

Mã nguồn do nhóm tạo được phát hành theo [Apache License 2.0](LICENSE).
