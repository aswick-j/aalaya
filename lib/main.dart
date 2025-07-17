import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'dart:io';

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
    _controller = WebViewController()
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
            _injectImageUploadScript();
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
      ..loadRequest(Uri.parse(_initialUrl));
  }

  void _injectImageUploadScript() {
    const String script = '''
      (function() {
        // Override file input click behavior for image inputs
        document.addEventListener('click', function(e) {
          if (e.target.type === 'file') {
            e.preventDefault();
            e.stopPropagation();
            
            // Store reference to the input element
            window.currentImageInput = e.target;
            
            // Check if it's for images
            const accept = e.target.accept || '';
            const multiple = e.target.multiple || false;
            
            // Send message to Flutter
            ImageUploader.postMessage(JSON.stringify({
              accept: accept,
              multiple: multiple
            }));
          }
        }, true);
        
        // Function to set image files (called from Flutter)
        window.setImageFiles = function(files) {
          if (window.currentImageInput && files.length > 0) {
            const dt = new DataTransfer();
            files.forEach(file => dt.items.add(file));
            window.currentImageInput.files = dt.files;
            
            // Trigger change event
            const event = new Event('change', { bubbles: true });
            window.currentImageInput.dispatchEvent(event);
            
            // Also trigger input event for some frameworks
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
      // Request permissions
      await _requestPermissions();
      
      // Parse the message to check for multiple selection
      bool allowMultiple = message.contains('"multiple": true');
      
      // Show image source selection dialog
      ImageSource? source = await _showImageSourceDialog();
      if (source == null) return;
      
      List<XFile> imageFiles = [];
      
      if (allowMultiple && source == ImageSource.gallery) {
        // Pick multiple images from gallery
        final List<XFile> selectedImages = await _imagePicker.pickMultiImage();
        imageFiles.addAll(selectedImages);
      } else {
        // Pick single image
        final XFile? selectedImage = await _imagePicker.pickImage(source: source);
        if (selectedImage != null) {
          imageFiles.add(selectedImage);
        }
      }

      if (imageFiles.isNotEmpty) {
        // Convert images to JavaScript File objects
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
              return new File([byteArray], '$fileName', {
                type: '$mimeType'
              });
            })()
          ''');
        }
        
        // Execute JavaScript to set image files
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
    // Request camera permission
    await Permission.camera.request();
    
    // Request storage permission
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