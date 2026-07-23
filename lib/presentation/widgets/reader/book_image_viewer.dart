import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../controllers/book_reader_controller.dart';

/// Full-screen image viewer for Foliate `onImageClick` data URLs.
class BookImageViewer extends StatelessWidget {
  const BookImageViewer({super.key, required this.controller});

  final BookReaderController controller;

  @override
  Widget build(BuildContext context) {
    final dataUrl = controller.imageViewerDataUrl;
    if (dataUrl == null) return const SizedBox.shrink();
    final bytes = _decodeDataUrl(dataUrl);

    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (bytes == null)
            const Center(
              child: Text('无法显示图片', style: TextStyle(color: Colors.white70)),
            )
          else
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Center(
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                tooltip: '关闭',
                onPressed: controller.closeImageViewer,
                icon: const Icon(
                  Icons.close,
                  color: Colors.white,
                  weight: 300,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Uint8List? _decodeDataUrl(String dataUrl) {
    final comma = dataUrl.indexOf(',');
    if (comma <= 5) return null;
    final header = dataUrl.substring(5, comma);
    try {
      final body = dataUrl.substring(comma + 1);
      return header.split(';').contains('base64')
          ? base64Decode(body)
          : Uint8List.fromList(utf8.encode(Uri.decodeComponent(body)));
    } on FormatException {
      return null;
    }
  }
}
