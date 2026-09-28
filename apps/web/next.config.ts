import type { NextConfig } from "next";
// Separate build output per mode so the real (`next dev`, .next) and demo
// (`NEXT_DIST_DIR=.next-demo`) web servers can run side by side: Next.js
// refuses a second `next dev` in the same directory when both share the
// dev lockfile (<distDir>/lock).
const nextConfig: NextConfig = {
  reactStrictMode: true,
  devIndicators: false,
  distDir: process.env.NEXT_DIST_DIR ?? ".next",
};
export default nextConfig;
