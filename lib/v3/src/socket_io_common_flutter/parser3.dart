/**
 * parser.dart
 *
 * Purpose:
 *
 * Description:
 *
 * History:
 *    20/02/2017, Created by jumperchen
 *
 * Copyright (C) 2017 Potix Corporation. All Rights Reserved.
 */
import 'dart:async';

import 'dart:convert';
import 'dart:typed_data';

import 'package:socket_io_common/src/engine/parser/wtf8.dart';

// Protocol version
enum PacketType3 { OPEN, CLOSE, PING, PONG, MESSAGE, UPGRADE, NOOP }

class PacketParser3 {
  static final protocol = 3;

  static final List<String?> PacketTypeList = const <String?>[
    'open',
    'close',
    'ping',
    'pong',
    'message',
    'upgrade',
    'noop'
  ];

  static final Map<String, int> PacketTypeMap = const <String, int>{
    'open': 0,
    'close': 1,
    'ping': 2,
    'pong': 3,
    'message': 4,
    'upgrade': 5,
    'noop': 6
  };

  static const ERROR_PACKET = const {'type': 'error', 'data': 'parser error'};
  static String? encodePacket(Map packet,
      {dynamic supportsBinary,
      utf8encode = false,
      required callback(_),
      bool fromClient = false}) {
    if (supportsBinary is Function) {
      callback = supportsBinary as dynamic Function(dynamic);
      supportsBinary = null;
    }

    if (utf8encode is Function) {
      callback = utf8encode as dynamic Function(dynamic);
      utf8encode = null;
    }

    if (packet['data'] != null) {
      if (packet['data'] is Uint8List) {
        return encodeBuffer(packet, supportsBinary, callback,
            fromClient: fromClient);
      } else if (packet['data'] is Map &&
          (packet['data']['buffer'] != null &&
              packet['data']['buffer'] is ByteBuffer)) {
        packet['data'] = (packet['data']['buffer'] as ByteBuffer).asUint8List();
        return encodeBuffer(packet, supportsBinary, callback,
            fromClient: fromClient);
      } else if (packet['data'] is ByteBuffer) {
        packet['data'] = (packet['data'] as ByteBuffer).asUint8List();
        return encodeBuffer(packet, supportsBinary, callback,
            fromClient: fromClient);
      }
    }

    // Sending data as a utf-8 string
    var encoded = '''${PacketTypeMap[packet['type']]}''';

    // data fragment is optional
    if (packet['data'] != null) {
      encoded += utf8encode == true
          ? WTF8.encode('''${packet['data']}''')
          : '''${packet['data']}''';
    }

    return callback('$encoded');
  }

  /**
   * Encode Buffer data
   */

  static encodeBuffer(packet, supportsBinary, callback,
      {fromClient = false /*use this to check whether is in client or not*/}) {
    if (!supportsBinary) {
      return encodeBase64Packet(packet, callback);
    }

    var data = packet['data'];
    // 'fromClient' is to check if the runtime is on server side or not,
    // because Dart server's websocket cannot send data with byte buffer.
    final newData = new Uint8List(data.length + 1);
    newData
      ..setAll(0, [PacketTypeMap[packet['type']]!]..length = 1)
      ..setAll(1, data);
    if (fromClient) {
      return callback(newData.buffer);
    } else {
      return callback(newData);
    }
  }

  /**
   * Encodes a packet with binary data in a base64 string
   *
   * @param {Object} packet, has `type` and `data`
   * @return {String} base64 encoded message
   */

  static encodeBase64Packet(packet, callback) {
    var message = '''b${PacketTypeMap[packet['type']]}''';
    message += base64.encode(packet.data.toString().codeUnits);
    return callback(message);
  }

  static decodePacket(dynamic encodedPacket, binaryType, bool utf8decode) {
    var type;

    // String data
    if (encodedPacket is String) {
      type = encodedPacket[0];

      if (type == 'b') {
        return decodeBase64Packet((encodedPacket).substring(1), binaryType);
      }

      if (utf8decode == true) {
        try {
          encodedPacket = utf8.decode(encodedPacket.codeUnits);
        } catch (e) {
          return ERROR_PACKET;
        }
      }
      if ('${int.parse(type)}' != type ||
          PacketTypeList[type = int.parse(type)] == null) {
        return ERROR_PACKET;
      }

      if (encodedPacket.length > 1) {
        return {
          'type': PacketTypeList[type],
          'data': encodedPacket.substring(1)
        };
      } else {
        return {'type': PacketTypeList[type]};
      }
    }

    // Binary data
    if (binaryType == 'arraybuffer' || encodedPacket is ByteBuffer) {
      // wrap Buffer/ArrayBuffer data into an Uint8Array
      var intArray = (encodedPacket as ByteBuffer).asUint8List();
      type = intArray[0];
      return {'type': PacketTypeList[type], 'data': intArray.sublist(0)};
    }

//    if (data instanceof ArrayBuffer) {
//      data = arrayBufferToBuffer(data);
//    }
    type = encodedPacket[0];
    return {'type': PacketTypeList[type], 'data': encodedPacket.sublist(1)};
  }

  static decodeBase64Packet(String msg, String binaryType) {
    var type = PacketTypeList[msg.codeUnitAt(0)];
    var data = base64.decode(utf8.decode(msg.substring(1).codeUnits));
    if (binaryType == 'arraybuffer') {
      var abv = new Uint8List(data.length);
      for (var i = 0; i < abv.length; i++) {
        abv[i] = data[i];
      }
      return {'type': type, 'data': abv.buffer};
    }
    return {'type': type, 'data': data};
  }

  static hasBinary(List packets) {
    return packets.any((map) {
      final data = map['data'];
      return data != null && data is ByteBuffer;
    });
  }

  static encodePayload(List packets,
      {bool supportsBinary = false, required callback(_)}) {
    if (supportsBinary && hasBinary(packets)) {
      return encodePayloadAsBinary(packets, callback);
    }

    if (packets.isEmpty) {
      return callback('0:');
    }

    var encodeOne = (packet, doneCallback(_)) {
      encodePacket(packet, supportsBinary: supportsBinary, utf8encode: false,
          callback: (message) {
        doneCallback(_setLengthHeader(message));
      });
    };

    map(packets, encodeOne, (results) {
      return callback(results.join(''));
    });
  }

  static _setLengthHeader(message) {
    return '${message.length}:$message';
  }

  /**
   * Async array map using after
   */
  static map(List ary, each(_, callback(msg)), done(results)) {
    var result = [];
    Future.wait(ary.map((e) {
      return new Future.microtask(() => each(e, (msg) {
            result.add(msg);
          }));
    })).then((r) => done(result));
  }

/*
 * Decodes data when a payload is maybe expected. Possible binary contents are
 * decoded from their base64 representation
 *
 * @param {String} data, callback method
 * @api public
 */

  static decodePayload(encodedPayload, binaryType) {
    if (encodedPayload is! String) {
      return decodePayloadAsBinary(encodedPayload, binaryType: binaryType);
    }

    if (encodedPayload == '') {
      // parser error - ignoring payload
      return [];
    }

    var length = '', n, msg, packet;
    var packets = [];

    for (int i = 0, l = encodedPayload.length; i < l; i++) {
      var chr = encodedPayload[i];

      if (chr != ':') {
        length += chr;
        continue;
      }

      if (length.isEmpty || (length != '${(n = num.tryParse(length))}')) {
        // parser error - ignoring payload
        break;
      }

      int nv = n!;
      msg = encodedPayload.substring(i + 1, i + 1 + nv);

      if (length != '${msg.length}') {
        // parser error - ignoring payload
        break;
      }

      if (msg.isNotEmpty) {
        packet = decodePacket(msg, binaryType, false);

        if (ERROR_PACKET['type'] == packet['type'] &&
            ERROR_PACKET['data'] == packet['data']) {
          // parser error in individual packet - ignoring payload
          break;
        }

        packets.add(packet);
      }

      // advance cursor
      i += nv;
      length = '';
    }

    return packets;
  }

  static decodePayloadAsBinary(List<int> data, {bool? binaryType}) {
    var bufferTail = data;
    var buffers = [];
    var i;
    var packets = [];

    while (bufferTail.length > 0) {
      var strLen = '';
      var isString = bufferTail[0] == 0;
      for (i = 1;; i++) {
        if (bufferTail[i] == 255) break;
        // 310 = char length of Number.MAX_VALUE
        if (strLen.length > 310) {
          return packets;
        }
        strLen += '${bufferTail[i]}';
      }
      bufferTail = bufferTail.skip(strLen.length + 1).toList();

      var msgLength = int.parse(strLen);

      dynamic msg = bufferTail.getRange(1, msgLength + 1);
      if (isString == true) msg = new String.fromCharCodes(msg);
      buffers.add(msg);
      bufferTail = bufferTail.skip(msgLength + 1).toList();
    }

    var total = buffers.length;
    for (i = 0; i < total; i++) {
      var buffer = buffers[i];
      packets.add(decodePacket(buffer, binaryType, true));
    }
    return packets;
  }

  static encodePayloadAsBinary(List packets, callback(_)) {
    if (packets.isEmpty) {
      return callback(new Uint8List(0));
    }

    map(packets, encodeOneBinaryPacket, (results) {
      var list = [];
      results.forEach((e) => list.addAll(e));
      return callback(list);
    });
  }

  static encodeOneBinaryPacket(p, doneCallback(dynamic _)) {
    var onBinaryPacketEncode = (packet) {
      var encodingLength = '${packet.length}';
      var sizeBuffer;

      if (packet is String) {
        sizeBuffer = new Uint8List(encodingLength.length + 2);
        sizeBuffer[0] = 0; // is a string (not true binary = 0)
        for (var i = 0; i < encodingLength.length; i++) {
          sizeBuffer[i + 1] = int.parse(encodingLength[i]);
        }
        sizeBuffer[sizeBuffer.length - 1] = 255;
        return doneCallback(
            new List.from(sizeBuffer)..addAll(stringToBuffer(packet)));
      }

      sizeBuffer = new Uint8List(encodingLength.length + 2);
      sizeBuffer[0] = 1; // is binary (true binary = 1)
      for (var i = 0; i < encodingLength.length; i++) {
        sizeBuffer[i + 1] = int.parse(encodingLength[i]);
      }
      sizeBuffer[sizeBuffer.length - 1] = 255;

      doneCallback(new List.from(sizeBuffer)..addAll(packet));
    };
    encodePacket(p,
        supportsBinary: true, utf8encode: true, callback: onBinaryPacketEncode);
  }

  static List<int> stringToBuffer(String string) {
    var buf = new Uint8List(string.length);
    for (var i = 0, l = string.length; i < l; i++) {
      buf[i] = string.codeUnitAt(i);
    }
    return buf;
  }
}
