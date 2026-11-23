import { useId, useRef } from 'react';
export function Tabs({ tabs, value, onChange, label = 'Secciones' }) {
 const id = useId(), refs = useRef([]); const selected = Math.max(0, tabs.findIndex((t) => t.value === value));
 const keyDown = (e) => { if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(e.key)) return; e.preventDefault(); const i = e.key === 'Home' ? 0 : e.key === 'End' ? tabs.length - 1 : (selected + (e.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length; onChange(tabs[i].value); refs.current[i]?.focus(); };
 return <><div className="tabs-row" role="tablist" aria-label={label} onKeyDown={keyDown}>{tabs.map((t, i) => <button key={t.value} ref={(el) => { refs.current[i] = el; }} className="chip" role="tab" id={`${id}-tab-${i}`} aria-controls={`${id}-panel-${i}`} aria-selected={i === selected} tabIndex={i === selected ? 0 : -1} onClick={() => onChange(t.value)}>{t.label}</button>)}</div>{tabs.map((t, i) => <div key={t.value} role="tabpanel" id={`${id}-panel-${i}`} aria-labelledby={`${id}-tab-${i}`} hidden={i !== selected}>{i === selected && t.content}</div>)}</>;
}
