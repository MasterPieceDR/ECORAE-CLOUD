import { useEffect, useRef } from 'react';
import { animate, useInView, useReducedMotion } from 'motion/react';

export function Counter({ to, suffix = '', decimals = 0 }) {
  const ref = useRef(null);
  const inView = useInView(ref, { once: true });
  const reduced = useReducedMotion();
  useEffect(() => {
    if (!ref.current) return undefined;
    const write = (v) => { if (ref.current) ref.current.textContent = `${v.toFixed(decimals).replace('.', ',')}${suffix}`; };
    if (!inView || reduced) { write(reduced ? to : 0); return undefined; }
    const controls = animate(0, to, { duration: 1.1, ease: [0.16, 1, 0.3, 1], onUpdate: write });
    return () => controls.stop();
  }, [inView, to, suffix, decimals, reduced]);
  return <span ref={ref}>{to}{suffix}</span>;
}
