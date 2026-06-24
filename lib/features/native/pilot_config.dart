const bool kEnableNativePilot = bool.fromEnvironment(
  'ENABLE_NATIVE_PILOT',
  defaultValue: false,
);

const Set<String> kNativePilotScreens = <String>{
  'B1',
  'B2',
  'B3',
  'B10',
  'B13',
  'B14',
  'C1',
  'C2',
  'C3',
  'C4',
  'C5',
  'C6',
  'C7',
  'C9',
  'C10',
  'C11',
  'C12',
  'C13',
  'Z2',
  'K1',
  'K2',
  'K3',
  'P1',
  'XF',
};

bool isNativePilotScreen(String screenId) {
  if (!kEnableNativePilot) return false;
  return kNativePilotScreens.contains(screenId);
}
