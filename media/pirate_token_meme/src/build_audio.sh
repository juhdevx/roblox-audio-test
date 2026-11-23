#!/bin/bash
set -e
S=/tmp/claude-0/-home-user-roblox-audio-test/12f87363-e15b-5a02-b8dd-9c1989d7812c/scratchpad
cd $S/work
$S/venv/bin/python mix_audio.py $S/audio $S/audio/mix_raw.wav $S/work | tail -1
J=$(ffmpeg -hide_banner -i $S/audio/mix_raw.wav -af loudnorm=I=-14:TP=-1.0:LRA=11:print_format=json -f null /dev/null 2>&1 | sed -n '/^{/,/^}/p')
g() { echo "$J" | grep "\"$1\"" | sed 's/.*: "\(.*\)".*/\1/'; }
ffmpeg -v error -y -i $S/audio/mix_raw.wav -af "loudnorm=I=-14:TP=-1.0:LRA=11:measured_I=$(g input_i):measured_TP=$(g input_tp):measured_LRA=$(g input_lra):measured_thresh=$(g input_thresh):offset=$(g target_offset):linear=true,aresample=48000" -ar 48000 $S/audio/mix.wav
ffmpeg -hide_banner -i $S/audio/mix.wav -af ebur128=peak=true -f null /dev/null 2>&1 | grep -E "^\s+(I:|Peak:)" | head -2
