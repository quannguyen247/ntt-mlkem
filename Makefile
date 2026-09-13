PYTHON ?= python3
DEMO := Demo/demo.py

.PHONY: test artix demo demo-doctor demo-doctor-hw demo-build demo-wave demo-arm-test demo-latest clean

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

demo-wave:
	$(PYTHON) $(DEMO) waveform --clean

demo-arm-test:
	$(PYTHON) $(DEMO) arm-test

demo-latest:
	$(PYTHON) $(DEMO) latest

clean:
	$(RM) -r build/regression build/artix200 Demo/waveform
