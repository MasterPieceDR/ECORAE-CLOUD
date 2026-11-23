import { Link } from 'react-router-dom';
export function PageHeader({ title, description, action, breadcrumbs = [] }) {
  return <header className="page-head"><div>{breadcrumbs.length > 0 && <nav aria-label="Migas de pan"><ol className="breadcrumbs">{breadcrumbs.map((b, i) => <li key={i}>{b.to ? <Link to={b.to}>{b.label}</Link> : <span aria-current="page">{b.label}</span>}</li>)}</ol></nav>}<h1 className="page-title">{title}</h1>{description && <p className="page-sub">{description}</p>}</div>{action}</header>;
}
