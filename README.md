# comproc-veryl

[ComProc CPU ボード Rev4](https://github.com/uchan-nos/comproc)（Tang Nano 9K）の
周辺機器を [Veryl](https://veryl-lang.org/) で駆動するデモ集。

CPU は使わず、すべて純ハードウェアとして実装している。

```
+-----------+  +-----------+  +------------+  +-----------+
| LifeEngine|  | SnakeEngine| | AnimEngine |  |    ADC    |
+-----------+  +-----------+  +------------+  +-----------+
      |              |              |              |
      +--------------+------+-------+--------------+
                            |
                    +----------------+     +----------------+
                    |   LedMatrix    |     |   LcdConsole   |
                    | 8x8 + 7セグ走査 |     | 16x2 テキスト   |
                    +----------------+     +----------------+
                            |                      |
                    8x8 LED / 7セグ            HD44780 LCD
```

実機で動作確認済み。

## モードと操作

SW1（8 連 DIP スイッチ）でモードと速度を選ぶ。

| SW1-1,2 | モード | 内容 |
| --- | --- | --- |
| 00 | LIFE | ライフゲーム（8x8 トーラス） |
| 01 | ANIM | アニメーション 4 種 |
| 10 | SNAKE | スネーク |
| 11 | ADC | 自作 ADC のレベルメーター |

| SW1 | 役割 |
| --- | --- |
| 1, 2 | モード |
| 3, 4, 5 | 速度（000=1 秒/コマ 〜 111=約 8ms/コマ） |
| 6, 7 | LIFE の初期パターン / ANIM のパターン番号 |
| 8 | 一時停止（7 セグが「-」になる） |

LIFE の初期パターン（SW1-6,7）: `00` ランダム / `01` グライダー / `10` R ペントミノ / `11` 全消去。

ボタン S1（Tang Nano の pin 3 側）:

- LIFE: 盤面をまき直す
- ANIM: パターンを次へ
- SNAKE: 右に曲がる（ゲームオーバー中はやり直し）

UART（115200bps 8N1）:

| キー | 動作 |
| --- | --- |
| `r` | やり直し / まき直し |
| スペース | 一時停止の切り替え |
| `n` | 一時停止中でも 1 コマ進める |
| `w` `a` `s` `d` | SNAKE の方向 / LIFE のカーソル移動 |
| `t` | LIFE のカーソル位置のセルを反転 |
| `g` | グライダーを置く |
| `c` | 盤面を全消去 |
| `p` | いまの状態を 1 行送り返す |

500ms ごとに LCD と同じ内容が 1 行で流れてくる。

```
LIFE G=0042 P=23|SPD=3 RUN SW=0C
```

## 周辺機器の使い方

| 周辺機器 | 使い道 |
| --- | --- |
| 8x8 LED マトリクス | ライフゲーム / スネーク / アニメーションの盤面 |
| 7 セグ LED | 世代数の 1 の位・スコア・ADC 値。一時停止中は「-」 |
| キャラクタ LCD 16x2 | モード・世代数・生存数・スコア・速度・SW の状態 |
| SW1（8 連 DIP） | モード・速度・パターン・一時停止 |
| ボタン S1 (pin 3) | モードごとの操作 |
| ボタン S2 (pin 4) | リセット |
| UART | 対話操作と状態表示 |
| ADC（コンパレータ + PWM DAC） | レベルメーター表示と乱数の種 |
| GPIO ヘッダ 8 本 | 表示中の列データをそのまま出力（外部 LED バー / ロジアナ用） |
| オンボード LED 6 個 | LCD 初期化完了・一時停止・UART 送信中・ボタン・モード |

**microSD だけは使っていない。** ピン 36〜39 が LED マトリクスの ROW1〜ROW3 と
7 セグの共通アノードと物理的に共有されているため、8 行フルのマトリクスと
7 セグを使いながら SD カードを読むことはできない（本家 comproc が
`led_row[7:3]` の 5 行しか使っていないのはこのため）。

## ディレクトリ構成

```
src/
  main.veryl            トップ。モードの切り替えと全体の配線
  board_pkg.veryl       7 セグのパターン・BCD 変換などの共通関数
  led_matrix.veryl      8x8 マトリクス + 7 セグの 9 スロット時分割走査
  life_engine.veryl     ライフゲーム（64 セルを組み合わせ回路で同時計算）
  snake_engine.veryl    スネーク（体の円形バッファ + 64 ビット占有マップ）
  anim_engine.veryl     アニメーション 4 種
  adc.veryl             逐次比較 AD 変換器
  uart.veryl            UART 送受信
  lfsr.veryl            32 ビット Galois LFSR
  sw_input.veryl        スイッチの同期化とチャタリング取り
  lcd_console.veryl     16x2 テキストを常時書き換える表示器
  lcd_writer.veryl      HD44780 を 4 ビットモードで駆動する書き込みエンジン
  lcd_hello.veryl       最初に作った "hello, world" 表示（単体デモとして残置）
  *_test.veryl          テストベンチ
board/rev4_tangnano9k/  Gowin EDA プロジェクトとピン制約
tool/build-bitstream.sh Gowin EDA を使わずに .fs を作るスクリプト
```

## ビルドと書き込み

### Veryl → SystemVerilog

```sh
veryl build
```

### Gowin EDA を使わない（オープンソースフロー）

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

macOS では oss-cad-suite を展開したあと `xattr -dr com.apple.quarantine <展開先>` が必要。

### Gowin EDA を使う

`board/rev4_tangnano9k/rev4_tangnano9k.gprj` を開いて Synthesize → Place & Route。

## テスト

```sh
veryl check                 # 静的解析
veryl test                  # Veryl 内蔵シミュレータ
veryl test --sim verilator  # Verilator
veryl synth                 # 概算のゲート数・クリティカルパス
```

| テスト | 内容 |
| --- | --- |
| `test_life_engine` | 3x3 近傍 **512 通りの全数検査**、ブリンカーの振動、グライダーが 4 世代で斜めに 1 マス進むこと、セル反転 |
| `test_snake_engine` | 初期配置、前進、折り返し入力の無視、端の回り込み、餌を食べて伸びること、自分の体との衝突 |
| `test_uart` | 送受信のループバック（0x00 / 0xff / 0x55 / 0xaa などを含む 8 バイト） |
| `test_lcd_hello` | LCD 端子に出る 38 ニブルの値と順序、電源投入待ち、E パルス幅、転送間隔 |

生成された SystemVerilog は `verilator --lint-only -Wall` が警告なしで通る。

## 回路の要点

### LED マトリクスと 7 セグ

ComProc CPU ボードの LED まわりは次のようになっている（回路図 rev4 より）。

```
FPGA --[1k]-- G  Q1..Q9 (SSM3J332R, P-ch MOSFET)   ROW1..ROW8 / 7SEG
              S = +3V3, D = 行                      → アクティブ Low

FPGA ---- D0..D7 ┬─ U5 TBD62083APG ─→ COL1..COL8   → アクティブ High
                 └─ U4 TBD62083AFG ─→ 7 セグのセグメント
```

行は 9 本（マトリクス 8 行 + 7 セグの共通アノード）あり、列データ D0..D7 は
マトリクスと 7 セグで共有されている。そのため 9 スロットを 1ms ずつ順に点灯させる
（1 巡 9ms ＝ 約 111Hz）。

基板では COL1 が右端に来るので、`LedMatrix` の `MIRROR_X` で左右を反転して
`i_frame[y][0]` が左端になるようにしてある。

### ライフゲーム

64 セルぶんの次世代を組み合わせ回路で同時に求め、1 クロックで置き換える。
盤面の端はつながっている（トーラス）。

x 方向の折り返しは添字の計算ではなく、行を 1 ビット回した複製を作って表現している。
動的な添字を使うと yosys が範囲外と判断して端のセルが undef になるため。

固定物（次世代が同じ）か 2 世代周期の振動子になった状態が 8 世代続くと、
自動で盤面をまき直す。

### ADC

外部回路はコンパレータ + PWM DAC + サンプル&ホールド。本家 comproc の `adc.sv` と
同じ逐次比較だが、内蔵発振器 (125MHz) を使わず sys_clk (27MHz) だけで動かしている。
PWM のキャリアは約 106kHz、1 回の変換は約 8.5ms。

何もつながっていなくてもコンパレータ入力のノイズが乗るので、
変換結果は LFSR の種としても使っている。

## ピン割り当て（Rev4）

| 信号 | ピン |
| --- | --- |
| `sys_clk` | 52 |
| `rst_n_raw` | 4（オンボードボタン S2） |
| `btn_n_raw` | 3（オンボードボタン S1） |
| `led_row[8:0]` | 37, 36, 39, 25, 26, 27, 28, 29, 38（最後が 7SEG） |
| `led_col[7:0]` | 30, 33, 34, 40, 35, 41, 42, 51 |
| `lcd_e` / `lcd_rw` / `lcd_rs` | 76 / 77 / 63 |
| `lcd_db[3:0]` | 32, 31, 49, 48（DB7..DB4） |
| `sw_n_raw[7:0]` | 79〜86（SW1） |
| `uart_rx` / `uart_tx` | 54 / 53（ComProc ボードの FT234X） |
| `uart_rx2` / `uart_tx2` | 18 / 17（Tang Nano 9K の BL702） |
| `adc_cmp` / `adc_sh_ctl` / `adc_dac_pwm` | 55 / 56 / 57 |
| `gpio[7:0]` | 68〜75 |
| `onboard_led[5:0]` | 10, 11, 13, 14, 15, 16 |

UART は 2 系統に同じものを出していて、受信はどちらからでも受け付ける
（使っていない側はプルアップで High のままなので論理積で合成できる）。

## 既知の注意点

- 本家 `port.cst` は `lcd_db[7:4]` という添字だが、Veryl は `[3:0]` のビット範囲しか
  生成しないため `lcd_db[3]` を DB7 として添字を振り直している。
- pin 4（ボタン）とオンボード LED は同じ I/O バンクなので `IO_TYPE` を指定していない。
  本家のように LVCMOS18 と LVCMOS33 を混ぜると `gowin_pack` がバンク電圧の衝突で落ちる。
- ループの中で関数を呼ぶと yosys が定数式として扱って失敗することがある
  （`Non-constant function call in constant expression`）。
  組み合わせ回路のループの中では関数呼び出しを避け、テーブルを引く形にしている。
- 使っていないビットを持つレジスタが残ると nextpnr-himbaechel が
  `no BELs remaining to implement cell type '$buf'` で落ちることがある。
  カウンタの幅は実際に読むビット数に合わせる。
- `Veryl.toml` で `omit_project_prefix = true` にしているため、生成される
  SystemVerilog のモジュール名にプロジェクト名の接頭辞が付かない。
