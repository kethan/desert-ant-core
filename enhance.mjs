// Clear + FFmpeg, on Windows, macOS or Linux.
// Example: node enhance.mjs "recording.mp3" --test --format=wav
// Run from the repository workspace after installing Clear and staging its native DLLs.
import { spawn, execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { basename, dirname, extname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const usage = "Usage: node enhance.mjs <input> [--test] [--test-seconds=30] [--chunk=30] [--overlap=1] [--sample-rate=48000] [--gain=15] [--lufs=-19] [--format=mp3|wav] [--model-dir=PATH]";

export function parseArgs(args) {
  if (args.includes("--help") || args.includes("-h")) return { help: true };
  const values = {};
  const allowed = new Set(["test-seconds", "chunk", "overlap", "sample-rate", "gain", "lufs", "format", "model-dir"]);
  let filename;
  let testOnly = false;
  for (const arg of args) {
    if (arg === "--test") { testOnly = true; continue; }
    if (arg.startsWith("--")) {
      const match = /^--([^=]+)=(.+)$/.exec(arg);
      if (!match || !allowed.has(match[1]) || Object.hasOwn(values, match[1])) {
        throw new Error(`Unknown, duplicate, or incomplete option: ${arg}\n${usage}`);
      }
      values[match[1]] = match[2];
    } else if (filename === undefined) filename = arg;
    else throw new Error(`Unexpected argument: ${arg}\n${usage}`);
  }
  if (!filename) throw new Error(usage);
  const number = (name, fallback) => values[name] === undefined ? fallback : Number(values[name]);
  const settings = {
    input: resolve(filename), testOnly,
    testSeconds: number("test-seconds", 30), chunkSeconds: number("chunk", 30),
    overlapSeconds: number("overlap", 1), sampleRate: number("sample-rate", 48000),
    maxGain: number("gain", 15), targetLUFS: number("lufs", -19),
    format: values.format ?? "mp3", modelDir: values["model-dir"] ? resolve(values["model-dir"]) : undefined,
  };
  const s = settings;
  if (!Number.isFinite(s.testSeconds) || s.testSeconds <= 0 ||
      !Number.isFinite(s.chunkSeconds) || s.chunkSeconds <= 0 ||
      !Number.isFinite(s.overlapSeconds) || s.overlapSeconds < 0 ||
      !Number.isInteger(s.sampleRate) || s.sampleRate < 8000 || s.sampleRate > 192000 ||
      !Number.isFinite(s.maxGain) || s.maxGain < 1 || s.maxGain > 100 ||
      !Number.isFinite(s.targetLUFS) || s.targetLUFS < -70 || s.targetLUFS > -5 ||
      !["mp3", "wav"].includes(s.format)) {
    throw new Error("Invalid settings: durations must be positive, overlap nonnegative, sample rate 8000–192000 Hz, gain factor 1–100, LUFS -70 to -5, and format mp3 or wav.");
  }
  // Bound the synchronous decoder buffer; a typo should not allocate gigabytes.
  if ((s.chunkSeconds + 2 * s.overlapSeconds) * s.sampleRate * 4 > 256 * 1024 * 1024) {
    throw new Error("Chunk and overlap are too large (maximum 256 MiB of decoded audio). Reduce --chunk or --overlap.");
  }
  const folder = dirname(s.input);
  const name = basename(s.input, extname(s.input));
  s.output = join(folder, `${name}${testOnly ? "-test" : ""}-cleaned.${s.format}`);
  return s;
}

export async function run(settings, { loadClear, exec = execFileSync, start = spawn, ffmpeg = "ffmpeg", ffprobe = "ffprobe" } = {}) {
  const s = settings;
  if (!existsSync(s.input)) throw new Error(`Input file not found: ${s.input}`);
  if (existsSync(s.output)) throw new Error(`Output already exists; not overwriting: ${s.output}`);
  const duration = Number(exec(ffprobe, ["-v", "error", "-show_entries", "format=duration",
    "-of", "default=noprint_wrappers=1:nokey=1", s.input], { encoding: "utf8" }).trim());
  if (!Number.isFinite(duration) || duration <= 0) throw new Error("Could not determine input duration using ffprobe.");
  const processDuration = Math.min(duration, s.testOnly ? s.testSeconds : duration);
  console.log(`Input: ${s.input}\nOutput: ${s.output}\nDuration: ${processDuration.toFixed(1)}s\nDynamic gain factor: ${s.maxGain}\nTarget loudness: ${s.targetLUFS} LUFS`);
  console.log("Loading Clear model...");
  const clear = await loadClear(s.modelDir ? { directory: s.modelDir } : {});
  let encoder;
  let closed;
  let completed = false;
  try {
    const codec = s.format === "wav" ? ["-c:a", "pcm_s24le"] : ["-c:a", "libmp3lame", "-b:a", "192k"];
    encoder = start(ffmpeg, ["-nostdin", "-n", "-v", "warning", "-f", "f32le", "-ar", String(s.sampleRate),
      "-ac", "1", "-i", "pipe:0", "-af", `dynaudnorm=f=150:g=${s.maxGain}:p=0.95,loudnorm=I=${s.targetLUFS}:TP=-1.5:LRA=11`,
      "-ar", String(s.sampleRate), ...codec, s.output], { stdio: ["pipe", "ignore", "inherit"] });
    // Observe errors immediately, including spawn failures or a broken pipe.
    let spawnError;
    encoder.on("error", error => { spawnError = error; });
    encoder.stdin.on("error", () => {});
    closed = new Promise(resolveClose => encoder.once("close", (code, signal) => resolveClose({ code, signal })));
    for (let coreStart = 0; coreStart < processDuration; coreStart += s.chunkSeconds) {
      const coreEnd = Math.min(coreStart + s.chunkSeconds, processDuration);
      const startTime = Math.max(0, coreStart - s.overlapSeconds);
      const endTime = Math.min(duration, coreEnd + s.overlapSeconds);
      console.log(`Enhancing ${coreStart.toFixed(1)}–${coreEnd.toFixed(1)} seconds...`);
      const maxBuffer = Math.ceil((endTime - startTime) * s.sampleRate * 4) + 1024 * 1024;
      const raw = exec(ffmpeg, ["-v", "error", "-ss", String(startTime), "-i", s.input,
        "-t", String(endTime - startTime), "-vn", "-ac", "1", "-ar", String(s.sampleRate),
        "-f", "f32le", "pipe:1"], { maxBuffer });
      if (raw.byteLength === 0 || raw.byteLength % 4 !== 0) throw new Error("FFmpeg returned empty or invalid float audio.");
      const samples = new Float32Array(raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength));
      const result = await clear.enhance(samples, s.sampleRate, {
        targetLUFS: null, channelMode: "mono", outputSampleRate: s.sampleRate,
      });
      const skip = Math.round((coreStart - startTime) * s.sampleRate);
      const count = Math.min(Math.round((coreEnd - coreStart) * s.sampleRate), result.samples.length - skip);
      if (count <= 0) throw new Error("Clear returned an unexpectedly short audio chunk.");
      const core = result.samples.subarray(skip, skip + count);
      const buffer = Buffer.from(core.buffer, core.byteOffset, core.byteLength);
      await new Promise((accept, reject) => encoder.stdin.write(buffer, error => error ? reject(error) : accept()));
      console.log(`  Enhanced in ${result.processingSec.toFixed(1)} seconds`);
    }
    encoder.stdin.end();
    const { code, signal } = await closed;
    if (spawnError) throw spawnError;
    if (code !== 0) throw new Error(`FFmpeg encoder failed (exit ${code ?? signal}).`);
    completed = true;
    console.log(`Finished: ${s.output}`);
  } finally {
    if (encoder && !completed) {
      if (!encoder.stdin.destroyed) encoder.stdin.destroy();
      encoder.kill();
      await closed;
      console.error(`Processing failed; a partial output may remain at: ${s.output}`);
    }
    clear.dispose();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const settings = parseArgs(process.argv.slice(2));
    if (settings.help) console.log(usage);
    else {
      const { Clear } = await import("@desert-ant-labs/clear/native");
      await run(settings, { loadClear: options => Clear.load(options) });
    }
  } catch (error) {
    if (error.code === "ENOENT" && ["ffmpeg", "ffprobe"].includes(error.path)) {
      console.error(`${error.path} was not found. Add the folder containing ffmpeg.exe and ffprobe.exe to PATH.`);
    } else console.error(error.message);
    process.exitCode = 1;
  }
}
