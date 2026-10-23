/** Native offsets address serialized text; the editor model addresses LF text. */
export function normalizedOffset(text: string, offset: number) {
  return text.slice(0, Math.max(0, offset)).replace(/\r\n/g, '\n').length;
}

export function serializedOffset(text: string, offset: number) {
  let serialized = 0, normalized = 0;
  while (serialized < text.length && normalized < offset) {
    if (text[serialized] === '\r' && text[serialized + 1] === '\n') serialized++;
    serialized++;
    normalized++;
  }
  return serialized;
}
