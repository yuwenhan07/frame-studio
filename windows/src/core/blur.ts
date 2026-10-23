// Three small box passes approximate a Gaussian on a deliberately small background.
export function blurRGBA(data: Uint8ClampedArray, width: number, height: number, radius: number): Uint8ClampedArray {
  if (data.length !== width * height * 4 || width < 1 || height < 1) throw new Error('背景像素尺寸无效');
  if (radius <= 0) return new Uint8ClampedArray(data);
  const r = Math.max(1, Math.min(64, Math.round(radius))), size = r * 2 + 1;
  let input = new Uint8ClampedArray(data), output = new Uint8ClampedArray(data.length);
  for (let pass = 0; pass < 3; pass++) {
    for (let y = 0; y < height; y++) for (let channel = 0; channel < 4; channel++) {
      let sum = 0;
      for (let k = -r; k <= r; k++) sum += input[(y * width + Math.min(width - 1, Math.max(0, k))) * 4 + channel];
      for (let x = 0; x < width; x++) {
        output[(y * width + x) * 4 + channel] = Math.round(sum / size);
        sum += input[(y * width + Math.min(width - 1, x + r + 1)) * 4 + channel]
          - input[(y * width + Math.max(0, x - r)) * 4 + channel];
      }
    }
    [input, output] = [output, input];
    for (let x = 0; x < width; x++) for (let channel = 0; channel < 4; channel++) {
      let sum = 0;
      for (let k = -r; k <= r; k++) sum += input[(Math.min(height - 1, Math.max(0, k)) * width + x) * 4 + channel];
      for (let y = 0; y < height; y++) {
        output[(y * width + x) * 4 + channel] = Math.round(sum / size);
        sum += input[(Math.min(height - 1, y + r + 1) * width + x) * 4 + channel]
          - input[(Math.max(0, y - r) * width + x) * 4 + channel];
      }
    }
    [input, output] = [output, input];
  }
  return input;
}
