import { useEffect, useRef } from 'react';
import * as echarts from 'echarts/core';
import { BarChart, PieChart, LineChart } from 'echarts/charts';
import { GridComponent, TooltipComponent, LegendComponent } from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';
echarts.use([BarChart, PieChart, LineChart, GridComponent, TooltipComponent, LegendComponent, CanvasRenderer]);

export function Chart({ option, onClick, label }) {
  const el = useRef(null), chart = useRef(null), click = useRef(onClick);
  click.current = onClick;
  useEffect(() => {
    chart.current = echarts.init(el.current);
    const c = chart.current;
    c.on('click', (p) => click.current?.(p));
    const observer = new ResizeObserver(() => c.resize()); observer.observe(el.current);
    return () => { observer.disconnect(); c.dispose(); chart.current = null; };
  }, []);
  useEffect(() => {
    const styles = getComputedStyle(document.documentElement);
    chart.current?.setOption({ textStyle: { color: styles.getPropertyValue('--text').trim() }, color: ['--lime', '--leaf', '--coral', '--sky', '--sun'].map((token) => styles.getPropertyValue(token).trim()), ...option }, { notMerge: false, lazyUpdate: true });
  }, [option]);
  return <div ref={el} role="img" aria-label={label} style={{ width: '100%', height: 320 }} />;
}
