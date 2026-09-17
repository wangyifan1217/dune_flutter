import 'package:dunes_app/features/nova/nova_icon.dart';
import 'package:dunes_app/features/nova/nova_welcome_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default person avatar is the static wink frame', () {
    expect(NovaPersonAvatar.asset, NovaPersonAvatar.winkAsset);
    expect(NovaPersonAvatar.winkAsset, 'assets/images/ai_avatar_wink.png');
  });

  testWidgets('conversation and call avatar uses static wink image', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: NovaBlinkingAvatar(size: 80))),
    );
    final image = tester.widget<Image>(find.byType(Image));
    var provider = image.image;
    if (provider is ResizeImage) {
      provider = provider.imageProvider;
    }
    expect(provider, isA<AssetImage>());
    expect((provider as AssetImage).assetName, NovaPersonAvatar.winkAsset);
  });
}
