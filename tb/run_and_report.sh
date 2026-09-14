#!/bin/bash
echo "Running tests..."
make clean
make

echo ""
echo "Generating Verilator Code Coverage Report..."
verilator_coverage --annotate annotated_src coverage.dat > code_coverage.log
echo "Code coverage report saved to tb/code_coverage.log"
echo "Annotated source files saved to tb/annotated_src/"

echo ""
echo "Simulation Logs:"
echo "Simulation log saved to tb/sim.log"
echo "Functional coverage saved to tb/coverage.xml"
