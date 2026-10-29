// Standard bleibt `node`: die Logik-Tests in `src/lib/*.spec.ts` brauchen
// kein DOM. Komponenten-Tests holen sich jsdom selbst über die Datei-Notiz
// `@jest-environment jsdom` (siehe `src/components/section-bar.spec.tsx`)
// und importieren Testing Library direkt — so bleibt dieser Setup-Hook im
// node-Fall frei von `document`.
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
