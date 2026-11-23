import { useEffect, useRef } from 'react';
import { Icon } from './Icon';

// Diálogo nativo <dialog>: foco atrapado, Esc para cerrar y fondo inerte sin librerías.
export function Modal({ title, onClose, children, wide = false, onSubmit, labelledBy = 'modal-title' }) {
  const ref = useRef(null);
  useEffect(() => { ref.current?.showModal(); }, []);
  const Body = onSubmit ? 'form' : 'div';
  return (
    <dialog ref={ref} className={`dialog ${wide ? 'dialog--wide' : ''}`} onClose={onClose} aria-labelledby={labelledBy}>
      <Body className="dialog__body" onSubmit={onSubmit ? (e) => { e.preventDefault(); onSubmit(e); } : undefined}>
        <header><h2 id={labelledBy}>{title}</h2><button type="button" className="icon-btn" onClick={onClose} aria-label="Cerrar"><Icon name="close" /></button></header>
        {children}
      </Body>
    </dialog>
  );
}
