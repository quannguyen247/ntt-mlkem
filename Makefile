PYTHON ?= python3
VIVADO_HOME ?=
VIVADO_BIN := $(if $(VIVADO_HOME),$(VIVADO_HOME)/bin/,)
XVLOG := $(VIVADO_BIN)xvlog
XELAB := $(VIVADO_BIN)xelab
XSIM := $(VIVADO_BIN)xsim
VIVADO := $(VIVADO_BIN)vivado

RTL := $(wildcard Implementation/rtl/modules/*.v)
TB := Implementation/testbench/tb_ntt_core_top.sv

.PHONY: test impl

test:
	$(PYTHON) Implementation/vector/ntt_gen.py 32
	$(XVLOG) --sv -i Implementation/rtl/utils $(TB) $(RTL)
	$(XELAB) tb_ntt_core_top -s ntt_ip_tb
	mkdir -p build
	$(XSIM) ntt_ip_tb -R > build/xsim.log
	grep -Fq '*** ALL TESTS PASSED ***' build/xsim.log
	tail -n 6 build/xsim.log

impl:
	$(VIVADO) -mode batch -source Implementation/run_impl.tcl
