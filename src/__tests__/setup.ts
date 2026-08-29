/** Shared test setup: stub the two things that reach outside the JS bundle. */

jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock'),
);

jest.mock('expo-haptics', () => ({
  selectionAsync: jest.fn(),
  impactAsync: jest.fn(),
  notificationAsync: jest.fn(),
}));

// SafeAreaProvider renders nothing until it receives a native layout event,
// which never arrives in a test renderer. The library's own mock supplies
// static insets so children mount immediately.
// The mock module uses `export default`, so reach through the interop wrapper.
jest.mock('react-native-safe-area-context', () =>
  require('react-native-safe-area-context/jest/mock').default,
);
