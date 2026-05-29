#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>

#include "Vaxis_async_fifo.h"
#include "verilated.h"

static vluint64_t sim_time = 0;

double sc_time_stamp() {
    return static_cast<double>(sim_time);
}

static void tick(Vaxis_async_fifo &dut, bool tick_s, bool tick_m) {
    if (tick_s) {
        dut.s_clk = 0;
    }
    if (tick_m) {
        dut.m_clk = 0;
    }
    dut.eval();
    sim_time++;

    if (tick_s) {
        dut.s_clk = 1;
    }
    if (tick_m) {
        dut.m_clk = 1;
    }
    dut.eval();
    sim_time++;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);

    Vaxis_async_fifo dut;
    dut.s_clk = 0;
    dut.m_clk = 0;
    dut.s_rst = 1;
    dut.m_rst = 1;
    dut.s_tvalid = 0;
    dut.s_tdata = 0;
    dut.m_tready = 0;

    std::deque<uint32_t> expected;
    uint32_t next_word = 0x51494453u;
    uint32_t received = 0;

    for (int step = 0; step < 8000; ++step) {
        const bool tick_s = true;
        const bool tick_m = (step % 2) == 0;

        dut.s_rst = step < 8;
        dut.m_rst = step < 11;

        if (!dut.s_rst && dut.s_tready && (step % 5) != 4) {
            dut.s_tvalid = 1;
            dut.s_tdata = next_word;
        } else {
            dut.s_tvalid = 0;
        }

        dut.m_tready = !dut.m_rst && ((step % 7) != 3);

        const bool push = tick_s && !dut.s_rst && dut.s_tvalid && dut.s_tready;
        const bool pop = tick_m && !dut.m_rst && dut.m_tvalid && dut.m_tready;
        const uint32_t pop_word = dut.m_tdata;

        tick(dut, tick_s, tick_m);

        if (push) {
            expected.push_back(next_word);
            next_word += 0x1020304u;
        }

        if (pop) {
            if (expected.empty()) {
                std::fprintf(stderr, "unexpected pop at step %d\n", step);
                return 1;
            }
            const uint32_t want = expected.front();
            expected.pop_front();
            if (pop_word != want) {
                std::fprintf(
                    stderr,
                    "data mismatch at step %d: got 0x%08x want 0x%08x\n",
                    step,
                    pop_word,
                    want
                );
                return 1;
            }
            received++;
        }
    }

    if (received < 1000) {
        std::fprintf(stderr, "too few transfers: %u\n", received);
        return 1;
    }

    std::printf("PASS: axis_async_fifo transferred %u words\n", received);
    return 0;
}
