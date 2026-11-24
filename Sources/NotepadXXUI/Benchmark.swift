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
        // Each step runs, then the next one starts from a fresh main-queue
        // turn, so the monitor's pending ping has run and its gap is counted.
        struct Step { let name: String; let body: @MainActor () -> Void }
        var timings: [String: (ms: Double, block: Double)] = [:]
        var lines = 1
        var openPeak = 0.0
        var document: TextDocument?
        var failed = false

        func finish() {
            monitor.stop()
            try? FileManager.default.removeItem(at: copy)
            guard !failed else { return finished() }
            func row(_ name: String) -> String {
                guard let t = timings[name] else { return "" }
                return String(format: "%.1f ms, main thread blocked at most %.0f ms", t.ms, t.block)
            }
            let megabytes = Double(size) / 1_048_576
            let report = """
            file          \(String(format: "%.1f", megabytes)) MB, \(lines) lines
            open          \(row("open"))
            peak resident \(String(format: "%.0f", openPeak)) MB after open, \(String(format: "%.0f", peakMegabytes())) MB at end
            edit at start \(row("edit"))
            scroll to end \(row("scroll"))
            save          \(row("save"))

            """
            FileHandle.standardOutput.write(Data(report.utf8))
            finished()
        }

        func measure(_ name: String, _ body: @MainActor (@escaping @MainActor () -> Void) -> Void,
                     then next: @escaping @MainActor () -> Void) {
            _ = monitor.takeWorst()
            let start = DispatchTime.now().uptimeNanoseconds
            body {
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                DispatchQueue.main.async {
                    timings[name] = (elapsed, monitor.takeWorst())
                    next()
                }
            }
        }

        measure("open", { done in
            controller.openForBenchmark(url: copy) { opened in
                guard opened, let opened = controller.documents.last else {
                    FileHandle.standardError.write(Data("cannot load \(path)\n".utf8))
                    failed = true
                    return done()
                }
                document = opened
                done()
            }
        }, then: {
            guard let document, !failed else { return finish() }
            openPeak = peakMegabytes()
            let view = controller.editorController(for: document)
            lines = document.text.utf8.reduce(into: 1) { count, byte in
                if byte == 10 { count += 1 }
            }
            // An insert at the very start is the worst case: everything after it
            // moves, so this is where a quadratic layout would show up.
            measure("edit", { done in
                view.textView.selectionManager.setSelectedRange(NSRange(location: 0, length: 0))
                view.replaceSelection(with: "x")
                view.textView.layoutManager.layoutLines()
                done()
            }, then: {
                measure("scroll", { done in
                    view.goToLine(lines)
                    view.textView.layoutManager.layoutLines()
                    done()
                }, then: {
                    // Save as the Save command does: the editor text is already in
                    // the document, so this is unfold, normalise, encode and write.
                    measure("save", { done in
                        controller.saveDocumentAction(nil)
                        done()
                    }, then: finish)
                })
            })
        })
    }
}
