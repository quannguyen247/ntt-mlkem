# 12-bit NTT Microarchitecture for ML-KEM Optimized for Medical Edge Devices

**Project:** 12-bit Number Theoretic Transform (NTT) microarchitecture for the ML-KEM post-quantum cryptography algorithm, focusing on hardware resource optimization for deployment on edge devices in the biomedical/healthcare sector.

This project is targeted for hardware implementation and physical testing on the **KV260** (Xilinx Kria KV260 Vision AI) FPGA/SoC.

## Development Team: IC4Duck
- **Nguyen Dong Quan**
- **Huynh Nhat Phat**
- **Nguyen Duc Phuc**
- **Ngo Gia Bao**

---

## Repository Structure and Usage Guidelines

### Artix-7 200 MHz core benchmark

Read [ARTIX200.md](Implementation/benchmark/ARTIX200.md) for the
`xc7a100tfgg676-3` OOC optimization, reproducible Vivado project, regression,
power-estimation method and paper comparison. The optimized multiplier adds
one pipeline cycle. Rebuild the KV260 design before testing this RTL on a board;
previously generated KV260 bitstreams contain the older RTL.

### KV260 sensor demo (Linux)

Read [DEMO_GUIDE.md](Implementation/kv260_axi_test/DEMO_GUIDE.md) for tools,
Vivado GUI/build steps, the one-button MAX30102 → ARM → AXI → NTT/INTT demo,
PASS/NOT RUN criteria and AI-agent handoff. Generated projects and captured
sensor data stay local. The root Makefile is a legacy flow, not this demo's test.

The directories in this repository are strictly organized by purpose. All team members must adhere to the following usage rules:

### 1. 📁 Implementation/
- **Purpose:** Main project directory.
- **Usage:** Members should place all official HDL source files (Verilog/VHDL), IP Cores, and main Vivado/Vitis project configuration files here. This is used for system integration, synthesis, and final deployment onto the KV260 hardware.

### 2. 📁 Test/
- **Purpose:** Testing and sandbox environment for tinkering. 
- **Usage:** Contains simulation scripts for individual modules, draft testbenches, and isolated debug tests. Feel free to experiment here without breaking the main project structure.

### 3. 📁 PQClean/ & 📁 Kyber-Round3-KAT/
- **Purpose:** Standard C source code (Reference Implementations / Known Answer Tests).
- **Usage:** Served as the golden reference. The output of our hardware HDL design will be compared against these software libraries to ensure functional correctness.
- ⚠️ **CRITICAL NOTE:** These are original source directories and **MUST NOT BE MODIFIED OR TOUCHED**. They are governed by their own independent licenses found within their respective folders. Therefore, no personal code commits should be made into these two directories.

---

## License
This project is distributed under the **[Apache License 2.0](LICENSE)** (Copyright 2026 IC4Duck). 
*(Note: This license applies exclusively to the source code created by the team in the Implementation/ and KV260_Test/ directories, and does not override the original licenses of the PQClean/ and Kyber-Round3-KAT/ reference directories).*
