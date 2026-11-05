import os
from vunit import VUnit

# Get project home dir
home_path = os.path.join(os.path.dirname(__file__), "../..")
rtl_path = os.path.join(home_path, "rtl/sha256_padder")
tb_path = os.path.join(home_path, "tb/sha256_padder")

# Set GHDL as the VUnit simulator
os.environ["VUNIT_SIMULATOR"] = "ghdl"

# Create VUnit instance by parsing command line arguments
vu = VUnit.from_argv()

# Optionally add VUnit's builtin HDL utilities for
# checking, logging, communication...
# See http://vunit.github.io/hdl_libraries.html.
vu.add_vhdl_builtins()

vu.add_random()

# Create library 'lib'
lib_tb = vu.add_library("sha256_tb")

# Add all needed RTL files
lib_tb.add_source_files(os.path.join(rtl_path, "sha256_padder.vhd"))

# Add all needed tesbench files
lib_tb.add_source_files(os.path.join(tb_path, "sha256_padder_pkg_tb.vhd"))
lib_tb.add_source_files(os.path.join(tb_path, "sha256_padder_tb.vhd"))

# Run vunit function
vu.main()