// Portable Windows entry point. All binaries and the model live beside this file.
import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs, run } from './enhance.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
try {
  if (args.length === 0) {
    const rl = createInterface({ input: stdin, output: stdout });
    try {
      const answer = (await rl.question('Audio file path (you can drag the file here): ')).trim();
      const input = answer.startsWith('"') && answer.endsWith('"') ? answer.slice(1, -1) : answer;
      if (!input) throw new Error('No audio file was provided.');
      args.push(input);
    } finally { rl.close(); }
  }
  // The portable version defaults to WAV, avoiding another lossy encode.
  if (!args.some(arg => arg.startsWith('--format='))) args.push('--format=wav');
  const settings = parseArgs(args);
  if (settings.help) {
    console.log('Usage: .\\node.exe .\\enhance.js "input.mp3" [--test] [--format=wav|mp3]');
  } else {
    settings.modelDir ??= join(here, 'model');
    if (!existsSync(join(settings.modelDir, 'clear-studio.tflite'))) {
      throw new Error(`Model missing: ${join(settings.modelDir, 'clear-studio.tflite')}. Extract the entire ZIP.`);
    }
    const { Clear } = await import('@desert-ant-labs/clear/native');
    await run(settings, {
      loadClear: options => Clear.load(options),
      ffmpeg: join(here, 'ffmpeg.exe'),
      ffprobe: join(here, 'ffprobe.exe'),
    });
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
