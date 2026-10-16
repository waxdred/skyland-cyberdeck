import Foundation
import IOKit.ps
import SystemConfiguration

// Real system metrics for the HUD, read from the kernel and IOKit, never made up.
// Every reader is cheap (no disk scan, no process spawn) and returns nil when the
// value is not available (no battery on a desktop Mac, no network interface...).
//
// Definitions:
// - CPU: share of non-idle ticks (user + system + nice) between two samples, all cores.
// - Memory used: app memory (internal pages minus purgeable) + wired + compressed,
//   like Activity Monitor's "Memory Used". Available = physical memory - used.
// - Network: bytes per second received / sent by the non-loopback interfaces, from
//   the interface counters (if_data), between two samples.
// - Storage: the startup volume, total and available for important usage (what
//   Finder shows, purgeable space included).

struct CPUTicks: Equatable {
    var busy: UInt64
    var total: UInt64
}

/// Share of busy ticks between two samples, 0...1; nil without a valid interval.
func cpuUsage(from old: CPUTicks, to new: CPUTicks) -> Double? {
    guard new.total > old.total, new.busy >= old.busy else { return nil }
    return min(1, Double(new.busy - old.busy) / Double(new.total - old.total))
}

/// Bytes per second between two counter samples; nil after a counter reset.
func rate(from old: UInt64, to new: UInt64, seconds: Double) -> Double? {
    guard new >= old, seconds > 0 else { return nil }
    return Double(new - old) / seconds
}

/// "1.2 MB/s", "340 KB/s", "0 B/s": bytes (B). Powers of 1000 like Finder (disk,
/// network), or of 1024 like Activity Monitor with `binary` (memory: 36 GB, not 38.7).
func formatBytes(_ bytes: Double, perSecond: Bool = false, binary: Bool = false) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    let step: Double = binary ? 1024 : 1000
    var value = max(0, bytes), unit = 0
    while value >= step && unit < units.count - 1 { value /= step; unit += 1 }
    let number = unit == 0 || value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    return "\(number) \(units[unit])\(perSecond ? "/s" : "")"
}

/// Fixed-size history for the graphs, oldest first.
struct History {
    let capacity: Int
    private(set) var values: [Double] = []
    init(capacity: Int) { self.capacity = capacity }
    mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }
}

enum SystemReaders {
    static func cpuTicks() -> CPUTicks? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        var ticks = CPUTicks(busy: 0, total: 0)
        for cpu in 0 ..< Int(count) {
            let base = cpu * Int(CPU_STATE_MAX)
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            ticks.busy += user + system + nice
            ticks.total += user + system + nice + idle
        }
        return ticks
    }

    /// (used, total) in bytes.
    static func memory() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        let app = UInt64(stats.internal_page_count) - min(UInt64(stats.internal_page_count), UInt64(stats.purgeable_count))
        let used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        let total = ProcessInfo.processInfo.physicalMemory
        return (min(used, total), total)
    }

    /// Received / sent byte counters summed over the non-loopback interfaces.
    static func networkBytes() -> (received: UInt64, sent: UInt64)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var received: UInt64 = 0, sent: UInt64 = 0
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0, let data = entry.ifa_data else { continue }
            let counters = data.assumingMemoryBound(to: if_data.self).pointee
            received += UInt64(counters.ifi_ibytes)
            sent += UInt64(counters.ifi_obytes)
        }
        return (received, sent)
    }

    /// Interface of the default route ("en0"), nil when offline.
    static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "skyland-cyberdeck" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return global["PrimaryInterface"] as? String
    }

    /// Startup volume: (available, total) in bytes.
    static func storage() -> (available: Int64, total: Int64)? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let available = values.volumeAvailableCapacityForImportantUsage, let total = values.volumeTotalCapacity
        else { return nil }
        return (available, Int64(total))
    }

    struct Battery: Equatable {
        var percent: Int
        var charging: Bool
        var onAC: Bool
        var minutesLeft: Int? // only when the system gives an estimate
    }

    /// Internal battery, nil on a Mac without one.
    static func battery() -> Battery? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int, let max = info[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            let charging = info[kIOPSIsChargingKey] as? Bool ?? false
            let onAC = info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let key = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutes = (info[key] as? Int).flatMap { $0 > 0 ? $0 : nil }
            return Battery(percent: current * 100 / max, charging: charging, onAC: onAC, minutesLeft: minutes)
        }
        return nil
    }
}
