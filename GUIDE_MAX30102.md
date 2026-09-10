# Hướng dẫn MAX30102 trên KV260

Hướng dẫn hiện hành: [KV260 demo](Implementation/kv260_demo/README.md).

File này thay thế bản nháp AXI IIC trước đây. Demo thực dùng ARM điều khiển
AXI GPIO để tạo I²C: J2.1/SCL → H12, J2.3/SDA → E10.
USB JTAG/UART là micro-USB J4. Làm theo runbook để chuẩn bị nguồn/dây,
build project, mở app và kiểm tra NTT/INTT.
