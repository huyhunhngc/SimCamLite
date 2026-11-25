export function formatInlineCode(text: string): string {
  const escaped = text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
  return escaped.replace(/`([^`]+)`/g, '<code>$1</code>');
}
