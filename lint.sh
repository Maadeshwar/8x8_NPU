#!/bin/bash
verilator --lint-only -Wall --top-module npu_top rtl/*.v
