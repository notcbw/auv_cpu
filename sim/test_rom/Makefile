AS := riscv32-elf-as
LD := riscv32-elf-ld
OBJCOPY := riscv32-elf-objcopy

SRCS := test.s
OBJS := $(patsubst %.s, %.o, $(SRCS))
LD_SCRIPT := auv.ld
OUTPUT_ELF := test.elf
OUTPUT_MEM := test.mem

.PHONY: all
all: check_toolchain $(OUTPUT_MEM)

.PHONY: check_toolchain
check_toolchain:
	@command -v $(AS) >/dev/null 2>&1 || { echo "Error: riscv32-elf toolchain not found."; exit 1; }
	@echo "RISC-V toolchain detected."

%.o: %.s
	$(AS) -march=rv32e_zicsr_zba_zbs -mabi=ilp32e -o $@ $<

$(OUTPUT_ELF): $(OBJS)
	$(LD) -o $@ $< -T $(LD_SCRIPT)

$(OUTPUT_MEM): $(OUTPUT_ELF)
	$(OBJCOPY) -O verilog --verilog-data-width 4 $< $@
	@echo "Generated bootrom file $@."

.PHONY: clean
clean:
	rm $(OBJS) $(OUTPUT_ELF) $(OUTPUT_MEM)