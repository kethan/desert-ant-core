import Foundation
import Clear
import WinSDK
import CRT

@main
struct ClearCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--help"] || args == ["-h"] {
            print("Usage: clear.exe INPUT.wav OUTPUT.wav [MODEL.tflite]")
            print("Default model: clear-studio.tflite beside clear.exe. Input and output are WAV files.")
            return
        }
        guard args.count == 2 || args.count == 3 else {
            fail("Usage: clear.exe INPUT.wav OUTPUT.wav [MODEL.tflite]")
        }
        let input = URL(fileURLWithPath: args[0]).standardizedFileURL
        let output = URL(fileURLWithPath: args[1]).standardizedFileURL
        guard input.path.lowercased() != output.path.lowercased() else {
            fail("Input and output must be different files.")
        }
        guard input.pathExtension.lowercased() == "wav", output.pathExtension.lowercased() == "wav" else {
            fail("Input and output must be WAV files.")
        }
        guard FileManager.default.fileExists(atPath: input.path) else {
            fail("Input file not found: \(input.path)")
        }
        var executable = [WCHAR](repeating: 0, count: 32768)
        let length = GetModuleFileNameW(nil, &executable, DWORD(executable.count))
        guard length > 0 && Int(length) < executable.count else {
            fail("Unable to locate clear.exe. Pass the model path explicitly.")
        }
        let executablePath = String(decoding: executable.prefix(Int(length)), as: UTF16.self)
        let model = args.count == 3
            ? URL(fileURLWithPath: args[2]).standardizedFileURL
            : URL(fileURLWithPath: executablePath).deletingLastPathComponent()
                .appendingPathComponent("clear-studio.tflite")
        guard FileManager.default.fileExists(atPath: model.path) else {
            fail("Model not found: \(model.path). Place clear-studio.tflite next to clear.exe or pass its path.")
        }
        do {
            // modelPath never downloads model weights; only local files are used.
            let clear = try Clear(modelPath: model.path)
            let result = try await clear.enhance(path: input.path, to: output.path)
            print("Wrote \(output.path) (\(result.durationSec)s, \(Int(result.sampleRate)) Hz)")
        } catch {
            fail("Enhancement failed: \(error.localizedDescription)")
        }
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }
}
