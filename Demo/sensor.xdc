# KV260 validation pinout; official kv260_bist pin.xdc: HDA11=H12, HDA12=E10.
set_property PACKAGE_PIN H12 [get_ports {sensor_tri_io[0]}]
set_property PACKAGE_PIN E10 [get_ports {sensor_tri_io[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sensor_tri_io[*]}]
# Asynchronous software-bitbanged I2C; not a synchronous external data bus.
set_false_path -from [get_ports {sensor_tri_io[*]}]
set_false_path -to [get_ports {sensor_tri_io[*]}]
