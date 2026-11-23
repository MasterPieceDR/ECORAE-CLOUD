import { motion } from 'motion/react';

const ARROWS = [0, 120, 240];

// Tres flechas en ciclo alrededor de un chip: el equipo vuelve a la economía circular.
export function LogoMark({ size = 40, animated = false, draw = false }) {
  return (
    <motion.svg width={size} height={size} viewBox="0 0 64 64" aria-hidden="true"
      animate={animated ? { rotate: 360 } : undefined} transition={animated ? { duration: 24, repeat: Infinity, ease: 'linear' } : undefined}>
      {ARROWS.map((deg, i) => (
        <g key={deg} transform={`rotate(${deg} 32 32)`}>
          <path data-load-draw={draw ? '' : undefined} d="M33.8 11.100A21 21 0 0 1 52.300 26.600" fill="none" stroke={i === 1 ? 'var(--text)' : 'var(--primary-strong)'} strokeWidth="7" />
          <path d="M60 24.500 55.200 37.300 44.600 28.700z" fill={i === 1 ? 'var(--text)' : 'var(--primary-strong)'} />
        </g>
      ))}
      <rect x="26" y="26" width="12" height="12" rx="2.500" fill="var(--primary-strong)" />
      <rect x="29.500" y="29.500" width="5" height="5" rx="1" fill="var(--on-primary)" />
    </motion.svg>
  );
}
export const Logo = () => (
  <span className="logo">
    <LogoMark />
    <span>EcoRAEE<br />Cloud</span>
  </span>
);
