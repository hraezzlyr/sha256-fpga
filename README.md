# SHA256 FPGA

## 🎯 Overview
A portable, vendor-independent SHA-256 hardware accelerator implemented in VHDL
for FPGA devices.
I created this project to refresh and preserve the knowledge I gained as
an FPGA engineer and to further develop my skills in FPGA design and
low-level security. The main features are:
- vendor-independent RTL
- functional verification
- FPGA resource and performance analysis
- future RISC-V SoC integration

## 🛠️ Toolchain
- Language: `VHDL-2008`
- Simulator: `GHDL 4.1.0`
- Waveform viewer: `Surfer`
- Build system: `Make`
- Verification framework: `VUnit`

## ✅️ Verification
I use `GHDL` to compile a VHDL code. It allows me to display the results of
its work as time-series plots in `Surfer`. `VUnit` is used as a verification
framework to test automation, including organizing, running, and
receiving results. To see a more detailed test strategy, take a look at the
*/docs/verification.md* file.

## 📃 Status
| Component | Status |
| :---: | :---: |
| Message padder | implemented |
| Message padder testbenches | implemented |
| Message scheduler | planned |
| Message scheduler testbenches | planned |
| Compression engine | planned |
| Compression engine testbenches | planned |
| SHA256 integration and tesbenches | planned |
| FPGA synthesis | planned |
| Hardware tests | planned |
| RISC-V integration | planned |

# Documentation
```text
docs/
├── verification.md
└── modules/
    └── padder.md
```
- *docs/verification.md* - detailed testing strategy
- *docs/modules/padder.md* - padder's architecure, supported cases,
design decisions


## 🏗️ Building
TODO - Build system is not implemented yet.

## 📝 License
This project is licensed under the Apache License 2.0.
See the `LICENSE` file for details.