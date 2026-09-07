# KV260 sensor → ARM → AXI → NTT/INTT

Hướng dẫn chính cho người dùng và AI agents: [DEMO_GUIDE.md](DEMO_GUIDE.md).

Từ root repo Linux có artifact đã build và PySide6:

```bash
export VITIS_HOME=/home/quan/tools/Xilinx/2025.2.1/Vitis
python3 Implementation/kv260_axi_test/simple_demo.py
```

Một nút thu 1024 cặp raw, kiểm tra tín hiệu rồi ARM đưa 256 cặp cuối qua
4 khối NTT/INTT trên PL. Tín hiệu bị loại → NTT/INTT chưa chạy.
PASS so 1024 hệ số mỗi chiều và round-trip sau chuẩn hóa Montgomery.
BPM/SpO₂ là ước lượng demo. Project/output local được tái tạo bằng Tcl.
