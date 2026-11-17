Clear portable enhancer - Windows x64

Extract ALL files and folders from the ZIP. Open PowerShell in this folder and run:

  .\node.exe .\enhance.js

Paste or drag an audio file path into the prompt and press Enter. A mono,
24-bit WAV named <input>-cleaned.wav is written beside the original file.
To process a file directly, or test the first 30 seconds:

  .\node.exe .\enhance.js "C:\audio\recording.mp3"
  .\node.exe .\enhance.js "C:\audio\recording.mp3" --test

Optional --format=mp3 writes a 192 kbps MP3 instead. Existing output files
are never overwritten. ffmpeg.exe, ffprobe.exe, Node, the Clear native DLLs,
and model/clear-studio.tflite are included; do not move them separately.
The model is loaded locally; no model download is required. The SDK may attempt
background license requests. Windows x64 and the Microsoft Visual C++ runtime
may be needed. See LICENSE.md, THIRD_PARTY_NOTICES.md and THIRD-PARTY/.

FFmpeg is a separate GPL-licensed program: its build information and source
links are in THIRD-PARTY/FFmpeg/. Node.js and Koffi license information is also
in THIRD-PARTY/. Clear has its own source-available license in LICENSE.md.
