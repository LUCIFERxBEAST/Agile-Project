#ifndef METRICS_HPP
#define METRICS_HPP

#include <cmath>

namespace metrics {

/**
 * Calculates CPU utilization percentage from tick deltas.
 * totalDiff: currTotal - prevTotal
 * idleDiff:  currIdle - prevIdle
 */
inline double calculateCpuPercent(long long totalDiff, long long idleDiff) {
    if (totalDiff <= 0) return 0.0;
    double cpu = static_cast<double>(totalDiff - idleDiff) / static_cast<double>(totalDiff) * 100.0;
    if (cpu < 0.0) cpu = 0.0;
    if (cpu > 100.0) cpu = 100.0;
    return std::round(cpu * 100.0) / 100.0;
}

/**
 * Calculates per-process CPU utilization relative to total CPU ticks.
 * procDiff:  currProc - prevProc
 * totalDiff: currTotal - prevTotal
 */
inline double calculateProcessCpuPercent(long long procDiff, long long totalDiff) {
    if (totalDiff <= 0 || procDiff <= 0) return 0.0;
    double procCpu = static_cast<double>(procDiff) / static_cast<double>(totalDiff) * 100.0;
    if (procCpu < 0.0) procCpu = 0.0;
    return std::round(procCpu * 100.0) / 100.0;
}

/**
 * Calculates RAM utilization percentage.
 * memTotal:  Total RAM in kB
 * memAvail:  Available RAM in kB
 */
inline double calculateRamPercent(long long memTotal, long long memAvail) {
    if (memTotal <= 0) return 0.0;
    long long diff = memTotal - memAvail;
    if (diff < 0) diff = 0;
    double mem = static_cast<double>(diff) / static_cast<double>(memTotal) * 100.0;
    if (mem < 0.0) mem = 0.0;
    if (mem > 100.0) mem = 100.0;
    return std::round(mem * 100.0) / 100.0;
}

/**
 * Calculates used RAM in megabytes.
 * memTotal: Total RAM in kB
 * memAvail: Available RAM in kB
 */
inline long long calculateRamUsedMb(long long memTotal, long long memAvail) {
    if (memTotal <= 0) return 0;
    long long diff = memTotal - memAvail;
    if (diff < 0) diff = 0;
    return diff / 1024;
}

/**
 * Calculates total RAM in megabytes.
 * memTotal: Total RAM in kB
 */
inline long long calculateRamTotalMb(long long memTotal) {
    if (memTotal <= 0) return 0;
    return memTotal / 1024;
}

} // namespace metrics

#endif // METRICS_HPP
