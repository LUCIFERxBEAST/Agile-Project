#include <unistd.h>
#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <thread>
#include <chrono>
#include <algorithm>
#include <unordered_map>
#include <filesystem>
#include <curl/curl.h>
#include "nlohmann/json.hpp" 

using namespace std;
namespace fs = std::filesystem;
using json = nlohmann::json;

const string QUEUE_FILE = "offline_queue.jsonl";

// --- Process Diagnostics Struct ---
struct ProcessCpuInfo {
    int pid;
    string cmd;
    double cpu_percent;
};

// --- CPU Parsing Function ---
// --- Dynamic Host Identity ---
string getServerId() {
    const char* envServerId = std::getenv("TELEMETRY_SERVER_ID");
    if (envServerId != nullptr && string(envServerId).length() > 0) {
        return string(envServerId);
    }
    char hostname[256];
    if (gethostname(hostname, sizeof(hostname)) == 0) {
        hostname[sizeof(hostname) - 1] = '\0';
        return string(hostname);
    }
    return "unknown-host";
}

void getCpuTicks(long long &totalTick, long long &totalIdle) {
    ifstream cpuStat("/proc/stat");
    string cpuLabel;
    cpuStat >> cpuLabel; 
    totalTick = 0;
    totalIdle = 0;
    long long tempValue = 0;
    for (int i = 0; i < 10; i++) {
        if (cpuStat >> tempValue) {
            totalTick += tempValue;
            if (i == 3 || i == 4) totalIdle += tempValue;
        }
    }
}

// Global mapping to track process ticks across sampling intervals (pid -> utime + stime)
unordered_map<int, long long> prevProcTicks;

// --- Process Scanner for Diagnostic Snapshot ---
vector<ProcessCpuInfo> getTopProcesses(long long totalDiff) {
    unordered_map<int, long long> currProcTicks;
    vector<ProcessCpuInfo> procList;

    if (totalDiff <= 0) return procList;

    try {
        for (const auto& entry : fs::directory_iterator("/proc")) {
            if (!entry.is_directory()) continue;

            string filename = entry.path().filename().string();
            if (filename.empty() || !all_of(filename.begin(), filename.end(), ::isdigit)) continue;

            int pid = 0;
            try {
                pid = stoi(filename);
            } catch (...) {
                continue; // Skip invalid directory names
            }

            // Read /proc/[pid]/stat for CPU utime & stime
            string statPath = "/proc/" + to_string(pid) + "/stat";
            ifstream statFile(statPath);
            if (!statFile.is_open()) continue; // Process exited mid-scan

            string statLine;
            getline(statFile, statLine);
            statFile.close();
            if (statLine.empty()) continue;

            size_t openParen = statLine.find('(');
            size_t closeParen = statLine.rfind(')');
            if (openParen == string::npos || closeParen == string::npos || closeParen <= openParen) continue;

            string comm = statLine.substr(openParen + 1, closeParen - openParen - 1);
            string rest = statLine.substr(closeParen + 2);
            stringstream ss(rest);
            string token;
            vector<string> fields;
            while (ss >> token) fields.push_back(token);

            // fields[11] is utime (14th stat field), fields[12] is stime (15th stat field)
            if (fields.size() < 13) continue;

            long long utime = 0, stime = 0;
            try {
                utime = stoll(fields[11]);
                stime = stoll(fields[12]);
            } catch (...) {
                continue;
            }

            long long totalProc = utime + stime;
            currProcTicks[pid] = totalProc;

            long long prevProc = 0;
            if (prevProcTicks.find(pid) != prevProcTicks.end()) {
                prevProc = prevProcTicks[pid];
            }

            long long procDiff = totalProc - prevProc;
            if (procDiff < 0) procDiff = 0;

            double procCpu = (double)procDiff / (double)totalDiff * 100.0;

            // Read /proc/[pid]/cmdline for full process command
            string cmdPath = "/proc/" + to_string(pid) + "/cmdline";
            ifstream cmdFile(cmdPath);
            string cmd;
            if (cmdFile.is_open()) {
                string rawCmd;
                getline(cmdFile, rawCmd);
                cmdFile.close();
                for (char c : rawCmd) {
                    if (c == '\0') cmd += ' ';
                    else cmd += c;
                }
                while (!cmd.empty() && cmd.back() == ' ') cmd.pop_back();
            }
            if (cmd.empty()) {
                cmd = comm;
            }

            procList.push_back({pid, cmd, round(procCpu * 100.0) / 100.0});
        }
    } catch (...) {
        // Handle any filesystem access exceptions gracefully
    }

    // Update baseline map for subsequent interval
    prevProcTicks = currProcTicks;

    // Sort processes by CPU percentage descending
    sort(procList.begin(), procList.end(), [](const ProcessCpuInfo& a, const ProcessCpuInfo& b) {
        return a.cpu_percent > b.cpu_percent;
    });

    // Retain top 3 entries
    if (procList.size() > 3) {
        procList.resize(3);
    }

    return procList;
}

// --- HTTP POST Function using libcurl ---
bool sendTelemetry(const string& url, const string& jsonPayload, const string& apiKey = "") {
    CURL *curl;
    CURLcode res;
    bool success = false;
    
    curl = curl_easy_init();
    if(curl) {
        struct curl_slist *headers = NULL;
        headers = curl_slist_append(headers, "Content-Type: application/json");
        if (!apiKey.empty()) {
            string authHeader = "x-api-key: " + apiKey;
            headers = curl_slist_append(headers, authHeader.c_str());
        }
        
        curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, jsonPayload.c_str());
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 5L); // 5s timeout
        
        // Perform the request
        res = curl_easy_perform(curl);
        
        if(res != CURLE_OK) {
            cerr << "[ERROR] curl_easy_perform() failed: " << curl_easy_strerror(res) << endl;
        } else {
            long response_code = 0;
            curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response_code);
            if (response_code >= 200 && response_code < 300) {
                cout << "[SUCCESS] Payload sent to " << url << " (HTTP " << response_code << ")" << endl;
                success = true;
            } else {
                cerr << "[ERROR] Server returned status code: " << response_code << endl;
            }
        }
        
        // Cleanup
        curl_easy_cleanup(curl);
        curl_slist_free_all(headers);
    }
    return success;
}

// --- Offline Queue Management ---
void saveToOfflineQueue(const string& jsonPayload) {
    ofstream outFile(QUEUE_FILE, ios::app);
    if (outFile.is_open()) {
        outFile << jsonPayload << "\n";
        outFile.close();
        cout << "[OFFLINE QUEUE] Saved payload locally to " << QUEUE_FILE << endl;
    } else {
        cerr << "[ERROR] Could not open " << QUEUE_FILE << " for writing!" << endl;
    }
}

void flushOfflineQueue(const string& url, const string& apiKey = "") {
    ifstream inFile(QUEUE_FILE);
    if (!inFile.is_open()) return; // Queue file does not exist or cannot be opened

    vector<string> lines;
    string line;
    while (getline(inFile, line)) {
        if (!line.empty()) {
            lines.push_back(line);
        }
    }
    inFile.close();

    if (lines.empty()) return;

    cout << "\n[AUTO-RETRY] Attempting to flush " << lines.size() << " queued metric(s)..." << endl;
    size_t sentCount = 0;

    for (size_t i = 0; i < lines.size(); ++i) {
        if (sendTelemetry(url, lines[i], apiKey)) {
            sentCount++;
        } else {
            cout << "[AUTO-RETRY] Connection failed mid-flush. Retaining remaining " 
                 << (lines.size() - sentCount) << " metric(s) in queue." << endl;
            break;
        }
    }

    // Rewrite remaining un-sent payloads back to queue file
    if (sentCount == lines.size()) {
        remove(QUEUE_FILE.c_str());
        cout << "[AUTO-RETRY] Successfully flushed all queued metrics! Queue cleared." << endl;
    } else {
        ofstream outFile(QUEUE_FILE, ios::trunc);
        if (outFile.is_open()) {
            for (size_t i = sentCount; i < lines.size(); ++i) {
                outFile << lines[i] << "\n";
            }
            outFile.close();
        }
    }
}

int main() {
    long long prevTotal = 0, prevIdle = 0;
    getCpuTicks(prevTotal, prevIdle);
    getTopProcesses(1); // Prime process baseline map
    
    // AWS API Gateway / Ingest Endpoint & API Key from environment variables
    const char* envUrl = std::getenv("TELEMETRY_API_URL");
    string apiUrl = (envUrl != nullptr && string(envUrl).length() > 0) 
                    ? string(envUrl) 
                    : "https://YOUR_AWS_API_GATEWAY_ID.execute-api.YOUR_REGION.amazonaws.com/IngestMetrics"; 

    const char* envKey = std::getenv("TELEMETRY_API_KEY");
    string apiKey = (envKey != nullptr) ? string(envKey) : "";

    string serverId = getServerId();
    cout << "[INIT] Server Identity (server_id): " << serverId << endl;
    cout << "[INIT] Telemetry Agent targeting endpoint: " << apiUrl << endl;
    if (!apiKey.empty()) {
        cout << "[AUTH] API Key loaded from TELEMETRY_API_KEY (x-api-key header enabled)." << endl;
    } else {
        cout << "[AUTH] No TELEMETRY_API_KEY set (sending unauthenticated requests)." << endl;
    }

    int highCpuConsecutiveCount = 0;

    while (true) {
        this_thread::sleep_for(chrono::seconds(5));

        // 1. Try to flush any offline queued metrics first
        flushOfflineQueue(apiUrl, apiKey);

        // 2. Get CPU metrics
        long long currTotal = 0, currIdle = 0;
        getCpuTicks(currTotal, currIdle);
        long long totalDiff = currTotal - prevTotal;
        long long idleDiff = currIdle - prevIdle;
        prevTotal = currTotal;
        prevIdle = currIdle;

        double cpuInUse = 0.0;
        if (totalDiff > 0) cpuInUse = (double)(totalDiff - idleDiff) / totalDiff * 100.0;

        // Scan process hierarchy and get top processes for this interval
        vector<ProcessCpuInfo> topProcesses = getTopProcesses(totalDiff);

        // Trigger tracking for >= 85.0% CPU usage across consecutive cycles
        if (cpuInUse >= 85.0) {
            highCpuConsecutiveCount++;
            cout << "[DIAGNOSTICS] High CPU detected (" << cpuInUse << "%). Consecutive count: " 
                 << highCpuConsecutiveCount << "/2" << endl;
        } else {
            highCpuConsecutiveCount = 0;
        }

        // 3. Get Memory metrics
        ifstream memStat("/proc/meminfo");
        long long memTotal = 0, memAvail = 0, value = 0;
        string key, unit;
        while (memStat >> key >> value >> unit) {
            if (key == "MemTotal:") memTotal = value;
            else if (key == "MemAvailable:") { memAvail = value; break; }
        }

        double memInUse = 0.0;
        long long usedMemMb = 0;
        if (memTotal > 0) {
            memInUse = (double)(memTotal - memAvail) / memTotal * 100.0;
            usedMemMb = (memTotal - memAvail) / 1024;
        }
        
        // 4. Construct JSON
        auto now = chrono::system_clock::now();
        long long timestamp = chrono::duration_cast<chrono::seconds>(now.time_since_epoch()).count();

        json payload;
        payload["timestamp"] = timestamp;
        payload["server_id"] = serverId; 
        payload["cpu_percent"] = round(cpuInUse * 100.0) / 100.0; 
        payload["ram_percent"] = round(memInUse * 100.0) / 100.0;
        payload["ram_used_mb"] = usedMemMb;
        payload["ram_total_mb"] = memTotal / 1024;

        // Include top_processes array ONLY when threshold is met (>= 2 consecutive cycles)
        if (highCpuConsecutiveCount >= 2) {
            json procArray = json::array();
            for (const auto& proc : topProcesses) {
                json p;
                p["pid"] = proc.pid;
                p["cmd"] = proc.cmd;
                p["cpu"] = proc.cpu_percent;
                procArray.push_back(p);
            }
            payload["top_processes"] = procArray;
            cout << "[DIAGNOSTICS] Spike threshold met! Attached top 3 processes to payload." << endl;
        }

        string jsonString = payload.dump(); 
        
        cout << "\nGenerated Payload: " << jsonString << endl;
        
        // 5. Send current payload or queue it offline
        if (!sendTelemetry(apiUrl, jsonString, apiKey)) {
            saveToOfflineQueue(jsonString);
        }
    }
    return 0;
}
