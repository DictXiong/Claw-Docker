#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?usage: smoke-test.sh IMAGE}"

docker run --rm --network none --entrypoint hermes "${IMAGE}" --version
docker run --rm --network none --user hermes --entrypoint sh "${IMAGE}" -c '
  command -v fd flyai gs jq libreoffice pandoc pdftoppm qpdf rg soffice >/dev/null
  flyai --help >/dev/null
  cd /opt/hermes
  node -e '\''for (const m of ["docx", "pptxgenjs", "react-icons", "sharp"]) require(m)'\''
  /opt/hermes/.venv/bin/python -c '\''import lark_oapi, lxml, markitdown, openpyxl, pandas, pymupdf, pypdf, qrcode, docx, pptx, reportlab'\''
  for skill in minimax-docx minimax-pdf minimax-xlsx pptx-generator; do
    test -f "/opt/hermes/skills/minimax/${skill}/SKILL.md"
    test -L "/opt/minimax-skills/skills/${skill}"
  done
  test -f /opt/hermes/skills/travel/flyai/LICENSE
  test -f /opt/hermes/skills/travel/flyai/SKILL.md
  bash /opt/minimax-skills/skills/minimax-docx/scripts/env_check.sh
  bash /opt/minimax-skills/skills/minimax-pdf/scripts/make.sh check

  probe_dir="$(mktemp -d)"
  trap '\''rm -rf "$probe_dir"'\'' EXIT
  printf '\''<!doctype html><style>html,body{width:794px;height:1123px;margin:0;background:#123;color:white}h1{padding:100px;font-size:72px}</style><h1>Hermes</h1>'\'' > "$probe_dir/cover.html"
  node /opt/minimax-skills/skills/minimax-pdf/scripts/render_cover.js \
    --input "$probe_dir/cover.html" --out "$probe_dir/cover.pdf"
  pdfinfo "$probe_dir/cover.pdf" | grep -q '\''Page size:.*A4'\''
'

docker run --rm --network none \
  --tmpfs /opt/data:rw,size=128m,mode=0700 \
  --entrypoint sh "${IMAGE}" -c '
    cd /opt/hermes
    /opt/hermes/.venv/bin/python -c \
      "from tools.skills_sync import sync_skills; sync_skills(quiet=True)"
    test -f /opt/data/skills/travel/flyai/SKILL.md
    grep -q "^flyai:" /opt/data/skills/.bundled_manifest
  '
