/**
 * Parser and geometry tests are pure TypeScript; the screen tests render the
 * real component tree under the jest-expo preset with network and storage
 * stubbed out (see src/__tests__/setup.ts).
 */
module.exports = {
  preset: 'jest-expo',
  setupFilesAfterEnv: ['<rootDir>/src/__tests__/setup.ts'],
  testMatch: ['**/__tests__/**/*.test.ts?(x)'],
  collectCoverageFrom: ['src/**/*.{ts,tsx}', '!src/__tests__/**'],
};
