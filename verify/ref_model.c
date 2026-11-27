#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

enum { IMEM_WORDS = 1024, DMEM_BYTES = 4096 };
static uint32_t program[IMEM_WORDS];
static uint32_t regs[32];
static uint8_t memory[DMEM_BYTES];

static uint32_t sext(uint32_t value, unsigned bits) {
    uint32_t sign = 1u << (bits - 1);
    return (value ^ sign) - sign;
}

static void fail(unsigned index, const char *message, uint32_t expected,
                 uint32_t actual) {
    fprintf(stderr, "retirement %u: %s: expected 0x%08" PRIx32
                    ", got 0x%08" PRIx32 "\n", index, message, expected, actual);
    exit(1);
}

static void check(unsigned index, const char *name, uint32_t expected,
                  uint32_t actual) {
    if (expected != actual) fail(index, name, expected, actual);
}

static uint32_t read_memory(unsigned index, uint32_t address, unsigned size) {
    if (address > DMEM_BYTES - size || address % size)
        fail(index, "invalid load address", 0, address);
    uint32_t value = 0;
    for (unsigned byte = 0; byte < size; ++byte)
        value |= (uint32_t)memory[address + byte] << (8 * byte);
    return value;
}

static void write_memory(unsigned index, uint32_t address, unsigned size,
                         uint32_t value) {
    if (address > DMEM_BYTES - size || address % size)
        fail(index, "invalid store address", 0, address);
    for (unsigned byte = 0; byte < size; ++byte)
        memory[address + byte] = (uint8_t)(value >> (8 * byte));
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: ref_model program.hex expected_retirements\n");
        return 2;
    }
    FILE *hex = fopen(argv[1], "r");
    if (!hex) {
        perror(argv[1]);
        return 2;
    }
    unsigned program_size = 0;
    while (program_size < IMEM_WORDS &&
           fscanf(hex, "%" SCNx32, &program[program_size]) == 1)
        ++program_size;
    fclose(hex);
    unsigned expected_count = (unsigned)strtoul(argv[2], NULL, 10);
    uint32_t pc = 0;

    for (unsigned index = 0; index < expected_count; ++index) {
        uint32_t trace_pc, trace_instr, trace_value, trace_addr, trace_wdata;
        unsigned trace_rd, trace_store;
        char tag[16];
        if (scanf("%15s %" SCNx32 " %" SCNx32 " %x %" SCNx32
                  " %x %" SCNx32 " %" SCNx32,
                  tag, &trace_pc, &trace_instr, &trace_rd, &trace_value,
                  &trace_store, &trace_addr, &trace_wdata) != 8) {
            fprintf(stderr, "missing or malformed trace at retirement %u\n", index);
            return 1;
        }
        if (pc & 3u || pc / 4 >= program_size)
            fail(index, "invalid instruction address", 0, pc);
        uint32_t instr = program[pc / 4];
        check(index, "PC", pc, trace_pc);
        check(index, "instruction", instr, trace_instr);
        uint32_t opcode = instr & 0x7f;
        uint32_t rd = (instr >> 7) & 31;
        uint32_t f3 = (instr >> 12) & 7;
        uint32_t rs1 = (instr >> 15) & 31;
        uint32_t rs2 = (instr >> 20) & 31;
        uint32_t f7 = instr >> 25;
        uint32_t a = regs[rs1], b = regs[rs2];
        uint32_t imm_i = sext(instr >> 20, 12);
        uint32_t imm_s = sext(((instr >> 25) << 5) | ((instr >> 7) & 31), 12);
        uint32_t imm_b = sext((((instr >> 31) & 1) << 12) |
                              (((instr >> 7) & 1) << 11) |
                              (((instr >> 25) & 63) << 5) |
                              (((instr >> 8) & 15) << 1), 13);
        uint32_t imm_j = sext((((instr >> 31) & 1) << 20) |
                              (((instr >> 12) & 255) << 12) |
                              (((instr >> 20) & 1) << 11) |
                              (((instr >> 21) & 1023) << 1), 21);
        uint32_t next_pc = pc + 4, result = 0;
        bool writes_rd = false, stores = false;
        uint32_t store_addr = 0, store_data = 0;

        switch (opcode) {
        case 0x37: // LUI
            writes_rd = true;
            result = instr & 0xfffff000u;
            break;
        case 0x17: // AUIPC
            writes_rd = true;
            result = pc + (instr & 0xfffff000u);
            break;
        case 0x6f: // JAL
            writes_rd = true;
            result = pc + 4;
            next_pc = pc + imm_j;
            break;
        case 0x67: // JALR
            writes_rd = true;
            result = pc + 4;
            next_pc = (a + imm_i) & ~1u;
            break;
        case 0x63: // Branch
            switch (f3) {
            case 0: if (a == b) next_pc = pc + imm_b; break;
            case 1: if (a != b) next_pc = pc + imm_b; break;
            case 4: if ((int32_t)a < (int32_t)b) next_pc = pc + imm_b; break;
            case 5: if ((int32_t)a >= (int32_t)b) next_pc = pc + imm_b; break;
            case 6: if (a < b) next_pc = pc + imm_b; break;
            case 7: if (a >= b) next_pc = pc + imm_b; break;
            default: fail(index, "unsupported branch", 0, f3);
            }
            break;
        case 0x03: { // Loads
            uint32_t address = a + imm_i, raw;
            writes_rd = true;
            switch (f3) {
            case 0: raw = read_memory(index, address, 1); result = sext(raw, 8); break;
            case 1: raw = read_memory(index, address, 2); result = sext(raw, 16); break;
            case 2: result = read_memory(index, address, 4); break;
            case 4: result = read_memory(index, address, 1); break;
            case 5: result = read_memory(index, address, 2); break;
            default: fail(index, "unsupported load", 0, f3);
            }
            break;
        }
        case 0x23: { // Stores
            store_addr = a + imm_s;
            store_data = b;
            stores = true;
            unsigned size = f3 == 0 ? 1 : f3 == 1 ? 2 : f3 == 2 ? 4 : 0;
            if (!size) fail(index, "unsupported store", 0, f3);
            write_memory(index, store_addr, size, store_data);
            break;
        }
        case 0x13: // ALU immediate
            writes_rd = true;
            switch (f3) {
            case 0: result = a + imm_i; break;
            case 1: result = a << (imm_i & 31); break;
            case 2: result = (int32_t)a < (int32_t)imm_i; break;
            case 3: result = a < imm_i; break;
            case 4: result = a ^ imm_i; break;
            case 5: result = f7 == 0x20 ? (uint32_t)((int32_t)a >> (imm_i & 31))
                                         : a >> (imm_i & 31); break;
            case 6: result = a | imm_i; break;
            case 7: result = a & imm_i; break;
            }
            break;
        case 0x33: // Register ALU
            writes_rd = true;
            if (f7 == 1) {
                switch (f3) {
                case 0: result = a * b; break;
                case 1: result = (uint32_t)(((uint64_t)((int64_t)(int32_t)a *
                                                           (int64_t)(int32_t)b)) >> 32); break;
                case 2: result = (uint32_t)(((uint64_t)((int64_t)(int32_t)a *
                                                           (int64_t)(uint64_t)b)) >> 32); break;
                case 3: result = (uint32_t)(((uint64_t)a * (uint64_t)b) >> 32); break;
                case 4: result = b == 0 ? UINT32_MAX :
                                 (a == 0x80000000u && b == UINT32_MAX) ? a :
                                 (uint32_t)((int32_t)a / (int32_t)b); break;
                case 5: result = b == 0 ? UINT32_MAX : a / b; break;
                case 6: result = b == 0 ? a :
                                 (a == 0x80000000u && b == UINT32_MAX) ? 0 :
                                 (uint32_t)((int32_t)a % (int32_t)b); break;
                case 7: result = b == 0 ? a : a % b; break;
                }
            } else {
                switch (f3) {
                case 0: result = f7 == 0x20 ? a - b : a + b; break;
                case 1: result = a << (b & 31); break;
                case 2: result = (int32_t)a < (int32_t)b; break;
                case 3: result = a < b; break;
                case 4: result = a ^ b; break;
                case 5: result = f7 == 0x20 ? (uint32_t)((int32_t)a >> (b & 31))
                                             : a >> (b & 31); break;
                case 6: result = a | b; break;
                case 7: result = a & b; break;
                }
            }
            break;
        case 0x0f: // FENCE is a no-op with this memory model.
            break;
        default:
            fail(index, "unsupported opcode", 0, opcode);
        }

        uint32_t expected_rd = writes_rd && rd ? rd : 0;
        check(index, "destination register", expected_rd, trace_rd);
        if (expected_rd) {
            check(index, "destination value", result, trace_value);
            regs[rd] = result;
        }
        check(index, "store flag", stores, trace_store);
        if (stores) {
            check(index, "store address", store_addr, trace_addr);
            check(index, "store data", store_data, trace_wdata);
        }
        regs[0] = 0;
        pc = next_pc;
    }
    printf("PASS C trace check: %u retirements\n", expected_count);
    return 0;
}
