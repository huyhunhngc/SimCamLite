import type { APIRoute } from 'astro';
import { getCollection } from 'astro:content';

export const prerender = true;

function stripMdx(raw: string): string {
  return raw
    .replace(/^---[\s\S]*?---/, '')
    .replace(/import\s+.*?;?\n/g, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/[`*_#>\[\]()]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function extractHeadings(raw: string): string[] {
  const matches = raw.matchAll(/^#{2,3}\s+(.+)$/gm);
  return Array.from(matches, (m) => m[1].trim());
}

export const GET: APIRoute = async () => {
  const docs = await getCollection('docs');

  const docEntries = docs.map((entry) => {
    const slug = entry.id.replace(/\.mdx?$/, '');
    const body = entry.body ?? '';
    return {
      title: entry.data.title,
      description: entry.data.description,
      section: entry.data.section,
      url: `/docs/${slug}/`,
      headings: extractHeadings(body),
      excerpt: stripMdx(body).slice(0, 600),
    };
  });

  const landingEntries = [
    {
      title: 'SimCam Lite Home',
      description: 'Overview, features, CLI showcase, installation, and FAQ for SimCam Lite.',
      section: 'Landing',
      url: '/',
      headings: ['Features', 'CLI & Automation', 'Install', 'FAQ'],
      excerpt: 'Free, open-source macOS camera emulator for the iOS Simulator with 4K video, QR codes, Mac webcam, and simcam CLI.',
    },
  ];

  return new Response(JSON.stringify([...docEntries, ...landingEntries]), {
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
    },
  });
};
