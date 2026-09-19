#!/bin/bash
verilator --lint-only -Wall --top-module axis_npu rtl/*.v
