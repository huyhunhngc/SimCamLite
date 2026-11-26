export const APP_VERSION = '0.2.7';
export const GITHUB_REPO = 'https://github.com/huyhunhngc/simulator-camera';
export const LATEST_RELEASE_URL = `${GITHUB_REPO}/releases/latest`;
export const DMG_DOWNLOAD_URL = `https://simcamupdates.ifateam.dev/releases/SimCamLite-${APP_VERSION}.dmg`;
export const HOMEBREW_CMD = 'brew install --cask huyhunhngc/tap/simcam-lite';
export const DOCS_EDIT_BASE = `${GITHUB_REPO}/tree/master/website/src/content/docs`;

export interface TopNavItem {
  label: string;
  href: string;
  matchPrefix?: string;
}

export const TOP_NAV: TopNavItem[] = [
  { label: 'Features', href: '/#features' },
  { label: 'CLI', href: '/#cli' },
  { label: 'Docs', href: '/docs/get-started/introduction/', matchPrefix: '/docs/' },
  { label: 'Changelog', href: '/changelog/', matchPrefix: '/changelog/' },
  { label: 'FAQ', href: '/#faq' },
];

export interface DocNavItem {
  title: string;
  href: string;
  badge?: string;
}

export interface DocNavGroup {
  title: string;
  items: DocNavItem[];
}

export const DOCS_SIDEBAR: DocNavGroup[] = [
  {
    title: 'Get Started',
    items: [
      { title: 'Introduction', href: '/docs/get-started/introduction/' },
      { title: 'Installation', href: '/docs/get-started/installation/' },
      { title: 'Quick Start', href: '/docs/get-started/quick-start/' },
    ],
  },
  {
    title: 'Guides',
    items: [
      { title: 'Sources & Camera Profiles', href: '/docs/guides/sources-and-profiles/' },
      { title: 'Simulator & Xcode Setup', href: '/docs/guides/simulator-and-xcode/' },
      { title: 'Testing Permissions & CI', href: '/docs/guides/permissions-and-ci/' },
    ],
  },
  {
    title: 'Architecture',
    items: [
      { title: 'How Injection Works', href: '/docs/architecture/how-injection-works/' },
      { title: 'Limitations & Compatibility', href: '/docs/architecture/limitations/' },
    ],
  },
  {
    title: 'Reference',
    items: [
      { title: 'CLI Reference', href: '/docs/reference/cli/' },
      { title: 'Development & Releasing', href: '/docs/reference/development/' },
    ],
  },
];

export function normalizePath(path: string): string {
  return path.endsWith('/') ? path : `${path}/`;
}

export function getFlatDocItems(): (DocNavItem & { section: string })[] {
  return DOCS_SIDEBAR.flatMap((group) =>
    group.items.map((item) => ({ ...item, section: group.title }))
  );
}

export function getPrevNext(currentPath: string): {
  prev?: DocNavItem & { section: string };
  next?: DocNavItem & { section: string };
} {
  const flat = getFlatDocItems();
  const normalized = normalizePath(currentPath);
  const idx = flat.findIndex((item) => item.href === normalized);
  if (idx === -1) return {};
  return {
    prev: idx > 0 ? flat[idx - 1] : undefined,
    next: idx < flat.length - 1 ? flat[idx + 1] : undefined,
  };
}

export function getBreadcrumb(currentPath: string): { section: string; title: string } | null {
  const flat = getFlatDocItems();
  const normalized = normalizePath(currentPath);
  const match = flat.find((item) => item.href === normalized);
  return match ? { section: match.section, title: match.title } : null;
}
