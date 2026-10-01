import type { CSSProperties } from 'react';

export const macBookGeometry = { width: 821.739, depth: 547.826, radius: 22 };

const { width, depth, radius } = macBookGeometry;
const corners = [
  { x: radius, y: radius, start: Math.PI },
  { x: width - radius, y: radius, start: Math.PI * 1.5 },
  { x: width - radius, y: depth - radius, start: 0 },
  { x: radius, y: depth - radius, start: Math.PI * 0.5 },
];
const perimeter = (inset: number) => corners.flatMap(corner => Array.from({ length: 9 }, (_, i) => {
  const angle = corner.start + i * Math.PI / 16;
  return { x: corner.x + (radius - inset) * Math.cos(angle), y: corner.y + (radius - inset) * Math.sin(angle) };
}));

type ShellProps = { thickness: number; offset: number; bottomRadius?: number };

export default function MacBookShell({ thickness, offset, bottomRadius = 0 }: ShellProps) {
  // A short vertical lip rolls inward through a quarter-circle to the underside.
  // Matching inset contours also carry that curve around all four corners.
  const curve = Math.min(bottomRadius, thickness, radius);
  const rings = curve ? [
    { z: 0, inset: 0, shade: 205 },
    ...Array.from({ length: 7 }, (_, i) => {
      const angle = i * Math.PI / 12;
      return { z: thickness - curve + curve * Math.sin(angle), inset: curve * (1 - Math.cos(angle)), shade: Math.round(205 - 65 * Math.sin(angle)) };
    }),
  ] : [{ z: 0, inset: 0, shade: 190 }, { z: thickness, inset: 0, shade: 155 }];

  return <div className="seamless-macbook__shell">
    {rings.slice(0, -1).flatMap((ring, band) => {
      const nextRing = rings[band + 1];
      const upper = perimeter(ring.inset);
      const lower = perimeter(nextRing.inset);
      return upper.map((point, i) => {
        const j = (i + 1) % upper.length;
        const dx = upper[j].x - point.x;
        const dy = upper[j].y - point.y;
        const length = Math.hypot(dx, dy);
        const lowerLength = Math.hypot(lower[j].x - lower[i].x, lower[j].y - lower[i].y);
        const inset = ((lower[i].x + lower[j].x - point.x - upper[j].x) * -dy
          + (lower[i].y + lower[j].y - point.y - upper[j].y) * dx) / (2 * length);
        const rise = nextRing.z - ring.z;
        const taper = (length - lowerLength) / 2;
        const metal = (shade: number) => `rgb(${shade - 3}, ${shade}, ${shade + 3})`;
        return <span key={`${band}-${i}`} style={{
          // Overlap subpixels at the joins; the clipped trapezoid preserves
          // the narrowing contour instead of leaving rectangular corner gaps.
          width: `${length + 0.4}px`,
          height: `${Math.hypot(inset, rise) + 0.2}px`,
          clipPath: `polygon(0 0, 100% 0, calc(100% - ${taper}px) 100%, ${taper}px 100%)`,
          background: curve ? `linear-gradient(${metal(ring.shade)}, ${metal(nextRing.shade)})` : undefined,
          transform: `translate3d(${point.x}px, ${point.y}px, ${offset + ring.z}px) rotateZ(${Math.atan2(dy, dx)}rad) rotateX(${Math.atan2(rise, inset)}rad)`,
        } as CSSProperties} />;
      });
    })}
  </div>;
}
