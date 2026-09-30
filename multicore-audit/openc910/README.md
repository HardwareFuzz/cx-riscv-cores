# OpenC910

Canonical [XUANTIE-RV/openc910](https://github.com/XUANTIE-RV/openc910)
production RTL instantiates two ct_top instances and has per-core reset and
hart-ID ports. The canonical smart-run integration, however, holds core 1 in
reset by default; downstream trace and PLIC observations belong to that
integration layer.

The audited canonical history contains no confirmed multi-hart HDL/RTL
defect with a complete mechanism and authoritative resolution or independent
reproduction. This directory intentionally contains no record.md files.
The OpenC910 source and smart-run artifacts were not modified.
