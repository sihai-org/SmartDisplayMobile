import 'dart:convert';
import 'dart:typed_data';

class FrameHeader {
  final int ver;
  final int flags;
  final int reqId;
  final int total;
  final int index;
  final int payloadLen;
  const FrameHeader({
    required this.ver,
    required this.flags,
    required this.reqId,
    required this.total,
    required this.index,
    required this.payloadLen,
  });
}

class FrameEncoder {
  final int mtu;
  FrameEncoder(this.mtu);

  List<Uint8List> encodeJson(int reqId, Map<String, dynamic> payload) {
    final bytes = utf8.encode(jsonEncode(payload));
    // Use same margin as peripheral to avoid MTU edge cases
    final maxPayload = ((mtu - 3) - 10 - 2);
    final total = (bytes.length + maxPayload - 1) ~/ maxPayload;
    final out = <Uint8List>[];
    var off = 0;
    for (var i = 0; i < total; i++) {
      final end = (off + maxPayload) > bytes.length ? bytes.length : off + maxPayload;
      final slice = bytes.sublist(off, end);
      final endFlag = end >= bytes.length ? 1 : 0;
      final flags = (endFlag == 1 ? 0x01 : 0x00);
      final header = _buildHeader(1, flags, reqId, total, i, slice.length);
      out.add(Uint8List.fromList(header + slice));
      off = end;
    }
    return out;
  }

  List<int> _buildHeader(int ver, int flags, int reqId, int total, int index, int payloadLen) {
    final out = List.filled(10, 0);
    void w8(int i, int v) => out[i] = v & 0xFF;
    void w16(int i, int v) {
      out[i + 0] = (v >> 8) & 0xFF;
      out[i + 1] = v & 0xFF;
    }
    w8(0, ver); w8(1, flags); w16(2, reqId); w16(4, total); w16(6, index); w16(8, payloadLen);
    return out;
  }
}

class FrameDecoder {
  final Map<int, _Incoming> _msgs = {};

  Map<String, dynamic>? addPacket(Uint8List bytes) {
    if (bytes.length < 10) return null;
    final h = _parseHeader(bytes);
    if (h == null) return null;
    // Basic header validation to drop spurious updates (e.g., non-framed reads)
    if (h.ver != 1) return null;
    if (h.total <= 0 || h.total > 64) return null;
    if (h.index < 0 || h.index >= h.total) return null;
    if (h.payloadLen < 0) return null;
    if (10 + h.payloadLen > bytes.length) return null;
    final payload = bytes.sublist(10, 10 + h.payloadLen);
    final msg = _msgs.putIfAbsent(h.reqId, () => _Incoming(h.total));
    msg.add(h.index, payload);
    if (h.flags & 0x01 != 0) msg.endSeen = true;
    if (msg.endSeen && msg.isComplete) {
      _msgs.remove(h.reqId);
      final merged = msg.merge();
      final obj = jsonDecode(utf8.decode(merged));
      if (obj is Map<String, dynamic>) {
        // Always expose header reqId separately to avoid payload type clashes
        // If payload carries a string reqId, higher layer can still use hReqId for matching
        obj['hReqId'] = h.reqId;
        obj['reqId'] = obj['reqId'] ?? h.reqId;
        return obj;
      }
      return null;
    }
    return null;
  }

  FrameHeader? _parseHeader(Uint8List buf) {
    int u8(int i) => buf[i] & 0xFF;
    int u16(int i) => ((buf[i] & 0xFF) << 8) | (buf[i + 1] & 0xFF);
    return FrameHeader(
      ver: u8(0),
      flags: u8(1),
      reqId: u16(2),
      total: u16(4),
      index: u16(6),
      payloadLen: u16(8),
    );
  }
}

class _Incoming {
  final int total;
  final Map<int, Uint8List> parts = {};
  bool endSeen = false;
  _Incoming(this.total);
  void add(int idx, Uint8List data) { parts[idx] = data; }
  bool get isComplete => parts.length >= total;
  Uint8List merge() {
    final size = parts.values.fold<int>(0, (p, e) => p + e.length);
    final out = Uint8List(size);
    var off = 0;
    for (var i = 0; i < total; i++) {
      final p = parts[i];
      if (p == null) continue;
      out.setRange(off, off + p.length, p);
      off += p.length;
    }
    return out;
  }
}
