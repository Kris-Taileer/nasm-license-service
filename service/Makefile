NASM      := nasm
LD        := ld
NASMFLAGS := -f elf64 -g -F dwarf
SRC_DIR   := src
OBJ_DIR   := obj
BIN       := license-service

SRCS := $(wildcard $(SRC_DIR)/*.asm)
OBJS := $(patsubst $(SRC_DIR)/%.asm,$(OBJ_DIR)/%.o,$(SRCS))

.PHONY: all run clean

all: $(BIN)

$(OBJ_DIR):
	mkdir -p $(OBJ_DIR)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.asm | $(OBJ_DIR)
	$(NASM) $(NASMFLAGS) $< -o $@

$(BIN): $(OBJS)
	$(LD) -o $@ $(OBJS)

run: $(BIN)
	./$(BIN)

clean:
	rm -rf $(OBJ_DIR) $(BIN)
