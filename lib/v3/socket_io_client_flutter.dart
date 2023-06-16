///
/// socket_io_client_flutter.dart
///
/// Purpose:
///
/// Description:
///
/// History:
///   26/04/2017, Created by jumperchen
///
/// Copyright (C) 2017 Potix Corporation. All Rights Reserved.
///

library socket_io_client_flutter;

import 'package:logging/logging.dart';
import './src/socket.dart';
import './socket_io_common/src/engine/parser/parser.dart' as parser;
import './src/engine/socket.dart' as eio;
import './src/engine/parseqs.dart';
import './src/manager.dart';

export './src/socket.dart';
export './src/darty.dart';

// Protocol version
final protocol = parser.protocol;

final Map<String, dynamic> cache = {};

final Logger _logger = Logger('socket_io_client_flutter');

///
/// Looks up an existing `Manager` for multiplexing.
/// If the user summons:
///
///   `io('http://localhost/a');`
///   `io('http://localhost/b');`
///
/// We reuse the existing instance based on same scheme/port/host,
/// and we initialize sockets for each namespace.
///
/// @api public
///
Socket io(uri, [opts]) => _lookup(uri, opts);

Socket _lookup(uri, opts) {
  opts = opts ?? <dynamic, dynamic>{};

  var parsed = Uri.parse(uri);
  var id = '${parsed.scheme}://${parsed.host}:${parsed.port}';
  var path = parsed.path;
  var sameNamespace = cache.containsKey(id) && cache[id].nsps.containsKey(path);
  var newConnection = opts['forceNew'] == true ||
      opts['force new connection'] == true ||
      false == opts['multiplex'] ||
      sameNamespace;

  Manager io;

  if (newConnection) {
    _logger.fine('ignoring socket cache for $uri');
    io = Manager(uri: uri, options: opts);
  } else {
    io = cache[id] ??= Manager(uri: uri, options: opts);
  }
  if (parsed.query.isNotEmpty && opts['query'] == null) {
    opts['query'] = parsed.query;
  } else if (opts != null && opts['query'] is Map) {
    opts['query'] = encode(opts['query']);
  }
  String nsp = parsed.path.isEmpty ? '/' : parsed.path;
  if (opts.containsKey('nsp')) {
    nsp = opts['nsp'];
  }
  return io.socket(nsp, opts);
}

const v4 = {
  'eio': eio.Socket,
  'eio_protocol': 3,
  'protocol': 4,
  'Manager': Manager,
  'Socket': Socket,
  'io': io,
  'connect': io,
};
