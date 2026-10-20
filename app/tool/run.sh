#!/usr/bin/env bash
# Запускает команду; при ошибке — хвост вывода одной аннотацией GitHub (её видно без полного лога).
set -o pipefail
"$@" 2>&1 | tee .run.log
code=${PIPESTATUS[0]}
if [ "$code" != 0 ]; then
  msg=$(tail -n 60 .run.log | sed 's/\r$//' | grep -v '^\s*$' | grep -v -E '\(.* available\)$' | tail -n 40 | sed 's/%/%25/g' | awk 'BEGIN{ORS="%0A"} {print}')
  echo "::error title=$1 $2 $3 $4::${msg}"
fi
exit "$code"
