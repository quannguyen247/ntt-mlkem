PYTHON ?= python3
DEMO := Demo/demo.py

.PHONY: test artix demo demo-doctor demo-doctor-hw demo-build demo-build-ila demo-wave demo-arm-test demo-trigger trigger demo-latest clean

# Current self-checking RTL regression. The previous src/ flow no longer exists.
test:
	$(PYTHON) $(DEMO) regression --out build/regression --random 32

artix:
	$(PYTHON) $(DEMO) artix --out build/artix200 --clean

# One public entry point for the board demonstration.
demo:
	$(PYTHON) $(DEMO) present

demo-doctor:
	$(PYTHON) $(DEMO) doctor

demo-doctor-hw:
	$(PYTHON) $(DEMO) doctor --hardware

demo-build:
	$(PYTHON) $(DEMO) build --clean

demo-build-ila:
	$(PYTHON) $(DEMO) build --clean --ila

demo-wave:
	$(PYTHON) $(DEMO) waveform --clean

demo-arm-test:
	$(PYTHON) $(DEMO) arm-test

demo-trigger:
	$(PYTHON) $(DEMO) trigger

trigger: demo-trigger

demo-latest:
	$(PYTHON) $(DEMO) latest

clean:
	$(RM) -r build/regression build/artix200 Demo/waveform
