module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  testRegex: '.*\\.spec\\.tsx?$',
  moduleFileExtensions: ['ts', 'tsx', 'js', 'json'],
  moduleNameMapper: {
    '^next/link$': '<rootDir>/test/stubs/next-link.cjs',
    '^next/navigation$': '<rootDir>/test/stubs/next-navigation.cjs',
  },
};
