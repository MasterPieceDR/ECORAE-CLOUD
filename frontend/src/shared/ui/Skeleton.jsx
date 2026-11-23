export const Skeleton = ({ h = 120, style }) => <div className="skeleton" style={{ height: h, ...style }} />;
export const PageSkeleton = () => (
  <div style={{ display: 'grid', gap: 16, padding: 16 }} aria-busy="true" aria-label="Cargando">
    <Skeleton h={120} /><Skeleton h={220} />
  </div>
);
