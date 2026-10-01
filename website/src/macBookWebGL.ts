import { desktopFragmentSource } from "./seamlessWallpaper";
import { macBookGeometry } from "./MacBookShell";

const W = 900;
const H = 623.043; // 20px of transparent padding above and below the original drawing.
const D = macBookGeometry.depth;
const L = (W - macBookGeometry.width) / 2;
const A = 4096;
const ATLAS_HEIGHT = 2432;
const vertexSource = `#version 300 es
precision highp float;
in vec3 position;
in vec2 uv;
in vec3 color;
in vec3 flags;
uniform float degrees;
out vec2 texUV;
out vec3 tint;
flat out float kind;
flat out float face;
vec3 turn(vec3 p, float angle) {
  float c = cos(angle), s = sin(angle);
  p.y -= ${D};
  p.yz = mat2(c, s, -s, c) * p.yz;
  p.y += ${D};
  return p;
}
void main() {
  vec3 p = position;
  float closure = degrees / 90.0;
  if (flags.x > 0.5) p = turn(p, -radians(degrees));
  if (flags.y < 2.5) p = turn(p, -radians(16.0 * closure));
  float w = 1.0 - p.z / 10000.0;
  float lift = flags.y < 2.5 ? 180.0 * closure : 0.0;
  gl_Position = vec4((p.x - 450.0) / 450.0,
    (1.0 - 2.0 * (${D} + 20.0 - lift) / ${H}) * w - 2.0 * (p.y - ${D}) / ${H},
    -p.z / 2000.0, w);
  texUV = uv; tint = color; kind = flags.y; face = flags.z;
}`;
const fragmentSource = `#version 300 es
precision highp float;
uniform sampler2D atlas;
uniform sampler2D wallpaper;
uniform float degrees;
in vec2 texUV;
in vec3 tint;
flat in float kind;
flat in float face;
out vec4 outputColor;
void main() {
  bool back = degrees * (106.0 / 90.0) >= 90.0;
  if ((face > .5 && back) || (face < -.5 && !back)) discard;
  if (kind > 2.5) {
    outputColor = texture(atlas, texUV);
    outputColor.a *= .12 + degrees / 90.0 * .16;
  } else if (kind > 1.5) outputColor = vec4(tint, 1.0);
  else if (kind > .5) {
    // The same rounded aperture as the CSS screen; avoid square wallpaper corners.
    vec2 p = texUV * vec2(799.739, 518.826);
    float r = p.y < 259.0 ? 13.0 : 3.0;
    vec2 q = abs(p - vec2(399.8695,259.413)) - vec2(399.8695,259.413) + r;
    float edge = length(max(q,0.0)) + min(max(q.x,q.y),0.0) - r;
    if (edge > 0.0) discard;
    outputColor = texture(wallpaper, vec2(texUV.x, 1.0-texUV.y));
  } else {
    outputColor = texture(atlas, texUV);
    if (outputColor.a < .01) discard;
  }
}`;
const quadVertex = `#version 300 es
in vec3 position;
out vec2 screenUV;
void main() {
  screenUV = vec2((position.x + 1.0) * .5, (1.0 - position.y) * .5);
  gl_Position = vec4(position.xy, 0.0, 1.0);
}`;

function rounded(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  r: number | number[],
) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}
function gradient(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  angle: number,
  stops: [number, string][],
) {
  const rad = (angle * Math.PI) / 180;
  const dx = Math.sin(rad),
    dy = -Math.cos(rad);
  const length = Math.abs(w * dx) + Math.abs(h * dy);
  const g = ctx.createLinearGradient(
    x + w / 2 - (dx * length) / 2,
    y + h / 2 - (dy * length) / 2,
    x + w / 2 + (dx * length) / 2,
    y + h / 2 + (dy * length) / 2,
  );
  stops.forEach(([at, color]) => g.addColorStop(at, color));
  return g;
}
function plate(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  r: number | number[],
  fill: string | CanvasGradient,
  stroke?: string,
  border = 1,
) {
  rounded(ctx, x, y, w, h, r);
  ctx.fillStyle = fill;
  ctx.fill();
  if (stroke) {
    const inset = border / 2;
    const radii = Array.isArray(r)
      ? r.map((value) => Math.max(0, value - inset))
      : Math.max(0, r - inset);
    rounded(ctx, x + inset, y + inset, w - border, h - border, radii);
    ctx.lineWidth = border;
    ctx.strokeStyle = stroke;
    ctx.stroke();
  }
}

// CSS radial-gradient(ellipse farthest-corner ...) in the static metal artwork.
function metalHighlight(
  c: CanvasRenderingContext2D,
  width: number,
  x: number,
  y: number,
  stop: number,
  color: string,
) {
  c.save();
  rounded(c, L, 0, width, D, 22);
  c.clip();
  c.translate(L + width * x, D * y);
  c.scale(
    Math.max(x, 1 - x) * width * Math.SQRT2,
    Math.max(y, 1 - y) * D * Math.SQRT2,
  );
  const shine = c.createRadialGradient(0, 0, 0, 0, 0, 1);
  shine.addColorStop(0, color);
  shine.addColorStop(stop, "#ffffff00");
  c.fillStyle = shine;
  c.fillRect(-2, -2, 4, 4);
  c.restore();
}

// Bake only static surface artwork. Positions come from the existing key layout;
// all movement and depth ordering are handled by the single WebGL scene.
function makeAtlas(
  device: HTMLElement,
  logo: HTMLImageElement,
  shadow: HTMLImageElement,
) {
  const canvas = document.createElement("canvas");
  canvas.width = A;
  canvas.height = ATLAS_HEIGHT;
  const c = canvas.getContext("2d")!;
  const begin = (x: number, y: number) => {
    c.save();
    c.translate(x, y);
    c.scale(2, 2);
  };
  const width = macBookGeometry.width;
  // Front bezel and camera. A transparent aperture is covered by the screen mesh.
  begin(0, 0);
  plate(
    c,
    L,
    0,
    width,
    D,
    22,
    gradient(c, L, 0, width, D, 105, [
      [0, "#191a1c"],
      [0.28, "#070809"],
      [0.74, "#111214"],
      [1, "#1c1d1f"],
    ]),
    "#929497",
    1.5,
  );
  c.globalCompositeOperation = "destination-out";
  plate(c, 50.13, 11, 799.739, 518.826, [13, 13, 3, 3], "black");
  c.globalCompositeOperation = "source-over";
  plate(c, 407, 9, 86, 21, [0, 0, 7, 7], "#090a0c");
  for (const x of [431, 465]) plate(c, x, 14, 3, 3, 1.5, "#17191c");
  const lens = c.createRadialGradient(449, 14, 0, 450, 15, 4);
  lens.addColorStop(0, "#789dbb");
  lens.addColorStop(0.25, "#32566a");
  lens.addColorStop(0.55, "#101c29");
  lens.addColorStop(1, "#030507");
  plate(c, 447, 12, 6, 6, 3, lens, "#202228");
  c.restore();
  // Outside of the lid. The mesh mirrors U just like the CSS rotateY(180deg).
  begin(2048, 0);
  plate(
    c,
    L,
    0,
    width,
    D,
    22,
    gradient(c, L, 0, width, D, 120, [
      [0, "#c4c7ca"],
      [0.35, "#e0e2e4"],
      [0.72, "#cbced1"],
      [1, "#b5b9bd"],
    ]),
    "#b1b5b9",
  );
  metalHighlight(c, width, 0.25, 0.12, 0.65, "#ffffff45");
  const mark = document.createElement("canvas");
  mark.width = 156;
  mark.height = 180;
  const m = mark.getContext("2d")!;
  m.drawImage(logo, 0, 0, 156, 180);
  m.globalCompositeOperation = "source-in";
  m.fillStyle = gradient(m, 0, 0, 156, 180, 120, [
    [0, "#80858b"],
    [0.38, "#ecedef"],
    [0.5, "#f7f8f9"],
    [0.68, "#a6abb0"],
    [1, "#797f86"],
  ]);
  m.fillRect(0, 0, 156, 180);
  c.drawImage(mark, 411, D / 2 - 45, 78, 90);
  c.restore();
  // Deck, including the original rounded keycaps, Touch ID and trackpad.
  begin(0, 1152);
  plate(
    c,
    L,
    0,
    width,
    D,
    22,
    gradient(c, L, 0, width, D, 100, [
      [0, "#b7bcc1"],
      [0.17, "#d1d4d7"],
      [0.5, "#e0e2e4"],
      [0.83, "#c9cdd1"],
      [1, "#aeb4ba"],
    ]),
    "#a8aeb4",
  );
  metalHighlight(c, width, 0.45, 0.15, 0.6, "#ffffff38");
  plate(
    c,
    L + width / 2 - 176,
    31,
    352,
    191,
    11,
    gradient(c, L + width / 2 - 176, 31, 352, 191, 110, [
      [0, "#ced1d4"],
      [0.55, "#d8dadd"],
      [1, "#c7cbcf"],
    ]),
    "#a1a6ac",
  );
  plate(
    c,
    L + 58,
    D - 17,
    width - 116,
    12,
    6,
    gradient(c, 0, D - 17, 1, 12, 180, [
      [0, "#181a1c"],
      [0.4, "#34373b"],
      [0.75, "#111214"],
      [1, "#575c60"],
    ]),
  );
  const keyboard = device.querySelector<HTMLElement>(
    ".seamless-macbook__keyboard",
  )!;
  for (const key of keyboard.querySelectorAll<HTMLElement>(
    ".seamless-macbook__key",
  )) {
    let x = 0,
      y = 0;
    let node: HTMLElement | null = key;
    while (node && node !== keyboard) {
      x += node.offsetLeft;
      y += node.offsetTop;
      node = node.offsetParent as HTMLElement | null;
    }
    const style = getComputedStyle(key),
      w = parseFloat(style.width),
      h = parseFloat(style.height);
    x += L + 86;
    y = D - 38 - y - h;
    c.save();
    c.shadowColor = "#ffffff75";
    c.shadowBlur = 1;
    c.shadowOffsetY = -1.5;
    plate(c, x - 1.25, y - 1.25, w + 2.5, h + 2.5, 6.25, "#777c80");
    c.restore();
    plate(
      c,
      x,
      y,
      w,
      h,
      key.classList.contains("seamless-macbook__key--arrow") ? 3 : 5,
      gradient(c, x, y, w, h, 35, [
        [0, "#303236"],
        [0.55, "#24262a"],
        [1, "#1d1f22"],
      ]),
      "#151719",
    );
    if (key.classList.contains("seamless-macbook__key--touch-id"))
      plate(
        c,
        x + w / 2 - 11,
        y + h / 2 - 11,
        22,
        22,
        11,
        gradient(c, x, y, w, h, 45, [
          [0, "#17191c"],
          [1, "#33363b"],
        ]),
        "#60636a",
      );
  }
  c.restore();
  // Front opening and feet occupy their original planes, not the deck texture.
  begin(2048, 1152);
  c.drawImage(shadow, 0, 0, 900, 623.043);
  plate(
    c,
    400,
    0,
    100,
    6,
    [0, 0, 10, 10],
    gradient(c, 400, 0, 100, 6, 180, [
      [0, "#74787d"],
      [0.7, "#aeb2b6"],
      [1, "#d7dadd"],
    ]),
  );
  for (const x of [L + 44, L + width - 86])
    plate(c, x, 18, 42, 3, [0, 0, 4, 4], "#4a4d52");
  c.restore();
  return canvas;
}

type Point = [number, number, number];
export async function createMacBookWebGL(
  canvas: HTMLCanvasElement,
  device: HTMLElement,
  image: HTMLImageElement,
  signal: AbortSignal,
) {
  const logo = new Image();
  logo.src = "/assets/macbook-lid-mark.svg";
  const shadow = new Image();
  shadow.src = `data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="1800" height="1246" viewBox="0 0 900 623.043"><defs><filter id="blur" x="-20%" y="-200%" width="140%" height="500%"><feGaussianBlur stdDeviation="10"/></filter></defs><ellipse cx="450" cy="567" rx="390" ry="9" fill="#41464b" filter="url(#blur)"/></svg>')}`;
  try {
    await Promise.all([logo.decode(), shadow.decode()]);
  } catch {
    return null;
  }
  if (signal.aborted) return null;
  // The geometry template is visible only during this synchronous layout read.
  device.classList.add("seamless-macbook--animated");
  let atlas: HTMLCanvasElement;
  try {
    atlas = makeAtlas(device, logo, shadow);
  } catch {
    return null;
  } finally {
    device.classList.remove("seamless-macbook--animated");
  }
  const gl = canvas.getContext("webgl2", {
    alpha: true,
    antialias: true,
    depth: true,
    premultipliedAlpha: true,
    preserveDrawingBuffer: true,
    powerPreference: "low-power",
  });
  if (!gl) return null;
  const shaders: WebGLShader[] = [],
    programs: WebGLProgram[] = [],
    buffers: WebGLBuffer[] = [],
    textures: WebGLTexture[] = [],
    vaos: WebGLVertexArrayObject[] = [];
  let framebuffer: WebGLFramebuffer | null = null;
  const dispose = () => {
    shaders.forEach((s) => gl.deleteShader(s));
    programs.forEach((p) => gl.deleteProgram(p));
    buffers.forEach((b) => gl.deleteBuffer(b));
    textures.forEach((t) => gl.deleteTexture(t));
    vaos.forEach((v) => gl.deleteVertexArray(v));
    gl.deleteFramebuffer(framebuffer);
    canvas.width = 1;
    canvas.height = 1;
  };
  try {
    const program = (vs: string, fs: string) => {
      const p = gl.createProgram()!;
      programs.push(p);
      for (const [type, source] of [
        [gl.VERTEX_SHADER, vs],
        [gl.FRAGMENT_SHADER, fs],
      ] as const) {
        const s = gl.createShader(type)!;
        shaders.push(s);
        gl.shaderSource(s, source);
        gl.compileShader(s);
        if (!gl.getShaderParameter(s, gl.COMPILE_STATUS))
          throw Error(gl.getShaderInfoLog(s) || "Shader compilation failed");
        gl.attachShader(p, s);
      }
      gl.linkProgram(p);
      if (!gl.getProgramParameter(p, gl.LINK_STATUS))
        throw Error(gl.getProgramInfoLog(p) || "Shader linking failed");
      return p;
    };
    const modelProgram = program(vertexSource, fragmentSource),
      wallpaperProgram = program(quadVertex, desktopFragmentSource);
    const texture = (
      source: TexImageSource | null,
      width = 960,
      height = 600,
      mipmaps = false,
    ) => {
      const t = gl.createTexture()!;
      textures.push(t);
      gl.bindTexture(gl.TEXTURE_2D, t);
      if (source)
        gl.texImage2D(
          gl.TEXTURE_2D,
          0,
          gl.RGBA,
          gl.RGBA,
          gl.UNSIGNED_BYTE,
          source,
        );
      else
        gl.texImage2D(
          gl.TEXTURE_2D,
          0,
          gl.RGBA,
          width,
          height,
          0,
          gl.RGBA,
          gl.UNSIGNED_BYTE,
          null,
        );
      gl.texParameteri(
        gl.TEXTURE_2D,
        gl.TEXTURE_MIN_FILTER,
        mipmaps ? gl.LINEAR_MIPMAP_LINEAR : gl.LINEAR,
      );
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      if (mipmaps) gl.generateMipmap(gl.TEXTURE_2D);
      return t;
    };
    const atlasTexture = texture(atlas, 0, 0, true),
      desktopTexture = texture(image, 0, 0, true),
      wallpaperTexture = texture(null);
    framebuffer = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
    gl.framebufferTexture2D(
      gl.FRAMEBUFFER,
      gl.COLOR_ATTACHMENT0,
      gl.TEXTURE_2D,
      wallpaperTexture,
      0,
    );
    if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE)
      throw Error("Wallpaper target unavailable");
    const vertices: number[] = [];
    const triangle = (
      points: Point[],
      uvs: number[][],
      part: number,
      kind: number,
      face: number,
      colors: number[][] = [
        [1, 1, 1],
        [1, 1, 1],
        [1, 1, 1],
      ],
    ) =>
      points.forEach((p, i) =>
        vertices.push(...p, ...uvs[i], ...colors[i], part, kind, face),
      );
    const quad = (
      points: Point[],
      tile: number,
      part: number,
      kind = 0,
      face = 0,
      flip = false,
      uvRect = [0, 0, 900, D],
    ) => {
      const tx = (tile % 2) * 2048,
        ty = Math.floor(tile / 2) * 1152;
      let u0 = (tx + uvRect[0] * 2) / A,
        u1 = (tx + (uvRect[0] + uvRect[2]) * 2) / A;
      let v0 = (ty + uvRect[1] * 2) / ATLAS_HEIGHT,
        v1 = (ty + (uvRect[1] + uvRect[3]) * 2) / ATLAS_HEIGHT;
      if (kind === 1 || kind === 2) {
        u0 = 0;
        u1 = 1;
        v0 = 0;
        v1 = 1;
      }
      if (flip) [u0, u1] = [u1, u0];
      const uv = [
        [u0, v0],
        [u1, v0],
        [u1, v1],
        [u0, v1],
      ];
      for (const ids of [
        [0, 1, 2],
        [0, 2, 3],
      ])
        triangle(
          ids.map((i) => points[i]),
          ids.map((i) => uv[i]),
          part,
          kind,
          face,
        );
    };
    const plane = (
      x: number,
      y: number,
      w: number,
      h: number,
      z: number,
      tile: number,
      part: number,
      kind = 0,
      face = 0,
      flip = false,
    ) =>
      quad(
        [
          [x, y, z],
          [x + w, y, z],
          [x + w, y + h, z],
          [x, y + h, z],
        ],
        tile,
        part,
        kind,
        face,
        flip,
      );
    // Shadow first, behind the depth-tested hardware.
    quad(
      [
        [0, 525, -1],
        [900, 525, -1],
        [900, 623.043, -1],
        [0, 623.043, -1],
      ],
      3,
      0,
      3,
      0,
      false,
      [0, 525, 900, 98.043],
    );
    const shadowCount = vertices.length / 11;
    const deckPoint = (x: number, y: number, z: number): Point => [
      L + x,
      D + 3 + z,
      D - y,
    ];
    quad(
      [
        deckPoint(-L, 0, -0.02),
        deckPoint(900 - L, 0, -0.02),
        deckPoint(900 - L, D, -0.02),
        deckPoint(-L, D, -0.02),
      ],
      2,
      0,
    );
    plane(0, 0, 900, D, -6, 1, 1, 0, -1, true);
    // Screen behind a single bezel/notch plane: depth, not CSS layer ordering.
    plane(50.13, 11, 799.739, 518.826, 0.05, 0, 1, 1, 1);
    plane(0, 0, 900, D, 0.1, 0, 1, 0, 1);
    // Front recess and feet retain the original local depths.
    quad(
      [
        [400, D + 2, D + 0.1],
        [500, D + 2, D + 0.1],
        [500, D + 8, D + 0.1],
        [400, D + 8, D + 0.1],
      ],
      3,
      0,
      0,
      0,
      false,
      [400, 0, 100, 6],
    );
    for (const x of [L + 44, L + macBookGeometry.width - 86])
      quad(
        [
          [x, D + 21, D - 12],
          [x + 42, D + 21, D - 12],
          [x + 42, D + 24, D - 12],
          [x, D + 24, D - 12],
        ],
        3,
        0,
        0,
        0,
        false,
        [x, 18, 42, 3],
      );
    const perimeter = (inset: number) =>
      [
        [22, 22, Math.PI],
        [macBookGeometry.width - 22, 22, Math.PI * 1.5],
        [macBookGeometry.width - 22, D - 22, 0],
        [22, D - 22, Math.PI * 0.5],
      ].flatMap(([x, y, start]) =>
        Array.from({ length: 9 }, (_, i) => [
          x + (22 - inset) * Math.cos(start + (i * Math.PI) / 16),
          y + (22 - inset) * Math.sin(start + (i * Math.PI) / 16),
        ]),
      );
    const shell = (
      part: number,
      rings: { z: number; inset: number; color: number[] }[],
    ) => {
      for (let band = 0; band < rings.length - 1; band++) {
        const a = rings[band],
          b = rings[band + 1],
          upper = perimeter(a.inset),
          lower = perimeter(b.inset);
        const point = (p: number[], z: number): Point =>
          part ? [L + p[0], p[1], z] : deckPoint(p[0], p[1], z);
        for (let i = 0; i < upper.length; i++) {
          const j = (i + 1) % upper.length;
          const points = [
            point(upper[i], a.z),
            point(upper[j], a.z),
            point(lower[j], b.z),
            point(lower[i], b.z),
          ];
          const colors = [a.color, a.color, b.color, b.color];
          for (const ids of [
            [0, 1, 2],
            [0, 2, 3],
          ])
            triangle(
              ids.map((k) => points[k]),
              ids.map(() => [0, 0]),
              part,
              2,
              0,
              ids.map((k) => colors[k]),
            );
        }
      }
    };
    shell(
      1,
      [
        { z: -6, inset: 0, color: [185, 190, 195] },
        { z: -4.68, inset: 0, color: [209, 212, 215] },
        { z: -1.8, inset: 0, color: [174, 179, 184] },
        { z: 0, inset: 0, color: [144, 150, 156] },
      ].map((r) => ({ ...r, color: r.color.map((v) => v / 255) })),
    );
    const metal = (shade: number) =>
      [shade - 3, shade, shade + 3].map((v) => v / 255);
    shell(0, [
      { z: 0, inset: 0, color: metal(205) },
      ...Array.from({ length: 7 }, (_, i) => {
        const a = (i * Math.PI) / 12;
        return {
          z: 6 + 11 * Math.sin(a),
          inset: 11 * (1 - Math.cos(a)),
          color: metal(Math.round(205 - 65 * Math.sin(a))),
        };
      }),
    ]);
    const vao = gl.createVertexArray()!;
    vaos.push(vao);
    gl.bindVertexArray(vao);
    const buffer = gl.createBuffer()!;
    buffers.push(buffer);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(vertices), gl.STATIC_DRAW);
    let offset = 0;
    for (const [name, size] of [
      ["position", 3],
      ["uv", 2],
      ["color", 3],
      ["flags", 3],
    ] as const) {
      const loc = gl.getAttribLocation(modelProgram, name);
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, size, gl.FLOAT, false, 44, offset * 4);
      offset += size;
    }
    const quadVao = gl.createVertexArray()!;
    vaos.push(quadVao);
    gl.bindVertexArray(quadVao);
    const quadBuffer = gl.createBuffer()!;
    buffers.push(quadBuffer);
    gl.bindBuffer(gl.ARRAY_BUFFER, quadBuffer);
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([-1, -1, 0, 1, -1, 0, -1, 1, 0, 1, 1, 0]),
      gl.STATIC_DRAW,
    );
    const loc = gl.getAttribLocation(wallpaperProgram, "position");
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 3, gl.FLOAT, false, 0, 0);
    const uniform = (p: WebGLProgram, name: string) =>
      gl.getUniformLocation(p, name);
    gl.useProgram(modelProgram);
    gl.uniform1i(uniform(modelProgram, "atlas"), 0);
    gl.uniform1i(uniform(modelProgram, "wallpaper"), 1);
    const modelFold = uniform(modelProgram, "degrees");
    gl.useProgram(wallpaperProgram);
    gl.uniform1i(uniform(wallpaperProgram, "desktop"), 0);
    gl.uniform2f(
      uniform(wallpaperProgram, "imageSize"),
      image.naturalWidth,
      image.naturalHeight,
    );
    const fold = uniform(wallpaperProgram, "fold"),
      projection = uniform(wallpaperProgram, "projection"),
      shading = uniform(wallpaperProgram, "shading");
    let previous = -1;
    let lastDrawn = -1;
    let lastFreeze = false;
    canvas.dataset.renderer = "single-webgl";
    return {
      resize(width: number, ratio: number) {
        if (!width) return;
        const w = Math.round(width * Math.min(ratio, 2));
        const h = Math.round((w * H) / W);
        if (canvas.width !== w || canvas.height !== h) {
          canvas.width = w;
          canvas.height = h;
          lastDrawn = -1;
        }
      },
      render(degrees: number, freezeWallpaper = false) {
        if (degrees === lastDrawn && freezeWallpaper === lastFreeze) return;
        lastDrawn = degrees;
        lastFreeze = freezeWallpaper;
        if (
          (degrees * 106) / 90 < 90 &&
          (!freezeWallpaper || previous < 0) &&
          degrees !== previous
        ) {
          gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
          gl.viewport(0, 0, 960, 600);
          gl.disable(gl.DEPTH_TEST);
          gl.disable(gl.BLEND);
          gl.useProgram(wallpaperProgram);
          gl.bindVertexArray(quadVao);
          gl.activeTexture(gl.TEXTURE0);
          gl.bindTexture(gl.TEXTURE_2D, desktopTexture);
          const radians = (degrees * Math.PI) / 180,
            imageAngle =
              0.22 * radians +
              (0.78 * radians) / (1 + (degrees / 34) ** 4) ** 0.25,
            p = Math.max(0, Math.min(1, degrees / 86)),
            t = Math.min(1, p / 0.75),
            strength = 0.65 * (0.6 + 0.4 * t * t * (3 - 2 * t));
          gl.uniform1f(fold, radians);
          gl.uniform4f(
            projection,
            Math.sin(imageAngle),
            Math.cos(imageAngle),
            1 - 0.58 * Math.min(1, degrees / 130),
            p,
          );
          gl.uniform4f(
            shading,
            p ** 0.7 * image.naturalHeight * strength,
            p ** 2.2,
            0.88 * (1 - Math.exp(-degrees / 3)),
            0.035 + 0.2 * (1 - Math.exp(-degrees / 22)),
          );
          gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
          previous = degrees;
        }
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
        gl.viewport(0, 0, canvas.width, canvas.height);
        gl.clearColor(0, 0, 0, 0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        gl.useProgram(modelProgram);
        gl.bindVertexArray(vao);
        gl.uniform1f(modelFold, degrees);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, atlasTexture);
        gl.activeTexture(gl.TEXTURE1);
        gl.bindTexture(gl.TEXTURE_2D, wallpaperTexture);
        gl.disable(gl.DEPTH_TEST);
        gl.enable(gl.BLEND);
        gl.blendFuncSeparate(
          gl.SRC_ALPHA,
          gl.ONE_MINUS_SRC_ALPHA,
          gl.ONE,
          gl.ONE_MINUS_SRC_ALPHA,
        );
        gl.drawArrays(gl.TRIANGLES, 0, shadowCount);
        gl.enable(gl.DEPTH_TEST);
        gl.depthFunc(gl.LEQUAL);
        gl.drawArrays(
          gl.TRIANGLES,
          shadowCount,
          vertices.length / 11 - shadowCount,
        );
      },
      dispose,
    };
  } catch (error) {
    console.error("MacBook WebGL initialization failed", error);
    dispose();
    return null;
  }
}
