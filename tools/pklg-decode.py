#!/usr/bin/env python3
"""PacketLogger の .pklg から体組成計の独自プロトコルを読む。

iPhone に Apple の Bluetooth ログ用プロファイルを入れ、PacketLogger の
`File → New iOS Trace` で記録したものを渡す。HCI レイヤの記録なので、
リンクが暗号化されていても ATT は平文で読める。

    python3 tools/pklg-decode.py trace.pklg              # 測定データを読む
    python3 tools/pklg-decode.py trace.pklg --messages   # 全メッセージを並べる
    python3 tools/pklg-decode.py trace.pklg --solve      # タグ長の表を作り直す

プロトコルの仕様は BiteLog/Utilities/TanitaProtocol.swift と issue #146 にある。
未知のタグが出たら --solve で長さを求め、Swift 側の表に足す。
"""

import argparse
import datetime
import struct

# PacketLogger のレコード種別
ACL_SENT, ACL_RECV = 0x02, 0x03
# L2CAP のチャネル
CID_ATT = 0x0004
# 値を読み出す ATT オペコード
ATT_WRITE_REQ, ATT_WRITE_CMD, ATT_NOTIFY, ATT_INDICATE = 0x12, 0x52, 0x1B, 0x1D
# タグの上位バイトとして観測されているもの
TAG_HIGH_BYTES = (0x60, 0x61, 0x6A, 0x6F, 0x7E)

# タグごとの値の長さ。Swift 側の TanitaTag.valueLength と同じ内容。
VALUE_LENGTH = {
    0x6021: 2, 0x6022: 2, 0x6023: 2, 0x6024: 1, 0x6025: 2, 0x6027: 2,
    0x6028: 1, 0x6029: 2, 0x602B: 2, 0x602F: 2, 0x604F: 2, 0x6056: 2,
    0x605A: 1, 0x605B: 1, 0x6070: 1, 0x6076: 1, 0x6077: 1, 0x607D: 1,
    0x607E: 1, 0x614B: 2, 0x614C: 2, 0x6151: 2, 0x6152: 2, 0x6A11: 4,
    0x6A12: 2, 0x6A13: 1, 0x6A14: 1, 0x6A15: 4, 0x6A16: 8, 0x6A29: 6,
    0x6A2E: 4, 0x6A2F: 1, 0x6A30: 1, 0x6A32: 2, 0x6A33: 3, 0x6A37: 1,
    0x6A38: 1, 0x6A3B: 1, 0x6A3C: 2, 0x6A3D: 5, 0x6A3E: 2, 0x6F21: 2,
    0x6F22: 2, 0x7E21: 1, 0x7E22: 11, 0x7E2F: 2,
}

EPOCH = datetime.date(2000, 1, 1)
MEASUREMENT_RESPONSE = 0xB010


def int_be(value: bytes) -> int:
    return int.from_bytes(value, "big")


def seconds_to_clock(seconds: float) -> str:
    total = int(seconds)
    return f"{total // 3600:02d}:{total % 3600 // 60:02d}:{total % 60:02d}"


# 意味が分かっているタグ。(名前, 変換)
KNOWN_TAGS = {
    0x6021: ("体重 kg", lambda v: int_be(v) / 100),
    0x6022: ("体脂肪率 %", lambda v: int_be(v) / 10),
    0x6023: ("筋肉量 kg", lambda v: int_be(v) / 100),
    0x6024: ("筋肉スコア", lambda v: -(v[0] & 0x7F) if v[0] & 0x80 else v[0]),
    0x6025: ("内臓脂肪レベル", lambda v: int_be(v) / 10),
    0x6027: ("基礎代謝量 kcal", lambda v: int_be(v)),
    0x6028: ("体内年齢 歳", lambda v: int_be(v)),
    0x6029: ("推定骨量 kg", lambda v: int_be(v) / 100),
    0x602B: ("体水分率 %", lambda v: int_be(v) / 10),
    0x6056: ("BMI", lambda v: int_be(v) / 10),
    0x6A16: ("機種名", lambda v: v.decode("ascii", "replace").strip()),
    0x6A32: ("日付", lambda v: str(EPOCH + datetime.timedelta(days=int_be(v)))),
    0x6A33: ("時刻", lambda v: seconds_to_clock(int_be(v) / 2)),
    0x6A3E: ("身長 cm", lambda v: int_be(v) / 10),
}


def read_records(path):
    """.pklg のレコードを (時刻, 種別, ペイロード) で返す。

    1レコードは [長さ: 4バイトLE][秒: 4][マイクロ秒: 4][種別: 1][ペイロード]。
    長さフィールドはそれ自身を含まない。
    """
    data = open(path, "rb").read()
    offset = 0
    while offset + 4 <= len(data):
        (length,) = struct.unpack_from("<I", data, offset)
        if length < 9 or offset + 4 + length > len(data):
            break
        secs, usecs = struct.unpack_from("<II", data, offset + 4)
        yield secs + usecs / 1e6, data[offset + 12], data[offset + 13 : offset + 4 + length]
        offset += 4 + length


def read_att(path):
    """ACL を組み直して ATT の書き込みと通知を (時刻, 向き, 値) で返す。"""
    pending = {}
    for ts, kind, payload in read_records(path):
        if kind not in (ACL_SENT, ACL_RECV) or len(payload) < 4:
            continue
        (header,) = struct.unpack_from("<H", payload, 0)
        handle, boundary = header & 0x0FFF, (header >> 12) & 0x3
        (data_length,) = struct.unpack_from("<H", payload, 2)
        body, key = payload[4 : 4 + data_length], (kind, handle)

        # boundary 2 は PDU の先頭、1 は継続
        if boundary == 2 or key not in pending:
            pending[key] = bytearray(body)
        else:
            pending[key] += body

        buffer = pending[key]
        if len(buffer) < 4:
            continue
        l2cap_length, cid = struct.unpack_from("<HH", buffer, 0)
        if len(buffer) < 4 + l2cap_length:
            continue
        pdu = bytes(buffer[4 : 4 + l2cap_length])
        del pending[key]
        if cid != CID_ATT or len(pdu) < 3:
            continue
        if pdu[0] in (ATT_WRITE_REQ, ATT_WRITE_CMD, ATT_NOTIFY, ATT_INDICATE):
            yield ts, "→" if kind == ACL_SENT else "←", pdu[3:]


def read_messages(path):
    """20バイトのフレームを組み直して (時刻, 向き, コマンド, データ) で返す。

    フレームは 00 <offset> <seq> <len> <ペイロード>、
    メッセージは [全長-2: 2バイトBE][コマンド: 2][データ][チェックサム: 1]。
    """
    building = {}
    for ts, direction, value in read_att(path):
        if len(value) < 4 or value[0] != 0x00:
            continue
        offset, seq, length = value[1], value[2], value[3]
        key = (direction, seq)
        if offset == 0:
            building[key] = [ts, bytearray(value[4 : 4 + length])]
        elif key in building:
            building[key][1] += value[4 : 4 + length]
        else:
            continue

        buffer = building[key][1]
        if len(buffer) < 2:
            continue
        total = struct.unpack_from(">H", buffer, 0)[0] + 2
        if len(buffer) < total:
            continue
        message = bytes(buffer[:total])
        del building[key]

        expected = (~sum(message[:-1])) & 0xFF
        command = struct.unpack_from(">H", message, 2)[0]
        yield ts, direction, command, message[4:-1], message[-1] == expected


def parse_tlv(data, lengths=VALUE_LENGTH):
    """タグと値に切り分ける。長さの分からないタグが出たらそこで止める。"""
    fields, index = [], 0
    while index + 2 <= len(data):
        tag = struct.unpack_from(">H", data, index)[0]
        length = lengths.get(tag)
        if length is None or index + 2 + length > len(data):
            fields.append((tag, None))
            break
        fields.append((tag, data[index + 2 : index + 2 + length]))
        index += 2 + length
    return fields


def tlv_start(data):
    """コマンドごとに前置きの長さが違うので、最初のタグらしい位置から読む。"""
    for start in range(min(8, len(data))):
        if data[start] in TAG_HIGH_BYTES:
            return data[start:]
    return b""


def solve_lengths(path):
    """全メッセージが末尾ぴったりで解ける長さの割り当てを総当たりで探す。"""

    def walk(buffer, index, table):
        if index == len(buffer):
            return dict(table)
        if index + 2 > len(buffer) or buffer[index] not in TAG_HIGH_BYTES:
            return None
        tag = struct.unpack_from(">H", buffer, index)[0]
        candidates = [table[tag]] if tag in table else range(1, 13)
        for length in candidates:
            if index + 2 + length > len(buffer):
                continue
            merged = dict(table)
            merged[tag] = length
            result = walk(buffer, index + 2 + length, merged)
            if result is not None:
                return result
        return None

    regions = [tlv_start(data) for _, _, _, data, _ in read_messages(path)]
    regions = [r for r in regions if len(r) >= 3]
    table = {}
    # 短いものから解くと候補が絞られ、長いものの探索が軽くなる
    for region in sorted(regions, key=len):
        solved = walk(region, 0, table)
        if solved:
            table = solved
    unsolved = sum(1 for r in regions if walk(r, 0, table) is None)
    return table, len(regions), unsolved


def print_measurements(path):
    count = 0
    for ts, direction, command, data, checksum_ok in read_messages(path):
        if command != MEASUREMENT_RESPONSE:
            continue
        count += 1
        print(f"\n測定 {count}{'' if checksum_ok else '  (チェックサム不一致)'}")
        # 先頭2バイトはステータスと連番
        for tag, value in parse_tlv(tlv_start(data[2:])):
            if value is None:
                print(f"  0x{tag:04x} 長さ不明のタグ。--solve で求めて表に足す")
            elif tag in KNOWN_TAGS:
                name, convert = KNOWN_TAGS[tag]
                print(f"  0x{tag:04x} {name:16} = {convert(value)}")
            else:
                print(f"  0x{tag:04x} {'未同定':16}   {value.hex(' ')}")
    if count == 0:
        print("測定データが見つかりませんでした。--messages で中身を確認してください")


def print_messages(path):
    first = None
    for ts, direction, command, data, checksum_ok in read_messages(path):
        first = ts if first is None else first
        mark = "" if checksum_ok else " !"
        print(f"{ts - first:8.3f} {direction} cmd={command:04x}{mark} {data.hex(' ')}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pklg", help="PacketLogger の .pklg")
    parser.add_argument("--messages", action="store_true", help="全メッセージを並べる")
    parser.add_argument("--solve", action="store_true", help="タグ長の表を作り直す")
    args = parser.parse_args()

    if args.solve:
        table, total, unsolved = solve_lengths(args.pklg)
        print(f"TLVを含むメッセージ {total} 件 / 解けなかったもの {unsolved} 件")
        items = sorted(table.items())
        for i in range(0, len(items), 6):
            print("    " + "  ".join(f"0x{t:04X}: {n}," for t, n in items[i : i + 6]))
        new = {t: n for t, n in table.items() if t not in VALUE_LENGTH}
        if new:
            print("表に無いタグ:", ", ".join(f"0x{t:04X}: {n}" for t, n in sorted(new.items())))
    elif args.messages:
        print_messages(args.pklg)
    else:
        print_measurements(args.pklg)


if __name__ == "__main__":
    main()
