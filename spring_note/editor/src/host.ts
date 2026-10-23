export async function request(message: Record<string, unknown>): Promise<any> {
  const response = await (window as any).flutter_inappwebview.callHandler('springNote', message);
  if (response?.error) throw new Error(response.error);
  return response;
}

export const host = {
  async importImage(_id: string, bytes: Uint8Array, name: string): Promise<string> {
    // Chunking avoids the argument limit for large clipboard images.
    let binary = '';
    for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
    return request({ type: 'image', name, data: btoa(binary) });
  },
  async openLink(url: string) { await request({ type: 'link', url }); },
  async openDocumentLink(_id: string, url: string) { await request({ type: 'link', url }); },
  async imageAction(): Promise<Record<string, string>> {
    throw new Error('请在 SpringNote 的图片管理中操作文件。');
  },
};
