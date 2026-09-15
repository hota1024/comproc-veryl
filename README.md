# comproc-veryl

[ComProc CPU ボード Rev4](https://github.com/uchan-nos/comproc)（Tang Nano 9K）の
キャラクタ LCD に `hello, world` を表示する回路を [Veryl](https://veryl-lang.org/) で書いたもの。

CPU は使わず、LCD コントローラ（HD44780 互換）を直接叩く純ハードウェアとして実装している。
コマンド列の考え方は本家の [`src/examples/lcd.c`](https://github.com/uchan-nos/comproc/blob/main/src/examples/lcd.c) と同じ。

ComProc CPU ボード Rev4 (Tang Nano 9K) の実機で表示を確認済み
（sv2v + yosys + nextpnr-himbaechel + gowin_pack のオープンソースフロー）。

```
+----------------+     +-----------+     +-----------+
|    LcdHello    | --> | LcdWriter | --> |    LCD    |
| 表示シーケンス |     | 4bit 転送 |     | HD44780   |
+----------------+     +-----------+     +-----------+
```

## ディレクトリ構成

```
src/
  main.veryl        Rev4 ボード用トップモジュール（ピン名は port.cst に対応）
  lcd_hello.veryl   初期化コマンド列と "hello, world" を送り出すシーケンサ
  lcd_writer.veryl  HD44780 を 4 ビットモードで駆動する書き込みエンジン
  lcd_hello_test.veryl  LCD 端子の波形を検証するテストベンチ（合成対象外）
board/rev4_tangnano9k/
  rev4_tangnano9k.gprj   Gowin EDA プロジェクト
  src/port.cst           ピン割り当て
  src/timing.sdc         27 MHz のクロック制約
  impl/project_process_config.json  合成オプション（トップは Main、SystemVerilog 2017）
tool/
  build-bitstream.sh     Gowin EDA を使わずに .fs を作るスクリプト
target/               veryl build が生成する SystemVerilog（git 管理外）
build/                オープンソースフローの中間生成物（git 管理外）
```

## ビルドと書き込み

### 1. Veryl → SystemVerilog

```sh
veryl build
```

`target/main.sv`、`target/lcd_hello.sv`、`target/lcd_writer.sv` が生成される。

### 2-a. Gowin EDA を使う

`board/rev4_tangnano9k/rev4_tangnano9k.gprj` を Gowin EDA で開き、Synthesize → Place & Route を実行する。
生成された `.fs` を Programmer か `openFPGALoader` で書き込む。

```sh
openFPGALoader -b tangnano9k board/rev4_tangnano9k/impl/pnr/*.fs      # SRAM
openFPGALoader -b tangnano9k -f board/rev4_tangnano9k/impl/pnr/*.fs   # フラッシュ
```

### 2-b. Gowin EDA を使わない（オープンソースフロー）

macOS には Gowin EDA が無いので、こちらが実用的。
[oss-cad-suite](https://github.com/YosysHQ/oss-cad-suite-build/releases)（yosys /
nextpnr-himbaechel / gowin_pack / openFPGALoader が入っている）と `sv2v` を用意して、

```sh
./tool/build-bitstream.sh
openFPGALoader -b tangnano9k build/hello.fs      # SRAM（電源断で消える）
openFPGALoader -b tangnano9k -f build/hello.fs   # フラッシュ
```

中身は sv2v → yosys → nextpnr-himbaechel → gowin_pack の 4 段。
`port.cst` は Gowin 形式のまま nextpnr に渡せる（SDC は使われないので `--freq 27` で代用）。
Veryl が出す SystemVerilog は yosys が直接読めない（ユーザー定義型を返す function がある）ため
sv2v を挟んでいる。

macOS では oss-cad-suite を展開したあと `xattr -dr com.apple.quarantine <展開先>` が必要。

## テスト

```sh
veryl check                 # 静的解析
veryl test                  # Veryl 内蔵シミュレータ
veryl test --sim verilator  # Verilator
veryl synth                 # 概算のゲート数・クリティカルパス
```

`src/lcd_hello_test.veryl` が、LCD の端子に出る波形を次の観点で検証する。

- E の立ち下がり 38 回分について、そのときの RS と DB7..DB4 が期待どおりか
  （初期化シーケンス 14 ニブル + `hello, world` の 24 ニブル）
- 最初の転送を始めるまでに 40ms 以上待っているか
- E の High 幅が PWEH(450ns) を満たしているか
- 取り込みと取り込みの間を 2ms 以上空けているか
- RW が常に 0 か
- 38 回の転送のあとに `o_done` が立ち、それ以上 E が動かないか

テストベンチではクロックを 1 MHz として扱い、シミュレーション時間を短くしている
（待ち時間はすべて `CLK_FREQ_HZ` から計算しているため、比率は 27 MHz のときと同じ）。

生成された SystemVerilog は `verilator --lint-only -Wall` が警告なしで通る。

オープンソースフロー（yosys + nextpnr-himbaechel）では 177 セル / 67 FF に収まり、
`Max frequency for clock 'clk': 164 MHz (PASS at 27.00 MHz)` と報告される。

## 動作

リセットボタンは 2 段のフリップフロップで同期化して同期リセットとして使う。
FPGA コンフィグ直後はフリップフロップが 0 から始まるため、電源投入時にもリセットがかかる。
リセット解除後の動作は次の通り。

1. LCD の内部リセット完了を 100 ms 待つ。
2. 8 ビットモードで Function set を 3 回送り、4 ビットモードへ切り替える。
3. Function set / Display on / Entry mode / Clear display / DDRAM アドレス設定を送る。
4. `hello, world` の 12 文字を 1 行目に書く。
5. 完了するとオンボード LED が 1 個点灯する（負論理）。

全体でおよそ 0.2 秒。

## ピン割り当て（Rev4）

| 信号 | ピン | 備考 |
| --- | --- | --- |
| `sys_clk` | 52 | 27 MHz |
| `rst_n_raw` | 4 | リセットボタン（負論理） |
| `lcd_e` | 76 | |
| `lcd_rw` | 77 | 常に 0（書き込み専用） |
| `lcd_rs` | 63 | |
| `lcd_db[3]` | 32 | LCD の DB7 |
| `lcd_db[2]` | 31 | LCD の DB6 |
| `lcd_db[1]` | 49 | LCD の DB5 |
| `lcd_db[0]` | 48 | LCD の DB4 |
| `onboard_led[5:0]` | 10, 11, 13, 14, 15, 16 | Tang Nano 9K のオンボード LED（負論理） |

本家 `port.cst` は `lcd_db[7:4]` という添字を使っているが、Veryl は `[3:0]` のビット範囲しか
生成しないため、本プロジェクトでは `lcd_db[3]` を DB7 として添字を振り直している。

また pin 4（リセットボタン）とオンボード LED は同じ I/O バンクにあるため、`IO_TYPE` を指定せず
バンクの既定電圧に任せている。本家は pin 4 を LVCMOS18、LED を LVCMOS33 としているが、
この組み合わせはバンク電圧が衝突するので `gowin_pack` が弾く（Gowin EDA は通す）。

## タイミング

`LcdWriter` は RW を Low 固定にしてビジーフラグを読まないため、転送ごとに固定時間待つ。

| 項目 | 値 | 根拠 |
| --- | --- | --- |
| 電源投入後の待ち | 100 ms | データシートの規定は 40 ms 以上 |
| RS/DB 確定から E 立ち上げまで | 1 µs | tAS = 60 ns |
| E の High 幅 | 2 µs | PWEH = 450 ns |
| 通常の転送後の待ち | 2 ms | 仕様上は 37 µs。`lcd.c` の実績値に合わせた |
| 初期化・Clear Display 後の待ち | 5 ms | Function set 4.1 ms、Clear Display 1.52 ms |

データは E の立ち下がりで LCD に取り込まれる。

## 他リビジョンのボードで使う場合

`board/rev4_tangnano9k/src/port.cst` のピン番号を差し替える。Rev2 の場合は次の通り。

```
IO_LOC "lcd_e"     76;
IO_LOC "lcd_rw"    75;
IO_LOC "lcd_rs"    74;
IO_LOC "lcd_db[3]" 73; // DB7
IO_LOC "lcd_db[2]" 72; // DB6
IO_LOC "lcd_db[1]" 71; // DB5
IO_LOC "lcd_db[0]" 70; // DB4
```

## 既知の注意点

- Veryl が生成するポート宣言は `input var logic` 形式になる。Gowin EDA 側の Verilog 標準が
  SystemVerilog 2017 になっていないと構文エラーになるので、
  `impl/project_process_config.json` の `Verilog_Standard` を `Vlg_Std_Sysv2017` にしてある
  （GUI では Project → Configuration → Synthesize → Verilog Language）。
  それでも合成が通らない場合は、`Main` を包む薄い Verilog-2001 のラッパを書いて
  トップに据えるのが手っ取り早い。
- `Veryl.toml` で `omit_project_prefix = true` にしているため、生成される SystemVerilog の
  モジュール名にプロジェクト名の接頭辞が付かない（`Main`、`LcdHello`、`LcdWriter`）。
