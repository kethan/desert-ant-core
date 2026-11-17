import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { parseArgs, run } from '../../enhance.mjs';

test('options validate FFmpeg ranges and do not mislabel the gain', () => {
  const s = parseArgs(['recording.mp3', '--test', '--gain=15', '--format=wav', '--sample-rate=44100']);
  assert.equal(s.maxGain, 15);
  assert.equal(s.output.endsWith('recording-test-cleaned.wav'), true);
  assert.equal(s.sampleRate, 44100);
  for (const arg of ['--gain=0', '--gain=101', '--lufs=-2', '--sample-rate=0', '--chunk=0', '--format=flac', '--unknown=1']) {
    assert.throws(() => parseArgs(['a.mp3', arg]));
  }
});

test('chunks preserve selected rate and stream only their centre to the encoder', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'clear-example-'));
  const input = join(dir, 'in.mp3');
  writeFileSync(input, 'fixture');
  let disposed = false;
  const calls = [];
  const s = parseArgs([input, '--chunk=1', '--overlap=0.25', '--sample-rate=8000', '--format=wav']);
  try {
    const fakeExec = (cmd, args) => {
      if (cmd === 'ffprobe') return '2.5';
      const duration = Number(args[args.indexOf('-t') + 1]);
      return Buffer.alloc(Math.round(duration * 8000) * 4);
    };
    const fakeStart = (cmd, args) => {
      assert.equal(cmd, 'ffmpeg');
      assert.ok(args.includes('-n'));
      assert.ok(args.includes('pcm_s24le'));
      const code = 'const fs=require("fs");const a=[];process.stdin.on("data",x=>a.push(x));process.stdin.on("end",()=>fs.writeFileSync(process.argv[1],Buffer.concat(a)))';
      return spawn(process.execPath, ['-e', code, s.output], { stdio: ['pipe', 'ignore', 'inherit'] });
    };
    await run(s, { exec: fakeExec, start: fakeStart, loadClear: async () => ({
      enhance: async (samples, rate, options) => {
        calls.push({ rate, options });
        return { samples, processingSec: 0 };
      },
      dispose: () => { disposed = true; },
    }) });
    assert.equal(calls.length, 3);
    assert.ok(calls.every(call => call.rate === 8000 && call.options.outputSampleRate === 8000 && call.options.targetLUFS === null));
    assert.equal(readFileSync(s.output).length, 2.5 * 8000 * 4);
    assert.equal(disposed, true);
    await assert.rejects(() => run(s, { exec: fakeExec }), /not overwriting/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
