/// 与 WebView `PRESET_AVATARS` 一致的系统默认头像。
class NativeAvatarPreset {
  const NativeAvatarPreset({required this.id, required this.svg});

  final String id;
  final String svg;
}

const kNativeAvatarPresets = <NativeAvatarPreset>[
  NativeAvatarPreset(
    id: 'cartoon-01',
    svg:
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120"><rect width="120" height="120" rx="60" fill="#FFE8A3"/><circle cx="60" cy="58" r="38" fill="#FFD36B"/><circle cx="44" cy="54" r="5" fill="#4A3580"/><circle cx="76" cy="54" r="5" fill="#4A3580"/><path d="M42 72 Q60 86 78 72" stroke="#4A3580" stroke-width="4" fill="none" stroke-linecap="round"/></svg>',
  ),
  NativeAvatarPreset(
    id: 'cartoon-02',
    svg:
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120"><rect width="120" height="120" rx="60" fill="#D8F5FF"/><circle cx="60" cy="58" r="38" fill="#7EC8E3"/><ellipse cx="44" cy="56" rx="6" ry="8" fill="#2D4A6E"/><ellipse cx="76" cy="56" rx="6" ry="8" fill="#2D4A6E"/><path d="M48 76 Q60 68 72 76" stroke="#2D4A6E" stroke-width="3.5" fill="none" stroke-linecap="round"/></svg>',
  ),
  NativeAvatarPreset(
    id: 'cartoon-03',
    svg:
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120"><rect width="120" height="120" rx="60" fill="#F3E8FF"/><circle cx="60" cy="58" r="38" fill="#B58AE8"/><circle cx="44" cy="54" r="5" fill="#3B2870"/><circle cx="76" cy="54" r="5" fill="#3B2870"/><path d="M46 74 Q60 84 74 74" stroke="#3B2870" stroke-width="4" fill="none" stroke-linecap="round"/></svg>',
  ),
  NativeAvatarPreset(
    id: 'cartoon-04',
    svg:
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120"><rect width="120" height="120" rx="60" fill="#E8FFF0"/><circle cx="60" cy="58" r="38" fill="#6BCB9A"/><rect x="38" y="50" width="12" height="4" rx="2" fill="#1F4D3A"/><rect x="70" y="50" width="12" height="4" rx="2" fill="#1F4D3A"/><path d="M44 74 Q60 80 76 74" stroke="#1F4D3A" stroke-width="4" fill="none" stroke-linecap="round"/></svg>',
  ),
  NativeAvatarPreset(
    id: 'cartoon-05',
    svg:
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120"><rect width="120" height="120" rx="60" fill="#FFE4EC"/><circle cx="60" cy="58" r="38" fill="#FF8FAB"/><circle cx="44" cy="54" r="5" fill="#6B1E3C"/><circle cx="76" cy="54" r="5" fill="#6B1E3C"/><path d="M42 70 Q60 88 78 70" stroke="#6B1E3C" stroke-width="4" fill="none" stroke-linecap="round"/></svg>',
  ),
  NativeAvatarPreset(
    id: 'cartoon-06',
    svg:
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120"><rect width="120" height="120" rx="60" fill="#FFF0D6"/><circle cx="60" cy="58" r="38" fill="#F4A261"/><circle cx="44" cy="52" r="6" fill="#5D3508"/><circle cx="76" cy="52" r="6" fill="#5D3508"/><path d="M46 76 Q60 70 74 76" stroke="#5D3508" stroke-width="4" fill="none" stroke-linecap="round"/></svg>',
  ),
];

String? nativeAvatarPresetSvg(String id) {
  for (final preset in kNativeAvatarPresets) {
    if (preset.id == id) return preset.svg;
  }
  return null;
}
