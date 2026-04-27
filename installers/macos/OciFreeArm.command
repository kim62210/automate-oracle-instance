#!/usr/bin/env bash
# OciFreeArm.command -- macOS Finder 더블클릭용 진입점.
# 같은 디렉토리의 install.sh 를 실행합니다.
#
# 처음 다운로드 후 한 번만 실행 권한 부여가 필요할 수 있습니다:
#   chmod +x OciFreeArm.command install.sh

set -euo pipefail

cd "$(dirname "$0")"

if [ ! -x "./install.sh" ]; then
    chmod +x ./install.sh 2>/dev/null || true
fi

exec ./install.sh
