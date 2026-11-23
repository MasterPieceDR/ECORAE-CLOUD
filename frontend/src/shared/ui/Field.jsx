import { cloneElement, useId, useState } from 'react';
export function Field({ label, help, error, children, id: suppliedId }) {
  const generated = useId(), id = suppliedId || generated;
  const [invalid, setInvalid] = useState('');
  const message = error || invalid;
  const described = [children.props['aria-describedby'], help && `${id}-help`, message && `${id}-error`].filter(Boolean).join(' ') || undefined;
  return <div className="field"><label htmlFor={id}>{label}</label>{cloneElement(children, { id, 'aria-describedby': described, 'aria-invalid': message ? true : undefined, onInvalid: (e) => { setInvalid(e.currentTarget.validationMessage); children.props.onInvalid?.(e); }, onInput: (e) => { if (invalid) setInvalid(e.currentTarget.validationMessage); children.props.onInput?.(e); } })}{help && <span className="hint" id={`${id}-help`}>{help}</span>}{message && <span className="field__error" id={`${id}-error`} role="alert">{message}</span>}</div>;
}
