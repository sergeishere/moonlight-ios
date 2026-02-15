//
//  Plot.h
//  Moonlight
//
//  Metrics structure for streaming statistics.
//

#ifndef Plot_h
#define Plot_h

typedef struct {
    float min;
    float max;
    float avg;
    float total;
    int nsamples;
} PlotMetrics;

static inline PlotMetrics PlotMetricsMake(void) {
    PlotMetrics m;
    m.min = __FLT_MAX__;
    m.max = 0;
    m.avg = 0;
    m.total = 0;
    m.nsamples = 0;
    return m;
}

static inline void PlotMetricsUpdate(PlotMetrics *m, float value) {
    if (value < m->min) m->min = value;
    if (value > m->max) m->max = value;
    m->total += value;
    m->nsamples++;
    m->avg = m->total / m->nsamples;
}

#endif /* Plot_h */
