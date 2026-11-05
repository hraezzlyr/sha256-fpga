VENV_DIR = .venv
PYTHON := $(VENV_DIR)/bin/python

BUILD_DIR = build/sha256_padder_out

$(PYTHON):
	python3 -m venv $(VENV_DIR)

vunit: $(PYTHON)
	$(PYTHON) -m pip install vunit-hdl

sim:
	$(PYTHON) vunit/sha256_padder/run.py --output-path $(BUILD_DIR)

wave:
	-$(PYTHON) vunit/sha256_padder/run.py \
	--gtkwave-fmt ghw \
	--output-path $(BUILD_DIR) \
	--gui

clean:
	rm -rf $(VENV_DIR)
	rm -rf build

.PHONY: vunit clean