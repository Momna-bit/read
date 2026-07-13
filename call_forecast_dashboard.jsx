import React, { useState, useMemo, useEffect, useRef, useCallback } from "react";
import {
  Area,
  BarChart,
  Bar,
  ComposedChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  ReferenceArea,
  ReferenceDot,
  Cell,
} from "recharts";

const C = {
  bg: "#070B18",
  bgGrid: "rgba(124,193,66,0.035)",
  panel: "rgba(16,24,46,0.72)",
  panelBorder: "rgba(255,255,255,0.07)",
  panelBorderHi: "rgba(124,193,66,0.22)",
  grid: "rgba(255,255,255,0.055)",
  navy: "#1B2A5C",
  navyLight: "#3E5590",
  green: "#7CC142",
  greenGlow: "rgba(124,193,66,0.55)",
  greenDim: "#3F5E2C",
  sky: "#5AA9E6",
  text: "#EDF2F7",
  muted: "#8B98B0",
  faint: "#54607A",
  alert: "#F2994A",
  alertBg: "rgba(242,153,74,0.10)",
  band: "rgba(124,193,66,0.10)",
};

const F_DISPLAY = "'Space Grotesk', 'IBM Plex Sans', system-ui, sans-serif";
const F_SANS = "'Inter', system-ui, sans-serif";
const F_MONO = "'IBM Plex Mono', ui-monospace, 'SF Mono', monospace";

const dayRates = [
  { day: "MON", full: "Monday", rate: 6.958, min: 6.451, max: 7.917 },
  { day: "TUE", full: "Tuesday", rate: 5.498, min: 4.749, max: 6.506 },
  { day: "WED", full: "Wednesday", rate: 5.183, min: 4.658, max: 5.925 },
  { day: "THU", full: "Thursday", rate: 4.462, min: 3.963, max: 5.164 },
  { day: "FRI", full: "Friday", rate: 4.223, min: 3.698, max: 4.672 },
  { day: "SAT", full: "Saturday", rate: 1.794, min: 1.171, max: 2.167 },
  { day: "SUN", full: "Sunday", rate: 0.0, min: 0, max: 0 },
];

const forecastBase = [
  { date: "Jul 11", day: "SAT", weekend: true },
  { date: "Jul 12", day: "SUN", weekend: true },
  { date: "Jul 13", day: "MON", weekend: false },
  { date: "Jul 14", day: "TUE", weekend: false },
  { date: "Jul 15", day: "WED", weekend: false },
  { date: "Jul 16", day: "THU", weekend: false },
  { date: "Jul 17", day: "FRI", weekend: false },
  { date: "Jul 18", day: "SAT", weekend: true },
  { date: "Jul 19", day: "SUN", weekend: true },
  { date: "Jul 20", day: "MON", weekend: false },
  { date: "Jul 21", day: "TUE", weekend: false },
  { date: "Jul 22", day: "WED", weekend: false },
  { date: "Jul 23", day: "THU", weekend: false },
  { date: "Jul 24", day: "FRI", weekend: false },
];

const rateByDay = Object.fromEntries(dayRates.map((d) => [d.day, d.rate]));
const fullByDay = Object.fromEntries(dayRates.map((d) => [d.day, d.full]));

const validationV1 = [
  { date: "Jun 1", actual: 4159, v1: 4455 }, { date: "Jun 2", actual: 3272, v1: 3512 },
  { date: "Jun 3", actual: 3077, v1: 3310 }, { date: "Jun 4", actual: 2615, v1: 2814 },
  { date: "Jun 5", actual: 2922, v1: 2697 }, { date: "Jun 6", actual: 1225, v1: 1145 },
  { date: "Jun 7", actual: 0, v1: 0 },       { date: "Jun 8", actual: 4344, v1: 4447 },
  { date: "Jun 9", actual: 3034, v1: 3512 }, { date: "Jun 10", actual: 2994, v1: 3312 },
  { date: "Jun 11", actual: 2720, v1: 2816 },{ date: "Jun 12", actual: 2768, v1: 2701 },
  { date: "Jun 13", actual: 1172, v1: 1147 },{ date: "Jun 14", actual: 0, v1: 0 },
  { date: "Jun 15", actual: 4130, v1: 4455 },{ date: "Jun 16", actual: 3224, v1: 3519 },
  { date: "Jun 17", actual: 2981, v1: 3317 },{ date: "Jun 18", actual: 2537, v1: 2821 },
  { date: "Jun 19", actual: 2460, v1: 2705 },{ date: "Jun 20", actual: 1204, v1: 1149 },
  { date: "Jun 21", actual: 0, v1: 0 },       { date: "Jun 22", actual: 4413, v1: 4462 },
  { date: "Jun 23", actual: 3455, v1: 3524 },{ date: "Jun 24", actual: 3332, v1: 3322 },
  { date: "Jun 25", actual: 2792, v1: 2826 },{ date: "Jun 26", actual: 2998, v1: 2710 },
  { date: "Jun 27", actual: 1391, v1: 1151 },{ date: "Jun 28", actual: 0, v1: 0 },
  { date: "Jun 29", actual: 4630, v1: 4471 },{ date: "Jun 30", actual: 3971, v1: 3532 },
  { date: "Jul 1", actual: 3733, v1: 3330 }, { date: "Jul 2", actual: 3316, v1: 2830 },
  { date: "Jul 3", actual: 2370, v1: 2706 }, { date: "Jul 4", actual: 751, v1: 1150 },
  { date: "Jul 5", actual: 0, v1: 0 },        { date: "Jul 6", actual: 5090, v1: 4474 },
  { date: "Jul 7", actual: 4175, v1: 3528 }, { date: "Jul 8", actual: 3801, v1: 3325 },
  { date: "Jul 9", actual: 3167, v1: 2827 },
];

const V2_FACTORS = { "Jul 4": 0.7, "Jul 6": 1.15, "Jul 7": 1.15, "Jul 8": 1.15, "Jul 9": 1.05 };
const BASE_CUSTOMERS = 639000;

function useIsNarrow(bp = 640) {
  const [narrow, setNarrow] = useState(typeof window !== "undefined" ? window.innerWidth < bp : false);
  useEffect(() => {
    const onR = () => setNarrow(window.innerWidth < bp);
    onR();
    window.addEventListener("resize", onR);
    return () => window.removeEventListener("resize", onR);
  }, [bp]);
  return narrow;
}

function useCountUp(target, duration = 900) {
  const [val, setVal] = useState(0);
  const fromRef = useRef(0);
  useEffect(() => {
    const reduced = typeof window !== "undefined" && window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduced) { setVal(target); return; }
    fromRef.current = val;
    let start = null;
    let raf;
    const step = (ts) => {
      if (start === null) start = ts;
      const p = Math.min((ts - start) / duration, 1);
      const eased = 1 - Math.pow(1 - p, 3);
      setVal(fromRef.current + (target - fromRef.current) * eased);
      if (p < 1) raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [target]);
  return val;
}

function useReveal() {
  const ref = useRef(null);
  const [visible, setVisible] = useState(false);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const obs = new IntersectionObserver(
      ([entry]) => { if (entry.isIntersecting) { setVisible(true); obs.disconnect(); } },
      { threshold: 0.12 }
    );
    obs.observe(el);
    return () => obs.disconnect();
  }, []);
  return [ref, visible];
}

function JustEnergyMark({ size = 40 }) {
  const blades = [0, 90, 180, 270];
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" style={{ overflow: "visible", flexShrink: 0 }}>
      <g>
        {blades.map((rot, i) => (
          <g key={i} transform={`rotate(${rot} 50 50)`}>
            <path
              d="M50 50 C 50 30, 40 10, 55 6 C 68 3, 78 18, 68 32 C 60 43, 50 46, 50 50 Z"
              fill={i === 0 ? C.navy : C.green}
              opacity={i === 0 ? 1 : 0.92}
            />
          </g>
        ))}
        <circle cx="50" cy="50" r="4.5" fill={C.bg} stroke={C.text} strokeWidth="1.5" />
      </g>
    </svg>
  );
}

function LiveDot() {
  return (
    <span style={{ position: "relative", display: "inline-flex", width: 8, height: 8 }}>
      <span style={{ position: "absolute", inset: 0, borderRadius: "50%", background: C.green, animation: "pulseRing 1.8s cubic-bezier(0.4,0,0.6,1) infinite" }} />
      <span style={{ position: "relative", width: 8, height: 8, borderRadius: "50%", background: C.green }} />
    </span>
  );
}

function Eyebrow({ children, style }) {
  return <div style={{ fontFamily: F_MONO, fontSize: 10.5, letterSpacing: "0.16em", color: C.faint, fontWeight: 600, textTransform: "uppercase", ...style }}>{children}</div>;
}

function SectionHeader({ eyebrow, title, note }) {
  return (
    <div className="flex items-end justify-between mb-5 flex-wrap gap-2">
      <div>
        <Eyebrow>{eyebrow}</Eyebrow>
        <div className="section-title" style={{ fontFamily: F_DISPLAY, fontWeight: 600, color: C.text, marginTop: 5 }}>{title}</div>
      </div>
      {note && <div style={{ fontFamily: F_MONO, fontSize: 11, color: C.muted }}>{note}</div>}
    </div>
  );
}

function Panel({ children, style, glow }) {
  const [ref, visible] = useReveal();
  return (
    <div
      ref={ref}
      className={`reveal panel-pad ${visible ? "visible" : ""}`}
      style={{
        background: C.panel,
        backdropFilter: "blur(10px)",
        WebkitBackdropFilter: "blur(10px)",
        border: `1px solid ${glow ? C.panelBorderHi : C.panelBorder}`,
        borderRadius: 12,
        boxShadow: glow ? `0 0 0 1px rgba(124,193,66,0.05), 0 20px 50px rgba(0,0,0,0.35)` : "0 20px 40px rgba(0,0,0,0.28)",
        position: "relative",
        overflow: "hidden",
        ...style,
      }}
    >
      {children}
    </div>
  );
}

function CustomTooltip({ active, payload, label }) {
  if (!active || !payload || !payload.length) return null;
  return (
    <div style={{ background: "#0B1226", border: `1px solid ${C.panelBorderHi}`, borderRadius: 8, padding: "10px 14px", fontFamily: F_MONO, fontSize: 12, color: C.text, boxShadow: "0 10px 30px rgba(0,0,0,0.5)" }}>
      <div style={{ color: C.muted, marginBottom: 6, letterSpacing: "0.05em" }}>{label}</div>
      {payload.map((p, i) => (
        <div key={i} style={{ display: "flex", justifyContent: "space-between", gap: 16 }}>
          <span style={{ color: C.muted }}>{p.name}</span>
          <span style={{ fontWeight: 600, color: p.color }}>{typeof p.value === "number" ? Math.round(p.value).toLocaleString() : p.value}</span>
        </div>
      ))}
    </div>
  );
}

function Toggle({ value, onChange, options }) {
  return (
    <div style={{ display: "inline-flex", background: "rgba(255,255,255,0.03)", border: `1px solid ${C.panelBorder}`, borderRadius: 8, padding: 3, flexWrap: "wrap" }}>
      {options.map((opt) => (
        <button
          key={opt.value}
          onClick={() => onChange(opt.value)}
          style={{
            fontFamily: F_MONO, fontSize: 11.5, padding: "6px 14px", borderRadius: 6, border: "none", cursor: "pointer",
            letterSpacing: "0.04em", fontWeight: 600, transition: "all 0.15s ease",
            background: value === opt.value ? opt.activeColor || C.green : "transparent",
            color: value === opt.value ? "#06110F" : C.muted,
          }}
        >
          {opt.label}
        </button>
      ))}
    </div>
  );
}

function ReadoutCard({ label, value, unit, color, sub, decimals = 1 }) {
  const animated = useCountUp(value);
  return (
    <Panel>
      <div style={{ fontFamily: F_MONO, fontSize: 10, color: C.faint, letterSpacing: "0.12em" }}>{label}</div>
      <div className="readout-value" style={{ fontFamily: F_MONO, fontWeight: 700, color, marginTop: 6, lineHeight: 1, fontVariantNumeric: "tabular-nums", textShadow: `0 0 24px ${color}33` }}>
        {animated.toFixed(decimals)}<span style={{ fontSize: "0.5em", color: C.muted }}>{unit}</span>
      </div>
      <div style={{ fontSize: 11.5, color: C.muted, marginTop: 6 }}>{sub}</div>
    </Panel>
  );
}

function DayChips({ selected, onSelect }) {
  return (
    <div className="day-chip-row">
      {dayRates.map((d) => (
        <button
          key={d.day}
          onClick={() => onSelect(selected === d.day ? null : d.day)}
          className="day-chip"
          style={{
            fontFamily: F_MONO,
            background: selected === d.day ? C.green : "transparent",
            color: selected === d.day ? "#06110F" : C.muted,
            borderColor: selected === d.day ? C.green : C.panelBorder,
          }}
        >
          {d.day}
        </button>
      ))}
    </div>
  );
}

export default function CallForecastDashboard() {
  const [customers, setCustomers] = useState(BASE_CUSTOMERS);
  const [modelVersion, setModelVersion] = useState("v1");
  const [showBand, setShowBand] = useState(true);
  const [selectedDay, setSelectedDay] = useState(null);
  const isNarrow = useIsNarrow();

  const scaledForecast = useMemo(
    () => forecastBase.map((d) => ({ ...d, calls: Math.round((rateByDay[d.day] * customers) / 1000) })),
    [customers]
  );

  const scaledDayRates = useMemo(
    () => dayRates.map((d) => ({
      ...d,
      calls: Math.round((d.rate * customers) / 1000),
      minCalls: Math.round((d.min * customers) / 1000),
      maxCalls: Math.round((d.max * customers) / 1000),
    })),
    [customers]
  );

  const validationData = useMemo(
    () => validationV1.map((d) => {
      const factor = V2_FACTORS[d.date] || 1;
      const v2 = Math.round(d.v1 * factor);
      return { ...d, v2, predicted: modelVersion === "v1" ? d.v1 : v2 };
    }),
    [modelVersion]
  );

  const avgErrorPct = useMemo(() => {
    const errs = validationData.filter((d) => d.actual > 0).map((d) => (Math.abs(d.actual - d.predicted) / d.actual) * 100);
    return errs.reduce((a, b) => a + b, 0) / errs.length;
  }, [validationData]);

  const holidayWindowErrorPct = useMemo(() => {
    const w = validationData.filter((d) => ["Jul 4", "Jul 6", "Jul 7", "Jul 8", "Jul 9"].includes(d.date));
    const errs = w.map((d) => (Math.abs(d.actual - d.predicted) / d.actual) * 100);
    return errs.reduce((a, b) => a + b, 0) / errs.length;
  }, [validationData]);

  const selectedPoint = selectedDay ? scaledDayRates.find((d) => d.day === selectedDay) : null;

  return (
    <div style={{ background: C.bg, minHeight: "100vh", fontFamily: F_SANS, color: C.text, position: "relative" }}>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@500;600;700&family=Inter:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500;600;700&display=swap');
        * { box-sizing: border-box; }
        @keyframes pulseRing { 0% { transform: scale(1); opacity: 0.7; } 70% { transform: scale(2.4); opacity: 0; } 100% { opacity: 0; } }
        input[type=range] { -webkit-appearance: none; appearance: none; width: 100%; height: 4px; background: rgba(255,255,255,0.1); border-radius: 2px; outline: none; }
        input[type=range]::-webkit-slider-thumb { -webkit-appearance: none; appearance: none; width: 17px; height: 17px; border-radius: 50%; background: ${C.green}; cursor: pointer; border: 3px solid ${C.bg}; box-shadow: 0 0 0 1.5px ${C.green}, 0 0 16px ${C.greenGlow}; }
        input[type=range]::-moz-range-thumb { width: 17px; height: 17px; border-radius: 50%; background: ${C.green}; cursor: pointer; border: 3px solid ${C.bg}; box-shadow: 0 0 0 1.5px ${C.green}, 0 0 16px ${C.greenGlow}; }

        .dash-wrap { max-width: 1040px; margin: 0 auto; padding: 44px 24px 60px; }
        @media (max-width: 640px) { .dash-wrap { padding: 24px 14px 40px; } }

        .panel-pad { padding: clamp(16px, 4vw, 28px) clamp(16px, 4.5vw, 28px); }

        .brand-title { font-size: clamp(22px, 5.2vw, 28px); font-weight: 700; letter-spacing: -0.01em; margin-top: 4px; }
        .section-title { font-size: clamp(16px, 3.6vw, 19px); }

        .stat-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 14px; margin-bottom: 24px; }
        @media (max-width: 680px) { .stat-grid { grid-template-columns: 1fr; gap: 12px; } }

        .readout-value { font-size: clamp(24px, 7vw, 36px); }

        .methodology-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px 40px; margin-top: 16px; }
        @media (max-width: 640px) { .methodology-grid { grid-template-columns: 1fr; } }

        .day-chip-row { display: flex; gap: 6px; flex-wrap: wrap; margin: 12px 0 10px; }
        .day-chip { font-size: 11px; padding: 6px 11px; border-radius: 7px; border: 1px solid; cursor: pointer; transition: all 0.15s ease; font-weight: 600; letter-spacing: 0.03em; }
        .day-chip:hover { border-color: ${C.green}; }

        .reveal { opacity: 0; transform: translateY(16px); transition: opacity 0.6s ease, transform 0.6s ease; }
        .reveal.visible { opacity: 1; transform: none; }
        @media (prefers-reduced-motion: reduce) { .reveal { transition: none; opacity: 1; transform: none; } }

        .header-flex { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; flex-wrap: wrap; margin-bottom: 8px; }
        @media (max-width: 560px) { .header-flex { flex-direction: column; } }
      `}</style>

      <div
        aria-hidden
        style={{
          position: "fixed", inset: 0, zIndex: 0, pointerEvents: "none",
          backgroundImage: `linear-gradient(${C.bgGrid} 1px, transparent 1px), linear-gradient(90deg, ${C.bgGrid} 1px, transparent 1px)`,
          backgroundSize: "48px 48px",
          maskImage: "radial-gradient(ellipse 80% 60% at 50% 0%, black 40%, transparent 100%)",
        }}
      />

      <div className="dash-wrap" style={{ position: "relative", zIndex: 1 }}>
        {/* HEADER */}
        <div className="header-flex">
          <div className="flex items-center gap-4">
            <JustEnergyMark size={isNarrow ? 32 : 40} />
            <div>
              <Eyebrow>CARE OPERATIONS · TEXAS RESIDENTIAL</Eyebrow>
              <div className="brand-title" style={{ fontFamily: F_DISPLAY, color: C.text }}>Call Volume Forecast</div>
            </div>
          </div>
          <div className="flex items-center gap-2" style={{ fontFamily: F_MONO, fontSize: 11, color: C.muted, paddingTop: 6 }}>
            <LiveDot />
            <span>MODEL V1 · LIVE · JUL 2026</span>
          </div>
        </div>

        <div style={{ color: C.muted, fontSize: 13.5, marginBottom: 26, maxWidth: 620 }}>
          Daily agent-handled call volume, modeled from active customer counts and observed
          day-of-week demand rhythm. Click a weekday below to trace it across every chart.
        </div>

        {/* READOUT STRIP */}
        <div className="stat-grid">
          <ReadoutCard label="VALIDATION ACCURACY" value={avgErrorPct} unit="%" color={C.green} sub={modelVersion === "v1" ? "avg error, all 39 days" : "avg error (proposed model)"} />
          <ReadoutCard label="ACTIVE CUSTOMERS" value={customers / 1000} unit="K" color={C.sky} sub="Texas · Residential (adjustable)" decimals={0} />
          <ReadoutCard label="HOLIDAY WINDOW ERROR" value={holidayWindowErrorPct} unit="%" color={C.alert} sub="Jul 4, 6-9 only" />
        </div>

        {/* SIMULATOR SLIDER */}
        <Panel style={{ marginBottom: 24 }} glow>
          <div className="flex items-center justify-between mb-2 flex-wrap gap-2">
            <Eyebrow style={{ color: C.green }}>◆ LIVE SIMULATOR</Eyebrow>
            <div style={{ fontFamily: F_MONO, fontSize: 13, color: C.text, fontWeight: 700 }}>{customers.toLocaleString()} customers</div>
          </div>
          <input type="range" min={580000} max={700000} step={1000} value={customers} onChange={(e) => setCustomers(Number(e.target.value))} />
          <div className="flex justify-between mt-1" style={{ fontFamily: F_MONO, fontSize: 10, color: C.faint }}>
            <span>580K</span><span>639K observed</span><span>700K</span>
          </div>
          <div style={{ fontSize: 12, color: C.muted, marginTop: 10 }}>
            Drag to see every chart below recompute live — the model's exact formula:{" "}
            <span style={{ fontFamily: F_MONO, color: C.text, fontWeight: 600 }}>customers × day-of-week rate ÷ 1000</span>.
          </div>
        </Panel>

        {/* WEEKLY LOAD PATTERN */}
        <Panel style={{ marginBottom: 24 }} glow>
          <div className="flex items-end justify-between mb-2 flex-wrap gap-2">
            <div>
              <Eyebrow>DEMAND RHYTHM</Eyebrow>
              <div className="section-title" style={{ fontFamily: F_DISPLAY, fontWeight: 600, color: C.text, marginTop: 5 }}>Weekly Load Pattern</div>
            </div>
            <button
              onClick={() => setShowBand(!showBand)}
              style={{ fontFamily: F_MONO, fontSize: 10.5, color: showBand ? C.green : C.muted, background: showBand ? C.band : "transparent", border: `1px solid ${showBand ? C.panelBorderHi : C.panelBorder}`, borderRadius: 6, padding: "5px 10px", cursor: "pointer" }}
            >
              {showBand ? "◉" : "○"} OBSERVED RANGE
            </button>
          </div>
          <DayChips selected={selectedDay} onSelect={setSelectedDay} />
          <div style={{ height: isNarrow ? 200 : 240 }}>
            <ResponsiveContainer width="100%" height="100%">
              <ComposedChart data={scaledDayRates} margin={{ top: 10, right: 10, left: -10, bottom: 0 }}>
                <defs>
                  <linearGradient id="loadFill" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor={C.green} stopOpacity={0.38} />
                    <stop offset="100%" stopColor={C.green} stopOpacity={0} />
                  </linearGradient>
                  <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
                    <feGaussianBlur stdDeviation="4" result="blur" />
                    <feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge>
                  </filter>
                </defs>
                <CartesianGrid stroke={C.grid} vertical={false} />
                <XAxis dataKey="day" tick={{ fill: C.muted, fontFamily: F_MONO, fontSize: 11 }} axisLine={{ stroke: C.panelBorder }} tickLine={false} />
                <YAxis hide />
                <Tooltip content={<CustomTooltip />} />
                {showBand && <Area type="monotone" dataKey="maxCalls" name="Max observed" stroke="none" fill={C.band} />}
                <Area type="monotone" dataKey="calls" name="Predicted" stroke={C.green} strokeWidth={2.5} fill="url(#loadFill)" dot={{ r: 3.5, fill: C.green, strokeWidth: 0 }} activeDot={{ r: 6, fill: C.green, stroke: C.bg, strokeWidth: 2 }} style={{ filter: "url(#glow)" }} />
                {selectedPoint && <ReferenceDot x={selectedPoint.day} y={selectedPoint.calls} r={7} fill={C.text} stroke={C.green} strokeWidth={3} />}
              </ComposedChart>
            </ResponsiveContainer>
          </div>
          <div style={{ fontSize: 12, color: C.muted, marginTop: 6, minHeight: 18 }}>
            {selectedDay ? (
              <span style={{ fontFamily: F_MONO, color: C.green }}>
                {customers.toLocaleString()} × {rateByDay[selectedDay]} ÷ 1000 = {selectedPoint.calls.toLocaleString()} predicted calls on {fullByDay[selectedDay]}s
              </span>
            ) : (
              <>Monday peaks at <span style={{ color: C.green, fontFamily: F_MONO, fontWeight: 600 }}>{scaledDayRates[0].calls.toLocaleString()}</span> predicted calls — nearly triple Friday's rate. Click a day above to inspect it.</>
            )}
          </div>
        </Panel>

        {/* 14-DAY FORECAST */}
        <Panel style={{ marginBottom: 24 }}>
          <SectionHeader eyebrow="FORWARD VIEW" title="14-Day Forecast" note={selectedDay ? `highlighting ${fullByDay[selectedDay]}s` : "predicted calls / day"} />
          <div style={{ height: isNarrow ? 170 : 200 }}>
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={scaledForecast} margin={{ top: 10, right: 10, left: -10, bottom: 0 }}>
                <CartesianGrid stroke={C.grid} vertical={false} />
                <XAxis dataKey="date" tick={{ fill: C.muted, fontFamily: F_MONO, fontSize: isNarrow ? 8.5 : 10 }} axisLine={{ stroke: C.panelBorder }} tickLine={false} interval={isNarrow ? 1 : 0} />
                <YAxis hide />
                <Tooltip content={<CustomTooltip />} />
                <Bar dataKey="calls" name="Predicted" radius={[3, 3, 0, 0]} onClick={(d) => setSelectedDay(selectedDay === d.day ? null : d.day)} style={{ cursor: "pointer" }}>
                  {scaledForecast.map((d, i) => {
                    const dim = selectedDay && d.day !== selectedDay;
                    const base = d.weekend ? C.greenDim : C.sky;
                    return <Cell key={i} fill={selectedDay === d.day ? C.green : base} opacity={dim ? 0.28 : 1} />;
                  })}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
          <div className="flex gap-5 mt-1 flex-wrap">
            <div className="flex items-center gap-2"><div style={{ width: 10, height: 10, background: C.sky, borderRadius: 2 }} /><span style={{ fontSize: 11.5, color: C.muted }}>Weekday</span></div>
            <div className="flex items-center gap-2"><div style={{ width: 10, height: 10, background: C.greenDim, borderRadius: 2 }} /><span style={{ fontSize: 11.5, color: C.muted }}>Weekend</span></div>
            <div className="flex items-center gap-2"><div style={{ width: 10, height: 10, background: C.green, borderRadius: 2 }} /><span style={{ fontSize: 11.5, color: C.muted }}>Selected</span></div>
          </div>
        </Panel>

        {/* VALIDATION CHART */}
        <Panel style={{ marginBottom: 24 }}>
          <div className="flex items-end justify-between mb-2 flex-wrap gap-3">
            <div>
              <Eyebrow>MODEL VALIDATION</Eyebrow>
              <div className="section-title" style={{ fontFamily: F_DISPLAY, fontWeight: 600, color: C.text, marginTop: 5 }}>Predicted vs. Actual</div>
            </div>
            <Toggle
              value={modelVersion}
              onChange={setModelVersion}
              options={[
                { value: "v1", label: "V1 — VALIDATED", activeColor: C.sky },
                { value: "v2", label: "V2 — PROPOSED", activeColor: C.alert },
              ]}
            />
          </div>
          {modelVersion === "v2" && (
            <div style={{ fontFamily: F_MONO, fontSize: 11, color: C.alert, background: C.alertBg, border: `1px solid rgba(242,153,74,0.3)`, borderRadius: 6, padding: "6px 10px", marginBottom: 14, display: "inline-block" }}>
              ⚠ ILLUSTRATIVE ONLY — shows the concept of a holiday-flag correction (-30% on the holiday, +5 to +15% the days after). Not yet built, run, or re-validated as a real model.
            </div>
          )}
          <div style={{ height: isNarrow ? 220 : 260 }}>
            <ResponsiveContainer width="100%" height="100%">
              <ComposedChart data={validationData} margin={{ top: 10, right: 10, left: -10, bottom: 0 }}>
                <CartesianGrid stroke={C.grid} vertical={false} />
                <XAxis dataKey="date" tick={{ fill: C.faint, fontFamily: F_MONO, fontSize: isNarrow ? 8 : 9 }} axisLine={{ stroke: C.panelBorder }} tickLine={false} interval={isNarrow ? 4 : 2} />
                <YAxis hide />
                <Tooltip content={<CustomTooltip />} />
                <ReferenceArea x1="Jul 4" x2="Jul 9" fill={C.alert} fillOpacity={0.08} stroke={C.alert} strokeOpacity={0.35} strokeDasharray="3 3" />
                <Line type="monotone" dataKey="actual" name="Actual" stroke={C.green} strokeWidth={2.25} dot={false} />
                <Line type="monotone" dataKey="predicted" name={modelVersion === "v1" ? "Predicted (V1)" : "Predicted (V2, proposed)"} stroke={C.sky} strokeWidth={2.25} strokeDasharray="5 3" dot={false} />
              </ComposedChart>
            </ResponsiveContainer>
          </div>
          <div className="flex items-center justify-between mt-3 flex-wrap gap-3">
            <div className="flex gap-5">
              <div className="flex items-center gap-2"><div style={{ width: 16, height: 2.5, background: C.green }} /><span style={{ fontSize: 11.5, color: C.muted }}>Actual</span></div>
              <div className="flex items-center gap-2"><div style={{ width: 16, height: 2.5, backgroundImage: `repeating-linear-gradient(90deg, ${C.sky} 0 4px, transparent 4px 7px)` }} /><span style={{ fontSize: 11.5, color: C.muted }}>Predicted</span></div>
            </div>
            <div style={{ fontFamily: F_MONO, fontSize: 11, color: C.alert, background: C.alertBg, border: `1px solid rgba(242,153,74,0.3)`, borderRadius: 6, padding: "4px 10px" }}>
              ⚠ FLAGGED: Jul 4-8 holiday window
            </div>
          </div>
        </Panel>

        {/* METHODOLOGY FOOTER */}
        <Panel style={{ marginBottom: 8 }}>
          <Eyebrow>METHODOLOGY</Eyebrow>
          <div className="methodology-grid" style={{ fontSize: 12.5 }}>
            <div><span style={{ color: C.muted }}>Source: </span><span style={{ fontFamily: F_MONO, color: C.text, fontWeight: 600 }}>dbo.IVR</span><span style={{ color: C.muted }}> — Care, Inbound/Transfer, AgentTalkTime {">"} 0</span></div>
            <div><span style={{ color: C.muted }}>Population: </span><span style={{ fontFamily: F_MONO, color: C.text, fontWeight: 600 }}>iSigma_Customer_Master</span><span style={{ color: C.muted }}> — Texas, Residential</span></div>
            <div><span style={{ color: C.muted }}>Formula: </span><span style={{ color: C.text }}>active customers × day-of-week rate</span></div>
            <div><span style={{ color: C.muted }}>V2 status: </span><span style={{ color: C.alert, fontWeight: 600 }}>proposed, not yet built or validated</span></div>
          </div>
        </Panel>
      </div>
    </div>
  );
}
