import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/nova/nova_model_utils.dart';

void main() {
  test('deepseek silently falls back to gpt5.5 for vision', () {
    expect(
      pickNovaVisionModel(
        selected: 'nova_deepseek',
        candidates: const ['nova_deepseek', 'nova_gpt5.5'],
      ),
      'nova_gpt5.5',
    );
  });

  test('already-vision model is kept', () {
    expect(
      pickNovaVisionModel(
        selected: 'nova_gpt5.5',
        candidates: const ['nova_deepseek', 'nova_gpt5.5'],
      ),
      'nova_gpt5.5',
    );
  });

  test('falls back to known vision model when catalog empty', () {
    expect(
      pickNovaVisionModel(selected: 'nova_deepseek'),
      'nova_gpt5.5',
    );
  });
}
