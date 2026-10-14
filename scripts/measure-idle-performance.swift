#!/usr/bin/env swift
import Foundation
import Darwin
import CoreGraphics

// 只测量指定进程的聚合资源，不读取窗口标题、任务正文或设备标识。
// 运行：xcrun swift app/scripts/measure-idle-performance.swift --pid 1234 --duration 1200 --interval 5 --output -
// --output - 输出终端；保存结果必须显式给出仓库外的 JSONL 路径。
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var arguments: [String: String] = [:]
var index = 1
let args = CommandLine.arguments
while index < args.count {
    guard ["--pid", "--duration", "--interval", "--output"].contains(args[index]),
          index + 1 < args.count, arguments[args[index]] == nil else {
        fail("用法：--pid <PID> --duration <秒> --interval <秒> --output <-或JSONL路径>")
    }
    arguments[args[index]] = args[index + 1]
    index += 2
}
guard let rawPID = arguments["--pid"], let pid = Int32(rawPID), pid > 0,
      let rawDuration = arguments["--duration"], let duration = Double(rawDuration), duration.isFinite, duration > 0,
      let rawInterval = arguments["--interval"], let interval = Double(rawInterval), interval.isFinite, interval > 0,
      interval <= duration, let output = arguments["--output"], !output.isEmpty else {
    fail("必须显式指定有效的 --pid、--duration、--interval、--output；终端输出使用 --output -。")
}

let sink: FileHandle
if output == "-" {
    sink = .standardOutput
} else {
    // 防止误覆盖已有测量证据。
    guard !FileManager.default.fileExists(atPath: output),
          FileManager.default.createFile(atPath: output, contents: nil),
          let file = FileHandle(forWritingAtPath: output) else { fail("无法创建输出文件，或文件已存在。") }
    sink = file
}
func emit(_ record: [String: Any]) {
    do {
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        try sink.write(contentsOf: data + Data([10]))
    } catch { fail("写入测量结果失败：\(error.localizedDescription)") }
}

let formatter = ISO8601DateFormatter()
formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
// libproc 的累计 CPU 时间是 Mach absolute ticks；Apple Silicon 不可直接当纳秒。
var timebase = mach_timebase_info_data_t()
guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom > 0 else {
    fail("无法读取 Mach 时间单位，CPU 量测不可用。")
}
let nanosecondsPerTick = Double(timebase.numer) / Double(timebase.denom)
let started = ProcessInfo.processInfo.systemUptime
var previousCPU: (time: Double, ticks: UInt64)?
var processIdentity: UInt64?
var records: [[String: Any]] = []
var totalErrors = 0
var targetUnavailable = false

emit(["type": "configuration", "pid": pid, "duration_seconds": duration, "interval_seconds": interval,
      "timestamp": formatter.string(from: Date()), "cpu_percent_semantics": "100% = one logical CPU",
      "cpu_time_source_unit": "Mach absolute ticks", "mach_timebase_numer": timebase.numer,
      "mach_timebase_denom": timebase.denom,
      "window_memory_semantics": "CoreGraphics API reported metric only; not total WindowServer/compositor/GPU memory"])

func sample() {
    let now = ProcessInfo.processInfo.systemUptime
    var record: [String: Any] = ["type": "sample", "timestamp": formatter.string(from: Date()),
                                "elapsed_seconds": now - started]
    var errors: [String] = []
    var usage = rusage_info_v2()
    errno = 0
    let usageResult = withUnsafeMutablePointer(to: &usage) {
        proc_pid_rusage(pid, RUSAGE_INFO_V2, UnsafeMutableRawPointer($0).assumingMemoryBound(to: rusage_info_t?.self))
    }
    if usageResult == 0 {
        if let identity = processIdentity, identity != usage.ri_proc_start_abstime {
            errors.append("pid_reused: target process changed")
            targetUnavailable = true
            previousCPU = nil
        } else {
            processIdentity = usage.ri_proc_start_abstime
            let cumulative = usage.ri_user_time + usage.ri_system_time
            if let previous = previousCPU, cumulative >= previous.ticks, now > previous.time {
                record["cpu_percent"] = Double(cumulative - previous.ticks) * nanosecondsPerTick / 1_000_000_000 / (now - previous.time) * 100
            } else { record["cpu_percent"] = NSNull() }
            previousCPU = (now, cumulative)
            record["rss_bytes"] = usage.ri_resident_size
            record["physical_footprint_bytes"] = usage.ri_phys_footprint
        }
    } else {
        let code = errno
        errors.append("proc_pid_rusage_failed errno=\(code)")
        previousCPU = nil
        if code == ESRCH { targetUnavailable = true }
    }
    // 目标退出或 PID 被复用时，后续指标无效；不能把窗口不存在误报为资源归零。
    if targetUnavailable {
        record["errors"] = errors
        totalErrors += errors.count
        records.append(record)
        emit(record)
        return
    }

    var task = proc_taskinfo()
    errno = 0
    let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
    if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize {
        record["thread_count"] = task.pti_threadnum
    } else { errors.append("proc_taskinfo_failed errno=\(errno)") }

    // 两次查询间文件描述符可能变化；报告第二次查询实际返回的数量。
    errno = 0
    let fdCapacity = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
    if fdCapacity > 0 {
        let bufferSize = Int(fdCapacity) + 32 * MemoryLayout<proc_fdinfo>.size
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: MemoryLayout<proc_fdinfo>.alignment)
        defer { buffer.deallocate() }
        errno = 0
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer, Int32(bufferSize))
        if bytes > 0 { record["fd_count"] = Int(bytes) / MemoryLayout<proc_fdinfo>.size }
        else { errors.append("proc_listfds_failed errno=\(errno)") }
    } else { errors.append("proc_listfds_size_failed errno=\(errno)") }

    if let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] {
        let owned = windows.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid }
        record["window_count"] = owned.count
        // 离屏窗口可能没有 IsOnscreen 字段，用系统过滤查询统计可见窗口。
        if let visible = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] {
            record["visible_window_count"] = visible.filter {
                ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
            }.count
        } else { errors.append("cg_visible_window_list_unavailable") }
        let memory = owned.compactMap { ($0[kCGWindowMemoryUsage as String] as? NSNumber)?.uint64Value }
        if memory.count == owned.count { record["window_memory_bytes"] = memory.reduce(UInt64(0), +) }
        else { errors.append("window_memory_unavailable") }
    } else { errors.append("cg_window_list_unavailable") }

    record["errors"] = errors
    totalErrors += errors.count
    records.append(record)
    emit(record)
}

sample()
// 用单调时钟调度，避免系统校时影响采样间隔；最后一条覆盖指定时长。
var nextElapsed = interval
while !targetUnavailable {
    let deadline = started + min(nextElapsed, duration)
    let remaining = deadline - ProcessInfo.processInfo.systemUptime
    if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
    sample()
    if nextElapsed >= duration { break }
    nextElapsed += interval
}

var summary: [String: Any] = ["type": "summary", "sample_count": records.count,
                            "elapsed_seconds": ProcessInfo.processInfo.systemUptime - started,
                            "error_count": totalErrors, "target_unavailable": targetUnavailable]
for metric in ["cpu_percent", "rss_bytes", "physical_footprint_bytes", "thread_count", "fd_count",
               "window_count", "visible_window_count", "window_memory_bytes"] {
    let values = records.compactMap { ($0[metric] as? NSNumber)?.doubleValue }
    if let first = values.first, let last = values.last {
        summary[metric] = ["valid_samples": values.count, "first": first, "last": last,
                           "min": values.min()!, "max": values.max()!, "mean": values.reduce(0, +) / Double(values.count),
                           "delta": last - first]
    } else { summary[metric] = NSNull() }
}
emit(summary)
if sink !== FileHandle.standardOutput { try? sink.close() }
if totalErrors > 0 { exit(2) }
