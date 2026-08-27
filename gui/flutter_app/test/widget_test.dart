import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:douk_gui/models.dart';
import 'package:douk_gui/pages/splash_page.dart';

void main() {
  testWidgets('app renders splash screen', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SplashPage(autoStart: false)),
    );
    expect(find.text('夜星视频下载器'), findsOneWidget);
  });

  test('WorkPreview parses extracted gallery data', () {
    final data = {
      'type': '图集',
      'id': '7123456789012345678',
      'desc': '测试图集',
      'nickname': '作者A',
      'create_time': '2024-01-01 12:00:00',
      'static_cover': 'https://p3-sign.douyinpic.com/cover.jpeg',
      'dynamic_cover': 'https://p3-sign.douyinpic.com/dynamic.webp',
      'downloads': [
        'https://p3-sign.douyinpic.com/img1.jpeg',
        'https://p3-sign.douyinpic.com/img2.jpeg',
        'https://p3-sign.douyinpic.com/img3.jpeg',
      ],
    };
    final preview = WorkPreview.tryParse(data);
    expect(preview, isNotNull);
    expect(preview!.isGallery, isTrue);
    expect(preview.imageUrls.length, 3);
    expect(preview.imageUrls.first, 'https://p3-sign.douyinpic.com/img1.jpeg');
    expect(preview.coverUrl, 'https://p3-sign.douyinpic.com/cover.jpeg');
    expect(preview.author, '作者A');
    expect(preview.title, '测试图集');
  });

  test('WorkPreview parses extracted video data', () {
    final data = {
      'type': '视频',
      'id': '7123456789012345679',
      'desc': '测试视频',
      'nickname': '作者B',
      'static_cover': 'https://p3-sign.douyinpic.com/vcover.jpeg',
      'downloads': ['https://v26-web.douyinvod.com/video.mp4'],
    };
    final preview = WorkPreview.tryParse(data);
    expect(preview, isNotNull);
    expect(preview!.isGallery, isFalse);
    expect(preview.imageUrls.length, 1);
    expect(preview.coverUrl, 'https://p3-sign.douyinpic.com/vcover.jpeg');
  });

  test('WorkPreview falls back to raw douyin format', () {
    final data = {
      'desc': '原始格式',
      'author': {'nickname': '原始作者'},
      'video': {
        'cover': {
          'url_list': ['https://example.com/raw_cover.jpeg'],
        },
      },
    };
    final preview = WorkPreview.tryParse(data);
    expect(preview, isNotNull);
    expect(preview!.isGallery, isFalse);
    expect(preview.coverUrl, 'https://example.com/raw_cover.jpeg');
    expect(preview.author, '原始作者');
  });

  test('YtdlpPreview parses single video with formats', () {
    final preview = YtdlpPreview.fromJson({
      'platform': 'bili',
      'kind': 'video',
      'title': '测试B站视频',
      'uploader': 'UP主C',
      'thumbnail': 'https://i0.hdslb.com/cover.jpg',
      'duration': 213,
      'formats': [
        {'format_id': '30120', 'label': '1080P60帧', 'ext': 'mp4', 'height': 1080, 'filesize': 123456789},
        {'format_id': '30112', 'label': '720P', 'ext': 'mp4', 'height': 720, 'filesize': null},
      ],
    });
    expect(preview.platformName, 'B站');
    expect(preview.isBatch, isFalse);
    expect(preview.title, '测试B站视频');
    expect(preview.formats.length, 2);
    expect(preview.formats.first.height, 1080);
  });

  test('YtdlpPreview parses batch playlist and errors', () {
    final batch = YtdlpPreview.fromJson({
      'platform': 'youtube',
      'kind': 'batch',
      'title': '我的频道',
      'uploader': 'ChannelD',
      'item_count': 42,
      'sample_titles': ['A', 'B'],
    });
    expect(batch.isBatch, isTrue);
    expect(batch.itemCount, 42);
    expect(batch.sampleTitles.length, 2);
    expect(batch.platformName, 'YouTube');

    final err = YtdlpPreview.fromJson({
      'platform': 'bili',
      'kind': 'video',
      'error': 'HTTP Error 404',
    });
    expect(err.hasError, isTrue);
    expect(err.error, 'HTTP Error 404');
  });
}
