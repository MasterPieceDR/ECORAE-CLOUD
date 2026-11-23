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
    const aplicar = () => {
      const styles = getComputedStyle(document.documentElement);
      const token = (name) => styles.getPropertyValue(name).trim();
      chart.current?.setOption({ ...option, textStyle: { ...option.textStyle, color: token('--text') },
        color: ['--primary', '--secondary', '--accent', '--accent-strong'].map(token),
        tooltip: { ...option.tooltip, backgroundColor: token('--surface'), borderColor: token('--line'), textStyle: { color: token('--text') } },
        legend: option.legend ? { ...option.legend, textStyle: { ...option.legend.textStyle, color: token('--text') } } : undefined,
        yAxis: option.yAxis ? { ...option.yAxis, axisLabel: { ...option.yAxis.axisLabel, color: token('--muted') } } : undefined,
      }, { notMerge: false, lazyUpdate: true });
    };
    aplicar();
    const observer = new MutationObserver(aplicar);
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
    return () => observer.disconnect();
  }, [option]);
  return <div ref={el} role="img" aria-label={label} style={{ width: '100%', height: 320 }} />;
}
