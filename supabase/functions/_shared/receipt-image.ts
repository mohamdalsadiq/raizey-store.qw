// Bounded structural validation before storage or any AI request.
// Content type and filename alone are never proof that the bytes are an image.
export function assertReceiptImage(bytes: Uint8Array, mime: string): void {
  const fail = () => { throw new Error('invalid_image_content'); };
  const text = (offset: number, size: number) => String.fromCharCode(...bytes.slice(offset, offset + size));
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const dimensions = (w: number, h: number) => {
    if (!w || !h || w > 10000 || h > 10000 || w * h > 32000000) fail();
  };
  if (bytes.length < 24) fail();
  if (mime === 'image/png') {
    if (text(0, 8) !== '\x89PNG\r\n\x1a\n') fail();
    let offset = 8, data = false, header = false, ended = false;
    while (offset + 12 <= bytes.length) {
      const length = view.getUint32(offset), kind = text(offset + 4, 4);
      if (length > bytes.length - offset - 12) fail();
      // Validate CRC, including the image data, rather than just accepting magic bytes.
      let crc = 0xffffffff;
      for (let i = offset + 4; i < offset + 8 + length; i++) {
        crc ^= bytes[i];
        for (let b = 0; b < 8; b++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
      }
      if (((crc ^ 0xffffffff) >>> 0) !== view.getUint32(offset + 8 + length)) fail();
      if (!header) {
        if (kind !== 'IHDR' || length !== 13) fail();
        dimensions(view.getUint32(offset + 8), view.getUint32(offset + 12));
        header = true;
      } else if (kind === 'IHDR') fail();
      if (kind === 'IDAT' && length > 0) data = true;
      offset += length + 12;
      if (kind === 'IEND') { if (length !== 0) fail(); ended = true; break; }
    }
    if (!header || !data || !ended || offset !== bytes.length) fail();
  } else if (mime === 'image/jpeg') {
    if (bytes[0] !== 255 || bytes[1] !== 216 || bytes.at(-2) !== 255 || bytes.at(-1) !== 217) fail();
    let offset = 2, frame = false, scan = false;
    while (offset < bytes.length - 2) {
      if (bytes[offset++] !== 255) fail();
      while (bytes[offset] === 255) offset++;
      const marker = bytes[offset++];
      if (offset + 2 > bytes.length) fail();
      const size = view.getUint16(offset);
      if (size < 2 || offset + size > bytes.length) fail();
      if ([192, 193, 194].includes(marker)) {
        if (size < 8) fail();
        dimensions(view.getUint16(offset + 5), view.getUint16(offset + 3)); frame = true;
      }
      if (marker === 218) { scan = true; break; }
      offset += size;
    }
    if (!frame || !scan) fail();
  } else if (mime === 'image/webp') {
    if (text(0, 4) !== 'RIFF' || text(8, 4) !== 'WEBP' || view.getUint32(4, true) + 8 !== bytes.length) fail();
    let offset = 12, image = false;
    while (offset + 8 <= bytes.length) {
      const kind = text(offset, 4), size = view.getUint32(offset + 4, true), start = offset + 8;
      if (size > bytes.length - start) fail();
      if (kind === 'VP8 ' && size >= 10) {
        if (text(start + 3, 3) !== '\x9d\x01\x2a') fail();
        dimensions(view.getUint16(start + 6, true) & 0x3fff, view.getUint16(start + 8, true) & 0x3fff); image = true;
      }
      if (kind === 'VP8L' && size >= 5) {
        if (bytes[start] !== 47) fail();
        const bits = view.getUint32(start + 1, true);
        dimensions((bits & 0x3fff) + 1, ((bits >>> 14) & 0x3fff) + 1); image = true;
      }
      offset = start + size + (size % 2);
    }
    if (!image || offset !== bytes.length) fail();
  } else fail();
}
