VERILATOR := verilator

.PHONY: all
all: clean check_toolchain build run

.PHONY: check_verilator
check_toolchain:
	@command -v $(VERILATOR) >/dev/null 2>&1 || { echo "Error: verilator not found."; exit 1; }
	@echo "Verilator detected."

.PHONY: build
build: auv_sim.sv check_toolchain
	$(VERILATOR) --binary -j 0 --timing --trace -sv -I'$(shell pwd)/../rtl' $<

.PHONY: run
run: obj_dir/Vauv_sim
	./obj_dir/Vauv_sim

.PHONY: trace
trace: dump.vcd
	gtkwave dump.vcd

.PHONY: clean
clean:
	rm -rf obj_dir dump.mem dump.vcd