import { Icon } from './Icon';
export function EmptyState({ title, description, action, icon = 'inbox' }) { return <div className="empty card"><Icon name={icon} size={36} /><h2>{title}</h2><p>{description}</p>{action}</div>; }
