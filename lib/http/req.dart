import 'dart:async';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;

final Logger _logger = Logger('socket_io_client_flutter:transport.XHRTransport');

class FlutterHttpRequestStreamSubscription extends StreamSubscription {
  @override
  Future<E> asFuture<E>([E? futureValue]) {
    return Future(() => (null as E));
  }
  @override
  Future cancel() {
    return Future(() => null);
  }
  @override
  bool get isPaused => false;
  @override
  void onData(void Function(dynamic data)? handleData) {}
  @override
  void onDone(void Function()? handleDone) {}
  @override
  void onError(Function? handleError) {}
  @override
  void pause([Future? resumeSignal]) {}
  @override
  void resume() {}
}

typedef HttpRequestCallback = Null Function(dynamic);

class FlutterEvent {}

class FlutterHttpRequestStream /*extends Stream<FlutterEvent>*/ {
  late FlutterHttpRequest req;
  HttpRequestCallback? listener;
  FlutterHttpRequestStream();
  StreamSubscription listen(HttpRequestCallback onData,
      {Function? onError, void onDone()?, bool? cancelOnError}) {
    this.listener = onData;
    return FlutterHttpRequestStreamSubscription();
  }
}

class FlutterHttpRequest {
  Future<http.Response>? future;
  String? method;
  String? url;
  static Map<String, String> headers = Map<String, String>();
  var timeout;
  var onload;
  var onerror;
  var readyState = -1;
  var onReadyStateChange = FlutterHttpRequestStream();
  var responseType;
  var status;
  var responseText;
  ByteBuffer? response;
  Map<String, String> responseHeaders = {};
  FlutterHttpRequest() {
    onReadyStateChange.req = this;
  }
  open(String method, String url, {bool asynch=false, String user='', String password=''}) {
    this.method = method;
    this.url = url;
  }
  abort() {}
  setRequestHeader(String key, String value) {
    headers[key] = value;
  }
  Future<http.Response> send(var data) {
    var self = this;
    try {
      if (method == 'GET') {
        _logger.fine('FlutterHttpRequest ${method} ${url}');
        future = http.get(Uri.parse(url!), headers: headers);
      } else if (method == 'POST') {
        _logger.fine('FlutterHttpRequest ${method} ${url} ${data}');
        future = http.post(Uri.parse(url!), headers: headers, body: data);
      }
      future?.then((response) {
        if (response.headers['set-cookie'] != null) {
          headers['cookie'] = response.headers['set-cookie'] ?? '';
        }
        responseText = response.body;
        status = response.statusCode;
        _logger.fine(
            'FlutterHttpRequest ${method} ${status} ${url} ${data} ${responseText}');
        Map event = {'target': self};
        readyState = 2;
        responseHeaders = response.headers;
        onReadyStateChange.listener!(event);
        if (responseType == 'arraybuffer') {
          this.response = response.bodyBytes.buffer;
        }
        readyState = 4;
        onReadyStateChange.listener!(event);
      });
      return future!;
    } catch (e) {
      onerror(e);
      return future!;
    }
  }
  String getResponseHeader(String typ) {
    for (String key in responseHeaders.keys) {
      if (key.toLowerCase() == typ.toLowerCase()) {
        return responseHeaders[key] ?? '';
      }
    }
    return '';
  }
}
