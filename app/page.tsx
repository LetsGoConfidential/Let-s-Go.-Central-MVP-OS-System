import { Activity, ArrowDownRight, ArrowUpRight, BadgeIndianRupee, CalendarClock, Check, ChevronDown, CircleAlert, CircleHelp, Command, FileText, LayoutDashboard, LifeBuoy, ListTodo, MoreHorizontal, Plus, Search, Settings2, Sparkles, Users, WalletCards, Zap } from "lucide-react";

const navigation = [
  { label: "Overview", icon: LayoutDashboard, active: true },
  { label: "Sales & CRM", icon: Activity },
  { label: "Clients", icon: Users },
  { label: "Projects", icon: FileText },
  { label: "Content", icon: CalendarClock },
  { label: "Tasks", icon: ListTodo },
  { label: "Team", icon: Users },
  { label: "Finance", icon: WalletCards },
  { label: "Reports", icon: BadgeIndianRupee },
];

const attention = [
  { tone: "amber", title: "3 invoices overdue", detail: "₹1,24,000 outstanding · View finance" },
  { tone: "blue", title: "4 content items need review", detail: "Across 3 clients · Review content" },
  { tone: "rose", title: "2 projects at risk", detail: "Deadlines within 48 hours · View projects" },
];

const activities = [
  { initials: "AK", color: "violet", text: <><b>Arjun Kapoor</b> moved <b>Brand Launch Campaign</b> to Client Review</>, time: "12 min ago" },
  { initials: "SM", color: "orange", text: <><b>Samprati Mehta</b> approved <b>September Content Calendar</b></>, time: "48 min ago" },
  { initials: "RK", color: "blue", text: <><b>Riya Khanna</b> added a new lead <b>Urban Brew Co.</b></>, time: "2 hours ago" },
];

function Metric({ label, value, change, positive = true, icon: Icon }: { label: string; value: string; change: string; positive?: boolean; icon: typeof WalletCards }) {
  return <article className="metric card"><div className="metric-top"><span>{label}</span><span className="metric-icon"><Icon size={17} /></span></div><div className="metric-value">{value}</div><div className={`metric-change ${positive ? "up" : "down"}`}>{positive ? <ArrowUpRight size={14} /> : <ArrowDownRight size={14} />}{change}<span>vs last month</span></div></article>;
}

export default function Home() {
  return <main className="app-shell">
    <aside className="sidebar">
      <a className="brand" href="#"><span className="brand-name">LET’S GO.</span><span className="brand-sub">CENTRAL OS</span></a>
      <div className="org-switch"><span className="org-mark">LG</span><span className="org-copy"><b>Let’s Go Digitals</b><small>Founder workspace</small></span><ChevronDown size={15} /></div>
      <div className="nav-caption">WORKSPACE</div>
      <nav aria-label="Main navigation">{navigation.map(({ label, icon: Icon, active }) => <a key={label} className={`nav-link ${active ? "active" : ""}`} href="#"><Icon size={17} strokeWidth={1.8} /><span>{label}</span>{label === "Tasks" && <span className="nav-count">8</span>}</a>)}</nav>
      <div className="nav-caption tools-caption">TOOLS</div>
      <a className="nav-link" href="#"><Zap size={17} strokeWidth={1.8} /><span>Automations</span></a>
      <a className="nav-link" href="#"><Command size={17} strokeWidth={1.8} /><span>Integrations</span></a>
      <div className="sidebar-bottom"><div className="ai-callout"><span className="ai-symbol"><Sparkles size={17} /></span><b>Ask Central AI</b><p>Your agency copilot is ready.</p><button>Start a conversation <span>↗</span></button></div><a className="nav-link" href="#"><Settings2 size={17} /><span>Settings</span></a><a className="nav-link" href="#"><LifeBuoy size={17} /><span>Help & support</span></a><div className="profile"><div className="avatar avatar-dark">JK</div><div><b>Jankhan Patel</b><small>Founder</small></div><MoreHorizontal size={18} /></div></div>
    </aside>

    <section className="main-area">
      <header className="topbar"><div className="breadcrumbs"><span>Workspace</span><span className="slash">/</span><b>Overview</b><span className="preview-label">Illustrative preview</span></div><div className="top-actions"><a className="signin-link" href="/login">Sign in</a><button className="search-button"><Search size={15} /><span>Search anything...</span><kbd>⌘ K</kbd></button><button className="help-button" aria-label="Help"><CircleHelp size={18} /></button><div className="avatar avatar-blue">JK</div></div></header>
      <div className="content-wrap">
        <section className="welcome-row"><div><div className="eyebrow">TUESDAY, 29 SEPTEMBER 2026</div><h1>Good morning, Jankhan <span>✦</span></h1><p>Here’s what’s happening across your agency today.</p></div><button className="primary-button"><Plus size={17} /> Create new <ChevronDown size={14} /></button></section>
        <section className="metrics-grid" aria-label="Business overview"><Metric label="Monthly revenue" value="₹8,42,500" change="12.8%" icon={WalletCards} /><Metric label="Receivables" value="₹2,16,000" change="8.2%" positive={false} icon={BadgeIndianRupee} /><Metric label="Active pipeline" value="₹12,80,000" change="18.4%" icon={Activity} /><Metric label="Estimated profit" value="₹3,26,400" change="6.5%" icon={ArrowUpRight} /></section>
        <section className="attention card"><div className="section-heading"><div className="heading-icon warning"><CircleAlert size={18} /></div><div><h2>Needs your attention</h2><p>A few things need a nudge to keep work moving.</p></div><button className="text-button">View all <span>→</span></button></div><div className="attention-list">{attention.map((item) => <div className="attention-item" key={item.title}><span className={`status-dot ${item.tone}`} /><div><b>{item.title}</b><small>{item.detail}</small></div><span className="row-arrow">↗</span></div>)}</div></section>
        <section className="lower-grid">
          <article className="card sales-card"><div className="card-heading"><div><h2>Sales snapshot</h2><p>Pipeline performance this month</p></div><button className="select-button">This month <ChevronDown size={14} /></button></div><div className="sales-total"><b>₹12,80,000</b><span className="positive-pill"><ArrowUpRight size={13} /> 18.4%</span></div><div className="sales-subtitle">Total pipeline value</div><div className="chart" aria-label="Sales pipeline trend"><div className="chart-y"><span>₹15L</span><span>₹10L</span><span>₹5L</span><span>₹0</span></div><div className="chart-main"><div className="chart-grid"><i /><i /><i /><i /></div><svg viewBox="0 0 560 125" preserveAspectRatio="none" role="img" aria-label="Pipeline trending upward"><defs><linearGradient id="fill" x1="0" x2="0" y1="0" y2="1"><stop offset="0%" stopColor="#3776f6" stopOpacity=".18"/><stop offset="100%" stopColor="#3776f6" stopOpacity="0"/></linearGradient></defs><path d="M0,103 C38,97 47,77 83,81 S129,101 167,73 S214,71 248,58 S294,67 329,44 S372,61 409,37 S457,48 483,25 S527,39 560,13 V125 H0 Z" fill="url(#fill)"/><path d="M0,103 C38,97 47,77 83,81 S129,101 167,73 S214,71 248,58 S294,67 329,44 S372,61 409,37 S457,48 483,25 S527,39 560,13" fill="none" stroke="#3776f6" strokeWidth="2.5" vectorEffect="non-scaling-stroke"/></svg><div className="chart-x"><span>Sep 1</span><span>Sep 5</span><span>Sep 10</span><span>Sep 15</span><span>Sep 20</span><span>Sep 25</span><span>Today</span></div></div></div><div className="pipeline-legend"><span><i className="legend-blue" />Qualified <b>₹5.4L</b></span><span><i className="legend-violet" />Proposal <b>₹4.2L</b></span><span><i className="legend-green" />Negotiation <b>₹3.2L</b></span></div></article>
          <article className="card activity-card"><div className="card-heading"><div><h2>Recent activity</h2><p>The latest across your workspace</p></div><button className="icon-button" aria-label="Activity options"><MoreHorizontal size={19} /></button></div><div className="activity-list">{activities.map((item, index) => <div className="activity-item" key={item.initials}><div className={`avatar avatar-${item.color}`}>{item.initials}</div><div className="activity-copy"><p>{item.text}</p><small>{item.time}</small></div>{index === 1 && <Check size={15} className="checkmark" />}</div>)}</div><button className="all-activity">View all activity <span>→</span></button></article>
        </section>
        <footer className="footer"><span>© 2026 Let’s Go Central</span><span>Built for agencies that move work forward.</span></footer>
      </div>
    </section>
  </main>;
}
