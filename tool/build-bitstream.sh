#!/usr/bin/env bash
# Gowin EDA を使わずにビットストリームを作る。
#
# 必要なもの:
#   - oss-cad-suite (yosys / nextpnr-himbaechel / gowin_pack / openFPGALoader)
#     https://github.com/YosysHQ/oss-cad-suite-build/releases
#     macOS では展開後に `xattr -dr com.apple.quarantine <展開先>` が必要。
#   - sv2v (brew install sv2v)
#   - veryl
set -euo pipefail

cd "$(dirname "$0")/.."

# oss-cad-suite を PATH に入れる。すでに通っていれば何もしない。
: "${OSS_CAD_SUITE:=$HOME/.local/share/oss-cad-suite}"
if ! command -v yosys >/dev/null 2>&1 && [ -d "$OSS_CAD_SUITE/bin" ]; then
  PATH="$OSS_CAD_SUITE/bin:$PATH"
  export PATH
fi

for cmd in veryl sv2v yosys nextpnr-himbaechel gowin_pack; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "$cmd が見つかりません。README の「Gowin EDA を使わない」を参照してください。" >&2
    exit 1
  }
done

BUILD=build
DEVICE="GW1NR-LV9QN88PC6/I5"
FAMILY=GW1N-9C
CST=board/rev4_tangnano9k/src/port.cst
FREQ=27

mkdir -p "$BUILD"

veryl build

# Veryl が出力する SystemVerilog には yosys が読めない構文
# （ユーザー定義型を返す function など）が含まれるので sv2v を通す。
sv2v target/lcd_writer.sv target/lcd_hello.sv target/main.sv >"$BUILD/top.v"

yosys -p "read_verilog $BUILD/top.v; synth_gowin -top Main -json $BUILD/top.json"

# port.cst は Gowin 形式のまま nextpnr に渡せる。SDC は使われないので --freq で代用する。
nextpnr-himbaechel \
  --json "$BUILD/top.json" --write "$BUILD/pnr.json" \
  --device "$DEVICE" --vopt family="$FAMILY" --vopt cst="$CST" --freq "$FREQ"

gowin_pack -d "$FAMILY" -o "$BUILD/hello.fs" "$BUILD/pnr.json"

echo
echo "built: $BUILD/hello.fs"
echo "  SRAM へ書き込み    : openFPGALoader -b tangnano9k $BUILD/hello.fs"
echo "  フラッシュへ書き込み: openFPGALoader -b tangnano9k -f $BUILD/hello.fs"
