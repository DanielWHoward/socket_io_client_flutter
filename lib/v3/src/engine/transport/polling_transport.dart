import '../../../src/engine/parseqs.dart';

///
/// polling_transport.dart
///
/// Purpose:
///
/// Description:
///
/// History:
///   26/04/2017, Created by jumperchen
///
/// Copyright (C) 2017 Potix Corporation. All Rights Reserved.
import 'package:logging/logging.dart';
import '../../../src/engine/transport/transport.dart';
import '../../../socket_io_common/src/engine/parser/parser.dart';

final Logger _logger = Logger('socket_io:transport.PollingTransport');

defaultCallback(err, [foo, bar]) {}

abstract class PollingTransport extends Transport {
  ///
  /// Transport name.
  @override
  String? name = 'polling';

  @override
  bool? supportsBinary;
  bool? polling;

  ///
  /// Polling interface.
  ///
  /// @param {Object} opts
  /// @api private
  PollingTransport(Map opts) : super(opts) {
    var forceBase64 = opts['forceBase64'];
    if (/*!hasXHR2 || */ forceBase64) {
      supportsBinary = false;
    }
  }

  ///
  /// Opens the socket (triggers polling). We write a PING message to determine
  /// when the transport is open.
  ///
  /// @api private
  @override
  void doOpen() {
    poll();
  }

  ///
  /// Pauses polling.
  ///
  /// @param {Function} callback upon buffers are flushed and transport is paused
  /// @api private
  void pause(onPause) {
    var self = this;

    readyState = 'pausing';

    var pause = () {
      _logger.fine('paused');
      self.readyState = 'paused';
      onPause();
    };

    if (polling == true || writable != true) {
      var total = 0;

      if (polling == true) {
        _logger.fine('we are currently polling - waiting to pause');
        total++;
        once('pollComplete', (_) {
          _logger.fine('pre-pause polling complete');
          if (--total == 0) pause();
        });
      }

      if (writable != true) {
        _logger.fine('we are currently writing - waiting to pause');
        total++;
        once('drain', (_) {
          _logger.fine('pre-pause writing complete');
          if (--total == 0) pause();
        });
      }
    } else {
      pause();
    }
  }

  ///
  /// Starts polling cycle.
  ///
  /// @api public
  void poll() {
    _logger.fine('polling');
    polling = true;
    doPoll();
    emit('poll');
  }

  ///
  /// Overloads onData to detect payloads.
  ///
  /// @api private
  @override
  void onData(data) {
    var self = this;
    _logger.fine('polling got data $data');
    var callback = (packet, [index, total]) {
      // if its the first message we consider the transport open
      if ('opening' == self.readyState) {
        self.onOpen();
      }

      // if its a close packet, we close the ongoing requests
      if ('close' == packet['type']) {
        self.onClose();
        return false;
      }

      // otherwise bypass onData and handle the message
      self.onPacket(packet);
      return null;
    };

    // decode payload
    self.decodePayload(data,
        binaryType: socket!.binaryType != true, callback: callback);

    // if an event did not trigger closing
    if ('closed' != readyState) {
      // if we got data we're not polling
      polling = false;
      emit('pollComplete');

      if ('open' == readyState) {
        poll();
      } else {
        _logger.fine('ignoring poll - transport state "${readyState}"');
      }
    }
  }

  ///
  /// For polling, send a close packet.
  ///
  /// @api private
  @override
  void doClose() {
    var self = this;

    var close = ([_]) {
      _logger.fine('writing close packet');
      self.write([
        {'type': 'close'}
      ]);
    };

    if ('open' == readyState) {
      _logger.fine('transport open - closing');
      close();
    } else {
      // in case we're trying to close while
      // handshaking is in progress (GH-164)
      _logger.fine('transport not open - deferring close');
      once('open', close);
    }
  }

  ///
  /// Removes out of band data and decodes the clean payload.
  ///
  /// @param {Array} data packets
  /// @param {Object} typ type
  /// @param {Function} callback parser callback
  /// @api private
  decodePayload(data,
      {bool binaryType = false, callback(err, [foo, bar])=defaultCallback}) {
    var self = this;
    var cleanData = '';
    var outOfBand = '';
    var matchPos = [];
    if (data is String) {
      data = data.substring(data.startsWith('ok') ? 2 : 0);
      // find packets
      var pos = data.indexOf(':');
      while (pos != -1) {
        if ((pos > 0) &&
            (pos < (data.length - 1)) &&
            (data[pos - 1].compareTo('0') != -1) &&
            (data[pos - 1].compareTo('9') != 1) &&
            (data[pos + 1].compareTo('0') != -1) &&
            (data[pos + 1].compareTo('9') != 1)) {
          matchPos.add(pos);
        }
        pos = data.indexOf(':', pos + 1);
      }
      // separate packets from out of band data
      var prev = 0;
      var start = 0;
      var end = 0;
      var del = 0;
      var len = 0;
      var heur = 0;
      for (var m=0; m < matchPos.length; ++m) {
        start = matchPos[m] - del - 1;
        end = start + 1;
        while ((start >= 0) &&
            (data[start].compareTo('0') != -1) &&
            (data[start].compareTo('9') != 1)) {
          len = int.parse(data.substring(start, end));
          // heuristic to ignore extra outOfBand digit
          heur = data.length;
          if ((m + 1) < matchPos.length) {
            heur = matchPos[m+1] - del - 1;
          }
          if ((end + len) >= heur) {
            break;
          }
          --start;
        }
        ++start;
        if ((start >= 2) && (data.substring(start - 2, start) == 'ok')) {
          data = data.substring(0, start - 2) + data.substring(start);
          del += 2;
          start -= 2;
        }
        end = matchPos[m] - del;
        len = int.parse(data.substring(start, end));
        cleanData += data.substring(start, end+len+1);
        outOfBand += data.substring(prev, start);
        prev = end+len+1;
      }
      if (prev < data.length) {
        outOfBand += data.substring(prev);
      }
      // decode packets
      if (cleanData != '') {
        PacketParser.decodePayload(cleanData, binaryType: binaryType, callback: callback);
      }
      if (outOfBand != '') {
        self.outOfBand(outOfBand);
      }
    } else if (data) {
      PacketParser.decodePayload(data, binaryType: binaryType, callback: callback);
    }
  }

  ///
  /// Writes a packets payload.
  ///
  /// @param {Array} data packets
  /// @param {Function} drain callback
  /// @api private
  @override
  void write(List packets) {
    var self = this;
    writable = false;
    var callback = (packet, [index, total]) {
      // handle the message
      self.onPacket(packet);
    };
    var callbackfn = (data) {
      data = data.substring(data.startsWith('ok') ? 2 : 0);
      if (data.length > 0) {
        final packetRegExp = RegExp(r'^\d+:\d+');
        if ((data is! String) || packetRegExp.hasMatch(data)) {
          // decode payload
          self.decodePayload(data,
              binaryType: self.socket!.binaryType, callback: callback);
        } else {
          self.outOfBand(data);
        }
      }
      self.writable = true;
      self.emit('drain');
    };

    PacketParser.encodePayload(packets, supportsBinary: supportsBinary != false,
        callback: (data) {
      self.doWrite(data, callbackfn);
    });
  }

  ///
  /// Generates uri for connection.
  ///
  /// @api private
  String uri() {
    var query = this.query ?? {};
    var schema = secure ? 'https' : 'http';
    var port = '';
    var basepath = path;
    if (path is Function) {
      basepath = (path as Function)();
      basepath = Uri.parse(basepath).path;
    }

    // cache busting is forced
    if (timestampRequests != false) {
      query[timestampParam] =
          DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    }

    if (supportsBinary == false && !query.containsKey('sid')) {
      query['b64'] = 1;
    }

    // avoid port if default for schema
    if (this.port != null &&
        (('https' == schema && this.port != 443) ||
            ('http' == schema && this.port != 80))) {
      port = ':${this.port}';
    }

    var queryString = encode(query);

    // prepend ? to query
    if (queryString.isNotEmpty) {
      queryString = '?$queryString';
    }

    var ipv6 = hostname.contains(':');
    return schema +
        '://' +
        (ipv6 ? '[' + hostname + ']' : hostname) +
        port +
        basepath +
        queryString;
  }

  void doWrite(data, callback);
  void doPoll();
}
