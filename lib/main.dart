import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/foundation.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Color(0xFFFFFFFF),
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SSMM ADMIN',
      theme: ThemeData(visualDensity: VisualDensity.adaptivePlatformDensity),
      home: const WebViewApp(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class WebViewApp extends StatefulWidget {
  const WebViewApp({Key? key}) : super(key: key);

  @override
  State<WebViewApp> createState() => _WebViewAppState();
}

class _WebViewAppState extends State<WebViewApp> {
  late WebViewController _controller;
  bool _isLoading = false;

  final String _initialUrl = 'https://ssmmadmin.in/';

  @override
  void initState() {
    super.initState();
    _controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (String url) {
                setState(() {
                  _isLoading = true;
                });
              },
              onPageFinished: (String url) {
                setState(() {
                  _isLoading = false;
                });
              },
              onNavigationRequest: (NavigationRequest request) {
                return NavigationDecision.navigate;
              },
              onWebResourceError: (WebResourceError error) {
                if (kDebugMode) {
                  print('WebView error: ${error.description}');
                }
              },
            ),
          )
          ..loadRequest(Uri.parse(_initialUrl));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        // appBar: AppBar(
        //   title: const Text('Flutter WebView'),
        //   elevation: 0,
        //   actions: [
        //     IconButton(
        //       icon: const Icon(Icons.refresh),
        //       onPressed: () {
        //         _controller.reload();
        //       },
        //     ),
        //   ],
        // ),
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_isLoading)
                Container(
                  color: Colors.white,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.blue),
                  ),
                ),
            ],
          ),
        ),
        // bottomNavigationBar: BottomAppBar(
        //   child: Row(
        //     mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        //     children: [
        //       IconButton(
        //         icon: const Icon(Icons.arrow_back),
        //         onPressed: () async {
        //           if (await _controller.canGoBack()) {
        //             _controller.goBack();
        //           }
        //         },
        //       ),
        //       IconButton(
        //         icon: const Icon(Icons.arrow_forward),
        //         onPressed: () async {
        //           if (await _controller.canGoForward()) {
        //             _controller.goForward();
        //           }
        //         },
        //       ),
        //       IconButton(
        //         icon: const Icon(Icons.home),
        //         onPressed: () {
        //           _controller.loadRequest(Uri.parse(_initialUrl));
        //         },
        //       ),
        //     ],
        //   ),
        // ),
      ),
    );
  }
}
