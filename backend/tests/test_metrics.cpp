#include <iostream>
#include <cassert>
#include <cmath>
#include "../src/metrics.hpp"

// Simple assert helper with diagnostic print
#define ASSERT_APPROX(val, expected, eps) \
    do { \
        if (std::fabs((val) - (expected)) > (eps)) { \
            std::cerr << "Assertion failed at line " << __LINE__ \
                      << ": got " << (val) << ", expected " << (expected) << std::endl; \
            std::exit(1); \
        } \
    } while (0)

#define ASSERT_EQ(val, expected) \
    do { \
        if ((val) != (expected)) { \
            std::cerr << "Assertion failed at line " << __LINE__ \
                      << ": got " << (val) << ", expected " << (expected) << std::endl; \
            std::exit(1); \
        } \
    } while (0)

void test_cpu_calculations() {
    std::cout << "[TEST] Running CPU calculation unit tests..." << std::endl;

    // Normal calculation: 800 active ticks out of 1000 total -> 80.0%
    double cpu1 = metrics::calculateCpuPercent(1000, 200);
    ASSERT_APPROX(cpu1, 80.0, 0.001);

    // 100% CPU utilization (idleDiff = 0)
    double cpu_full = metrics::calculateCpuPercent(500, 0);
    ASSERT_APPROX(cpu_full, 100.0, 0.001);

    // 0% CPU utilization (totalDiff == idleDiff)
    double cpu_idle = metrics::calculateCpuPercent(500, 500);
    ASSERT_APPROX(cpu_idle, 0.0, 0.001);

    // Edge case: zero or negative tick delta
    double cpu_zero = metrics::calculateCpuPercent(0, 0);
    ASSERT_APPROX(cpu_zero, 0.0, 0.001);

    double cpu_neg = metrics::calculateCpuPercent(-100, 50);
    ASSERT_APPROX(cpu_neg, 0.0, 0.001);

    // Rounding: 200/300 active = 66.6666...% -> rounds to 66.67%
    double cpu_round = metrics::calculateCpuPercent(300, 100);
    ASSERT_APPROX(cpu_round, 66.67, 0.001);

    // Spike threshold boundary tests (85.0%)
    double cpu_threshold = metrics::calculateCpuPercent(1000, 150);
    ASSERT_APPROX(cpu_threshold, 85.0, 0.001);
    assert(cpu_threshold >= 85.0); // Verifies comparison >= in utility.cpp

    double cpu_sub = metrics::calculateCpuPercent(1000, 151);
    ASSERT_APPROX(cpu_sub, 84.9, 0.001);
    assert(cpu_sub < 85.0);

    std::cout << "  -> CPU tests passed!" << std::endl;
}

void test_process_cpu_calculations() {
    std::cout << "[TEST] Running process CPU calculation unit tests..." << std::endl;

    // Process using 500 ticks out of 1000 system ticks -> 50.0%
    double p_cpu = metrics::calculateProcessCpuPercent(500, 1000);
    ASSERT_APPROX(p_cpu, 50.0, 0.001);

    // Zero process ticks
    double p_zero = metrics::calculateProcessCpuPercent(0, 1000);
    ASSERT_APPROX(p_zero, 0.0, 0.001);

    // Negative process diff (counter reset)
    double p_neg = metrics::calculateProcessCpuPercent(-50, 1000);
    ASSERT_APPROX(p_neg, 0.0, 0.001);

    // Zero total system delta
    double p_total_zero = metrics::calculateProcessCpuPercent(500, 0);
    ASSERT_APPROX(p_total_zero, 0.0, 0.001);

    // Rounding check
    double p_round = metrics::calculateProcessCpuPercent(333, 1000);
    ASSERT_APPROX(p_round, 33.3, 0.001);

    std::cout << "  -> Process CPU tests passed!" << std::endl;
}

void test_ram_calculations() {
    std::cout << "[TEST] Running RAM calculation unit tests..." << std::endl;

    long long memTotal = 16384000; // ~16000 MB
    long long memAvail = 8192000;  // ~8000 MB

    double ramPercent = metrics::calculateRamPercent(memTotal, memAvail);
    ASSERT_APPROX(ramPercent, 50.0, 0.001);

    long long usedMb = metrics::calculateRamUsedMb(memTotal, memAvail);
    ASSERT_EQ(usedMb, 8000);

    long long totalMb = metrics::calculateRamTotalMb(memTotal);
    ASSERT_EQ(totalMb, 16000);

    // Zero total RAM edge case
    ASSERT_APPROX(metrics::calculateRamPercent(0, 0), 0.0, 0.001);
    ASSERT_EQ(metrics::calculateRamUsedMb(0, 0), 0);
    ASSERT_EQ(metrics::calculateRamTotalMb(0), 0);

    // Available greater than Total (system metric inconsistency safety)
    ASSERT_APPROX(metrics::calculateRamPercent(1000, 2000), 0.0, 0.001);
    ASSERT_EQ(metrics::calculateRamUsedMb(1000, 2000), 0);

    // High RAM utilization (90%)
    double highRam = metrics::calculateRamPercent(1000000, 100000);
    ASSERT_APPROX(highRam, 90.0, 0.001);

    std::cout << "  -> RAM tests passed!" << std::endl;
}

int main() {
    std::cout << "========================================" << std::endl;
    std::cout << "Starting C++ Telemetry Unit Tests" << std::endl;
    std::cout << "========================================" << std::endl;

    test_cpu_calculations();
    test_process_cpu_calculations();
    test_ram_calculations();

    std::cout << "========================================" << std::endl;
    std::cout << "ALL 3/3 TEST SUITES PASSED SUCCESSFULLY!" << std::endl;
    std::cout << "========================================" << std::endl;
    return 0;
}
