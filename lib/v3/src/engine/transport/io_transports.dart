// Copyright (C) 2019 Potix Corporation. All Rights Reserved
// History: 2019-01-21 12:15
// Author: jumperchen<jumperchen@potix.com>
import '../../../src/engine/transport/xhr_transport.dart';
import '../../../src/engine/transport/io_websocket_transport.dart';
import '../../../src/engine/transport/transport.dart';

class Transports {
  static List<String> upgradesTo(String from) {
    if ('polling' == from) {
      return ['websocket'];
    }
    return [];
  }

  static Transport newInstance(String name, options) {
    if (name == 'polling') {
      return XHRTransport(options);
    }
    // only support websocket here.
    return IOWebSocketTransport(options);
  }
}
