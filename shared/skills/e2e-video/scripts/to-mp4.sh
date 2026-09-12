#!/bin/sh
# 録画 webm を PR 掲載用の mp4（H.264・ストリーミング再生対応）に変換する。
# 使い方: to-mp4.sh <入力.webm> <出力.mp4>
# ffmpeg が無ければ `pip install imageio-ffmpeg` し、その binaries/ffmpeg-* を
# PATH に置くか FFMPEG_BIN で指す。
set -e
FF="${FFMPEG_BIN:-ffmpeg}"
if [ $# -ne 2 ]; then
  echo "usage: to-mp4.sh <input.webm> <output.mp4>" >&2
  exit 1
fi
"$FF" -hide_banner -loglevel error -y -i "$1" \
  -c:v libx264 -pix_fmt yuv420p -crf 23 -preset veryfast -movflags +faststart \
  "$2"
