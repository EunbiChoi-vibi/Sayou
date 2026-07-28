#!/usr/bin/env bash
# Sayou Alt Manager를 SketchUp Extension Manager로 설치 가능한
# .rbz(=zip) 파일로 패키징한다.
#
# 사용법: sketchup-extension/ 안에서 ./build.sh 실행
#   -> dist/sayou_altmanager.rbz 생성

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DIST_DIR="$SCRIPT_DIR/dist"
OUTPUT="$DIST_DIR/sayou_altmanager.rbz"

mkdir -p "$DIST_DIR"
rm -f "$OUTPUT"

zip -r -X "$OUTPUT" altmanager.rb altmanager -x "*.DS_Store"

echo "생성 완료: $OUTPUT"
echo "SketchUp > Extensions > Extension Manager > Install Extension 에서 이 파일을 선택하세요."
