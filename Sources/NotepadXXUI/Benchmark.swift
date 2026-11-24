import AppKit
import NotepadXXCore
import NotepadXXEditor

/// Times the operations quoted in the README's performance table.
///
/// The table exists to make a claim about large files, and a claim in a README
/// rots the moment the code moves. Running it is `NotepadXX --benchmark <file>`,
/// so anyone can check the numbers on their own machine instead of taking them
/// on trust. The file is opened and saved through the same controller calls the
/// menus use, on a copy, so the figures are what a person would wait for.
@MainActor
public enum Benchmark {
    private static func milliseconds(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    /// Peak resident size of this process so far.
    private static func peakMegabytes() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_maxrss) / 1_048_576   // bytes on macOS
    }

    /// Longest time the main thread went without servicing its queue.
    ///
    /// A background thread posts a no-op to the main queue every few
    /// milliseconds and records how long each took to run. A beachball is a
    /// long gap; the largest gap in a window is the number that matters.
    private final class StallMonitor: @unchecked Sendable {
        private let lock = NSLock()
        private var worst = 0.0
        private var running = true

        func start() {
            let thread = Thread { [self] in
                while true {
                    lock.lock(); let go = running; lock.unlock()
                    if !go { return }
                    let posted = DispatchTime.now().uptimeNanoseconds
                    let done = DispatchSemaphore(value: 0)
                    DispatchQueue.main.async {
                        let gap = Double(DispatchTime.now().uptimeNanoseconds - posted) / 1_000_000
                        self.lock.lock(); self.worst = max(self.worst, gap); self.lock.unlock()
                        done.signal()
                    }
                    done.wait()
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }
            thread.qualityOfService = .userInteractive
            thread.start()
        }

        /// Largest gap since the last call, then starts a new window.
        func takeWorst() -> Double {
            lock.lock(); defer { lock.unlock() }
            let value = worst
            worst = 0
            return value
        }

        func stop() { lock.lock(); running = false; lock.unlock() }
    }

    public static func run(path: String, controller: MainWindowController, finished: @escaping @MainActor () -> Void) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int else {
            FileHandle.standardError.write(Data("cannot read \(path)\n".utf8))
            return finished()
        }

        // Saving writes to the file, so the run works on a copy.
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadXX-benchmark-\(ProcessInfo.processInfo.processIdentifier)-\((path as NSString).lastPathComponent)")
        try? FileManager.default.removeItem(at: copy)
        guard (try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: copy)) != nil else {
            FileHandle.standardError.write(Data("cannot copy \(path)\n".utf8))
            return finished()
        }

        let monitor = StallMonitor()
        monitor.start()
        let openStart = DispatchTime.now().uptimeNanoseconds
        controller.openForBenchmark(url: copy) { opened in
            let openMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - openStart) / 1_000_000
            let openBlock = monitor.takeWorst()
            guard opened, let document = controller.documents.last else {
                FileHandle.standardError.write(Data("cannot load \(path)\n".utf8))
                monitor.stop(); try? FileManager.default.removeItem(at: copy)
                return finished()
            }
            let openPeak = peakMegabytes()
            let editor = controller.editorController(for: document)
            let lines = document.text.utf8.reduce(into: 1) { count, byte in
                if byte == 10 { count += 1 }
            }

            // An insert at the very start is the worst case: everything after it
            // moves, so this is where a quadratic layout would show up.
            let editMilliseconds = milliseconds {
                editor.textView.selectionManager.setSelectedRange(NSRange(location: 0, length: 0))
                editor.replaceSelection(with: "x")
                editor.textView.layoutManager.layoutLines()
            }
            _ = monitor.takeWorst()

            let scrollMilliseconds = milliseconds {
                editor.goToLine(lines)
                editor.textView.layoutManager.layoutLines()
            }
            _ = monitor.takeWorst()

            // Save as the Save command does: editor text is already in the
            // document, so this is unfold, normalise, encode and write.
            let saveMilliseconds = milliseconds { controller.saveDocumentAction(nil) }
            // The gap monitor can only report once the main queue runs again.
            DispatchQueue.main.async {
                let saveBlock = monitor.takeWorst()
                monitor.stop()
                try? FileManager.default.removeItem(at: copy)
                let megabytes = Double(size) / 1_048_576
                let report = """
                file          \(String(format: "%.1f", megabytes)) MB, \(lines) lines
                open          \(String(format: "%.1f", openMilliseconds)) ms (open call to document shown)
                  main thread blocked at most \(String(format: "%.0f", openBlock)) ms
                  peak resident \(String(format: "%.0f", openPeak)) MB
                edit at start \(String(format: "%.1f", editMilliseconds)) ms
                scroll to end \(String(format: "%.1f", scrollMilliseconds)) ms
                save          \(String(format: "%.1f", saveMilliseconds)) ms (main thread blocked \(String(format: "%.0f", saveBlock)) ms)
                peak resident \(String(format: "%.0f", peakMegabytes())) MB at end

                """
                FileHandle.standardOutput.write(Data(report.utf8))
                finished()
            }
        }
    }
}
