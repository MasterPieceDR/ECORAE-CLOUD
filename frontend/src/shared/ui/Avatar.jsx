import { initials } from '@/shared/api';

export const Avatar = ({ name, large = false }) => <span className={`avatar ${large ? 'avatar--lg' : ''}`} aria-hidden="true">{initials(name)}</span>;
