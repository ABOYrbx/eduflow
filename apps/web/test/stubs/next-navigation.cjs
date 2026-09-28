// Minimaler Stub für `next/navigation` in Unit-Tests.
module.exports = {
  __esModule: true,
  usePathname: () => '/',
  useRouter: () => ({ replace: () => undefined, push: () => undefined }),
};
