import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart'; // 👈 Add this

void main() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFFFFFFF),
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zoy Business',
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
  final ImagePicker _imagePicker = ImagePicker();

  final String _initialUrl = 'https://zoybiz.com/';

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
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

                // Inject scripts after page load
                _injectImageUploadScript();
                _injectPrintScript();
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
          ..addJavaScriptChannel(
            'ImageUploader',
            onMessageReceived: (JavaScriptMessage message) {
              _handleImageUpload(message.message);
            },
          )
          ..addJavaScriptChannel(
            'PrintHandler',
            onMessageReceived: (JavaScriptMessage message) {
              _handlePrint(message.message);
            },
          )
          ..loadRequest(Uri.parse(_initialUrl));
  }

  void _injectPrintScript() {
    const String script = """
      (function() {
        window.PrintDiv = function() {
          var divToPrint = document.getElementById('divToPrint');
          if (divToPrint) {
            PrintHandler.postMessage(divToPrint.innerHTML);
          } else {
            alert('Invoice section not found!');
          }
        }
      })();
    """;

    _controller.runJavaScript(script);
  }

  Future<void> _handlePrint(String htmlContent) async {
    try {
      await Printing.layoutPdf(
        onLayout: (format) async {
          final pdf = await Printing.convertHtml(
            format: format,
            html: htmlContent,
          );
          return pdf;
        },
      );
    } catch (e) {
      if (kDebugMode) {
        print("Error in printing: $e");
      }
    }
  }

  void _injectImageUploadScript() {
    const String script = '''
      (function() {
        document.addEventListener('click', function(e) {
          if (e.target.type === 'file') {
            e.preventDefault();
            e.stopPropagation();
            window.currentImageInput = e.target;
            const accept = e.target.accept || '';
            const multiple = e.target.multiple || false;
            ImageUploader.postMessage(JSON.stringify({
              accept: accept,
              multiple: multiple
            }));
          }
        }, true);
        window.setImageFiles = function(files) {
          if (window.currentImageInput && files.length > 0) {
            const dt = new DataTransfer();
            files.forEach(file => dt.items.add(file));
            window.currentImageInput.files = dt.files;
            const event = new Event('change', { bubbles: true });
            window.currentImageInput.dispatchEvent(event);
            const inputEvent = new Event('input', { bubbles: true });
            window.currentImageInput.dispatchEvent(inputEvent);
          }
        };
      })();
    ''';
    _controller.runJavaScript(script);
  }

  Future<void> _handleImageUpload(String message) async {
    try {
      await _requestPermissions();
      bool allowMultiple = message.contains('"multiple": true');
      ImageSource? source = await _showImageSourceDialog();
      if (source == null) return;
      List<XFile> imageFiles = [];

      if (allowMultiple && source == ImageSource.gallery) {
        final List<XFile> selectedImages = await _imagePicker.pickMultiImage();
        imageFiles.addAll(selectedImages);
      } else {
        final XFile? selectedImage = await _imagePicker.pickImage(
          source: source,
        );
        if (selectedImage != null) {
          imageFiles.add(selectedImage);
        }
      }

      if (imageFiles.isNotEmpty) {
        List<String> fileScripts = [];
        for (var imageFile in imageFiles) {
          final bytes = await imageFile.readAsBytes();
          String base64 = base64Encode(bytes);
          String mimeType = _getMimeTypeFromPath(imageFile.path);
          String fileName = imageFile.name;

          fileScripts.add('''
            (function() {
              const byteCharacters = atob('$base64');
              const byteNumbers = new Array(byteCharacters.length);
              for (let i = 0; i < byteCharacters.length; i++) {
                byteNumbers[i] = byteCharacters.charCodeAt(i);
              }
              const byteArray = new Uint8Array(byteNumbers);
              return new File([byteArray], '$fileName', { type: '$mimeType' });
            })()
          ''');
        }

        String setFilesScript = '''
          (function() {
            const files = [${fileScripts.join(', ')}];
            window.setImageFiles(files);
          })();
        ''';

        await _controller.runJavaScript(setFilesScript);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling image upload: $e');
      }
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    if (Platform.isIOS) {
      return showCupertinoModalPopup<ImageSource>(
        context: context,
        builder: (BuildContext context) {
          return CupertinoActionSheet(
            title: const Text('Select Image Source'),
            actions: [
              CupertinoActionSheetAction(
                onPressed: () => Navigator.of(context).pop(ImageSource.gallery),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.photo_on_rectangle),
                    SizedBox(width: 8),
                    Text('Gallery'),
                  ],
                ),
              ),
              CupertinoActionSheetAction(
                onPressed: () => Navigator.of(context).pop(ImageSource.camera),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.camera),
                    SizedBox(width: 8),
                    Text('Camera'),
                  ],
                ),
              ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          );
        },
      );
    } else {
      return showDialog<ImageSource>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Select Image Source'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Gallery'),
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('Camera'),
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    if (Platform.isAndroid) {
      await Permission.storage.request();
      await Permission.photos.request();
    } else if (Platform.isIOS) {
      await Permission.photos.request();
    }
  }

  String _getMimeTypeFromPath(String path) {
    String extension = path.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
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
      ),
    );
  }
}
