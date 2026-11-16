Clear portable command line (Windows x64)

Keep clear.exe and the accompanying DLLs together. Put clear-studio.tflite from
https://huggingface.co/desert-ant-labs/clear/tree/v0.3.0 next to clear.exe.
Alternatively supply the model file as the third argument:

  clear.exe input.wav output.wav [model.tflite]

Input must be PCM or float WAV; output is 48 kHz mono PCM WAV. The model is
loaded from the local file, so inference does not download weights. The SDK may
attempt background licensing requests; see LICENSE.md and THIRD_PARTY_NOTICES.md.
No Node or Swift installation is needed. Windows x64 and Microsoft's Visual C++
runtime may be needed on the target system.
