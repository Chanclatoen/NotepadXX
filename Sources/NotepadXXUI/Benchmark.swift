import AppKit
import NotepadXXCore
import NotepadXXEditor

/// Times the operations quoted in the README's performance table.
///
/// The table exists to make a claim about large files, and a claim in a README
/// rots the moment the code moves. Running it is `NotepadXX --benchmark <file>`,
/// so anyone can check the numbers on their own machine instead of taking them
/// on trust.
@MainActor
public enum Benchmark {
    private static func milliseconds(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    /// Resident size of this process, which is what "peak memory" means here.
    private static func residentMegabytes() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576
    }

    public static func run(path: String, controller: MainWindowController) {
        let url = URL(fileURLWithPath: path)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int else {
            FileHandle.standardError.write(Data("cannot read \(path)\n".utf8))
            return
        }

        var document: TextDocument?
        let readMilliseconds = milliseconds {
            document = try? TextDocument.load(contentsOf: url)
        }
        var adoptMilliseconds = 0.0
        var layoutMilliseconds = 0.0
        if let document {
            adoptMilliseconds = milliseconds {
                controller.adopt(documents: [document], activeIndex: 0)
            }
            layoutMilliseconds = milliseconds {
                controller.window?.contentView?.layoutSubtreeIfNeeded()
            }
        }
        let openMilliseconds = readMilliseconds + adoptMilliseconds + layoutMilliseconds
        guard let document else {
            FileHandle.standardError.write(Data("cannot load \(path)\n".utf8))
            return
        }

        let editor = controller.editorController(for: document)
        let lines = document.text.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }

        // An insert at the very start is the worst case: everything after it
        // moves, so this is where a quadratic layout would show up.
        let editMilliseconds = milliseconds {
            editor.textView.selectionManager.setSelectedRange(NSRange(location: 0, length: 0))
            editor.replaceSelection(with: "x")
            editor.textView.layoutManager.layoutLines()
        }

        let scrollMilliseconds = milliseconds {
            editor.goToLine(lines)
            editor.textView.layoutManager.layoutLines()
        }

        let megabytes = Double(size) / 1_048_576
        let report = """
        file          \(String(format: "%.1f", megabytes)) MB, \(lines) lines
        open          \(String(format: "%.1f", openMilliseconds)) ms
          read        \(String(format: "%.1f", readMilliseconds)) ms
          adopt       \(String(format: "%.1f", adoptMilliseconds)) ms
          first layout \(String(format: "%.1f", layoutMilliseconds)) ms
        edit at start \(String(format: "%.1f", editMilliseconds)) ms
        scroll to end \(String(format: "%.1f", scrollMilliseconds)) ms
        resident      \(String(format: "%.0f", residentMegabytes())) MB

        """
        FileHandle.standardOutput.write(Data(report.utf8))
    }
}
