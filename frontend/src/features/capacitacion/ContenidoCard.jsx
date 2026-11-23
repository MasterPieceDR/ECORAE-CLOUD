import { Link } from 'react-router-dom';
import { motion } from 'motion/react';
import { fotoTema, formatNumber, TEMA } from '@/shared/api';
import { Icon } from '@/shared/ui/Icon';
import './capacitacion.css';

export const ContenidoCard = ({ c, index = 0 }) => (
  <motion.article className="vcard" initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: index * .05 }} whileHover={{ y: -4 }}>
    <Link to={`/app/capacitacion/${c.uid}`}>
      <div className="vcard__thumb"><img src={fotoTema(c.tema, index)} alt="" loading="lazy" /><span>{TEMA[c.tema] ?? c.tema}</span></div>
      <h3>{c.titulo}</h3>
      <p><Icon name="eye" size={15} /> {formatNumber(c.vistas)} <Icon name="like" size={15} /> {c.me_gusta} <Icon name="comment" size={15} /> {c.comentarios}{c.estado === 'OCULTO' && <span className="badge" data-tone="coral">Oculto</span>}</p>
      <small className="vcard__by">{c.autor} · {c.organizacion_autor}</small>
    </Link>
  </motion.article>
);
